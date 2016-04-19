

#' Convert aligned reads from various file formats into read counts in equidistant bins
#'
#' Convert aligned reads in .bam or .bed(.gz) format into read counts in equidistant windows.
#'
#' Convert aligned reads from .bam or .bed(.gz) files into read counts in equidistant windows (bins). This function uses \code{\link[GenomicRanges]{countOverlaps}} to calculate the read counts.
#'
#' @aliases binning
#' @param file A file with aligned reads. Alternatively a \code{\link{GRanges}} with aligned reads if format is set to 'GRanges'.
#' @param format One of \code{c('bam', 'bed', 'GRanges')}. If set to \code{NULL}, the function will try to determine the format automatically from the file ending.
#' @param ID An identifier that will be used to identify the file throughout the workflow and in plotting.
#' @inheritParams bam2GRanges
#' @inheritParams bed2GRanges
#' @param outputfolder.binned Folder to which the binned data will be saved. If the specified folder does not exist, it will be created.
#' @param binsizes An integer vector with bin sizes. If more than one binsize is supplied, a \code{list()} with \code{\link{GRanges}} is returned instead of a single \code{\link{GRanges}}.
#' @param bins A named \code{list} with \code{\link{GRanges}} containing precalculated bins produced by \code{\link{fixedWidthBins}} or \code{\link{variableWidthBins}}. Names must correspond to the binsize.
#' @param reads.per.bin Approximate number of desired reads per bin. The bin size will be selected accordingly. Output files are produced for each value.
#' @param variable.width.reference A BAM file that is used as reference to produce variable width bins. See \code{\link{variableWidthBins}} for details.
#' @param stepsize Fraction of the binsize that the sliding window is offset at each step. Example: If \code{stepsize=0.1} and \code{binsizes=c(200000,500000)}, the actual stepsize in basepairs is 20000 and 50000, respectively. NOT USED AT THE MOMENT.
#' @param chromosomes If only a subset of the chromosomes should be binned, specify them here.
#' @param save.as.RData If set to \code{FALSE}, no output file will be written. Instead, a \link{GenomicRanges} object containing the binned data will be returned. Only the first binsize will be processed in this case.
#' @param call The \code{match.call()} of the parent function.
#' @param reads.store If \code{TRUE} processed read fragments will be saved to file. Reads are processed according to \code{min.mapq} and \code{remove.duplicate.reads}. Paired end reads are coerced to single end fragments.
#' @param outputfolder.reads Folder to which the read fragments will be saved. If the specified folder does not exist, it will be created.
#' @param reads.return If \code{TRUE} no binning is done and instead, read fragments from the input file are returned in \code{\link{GRanges}} format.
#' @param reads.overwrite Whether or not an existing file with read fragments should be overwritten.
#' @param reads.only If \code{TRUE} only read fragments are stored and/or returned and no binning is done.
#' @return If only one bin size was specified for option \code{binsizes}, the function returns a single \code{\link{GRanges}} object with meta data column 'counts' that contains the read count. If multiple \code{binsizes} were specified , the function returns a \code{list()} of \link{GRanges} objects. Results can also be written to file (\code{save.as.RData=TRUE}).
#' @export
#'
#'@examples
#'## Get an example BED file with ChIP-seq reads
#'bedfile <- system.file("extdata", "euratrans",
#'                       "lv-H3K27me3-BN-male-bio2-tech1.bed.gz",
#'                        package="chromstaRData")
#'## Bin the BED file into bin size 1000bp
#'data(rn4_chrominfo)
#'binned <- binReads(bedfile, assembly=rn4_chrominfo, binsize=1000,
#'                   chromosomes='chr12')
#'print(binned)
#'
binReads <- function(file, format=NULL, assembly, ID=basename(file), bamindex=file, chromosomes=NULL, pairedEndReads=FALSE, min.mapq=10, remove.duplicate.reads=TRUE, max.fragment.width=1000, blacklist=NULL, outputfolder.binned="binned_data", binsizes=1000, reads.per.bin=NULL, bins=NULL, variable.width.reference=NULL, stepsize=NULL, save.as.RData=FALSE, call=match.call(), reads.store=FALSE, outputfolder.reads="data", reads.return=FALSE, reads.overwrite=FALSE, reads.only=FALSE) {

    ## Check user input
    if (reads.return==FALSE & reads.only==FALSE) {
        if (is.null(binsizes) & is.null(reads.per.bin) & is.null(bins)) {
            stop("Please specify either argument 'binsizes' or 'reads.per.bin'")
        }
    }

    ## Determine format
    if (is.character(file)) {
        file.clean <- sub('\\.gz$','', file)
        format <- rev(strsplit(file.clean, '\\.')[[1]])[1]
    } else if (class(file)=='GRanges') {
        format <- 'GRanges'
    }

    ## Create outputfolder.binned if not exists
    if (!file.exists(outputfolder.binned) & save.as.RData==TRUE) {
        dir.create(outputfolder.binned)
    }

    ### Read in the data
    if (format == "bed") {
        ## BED (0-based)
        if (!remove.duplicate.reads) {
            data <- bed2GRanges(file, assembly=assembly, chromosomes=chromosomes, remove.duplicate.reads=FALSE, min.mapq=min.mapq, max.fragment.width=max.fragment.width, blacklist=blacklist)
        } else {
            data <- bed2GRanges(file, assembly=assembly, chromosomes=chromosomes, remove.duplicate.reads=TRUE, min.mapq=min.mapq, max.fragment.width=max.fragment.width, blacklist=blacklist)
        }
    } else if (format == "bam") {
        ## BAM (1-based)
        if (!remove.duplicate.reads) {
            data <- bam2GRanges(file, bamindex, chromosomes=chromosomes, pairedEndReads=pairedEndReads, remove.duplicate.reads=FALSE, min.mapq=min.mapq, max.fragment.width=max.fragment.width, blacklist=blacklist)
        } else {
            data <- bam2GRanges(file, bamindex, chromosomes=chromosomes, pairedEndReads=pairedEndReads, remove.duplicate.reads=TRUE, min.mapq=min.mapq, max.fragment.width=max.fragment.width, blacklist=blacklist)
        }
    } else if (format == "GRanges") {
        ## GRanges (1-based)
        data <- file
        err <- tryCatch({
            !is.character(ID)
        }, error = function(err) {
            TRUE
        })
        if (err) {
            ID <- 'GRanges'
        }
    }

    ## Select chromosomes to bin
    if (is.null(chromosomes)) {
        chromosomes <- seqlevels(data)
    }
    chroms2use <- intersect(chromosomes, seqlevels(data))

    ## Select only desired chromosomes
    data <- data[seqnames(data) %in% chroms2use]
    data <- keepSeqlevels(data, as.character(unique(seqnames(data))))
    ## Drop seqlevels where seqlength is NA
    na.seqlevels <- seqlevels(data)[is.na(seqlengths(data))]
    data <- data[seqnames(data) %in% seqlevels(data)[!is.na(seqlengths(data))]]
    data <- keepSeqlevels(data, as.character(unique(seqnames(data))))
    if (length(na.seqlevels) > 0) {
        warning("Dropped seqlevels because no length information was available: ", paste0(na.seqlevels, collapse=', '))
    }
 
    ### Return fragments if desired ###
    if (reads.store) {
        if (!file.exists(outputfolder.reads)) { dir.create(outputfolder.reads) }
        filename <- file.path(outputfolder.reads,paste0(ID,'.RData'))
        if (reads.overwrite | !file.exists(filename)) {
            ptm <- startTimedMessage(paste0("Saving fragments to ", filename, " ..."))
            save(data, file=filename)
            stopTimedMessage(ptm)
        }
    }
    if (reads.return) {
        return(data)
    }
    if (reads.only) {
        return()
    }

    ### Coverage and percentage of genome covered ###
    ptm <- startTimedMessage("Calculating coverage ...")
    genome.length <- sum(as.numeric(seqlengths(data)))
    data.strand <- data
    strand(data.strand) <- '*'
    coverage <- sum(as.numeric(width(data.strand))) / genome.length
    genome.covered <- sum(as.numeric(width(reduce(data.strand)))) / genome.length
    ## Per chromosome
    coverage.per.chrom <- numeric()
    genome.covered.per.chrom <- numeric()
    for (chr in chroms2use) {
        data.strand.chr <- data.strand[seqnames(data.strand)==chr]
        coverage.per.chrom[chr] <- sum(as.numeric(width(data.strand.chr))) / seqlengths(data.strand)[chr]
        genome.covered.per.chrom[chr] <- sum(as.numeric(width(reduce(data.strand.chr)))) / seqlengths(data.strand)[chr]
    }
    coverage <- list(coverage=coverage, genome.covered=genome.covered, coverage.per.chrom=coverage.per.chrom, genome.covered.per.chrom=genome.covered.per.chrom)
    stopTimedMessage(ptm)


    ## Pad binsizes and reads.per.bin with each others value
    numcountsperbp <- length(data) / sum(as.numeric(seqlengths(data)))
    binsizes.add <- round(reads.per.bin / numcountsperbp, -2)
    reads.per.bin.add <- round(binsizes * numcountsperbp, 2)
    binsizes <- c(binsizes, binsizes.add)
    reads.per.bin <- c(reads.per.bin.add, reads.per.bin)

    if (!is.null(variable.width.reference)) {
        ### Variable width bins ###
        message("Making variable width bins:")
        if (format == 'bam') {
            refreads <- bam2GRanges(variable.width.reference, bamindex=variable.width.reference, chromosomes=chroms2use, pairedEndReads=pairedEndReads, remove.duplicate.reads=remove.duplicate.reads, min.mapq=min.mapq, max.fragment.width=max.fragment.width, blacklist=blacklist)
        } else if (format == 'bed') {
            refreads <- bed2GRanges(variable.width.reference, assembly=assembly, chromosomes=chroms2use, remove.duplicate.reads=remove.duplicate.reads, min.mapq=min.mapq, max.fragment.width=max.fragment.width, blacklist=blacklist)
        }
        bins.list <- variableWidthBins(refreads, binsizes=binsizes, chromosomes=chroms2use)
        message("Finished making variable width bins.")
    } else {
        ### Fixed width bins ###
        bins.list <- fixedWidthBins(chrom.lengths=seqlengths(data), binsizes=binsizes, chromosomes=chroms2use)
    }
    ## Append precalculated bins ##
    bins.list <- c(bins.list, bins)

    ### Loop over all binsizes ###
    data.plus <- data[strand(data)=='+']
    data.minus <- data[strand(data)=='-']
    data.star <- data[strand(data)=='*']
    binned.data.list <- list()
    for (ibinsize in 1:length(bins.list)) {
        binsize <- as.numeric(names(bins.list)[ibinsize])
        readsperbin <- round(length(data) / sum(as.numeric(seqlengths(data))) * binsize, 2)
        message("Binning into bin size ",binsize," with on average ",readsperbin," reads per bin")
        binned.data <- bins.list[[ibinsize]]

        ### Loop over offsets ###
        countmatrices <- list()
#         if (is.null(stepsize)) {
            offsets <- 0
#         } else {
#             offsets <- seq(from=0, to=binsize, by=as.integer(stepsize*binsize))
#         }
        for (ioff in offsets) {
            ## Count overlaps
            ptm <- startTimedMessage(paste0("Counting overlaps for offset ",ioff," ..."))
            binned.data.shift <- suppressWarnings( shift(binned.data, shift=ioff) )
            scounts <- suppressWarnings( GenomicRanges::countOverlaps(binned.data.shift, data.star) )
            mcounts <- suppressWarnings( GenomicRanges::countOverlaps(binned.data.shift, data.minus) )
            pcounts <- suppressWarnings( GenomicRanges::countOverlaps(binned.data.shift, data.plus) )
            counts <- mcounts + pcounts + scounts
            countmatrix <- matrix(c(counts,mcounts,pcounts), ncol=3)
            colnames(countmatrix) <- c('counts','mcounts','pcounts')
            countmatrices[[as.character(ioff)]] <- countmatrix
            stopTimedMessage(ptm)
        }
#         mcols(binned.data) <- as(countmatrices[['0']],'DataFrame') # counts, mcounts, pcounts
        mcols(binned.data)$counts <- countmatrices[['0']][,'counts']
#         attr(binned.data,'offset.counts') <- countmatrices

        if (length(binned.data) == 0) {
            warning(paste0("The bin size of ",binsize," with reads per bin ",reads.per.bin," is larger than any of the chromosomes."))
            return(NULL)
        }

        ### Quality measures ###
        qualityInfo <- list(coverage=coverage)
        attr(binned.data, 'qualityInfo') <- qualityInfo
        attr(binned.data, 'min.mapq') <- min.mapq

        ### ID ###
        attr(binned.data, 'ID') <- ID

        ### Save or return the binned data ###
        if (save.as.RData==TRUE) {
            # Save to file
            filename <- paste0(ID,"_binsize",format(binsize, scientific=FALSE, trim=TRUE),".RData")
            ptm <- startTimedMessage("Saving to file ...")
#             attr(binned.data, 'call') <- call # do not store along with GRanges because it inflates disk usage
            save(binned.data, file=file.path(outputfolder.binned,filename) )
            stopTimedMessage(ptm)
        } else {
#             attr(binned.data, 'call') <- call
            binned.data.list[[as.character(binsize)]] <- binned.data
        }

    } ### end loop binsizes ###

    if (!save.as.RData) {
        if (length(binned.data.list) == 1) {
            return(binned.data.list[[1]])
        } else {
            return(binned.data.list)
        }
    }


}

