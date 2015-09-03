#' Merge several \code{\link{chromstaR_multivariateHMM}}s into one object
#'
#' Merge several \code{\link{chromstaR_multivariateHMM}}s into one object. This can be done to merge fits for separate chromosomes into one object for easier handling. Merging will only be done if all models have the same IDs.
#'
#' @author Aaron Taudt
#' @param multi.hmm.list A list of \code{\link{chromstaR_multivariateHMM}} objects.
#' @param filename The file name where the merged object will be stored. If \code{filename} is not specified, a \code{\link{chromstaR_multivariateHMM}} is returned.
#' @return A \code{\link{chromstaR_multivariateHMM}} object or NULL, depending on option \code{filename}.
#' @export
mergeChroms <- function(multi.hmm.list, filename=NULL) {

	## Check user input
	multi.hmm.list <- loadMultiHmmsFromFiles(multi.hmm.list)
	## Check if all models have the same ID
	same.IDs <- Reduce('|', unlist(lapply(multi.hmm.list, function(x) { x$IDs == multi.hmm.list[[1]]$IDs })))
	if (!same.IDs) {
		stop("Will not merge the multivariate HMMs because their IDs differ.")
	}
		
	## Check if posteriors are present everywhere
	post.present <- Reduce('|', unlist(lapply(multi.hmm.list, function(x) { !is.null(x$bins$posteriors) })))

	## Variables
	num.models <- length(multi.hmm.list)
	
	## Construct list of bins and segments
	message("Concatenating HMMs ...", appendLF=FALSE); ptm <- proc.time()
	bins <- list()	# do not use GRangesList() because it copies the whole list each time an element is added
	segments <- list()
	for (i1 in 1:num.models) {
		hmm <- multi.hmm.list[[1]]	# select always first because we remove it at the end of the loop
		if (!post.present) {
			hmm$bins$posteriors <- NULL
			hmm$segments$mean.posteriors <- NULL
		}
		bins[[i1]] <- hmm$bins
		segments[[i1]] <- hmm$segments
		# Remove current HMM to save memory
		if (i1 < num.models) remove(hmm)	# remove it because otherwise R will make a copy when we NULL the underlying reference (multi.hmm.list[[1]])
		multi.hmm.list[[1]] <- NULL
	}
	time <- proc.time() - ptm; message(" ",round(time[3],2),"s")

	## Merge the list
	message("Merging ...", appendLF=F); ptm <- proc.time()
	bins <- do.call('c', bins)	# this can be too memory intensive if posteriors are present
	segments <- do.call('c', segments)
	time <- proc.time() - ptm; message(" ",round(time[3],2),"s")

	## Reassign
	multi.hmm <- hmm
	multi.hmm$bins <- bins
	multi.hmm$segments <- segments

	## Weights
	message("Calculating weights ...", appendLF=F); ptm <- proc.time()
	multi.hmm$weights <- table(multi.hmm$bins$state) / length(multi.hmm$bins)
	time <- proc.time() - ptm; message(" ",round(time[3],2),"s")

	if (is.null(filename)) {
		return(multi.hmm)
	} else {
		message("Writing to file ",filename," ...", appendLF=F); ptm <- proc.time()
		save(multi.hmm, file=filename)
		time <- proc.time() - ptm; message(" ",round(time[3],2),"s")
	}

	return(NULL)
}