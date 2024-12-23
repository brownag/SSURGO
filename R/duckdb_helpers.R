#' Helpers for DuckDB Connections
#'
#' @param dsn _character_. Path to DuckDB data source. A file will be created if
#'   one does not already exist. With the default `":memory:"` (or `""`) all
#'   data are stored in RAM.
#'
#' @return `create_duckdb_connection()`: A _duckdb_connection_ object.
#' @export
#' @rdname duckdb-helpers
#' @examples
#'
#' conn <- duckdb_create_connection()
#'
#' conn
#'
#' duckdb_install_spatial(conn)
#'
#' DBI::dbDisconnect(conn)
#'
duckdb_create_connection <- function(dsn = ":memory:") {
  DBI::dbConnect(duckdb::duckdb(), dsn)
}

#' @param conn A _duckdb_connection_ object.
#' @return `install_duckdb_spatial()`: A _duckdb_result_ object.
#' @export
#' @rdname duckdb-helpers
duckdb_install_spatial <- function(conn) {
	duckdb::dbSendQuery(conn, "INSTALL spatial;
    												 LOAD spatial;")
}

duckdb_query <- function(conn, query, n = -1) {
	res <- duckdb::dbSendQuery(conn, query)
	duckdb::dbFetch(res, n = n)
}

duckdb_spatial_query <- function(conn, table, x, geometry_column = "geom") {
	duckdb_sf(
		conn,
		table,
		WHERE = paste0("ST_Intersects(geom, ST_GeomFromText('",
		  as.character(wk::as_wkt(x)),
		"'))"),
		geometry_column = geometry_column
	)
}

duckdb_sf <- function(conn, table, n = -1, JOIN = NULL, WHERE = NULL, geometry_column = "geom", add_columns = NULL) {
	duckdb_install_spatial(conn)
	cn <- colnames(duckdb_query(conn, paste0("SELECT * FROM ", table), 0))
	x <- sf::st_read(
		conn,
		query = paste0(
				"SELECT ", paste0(c(paste0(table, ".", cn[cn != "geom"]), add_columns, ""), collapse = ", "),
				"ST_AsWKB(geom) AS ", geometry_column, "
		     FROM ", table, "\n",
				paste0(JOIN, collapse = "\n"),
				ifelse(!is.null(WHERE), paste0(" WHERE ", WHERE), ""),
				ifelse(n != -1, paste0(" LIMIT ", n, ";"), "")
			 ),
		geometry_column = geometry_column
	)
	sf::st_crs(x) <- "OGC:CRS84"
	x
}

duckdb_table <- function(conn, layer) {
	duckdb_query(conn, paste0("SELECT * FROM ", layer))
}


