
#' Get Soil Survey Area Symbols from Catalog
#'
#' @param except Soil Survey Area Symbols to exclude. Default "US" (STATSGO) and "MXNL001" (Mexico)
#'
#' @returns Character vector of area symbols.
#' @export
get_area_symbols <- function(except = c("US", "MXNL001")) {
	sac <- soilDB::SDA_query("SELECT areasymbol FROM sacatalog")[[1]]
	sac[!sac %in% except]
}

#' Get Unique State Symbols from Area Symbols
#'
#' @param x Character vector of soil survey area symbols.
#'
#' @returns Character. The unique set of the first two characters from each soil survey area.
#' @export
get_state_symbols <- function(x) {
	unique(gsub("^([A-Z]{2})\\d{3}", "\\1", x))
}

#' Download All Soil Survey Areas in a State
#'
#' @param x Character. State abbreviation. For example: `"UT"`, `"PR"`, `"GU"`
#' @param destdir Character. Destination directory. Default: `"data"`
#'
#' @returns Character. Path to downloaded zip
#' @export
download_state <- function(x, y, destdir = "data") {
	stopifnot(length(x) == 1)
	sapply(y[grep(paste0(x, "\\d{3}"), y)], function(xx) {
		download_ssurgo(areasymbol = xx, destdir = destdir)
	})
}
