#' Download Soil Survey Area Data from Web Soil Survey
#'
#' @param areasymbol _character_. Soil Survey Area Symbol. e.g. `"RI600"`
#' @param destdir _character_. Path where ZIP files will be downloaded and extracted to.
#'
#' @return _character_. Path to downloaded ZIP file, with SHA1 hash of ZIP contents as attribute name `"sha1"`
#' @export
#' @examples
#'
#' download_ssurgo("CA630")
#'
download_ssurgo <- function(areasymbol, destdir = "data") {
    stopifnot(length(areasymbol) == 1)
    message(areasymbol)
    options(soilDB.timeout=3000)
    x <- try(soilDB::downloadSSURGO(areasymbols = areasymbol,
                                    destdir = file.path(destdir, areasymbol)))
    if (inherits(x, 'try-error')) {
        x <- x[1]
        attr(x, "sha1") <- NA
    } else {
        attr(x, "sha1") <- digest::sha1(readBin(x, "raw"))
    }
    x
}
