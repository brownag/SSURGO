#!/usr/bin/env Rscript
#' Ensure all SSURGO data is downloaded before pipeline runs
#'
#' Downloads missing SSAs and validates completeness.
#' Exit status: 0 = all data present, 1 = download/validation failed

source('R/ssurgo_helpers.R')
source('R/download_ssurgo.R')

ensure_ssurgo_data <- function(destdir = "data") {
  # Get expected SSAs
  expected <- get_area_symbols()

  # Check what's downloaded
  all_dirs <- list.dirs(destdir, recursive = FALSE, full.names = FALSE)
  downloaded <- all_dirs[nchar(all_dirs) == 5]  # SSA format

  # Find missing
  missing <- setdiff(expected, downloaded)
  n_expected <- length(expected)
  n_downloaded <- length(downloaded)
  n_missing <- length(missing)

  cat("Expected SSAs:", n_expected, "\n")
  cat("Downloaded:", n_downloaded, "\n")
  cat("Missing:", n_missing, "\n")

  if (n_missing > 0) {
    cat("\nDownloading", n_missing, "missing SSAs...\n")

    # Download missing
    results <- sapply(missing, function(ssa) {
      tryCatch(
        download_ssurgo(areasymbol = ssa, destdir = destdir),
        error = function(e) {
          cat("ERROR downloading", ssa, ":", e$message, "\n")
          structure(paste("Error:", e$message), class = "try-error")
        }
      )
    })

    # Check for download failures
    failed <- results[inherits(results, "try-error")]
    if (length(failed) > 0) {
      cat("\nWARNING: Failed to download", length(failed), "SSAs:\n")
      print(names(failed))
      return(FALSE)
    }

    cat("\nAll missing SSAs downloaded.\n")
  } else {
    cat("\nAll SSAs already present.\n")
  }

  # Final validation
  all_dirs <- list.dirs(destdir, recursive = FALSE, full.names = FALSE)
  final_downloaded <- all_dirs[nchar(all_dirs) == 5]
  final_missing <- setdiff(expected, final_downloaded)

  if (length(final_missing) > 0) {
    cat("\nERROR: Validation failed. Still missing:\n")
    print(final_missing)
    return(FALSE)
  }

  cat("\n✓ Validation passed. All", length(expected), "SSAs present.\n")
  return(TRUE)
}

if (!interactive()) {
  success <- ensure_ssurgo_data()
  quit(status = if (success) 0 else 1)
}
