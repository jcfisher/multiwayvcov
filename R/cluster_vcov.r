###################################################################### 
#' @title Multi-way standard error clustering
#' 
#' @description Return a multi-way cluster-robust variance-covariance matrix
#'
#' @param model The estimated model, usually an \code{lm} or \code{glm} class object
#' @param cluster A \code{vector}, \code{matrix}, or \code{data.frame} of cluster variables,
#' where each column is a separate variable.  If the vector \code{1:nrow(data)}
#' is used, the function effectively produces a regular 
#' heteroskedasticity-robust matrix.
#' @param cluster.varnames A character vector of variable names from the fitted
#' model to use as cluster variables.  Can be specified instead of cluster.
#' @param parallel Scalar or list.  If a list, use the list as a list
#' of connected processing cores/clusters.  A scalar indicates no
#' parallelization.  See the \bold{parallel} package.
#' @param use_white Logical or \code{NULL}.  See description below.
#' @param df_correction Logical or \code{vector}.  \code{TRUE} computes degrees
#' of freedom corrections, \code{FALSE} uses no corrections.  A vector of length
#' \eqn{2^D - 1} will directly set the degrees of freedom corrections.
#' @param leverage Integer. EXPERIMENTAL Uses Mackinnon-White HC3-style leverage
#' adjustments.  Known to work in the non-clustering case, 
#' e.g., it reproduces HC3 if \code{df_correction=FALSE}.  Set to 3 for HC3-style
#' and 2 for HC2-style leverage adjustments.
#' @param debug Logical.  Print internal values useful for debugging to 
#' the console.
#' @param force_posdef Logical.  Force the eigenvalues of the variance-covariance
#' matrix to be positive.
#'
#' @keywords clustering multi-way robust standard errors
#'
#' @details
#' This function implements multi-way clustering using the method 
#' suggested by Cameron, Gelbach, & Miller (2011), which involves
#' clustering on \eqn{2^D - 1} dimensional combinations, e.g.,
#' if we're cluster on firm and year, then we compute for firm,
#' year, and firm-year.  Variance-covariance matrices with an odd
#' number of cluster variables are added, and those with an even
#' number are subtracted.
#'
#' The cluster variable(s) are specified by passing the entire variable(s)
#' to cluster (\code{cbind()}'ed as necessary).  The cluster variables should
#' be of the same number of rows as the original data set; observations
#' omitted or excluded in the model estimation will be handled accordingly.
#'
#' Ma (2014) suggests using the White (1980) variance-covariance matrix
#' as the final, subtracted matrix when the union of the clustering
#' dimensions U results in a single observation per group in U;
#' e.g., if clustering by firm and year, there is only one observation
#' per firm-year, we subtract the White (1980) HC0 variance-covariance
#' from the sum of the firm and year vcov matrices.  This is detected
#' automatically (if \code{use_white = NULL}), but you can force this one way 
#' or the other by setting \code{use_white = TRUE} or \code{FALSE}.
#' 
#' Some authors suggest avoiding degrees of freedom corrections with
#' multi-way clustering.  By default, the function uses corrections
#' identical to Petersen (2009) corrections.  Passing a numerical
#' vector to \code{df_correction} (of length \eqn{2^D - 1}) will override
#' the default, and setting \code{df_correction = FALSE} will use no correction.
#' 
#' Cameron, Gelbach, & Miller (2011) futher suggest a method for forcing
#' the variance-covariance matrix to be positive semidefinite by correcting
#' the eigenvalues of the matrix.  To use this method, set \code{force_posdef = TRUE}.
#' Do not use this method unless absolutely necessary!  The eigen/spectral
#' decomposition used is not ideal numerically, and may introduce small
#' errors or deviations.  If \code{force_posdef = TRUE}, the correction is applied
#' regardless of whether it's necessary.
#' 
#' The defaults deliberately match the Stata default output for one-way and
#' Mitchell Petersen's two-way Stata code results.  To match the
#' SAS default output (obtained using the class & repeated subject 
#' statements, see Arellano (1987)) simply turn off the degrees of freedom correction.
#' 
#' Parallelization is available via the \bold{parallel} package by passing
#' the "cluster" list (usually called \code{cl}) to the parallel argument.
#' 
#' @return a \eqn{k} x \eqn{k} variance-covariance matrix of type 'matrix'
#' 
#' @export
#' @author Nathaniel Graham \email{npgraham1@@gmail.com}
#' 
#' @references 
#' Arellano, M. (1987). PRACTITIONERS' CORNER: Computing Robust Standard Errors for 
#' Within-groups Estimators. Oxford bulletin of Economics and Statistics, 49(4), 431-434.
#' 
#' Cameron, A. C., Gelbach, J. B., & Miller, D. L. (2011). Robust inference with multiway 
#' clustering. Journal of Business & Economic Statistics, 29(2).
#' 
#' Ma, Mark (Shuai), Are We Really Doing What We Think We Are Doing? A Note on Finite-Sample 
#' Estimates of Two-Way Cluster-Robust Standard Errors (April 9, 2014).
#' 
#' MacKinnon, J. G., & White, H. (1985). Some heteroskedasticity-consistent covariance matrix 
#' estimators with improved finite sample properties. Journal of Econometrics, 29(3), 305-325.
#' 
#' Petersen, M. A. (2009). Estimating standard errors in finance panel data sets: Comparing 
#' approaches. Review of financial studies, 22(1), 435-480.
#' 
#' White, H. (1980). A heteroskedasticity-consistent covariance matrix estimator and a direct 
#' test for heteroskedasticity. Econometrica: Journal of the Econometric Society, 817-838.
#' 
#' @importFrom sandwich estfun meatHC sandwich
#' @importFrom parallel clusterExport parApply
#' 
#' @examples
#' library(lmtest)
#' data(petersen)
#' m1 <- lm(y ~ x, data = petersen)
#' 
#' # Cluster by firm
#' vcov_firm <- cluster.vcov(m1, petersen$firmid)
#' coeftest(m1, vcov_firm)
#' 
#' # Cluster by year
#' vcov_year <- cluster.vcov(m1, petersen$year)
#' coeftest(m1, vcov_year)
#' 
#' # Double cluster by firm and year
#' vcov_both <- cluster.vcov(m1, cbind(petersen$firmid, petersen$year))
#' coeftest(m1, vcov_both)
#' 
#' # Replicate Mahmood Arai's double cluster by firm and year
#' vcov_both <- cluster.vcov(m1, cbind(petersen$firmid, petersen$year), use_white = FALSE)
#' coeftest(m1, vcov_both)
#' 
#' # For comparison, produce White HC0 VCOV the hard way
#' vcov_hc0 <- cluster.vcov(m1, 1:nrow(petersen), df_correction = FALSE)
#' coeftest(m1, vcov_hc0)
#' 
#' # Produce White HC1 VCOV the hard way
#' vcov_hc1 <- cluster.vcov(m1, 1:nrow(petersen), df_correction = TRUE)
#' coeftest(m1, vcov_hc1)
#' 
#' # Produce White HC2 VCOV the hard way
#' vcov_hc2 <- cluster.vcov(m1, 1:nrow(petersen), df_correction = FALSE, leverage = 2)
#' coeftest(m1, vcov_hc2)
#' 
#' # Produce White HC3 VCOV the hard way
#' vcov_hc3 <- cluster.vcov(m1, 1:nrow(petersen), df_correction = FALSE, leverage = 3)
#' coeftest(m1, vcov_hc3)
#' 
#' # Go multicore using the parallel package
#' \dontrun{
#' require(parallel)
#' cl <- makeCluster(4)
#' vcov_both <- cluster.vcov(m1, cbind(petersen$firmid, petersen$year), parallel = cl)
#' stopCluster(cl)
#' coeftest(m1, vcov_both)
#' }
cluster.vcov <- function(model, cluster = NULL, cluster.varname = NULL,
                         parallel = FALSE, use_white = NULL, 
                         df_correction = TRUE, leverage = FALSE, force_posdef = FALSE,
                         debug = FALSE) {
  
  # Error checking inputs
  if (is.null(cluster) && is.null(cluster.varname))
    stop("Either cluster or cluster.varname must be specified.")
  
  # If cluster.varnames isn't specified, the save the cluster as a data.frame
  if (is.null(cluster.varname)) {
    cluster <- as.data.frame(cluster)
    
  # If cluster.varnames *is* specified, pull the vectors from the data.frame
  # saved with the model
  } else {
    if (!all(cluster.varname %in% names(model$model)))
      stop("All values of cluster.varname must be variables in the data.frame stored in model.")
    cluster <- as.data.frame(model$model[, cluster.varname])
  }
  
  cluster_dims <- ncol(cluster)
  # total cluster combinations, 2^D - 1
  tcc <- 2 ** cluster_dims - 1
  # all cluster combinations
  acc <- list()
  for(i in 1:cluster_dims) {
    acc <- append(acc, combn(1:cluster_dims, i, simplify = FALSE))
  }
  if(debug) print(acc)
  
  # We need to subtract matrices with an even number of combinations and add
  # matrices with an odd number of combinations
  vcov_sign <- sapply(acc, function(i) (-1) ** (length(i) + 1))
  
  # Drop the original cluster vars from the combinations list
  acc <- acc[-1:-cluster_dims]
  if(debug) print(acc)
  
  # Handle omitted or excluded observations
  if(!is.null(model$na.action) && is.null(cluster)) {
    if(class(model$na.action) == "exclude") {
      cluster <- cluster[-model$na.action,]
      esttmp <- estfun(model)[-model$na.action,]
    } else if(class(model$na.action) == "omit") {
      cluster <- cluster[-model$na.action,]
      esttmp <- estfun(model)
    }
    cluster <- as.data.frame(cluster)  # silly error somewhere
  } else {
    esttmp <- estfun(model)
  }
  if(debug) print(class(cluster))
  
  # Make all combinations of cluster dimensions
  if(cluster_dims > 1) {
    for(i in acc) {
      cluster <- cbind(cluster, Reduce(paste0, cluster[,i]))
    }
  }
  
  df <- data.frame(M = integer(tcc),
                   N = integer(tcc),
                   K = integer(tcc))
  
  for(i in 1:tcc) {
    df[i, "M"] <- length(unique(cluster[,i]))
    df[i, "N"] <- length(cluster[,i])
    df[i, "K"] <- model$rank
  }
  
  
  if(df_correction == TRUE) {
    df$dfc <- (df$M / (df$M - 1)) * ((df$N - 1) / (df$N - df$K))
  } else if(length(df_correction) > 1) {
    df$dfc <- df_correction
  } else {
    df$dfc <- 1
  }
  
  if(is.null(use_white)) {
    if(cluster_dims > 1 && df[tcc, "M"] == prod(df[-tcc, "M"])) {
      use_white <- TRUE
    } else {
      use_white <- FALSE
    }
  }
  
  if(use_white) {
    df <- df[-tcc,]
    tcc <- tcc - 1
  }
  
  if(debug) {
    print(acc)
    print(paste("Original Cluster Dimensions", cluster_dims))
    print(paste("Theoretical Cluster Combinations", tcc))
    print(paste("Use White VCOV for final matrix?", use_white))
  }
  
  if(leverage) {
    if("x" %in% names(model)) {
      X <- model$x
    } else {
      X <- model.matrix(model)
    }
    
    ixtx <- solve(crossprod(X))
    h <- 1 - vapply(1:df[1, "N"], function(i) X[i,] %*% ixtx %*% as.matrix(X[i,]), numeric(1))
    
    if(leverage == 3) {
      esttmp <- esttmp / h
    } else if(leverage == 2) {
      esttmp <- esttmp / sqrt(h)
    }
  }
  
  uj <- list()
  
  if(length(parallel) > 1) {
    clusterExport(parallel, varlist = c("cluster", "model"), envir = environment())
  }
  
  for(i in 1:tcc) {
    if(length(parallel) > 1) {
      uj[[i]] <- crossprod(parApply(parallel, esttmp, 2, 
                                    function(x) tapply(x, cluster[,i], sum)))
    } else {
      uj[[i]] <- crossprod(apply(esttmp, 2, function(x) tapply(x, cluster[,i], sum)))
    }
  }
  
  if(debug) {
    print(df)
    print(uj)
    print(vcov_sign)
  }
  
  vcov_matrices <- list()
  for(i in 1:tcc) {
    vcov_matrices[[i]] <- vcov_sign[i] * df[i, "dfc"] * (uj[[i]] / df[i, "N"])
  }
  
  if(use_white) {
    i <- i + 1
    vcov_matrices[[i]] <- vcov_sign[i] * meatHC(model, type = "HC0")
  }
  
  if(debug) {
    print(vcov_matrices)
  }
  
  vcov_matrix <- sandwich(model, meat. = Reduce('+', vcov_matrices))
  
  if(force_posdef) {
    decomp <- eigen(vcov_matrix, symmetric = TRUE)
    if(debug) print(decomp$values)
    pos_eigens <- pmax(decomp$values, rep.int(0, length(decomp$values)))
    vcov_matrix <- decomp$vectors %*% diag(pos_eigens) %*% t(decomp$vectors)
  }
  
  return(vcov_matrix)
}

