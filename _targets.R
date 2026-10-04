library(targets)
library(tarchetypes)
library(geotargets)
tar_option_set(packages = c("SSURGO", "soilDB", "duckdb", "DBI", 
    "sf", "units", "future", "future.callr"))
DESTINATION_DIR <- "data"
tar_source()
future::plan(future.callr::callr)
list(tar_target(destdir, DESTINATION_DIR), tar_target(name = ssa_list, 
    command = {
        files <- list.files(file.path(DESTINATION_DIR), pattern = "^wss_.*_.*\\.zip$", 
            recursive = TRUE, full.names = TRUE)
        stopifnot(length(files) == 3385)
        sort(files)
    }), tar_target(ssurgo_duckdb_path, "data/SSURGO.duckdb"), 
    tar_target(ssurgo_create_duckdb, {
        res <- ssa_list
        if (file.exists(ssurgo_duckdb_path)) {
            file.remove(ssurgo_duckdb_path)
        }
        conn <- duckdb_create_connection(ssurgo_duckdb_path)
        res <- soilDB::createSSURGO(exdir = DESTINATION_DIR, 
            conn = conn, maxruledepth = 0, include_spatial = c("mupolygon", 
                "featpoint"), include_tabular = TRUE)
        DBI::dbDisconnect(conn)
        res
    }), tar_target(ssurgo_duckdb, {
        list(tables = ssurgo_create_duckdb, dsn = ssurgo_duckdb_path)
    }), tar_files(ssurgo_dsn, {
        ssurgo_duckdb$dsn
    }, cue = targets::tar_cue("never")), tar_target(n_mapunit, 
        {
            conn <- duckdb_create_connection(ssurgo_dsn)
            x <- duckdb_query(conn, "SELECT COUNT(DISTINCT mukey) AS n_mapunit FROM mapunit")
            dbDisconnect(conn)
            x$n_mapunit
        }), tar_target(n_polygon, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_query(conn, "SELECT COUNT(mukey) AS n_polygon FROM mupolygon")
        dbDisconnect(conn)
        x$n_polygon
    }), tar_target(n_mapunit_polygon, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_query(conn, "SELECT COUNT(DISTINCT mukey) AS n_mapunit_polygon FROM mupolygon")
        dbDisconnect(conn)
        x$n_mapunit_polygon
    }), tar_target(legend, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_table(conn, "legend")
        dbDisconnect(conn)
        x
    }), tar_target(mapunit, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_table(conn, "mapunit")
        dbDisconnect(conn)
        x
    }), tar_target(mupolygon_spatial_index, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        duckdb_install_spatial(conn)
        x <- duckdb_create_spatial_index(conn, "mupolygon")
        y <- duckdb_analyze_table(conn, "mupolygon")
        dbDisconnect(conn)
        x
    }), tar_files(ssurgo_dsn_indexed, {
        mupolygon_spatial_index
        ssurgo_dsn
    }), tar_target(spatial_subset, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        b <- c(-119.747629, -119.67935, 36.912019, 36.944987)
        bbox.sp <- sf::st_as_sf(wk::rct(xmin = b[1], xmax = b[2], 
            ymin = b[3], ymax = b[4], crs = sf::st_crs(4326)))
        duckdb_install_spatial(conn)
        res <- duckdb_spatial_query(conn, "mupolygon", bbox.sp)
        dbDisconnect(conn)
        res
    }))
