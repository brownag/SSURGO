library(targets)
library(tarchetypes)
library(geotargets)
tar_option_set(packages = c("soilDB", "duckdb", "sf", "units"))
tar_source()
list(tar_target(statesym, "CA"), tar_target(name = ssas, command = soilDB::SDA_query(sprintf("SELECT DISTINCT areasymbol FROM sacatalog\n             WHERE areasymbol LIKE '%s%%'", 
    statesym))[[1]]), tar_target(name = ssa, command = download_ssurgo(ssas), 
    pattern = map(ssas)), tar_files(ssa_files, file.path("data", 
    list.files("data", pattern = paste0(statesym, "\\d+{3}"), 
        recursive = TRUE))), tar_target(ssurgo_duckdb_path, "data/SSURGO.duckdb"), 
    tar_target(ssurgo_create_duckdb, {
        res <- ssa_files
        if (file.exists(ssurgo_duckdb_path)) {
            file.remove(ssurgo_duckdb_path)
        }
        conn <- duckdb_create_connection(ssurgo_duckdb_path)
        res <- soilDB::createSSURGO(exdir = "data", conn = conn, 
            maxruledepth = 0, include_spatial = c("mupolygon"), 
            include_tabular = c("legend", "mapunit", "muaggatt", 
                "component", "coecoclass"))
        dbDisconnect(conn)
        res
    }), tar_target(ssurgo_duckdb, {
        list(tables = ssurgo_create_duckdb, dsn = ssurgo_duckdb_path)
    }), tar_files(ssurgo_dsn, {
        ssurgo_duckdb$dsn
    }), tar_target(n_mapunit, {
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
    }), tar_target(mupolygon_area, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        duckdb_install_spatial(conn)
        x <- duckdb_query(conn, "SELECT mapunit.mukey, mapunit.musym, mapunit.muname,\n    \t\t        ST_Area(ST_Transform(geom, 'OGC:CRS84', 'EPSG:5070')) / 4046.86 AS acres\n    \t\t FROM mupolygon\n         INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey;")
        DBI::dbDisconnect(conn)
        x
    }), tar_target(mupolygon_vertices, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        duckdb_install_spatial(conn)
        x <- duckdb_query(conn, "SELECT mapunit.mukey, mapunit.musym, mapunit.muname,\n    \t\t        ST_NumPoints(geom) AS vertices\n    \t\t FROM mupolygon\n         INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey;")
        DBI::dbDisconnect(conn)
        x
    }), tar_target(missing_mupolygon, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_query(conn, "SELECT legend.areasymbol, areaname,\n                mapunit.mukey, mapunit.musym, mapunit.muname\n    \t\tFROM mapunit\n    \t\tINNER JOIN legend ON legend.lkey = mapunit.lkey\n        LEFT JOIN mupolygon ON mapunit.mukey = mupolygon.mukey\n        WHERE spatialver IS NULL;")
        dbDisconnect(conn)
        x
    }), tar_target(mukey_acres, {
        setNames(aggregate(mupolygon_area$acres, by = list(mukey = mupolygon_area$mukey), 
            sum, na.rm = TRUE), c("mukey", "acres"))
    }), tar_target(mapunit_acres, {
        mapunit[c("mukey", "muacres")]
    }), tar_target(acre_compare, {
        within(merge(mapunit_acres, mukey_acres, by = "mukey", 
            all.x = TRUE, sort = FALSE), {
            acres_round = round(acres)
            legend_missing = is.na(muacres)
            spatial_missing = is.na(acres)
            missing = legend_missing | spatial_missing
            exact = acres_round == muacres
            exact = ifelse(is.na(exact), FALSE, exact)
            thresh = (abs(acres_round != muacres)/acres_round) < 
                0.1
            thresh = ifelse(is.na(thresh), FALSE, thresh)
        })
    }), tar_target(acres_to_fix, {
        merge(merge(legend[c("lkey", "areasymbol", "areaname", 
            "areaacres")], mapunit[c("lkey", "mukey", "musym", 
            "muname")], by = "lkey", all.x = TRUE, sort = FALSE), 
            subset(acre_compare, mukey %in% acre_compare$mukey[!acre_compare$thresh]), 
            by = "mukey", all.y = TRUE, sort = FALSE)
    }), tar_target(spatial_subset, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        b <- c(-119.747629, -119.67935, 36.912019, 36.944987)
        bbox.sp <- sf::st_as_sf(wk::rct(xmin = b[1], xmax = b[2], 
            ymin = b[3], ymax = b[4], crs = sf::st_crs(4326)))
        res <- duckdb_spatial_query(conn, "mupolygon", bbox.sp)
        dbDisconnect(conn)
        res
    }), tar_target(biggest_polygon, {
        mupolygon_area_mu <- subset(mupolygon_area, !musym %in% 
            c("NOTCOM", "NOTPUB", "W"))
        idx <- which(mupolygon_area_mu$acres == max(mupolygon_area_mu$acres))
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_sf(conn, "mupolygon", n = 1, WHERE = paste0("MUKEY = ", 
            mupolygon_area_mu[idx, "mukey"], " ORDER BY ST_Area(geom) DESC"))
        dbDisconnect(conn)
        x
    }), tar_target(pointiest_polygon, {
        mupolygon_vert_mu <- subset(mupolygon_vertices, !musym %in% 
            c("NOTCOM", "NOTPUB", "W"))
        idx <- which(mupolygon_vert_mu$vertices == max(mupolygon_vert_mu$vertices))
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_sf(conn, "mupolygon", n = 1, WHERE = paste0("MUKEY = ", 
            mupolygon_vert_mu[idx, "mukey"], " ORDER BY ST_NumPoints(geom) DESC"))
        dbDisconnect(conn)
        x
    }), tar_target(pointiest_consociation_polygon, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_sf(conn, "mupolygon", n = 1, add_columns = "mapunit.muname", 
            JOIN = "INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey AND mukind = 'Consociation'", 
            WHERE = "muname NOT IN ('Rock outcrop', 'Water', 'Badland')\n                              ORDER BY ST_NumPoints(geom) DESC")
        dbDisconnect(conn)
        x
    }), tar_target(pointiest_association_polygon, {
        conn <- duckdb_create_connection(ssurgo_dsn)
        x <- duckdb_sf(conn, "mupolygon", n = 1, add_columns = c("mapunit.muname", 
            "ST_NumPoints(geom) AS vertices", "ST_Perimeter(geom) AS perimeter", 
            "ST_Area_Spheroid(geom) AS area"), JOIN = "INNER JOIN mapunit ON mapunit.mukey = mupolygon.mukey AND mukind = 'Association'", 
            WHERE = "vertices > 100\n                              ORDER BY perimeter/vertices DESC")
        dbDisconnect(conn)
        x
    }))
