library(targets)
library(soilDB)
library(duckdb)
library(sf)

targets::tar_script({	## begin tar_script()

library(tarchetypes)
library(geotargets)

tar_option_set(
    packages = c("SSURGO", "soilDB", "duckdb", "DBI",
                 "sf", "units", "future", "future.callr")
)

DESTINATION_DIR <- "data"

tar_source()

future::plan(future.callr::callr)

list(
    tar_target(destdir, DESTINATION_DIR),
    tar_target(ssas, get_area_symbols()),
    tar_target(statesym, get_state_symbols(ssas)),
    tar_target(
        name = ssa,
        command = download_state(statesym, ssas, destdir),
        pattern = map(statesym)
    ),
    tar_files(ssa_files, ssa[!grepl("^Error", ssa)]),
    tar_target(ssurgo_duckdb_path, "data/SSURGO.duckdb"),
    tar_target(ssurgo_create_duckdb, {
        res <- ssa_files
        if (file.exists(ssurgo_duckdb_path)) {
          file.remove(ssurgo_duckdb_path)
        }
        conn <- duckdb_create_connection(ssurgo_duckdb_path)

        res <- soilDB::createSSURGO(
          exdir = DESTINATION_DIR,
          conn = conn,
          maxruledepth = 0,
          include_spatial = c("mupolygon"),
          include_tabular = c("legend", "mapunit", "muaggatt", "component", "coecoclass")
        )
        DBI::dbDisconnect(conn)
        res
    }),
    tar_target(ssurgo_duckdb, {
        list(tables = ssurgo_create_duckdb,
    	       dsn = ssurgo_duckdb_path)
    }),
    tar_files(ssurgo_dsn, {
      ssurgo_duckdb$dsn
    }, cue = targets::tar_cue("never")),
    tar_target(n_mapunit, {
      conn <- duckdb_create_connection(ssurgo_dsn)
      x <- duckdb_query(conn, "SELECT COUNT(DISTINCT mukey) AS n_mapunit FROM mapunit")
      dbDisconnect(conn)
      x$n_mapunit
    }),
    tar_target(n_polygon, {
      conn <- duckdb_create_connection(ssurgo_dsn)
      x <- duckdb_query(conn, "SELECT COUNT(mukey) AS n_polygon FROM mupolygon")
      dbDisconnect(conn)
      x$n_polygon
    }), tar_target(n_mapunit_polygon, {
      conn <- duckdb_create_connection(ssurgo_dsn)
      x <- duckdb_query(conn, "SELECT COUNT(DISTINCT mukey) AS n_mapunit_polygon FROM mupolygon")
      dbDisconnect(conn)
      x$n_mapunit_polygon
    }),
    tar_target(legend, {
      conn <- duckdb_create_connection(ssurgo_dsn)
      x <- duckdb_table(conn, "legend")
      dbDisconnect(conn)
      x
    }),
    tar_target(mapunit, {
      conn <- duckdb_create_connection(ssurgo_dsn)
      x <- duckdb_table(conn, "mapunit")
      dbDisconnect(conn)
      x
    }),
    tar_target(mupolygon_spatial_index, {
      conn <- duckdb_create_connection(ssurgo_dsn)
      duckdb_install_spatial(conn)
      x <- duckdb_create_spatial_index(conn, "mupolygon")
      y <- duckdb_analyze_table(conn, "mupolygon")
      dbDisconnect(conn)
      x
    }),
    tar_files(ssurgo_dsn_indexed, {
      mupolygon_spatial_index
      ssurgo_dsn
    }),
    # # tar_target(mupolygon_area, {
    # #   conn <- duckdb_create_connection(ssurgo_dsn)
    # #   duckdb_install_spatial(conn)
    # #   x <- duckdb_query(
    # #     conn,
    # #     "SELECT mapunit.mukey, mapunit.musym, mapunit.muname,
    # # 		        ST_Area(ST_Transform(geom, 'OGC:CRS84', 'EPSG:5070')) / 4046.86 AS acres
    # # 		 FROM mupolygon
    # #      INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey;"
    # #   )
    # #   DBI::dbDisconnect(conn)
    # #   x
    # # }),
    # # tar_target(mupolygon_vertices, {
    # #   conn <- duckdb_create_connection(ssurgo_dsn)
    # #   duckdb_install_spatial(conn)
    # #   x <- duckdb_query(
    # #     conn,
    # #     "SELECT mapunit.mukey, mapunit.musym, mapunit.muname,
    # # 		        ST_NumPoints(geom) AS vertices
    # # 		 FROM mupolygon
    # #      INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey;"
    # #   )
    # #   DBI::dbDisconnect(conn)
    # #   x
    # # }),
    # # tar_target(missing_mupolygon, {
    # #   conn <- duckdb_create_connection(ssurgo_dsn)
    # #   x <- duckdb_query(
    # #     conn,
    # #     "SELECT legend.areasymbol, areaname,
    # #             mapunit.mukey, mapunit.musym, mapunit.muname
    # # 		FROM mapunit
    # # 		INNER JOIN legend ON legend.lkey = mapunit.lkey
    # #     LEFT JOIN mupolygon ON mapunit.mukey = mupolygon.mukey
    # #     WHERE spatialver IS NULL;"
    # #   )
    # #   dbDisconnect(conn)
    # #   x
    # # }),
    # # tar_target(mukey_acres, {
    # #   aggregate(
    # #     mupolygon_area$acres,
    # #     by = list(mukey = mupolygon_area$mukey),
    # #     sum, na.rm = TRUE
    # #   ) |>
    # #     setNames(c("mukey", "acres"))
    # # }),
    # # tar_target(mapunit_acres, {
    # #   mapunit[c("mukey", "muacres")]
    # # }),
    # # tar_target(acre_compare, {
    # #   merge(
    # #     mapunit_acres,
    # #     mukey_acres,
    # #     by = "mukey",
    # #     all.x = TRUE,
    # #     sort = FALSE
    # #   ) |>
    # #     within({
    # #       acres_round = round(acres)
    # #       legend_missing = is.na(muacres)
    # #       spatial_missing = is.na(acres)
    # #       missing = legend_missing | spatial_missing
    # #       exact = acres_round == muacres
    # #       exact = ifelse(is.na(exact), FALSE, exact)
    # #       thresh = (abs(acres_round != muacres) / acres_round) < 0.1
    # #       thresh = ifelse(is.na(thresh), FALSE, thresh)
    # #     })
    # # }),
    # # tar_target(acres_to_fix, {
    # #   merge(legend[c("lkey", "areasymbol", "areaname", "areaacres")],
    # #         mapunit[c("lkey", "mukey", "musym", "muname")],
    # #         by = "lkey",
    # #         all.x = TRUE,
    # #         sort = FALSE) |>
    # #     merge(
    # #       subset(acre_compare, mukey %in% acre_compare$mukey[!acre_compare$thresh]),
    # #       by = "mukey",
    # #       all.y = TRUE,
    # #       sort = FALSE
    # #     )
    # # }),
    tar_target(spatial_subset, {
      conn <- duckdb_create_connection(ssurgo_dsn)

      b <- c(-119.747629, -119.67935, 36.912019, 36.944987)
      bbox.sp <- sf::st_as_sf(wk::rct(
        xmin = b[1], xmax = b[2], ymin = b[3], ymax = b[4],
        crs = sf::st_crs(4326)
      ))
      duckdb_install_spatial(conn)
      res <- duckdb_spatial_query(conn, "mupolygon", bbox.sp)

      dbDisconnect(conn)
      res
    })#,
    # tar_target(biggest_polygon, {
    #   mupolygon_area_mu <- subset(mupolygon_area, !musym %in% c("NOTCOM", "NOTPUB", "W"))
    #   idx <- which(mupolygon_area_mu$acres == max(mupolygon_area_mu$acres))
    #   conn <- duckdb_create_connection(ssurgo_dsn)
    #   x <- duckdb_sf(conn, "mupolygon", n = 1,
    #                  WHERE = paste0("MUKEY = ", mupolygon_area_mu[idx, 'mukey'],
    #                                 " ORDER BY ST_Area(geom) DESC"))
    #   dbDisconnect(conn)
    #   x
    # }),
    # # tar_target(pointiest_polygon, {
    # #   mupolygon_vert_mu <- subset(mupolygon_vertices, !musym %in% c("NOTCOM", "NOTPUB", "W"))
    # #   idx <- which(mupolygon_vert_mu$vertices == max(mupolygon_vert_mu$vertices))
    # #   conn <- duckdb_create_connection(ssurgo_dsn)
    # #   x <- duckdb_sf(conn, "mupolygon", n = 1,
    # #                  WHERE = paste0("MUKEY = ", mupolygon_vert_mu[idx, 'mukey'],
    # #                                 " ORDER BY ST_NumPoints(geom) DESC"))
    # #   dbDisconnect(conn)
    # #   x
    # # }),
    # # tar_target(pointiest_consociation_polygon, {
    # #   conn <- duckdb_create_connection(ssurgo_dsn)
    # #   x <- duckdb_sf(conn, "mupolygon", n = 1,
    # #                  add_columns = "mapunit.muname",
    # #                  JOIN = "INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey AND mukind = 'Consociation'",
    # #                  WHERE = "muname NOT IN ('Rock outcrop', 'Water', 'Badland')
    # #                           ORDER BY ST_NumPoints(geom) DESC")
    # #   dbDisconnect(conn)
    # #   x
    # # }),
    # # tar_target(pointiest_association_polygon, {
    # #   conn <- duckdb_create_connection(ssurgo_dsn)
    # #   x <- duckdb_sf(conn, "mupolygon", n = 1,
    # #                  add_columns = c("mapunit.muname",
    # #                                  "ST_NumPoints(geom) AS vertices",
    # #                                  "ST_Perimeter(geom) AS perimeter",
    # #                                  "ST_Area_Spheroid(geom) AS area"),
    # #                  JOIN = "INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey AND mukind = 'Association'",
    # #                  WHERE = "vertices > 100
    # #                           ORDER BY perimeter/vertices DESC")
    # #   dbDisconnect(conn)
    # #   x
    # # })
)

}) ## end tar_script()

# targets::tar_make_future(workers = 8)
targets::tar_make()
source("R/target_info.R")

# say hi
# greet_database()
