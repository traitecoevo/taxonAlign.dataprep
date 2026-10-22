# The World Checklist of Vascular Plants (WCVP), Royal Botanic Gardens, Kew -- every vascular plant
# name worldwide (~1.45 million in version 16), with accepted names, synonyms and Kew's other name
# statuses. Kew publishes the current version as one zip (`wcvp.zip`) and moves each superseded
# version to an archive (`Archive/wcvp_v<N>.zip`); the zip's `README_WCVP.xlsx` names its version.

taxonAlign_WCVP_url <- "https://sftp.kew.org/pub/data-repositories/WCVP/"

# WCVP taxon_status values, as taxonAlign statuses. Kept as Kew labels them (lower case), except
# "Orthographic", taxonAlign's "orthographic variant". "Artificial Hybrid" and "Local Biotype" are
# names of their own, not synonyms (each is self-referential in the data), and "Unplaced" names have no
# accepted name; none of these three is "accepted", so update_taxa() never reports an accepted name for
# them (or for the few synonyms that lead to them).
taxonAlign_WCVP_status <- c(
  Accepted = "accepted", Synonym = "synonym", Illegitimate = "illegitimate", Invalid = "invalid",
  Unplaced = "unplaced", Orthographic = "orthographic variant", Misapplied = "misapplied",
  `Artificial Hybrid` = "artificial hybrid", `Local Biotype` = "local biotype"
)

#' Load the World Checklist of Vascular Plants
#'
#' Downloads the World Checklist of Vascular Plants (WCVP; Royal Botanic Gardens, Kew) -- every
#' vascular plant name worldwide, with its accepted name -- and reshapes it into taxonAlign's
#' reference format, ready for [taxonAlign::create_taxonomic_update_lookup()] or
#' [taxonAlign::prepare_taxonomic_resources()]. It's downloaded from Kew the first time; the download
#' (~90MB) and the reshaped result are cached, so after that it loads from your computer, offline.
#'
#' Each name in `wcvp_names.csv` becomes one record: `canonical_name` is WCVP's `taxon_name`,
#' `scientific_name` adds `taxon_authors`, and `accepted_name_usage_ID` is `accepted_plant_name_id`
#' (or the record's own ID, for an accepted name or one with no accepted name, such as an unplaced
#' name). Statuses keep Kew's labels, in lower case (`"accepted"`, `"synonym"`, `"illegitimate"`,
#' `"invalid"`, `"unplaced"`, `"misapplied"`, `"artificial hybrid"`, `"local biotype"`), except
#' `"Orthographic"`, which becomes `"orthographic variant"`. The `family` column is kept, so
#' taxonAlign adds a family-rank record for each family (WCVP has no family records of its own). The
#' 2,744 names with no rank in version 16 (infraspecific names written without a rank marker, such as
#' *Aquilegia vulgaris inversa*) get the rank `"infraspecific name"`. Distribution data
#' (`wcvp_distribution.csv`) isn't read.
#'
#' @param version WCVP version number to load, e.g. `16`. Defaults to the current version: the first
#'  time, the current version is downloaded from Kew; after that, that same version is used from the
#'  cache, without going online, until you ask for a newer one with `refresh_cache = TRUE`. A named
#'  version is downloaded only if it isn't already cached.
#' @param path Optional path to your own copy of `wcvp.zip` (or of `wcvp_names.csv`), instead of
#'  downloading it. `version` is then ignored.
#' @param refresh_cache Logical; if `TRUE`, checks Kew for a newer current version (when `version` isn't
#'  given), downloading it if there is one, and reshapes the file again. Defaults to `FALSE`.
#' @param cache_dir Directory the download and reshaped result are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A tibble in taxonAlign's reference format (see [taxonAlign::taxonomic_reference_schema()]),
#'  with `taxonomic_dataset = "WCVP"` and a `family` column. Its `"version"` attribute is the WCVP
#'  version, and its `"citation"` attribute how Kew asks for it to be cited.
#'
#' @examples
#' \dontrun{
#' wcvp <- load_WCVP()
#' taxonAlign::create_taxonomic_update_lookup(c("Eucalyptus globulus", "Acacia dealbata"), wcvp)
#' }
#'
#' @export
load_WCVP <- function(version = NULL,
                      path = NULL,
                      refresh_cache = FALSE,
                      cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                      quiet = FALSE) {
  if (!is.null(path)) {
    if (!file.exists(path)) stop("Couldn't find the WCVP file at \"", path, "\".", call. = FALSE)
    file <- path
    info <- file.info(path)
    key <- paste0("file_", round(as.numeric(info$size)), "_", round(as.numeric(info$mtime)))
  } else {
    file <- get_WCVP_zip(version, refresh_cache, cache_dir, quiet)
    key <- paste0("v", attr(file, "version"))
  }

  cache_file <- file.path(cache_dir, "WCVP", paste0("WCVP_", key, ".rds"))
  if (!refresh_cache && file.exists(cache_file)) {
    if (!quiet) message("Using cached WCVP reference (", key, ").")
    return(readRDS(cache_file))
  }

  if (!quiet) message("Reading and reshaping the WCVP (~1.5 million names) -- slow the first time you load it; ",
                      "after this, it loads from your computer in seconds.")
  names_file <- if (grepl("\\.zip$", file, ignore.case = TRUE)) unz(file, "wcvp_names.csv") else file
  raw <- readr::read_delim(
    names_file, delim = "|", quote = "", na = "", progress = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )
  readme <- if (grepl("\\.zip$", file, ignore.case = TRUE)) WCVP_zip_readme(file) else list(version = NA_character_, citation = NA_character_)
  reference <- reshape_WCVP(raw)
  attr(reference, "version") <- readme$version
  # as the README asks: the dataset itself, and the paper describing it
  attr(reference, "citation") <- paste(c(
    readme$citation,
    paste("Govaerts, R., Nic Lughadha, E. et al. The World Checklist of Vascular Plants, a continuously",
          "updated resource for exploring global plant diversity. Sci Data 8, 215 (2021).",
          "https://doi.org/10.1038/s41597-021-00997-6")
  )[!is.na(c(readme$citation, ""))], collapse = " ")
  dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
  saveRDS(reference, cache_file)
  reference
}

# wcvp_names.csv -> taxonAlign's format.
#' @noRd
reshape_WCVP <- function(raw) {
  unknown <- setdiff(unique(raw$taxon_status), names(taxonAlign_WCVP_status))
  if (length(unknown) > 0) {
    stop("The WCVP has status(es) load_WCVP() doesn't know: ", paste(unknown, collapse = ", "),
         ". Add them to taxonAlign_WCVP_status.", call. = FALSE)
  }
  # the genus as written in the names themselves, hybrid sign included ("× Cleisocalpa"), so it lines up
  # with the genus-rank records' own names
  genus <- stringr::str_squish(paste(dplyr::coalesce(raw$genus_hybrid, ""), dplyr::coalesce(raw$genus, "")))
  dplyr::tibble(
    canonical_name = raw$taxon_name,
    scientific_name = stringr::str_squish(paste(raw$taxon_name, dplyr::coalesce(raw$taxon_authors, ""))),
    taxon_rank = dplyr::coalesce(tolower(raw$taxon_rank), "infraspecific name"),
    taxonomic_status = unname(taxonAlign_WCVP_status[raw$taxon_status]),
    taxonomic_dataset = "WCVP",
    genus = dplyr::na_if(genus, ""),
    taxon_ID = raw$plant_name_id,
    accepted_name_usage_ID = dplyr::coalesce(raw$accepted_plant_name_id, raw$plant_name_id),
    family = raw$family
  )
}

# Local path to the WCVP zip for `version` (or the current one), downloading it if it isn't cached.
# Cached as <cache_dir>/WCVP/wcvp_v<N>.zip. With no `version`, the first call downloads Kew's current
# version and records it in `current.dcf` (version, Last-Modified, download date); later calls use it
# without going online (user's requirement, 2026-10-22). `refresh_cache = TRUE` checks Kew's
# Last-Modified date, downloading again only if Kew has published a new version.
#' @noRd
get_WCVP_zip <- function(version, refresh_cache, cache_dir, quiet, check_online = FALSE) {
  dir <- file.path(cache_dir, "WCVP")
  cached <- function(v) file.path(dir, paste0("wcvp_v", v, ".zip"))
  found <- function(file, v) structure(file, version = as.character(v))

  if (!is.null(version)) {
    version <- as.character(version)
    if (!refresh_cache && file.exists(cached(version))) return(found(cached(version), version))
    # a superseded version is in the archive; the current one isn't yet
    archived <- tryCatch(
      download_to_cache(paste0(taxonAlign_WCVP_url, "Archive/wcvp_v", version, ".zip"), cached(version),
                        paste("WCVP version", version), quiet = TRUE),
      error = function(e) NULL
    )
    if (!is.null(archived)) return(found(archived, version))
    current <- get_WCVP_zip(NULL, refresh_cache, cache_dir, quiet, check_online = TRUE)
    if (identical(attr(current, "version"), version)) return(current)
    stop("Couldn't find WCVP version ", version, " (the current version is ", attr(current, "version"),
         "; older ones are at ", taxonAlign_WCVP_url, "Archive/).", call. = FALSE)
  }

  state_file <- file.path(dir, "current.dcf")
  state <- if (file.exists(state_file)) as.list(read.dcf(state_file)[1, ]) else NULL
  # once a current version has been downloaded, it's used from then on without going online; only
  # `refresh_cache = TRUE` (or asking for a version not yet downloaded) checks Kew for a newer one
  if (!refresh_cache && !check_online && !is.null(state) && file.exists(cached(state$version))) {
    if (!quiet) message("Using WCVP version ", state$version, ", downloaded ", state$downloaded %||% "earlier",
                        ". To check for a newer version, use `refresh_cache = TRUE`.")
    return(found(cached(state$version), state$version))
  }
  head <- try_fetch(paste0(taxonAlign_WCVP_url, "wcvp.zip"), nobody = TRUE)
  if (is.null(head)) {
    if (!is.null(state) && file.exists(cached(state$version))) {
      if (!quiet) message("Couldn't reach Kew; using the most recent WCVP version already downloaded, ", state$version, ".")
      return(found(cached(state$version), state$version))
    }
    stop("Couldn't reach Kew to download the WCVP, and no version is cached. Check that you're online.", call. = FALSE)
  }
  modified <- curl::parse_headers_list(head$headers)[["last-modified"]]
  # unchanged since it was downloaded: no need to download it again
  if (!is.null(state) && identical(state$modified, modified) && file.exists(cached(state$version))) {
    if (!quiet && refresh_cache) message("WCVP version ", state$version, " is still the current version.")
    return(found(cached(state$version), state$version))
  }
  tmp <- download_to_cache(paste0(taxonAlign_WCVP_url, "wcvp.zip"), file.path(dir, "wcvp_current.zip"),
                           "the current WCVP", quiet)
  v <- WCVP_zip_readme(tmp)$version
  if (is.na(v)) stop("Couldn't tell which WCVP version Kew's current download is.", call. = FALSE)
  file.rename(tmp, cached(v))
  write.dcf(data.frame(version = v, modified = modified, downloaded = format(Sys.Date())), state_file)
  found(cached(v), v)
}

# What a WCVP zip's README_WCVP.xlsx says about it: its version ('Version "16"') and how to cite it
# ("Govaerts R (ed.). 2026. WCVP: ..."), each NA if not found.
#' @noRd
WCVP_zip_readme <- function(zip) {
  none <- list(version = NA_character_, citation = NA_character_)
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  readme <- tryCatch(utils::unzip(zip, "README_WCVP.xlsx", exdir = dir), error = function(e) character(0), warning = function(w) character(0))
  if (length(readme) == 0) return(none)
  xml <- tryCatch({
    utils::unzip(readme, "xl/sharedStrings.xml", exdir = dir)
    paste(readLines(file.path(dir, "xl", "sharedStrings.xml"), warn = FALSE, encoding = "UTF-8"), collapse = "")
  }, error = function(e) "", warning = function(w) "")
  strings <- stringr::str_match_all(xml, "<t[^>]*>([^<]*)</t>")[[1]][, 2]
  strings <- stringr::str_squish(gsub("&quot;", "\"", gsub("&amp;", "&", strings, fixed = TRUE), fixed = TRUE))
  version <- stringr::str_match(strings, '^Version "(\\d+)"$')[, 2]
  citation <- strings[grepl("^Govaerts R \\(ed\\.\\)", strings)]
  list(
    version = if (any(!is.na(version))) version[!is.na(version)][1] else NA_character_,
    citation = if (length(citation) > 0) citation[1] else NA_character_
  )
}
