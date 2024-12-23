# lightweight functions that depend on the pipeline
# they call tar_load(), but are not dependencies of any target or pipeline output

#' Summarize SSURGO Database Contents
#'
#' Prints database path, file size, number of mapunits, and number of mapunit
#' polygons.
#'
#' @return Function is called for side-effects (messages in console).
#'
#' @examples
#' \dontrun{
#' greet_database()
#' }
greet_database <- function() {

	targets::tar_load(c(ssurgo_duckdb_path, n_mapunit, n_mapunit_polygon,
											n_polygon, mapunit_acres, mukey_acres, acre_compare))

	fs <- file.size(ssurgo_duckdb_path) / 1024 / 1024
	message(
		"DuckDB database (",	ssurgo_duckdb_path, "; ",
		signif(fs, round(log10(fs)) + 1), "MB) contains ",
		n_mapunit, " mapunits and ",
		n_polygon, " mapunit polygons."
	)

	if (n_mapunit != n_mapunit_polygon) {
		message(
			"Number of mapunit records (",
			n_mapunit,
			") does not match number of unique MUKEY in mupolygon (",
			n_mapunit_polygon,
			")!"
		)
	}

	muacre_sum <- sum(acre_compare$muacres, na.rm = TRUE)
	spacre_sum <- sum(acre_compare$acres_round, na.rm = TRUE)
	message("Sum of legend acres is ", muacre_sum,
	        " and sum of spatial acres is ", spacre_sum,
					" (relative difference of ", signif(abs(muacre_sum - spacre_sum) / spacre_sum * 100, 3), "%)")

	if (any(acre_compare$legend_missing)) {
		message("Legend acres are missing (n=", sum(acre_compare$legend_missing), " mapunits)")
	}

	if (any(acre_compare$spatial_missing)) {
		message("Spatial acres are missing (n=", sum(acre_compare$spatial_missing), " mapunits)")
	}

	if (any(acre_compare$exact)) {
		message("Spatial acres (rounded) do not match legend acres (n=", sum(!acre_compare$exact[!acre_compare$missing]), " mapunits)")
	}

	if (any(acre_compare$thresh)) {
		message("Spatial acres have more than 10% relative difference from legend acres (n=", sum(!acre_compare$thresh[!acre_compare$missing]), " mapunits)")
	}
}
