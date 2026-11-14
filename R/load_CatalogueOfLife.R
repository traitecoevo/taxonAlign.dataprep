# The Catalogue of Life (COL), from ChecklistBank (https://api.checklistbank.org). COL publishes
# monthly releases and an annual one, each a ChecklistBank dataset with its own numeric key (316595 =
# COL26.10, 310463 = COL25); the alias "3LR" always means the latest release. Each monthly release also
# has an Extended Release ("XR", e.g. 316691 = "COL26.10 XR", ~8.5 million names vs ~5.5 million),
# which adds names from further sources; "3LXR" is the latest. The XR is GBIF's taxonomy since rgbif
# 3.9.0 (October 2026), replacing the GBIF Backbone. Named in full (load_CatalogueOfLife(), not
# load_CoL()) at the user's request, 2026-11-14, "so people know". A release's ColDP export
# is prepared by ChecklistBank and downloaded as a zip (~170MB) holding NameUsage.tsv: one row per
# name, with its ID, parentID (for a synonym, its accepted name; for an accepted name, its parent
# taxon), status, rank, scientificName and authorship.

taxonAlign_CoL_api <- "https://api.checklistbank.org"

#' Load the Catalogue of Life
#'
#' Downloads a Catalogue of Life (COL) release from [ChecklistBank](https://api.checklistbank.org) --
#' every name in the COL, of every kingdom, with its accepted name -- and reshapes it into
#' taxonAlign's reference format, ready for [taxonAlign::create_taxonomic_update_lookup()] or
#' [taxonAlign::prepare_taxonomic_resources()]. It's downloaded from ChecklistBank the first time; the
#' download (~170MB) and the reshaped result (~5.5 million names in COL26.10) are cached, so after that
#' it loads from your computer, offline.
#'
#' Name a release to make an alignment reproducible, by its ChecklistBank key (e.g. `316595` for
#' COL26.10, `310463` for the COL25 annual release, `316691` for the COL26.10 Extended Release) or
#' alias (`"COL26.10"`). By default it's the latest release (as of your first download; see `version`).
#'
#' `extended = TRUE` loads the Extended Release instead (~8.5 million names): the COL plus names from
#' further sources, as used by GBIF as its taxonomy. It includes ~2.2 million `"unranked"` barcode
#' clusters -- BOLD Barcode Index Numbers (`"BOLD:AAX6343"`) and UNITE species hypotheses
#' (`"SH1234567.10FU"`) -- kept as they are. Combined with [filter_to_country()], it's what the
#' data releases' `CatalogueOfLife_AU` dataset is built from. `https://api.checklistbank.org/dataset?releasedFrom=3&origin=release`
#' lists every release.
#'
#' Each name becomes one record, read from the release's ColDP `NameUsage.tsv`: `canonical_name` is
#' the scientific name without authorship, and `accepted_name_usage_ID` the record's own ID for an
#' accepted name, or, for a synonym (`"synonym"`, `"ambiguous synonym"`, `"misapplied"`), the ID of
#' its accepted name. COL's `extinct` flag is kept as a logical `extinct` column (taxonAlign's
#' [taxonAlign::load_taxonomic_resources()] leaves extinct taxa out of a released dataset by default). COL's `"provisionally accepted"` names (86,470 in COL26.10) become `"accepted"`:
#' they're the accepted names of their taxa in the COL, and taxonAlign's [taxonAlign::update_taxa()]
#' only reports an accepted name for a record labelled `"accepted"`. A subgenus (COL writes
#' `"Zyras (Craspa)"`) is split into its genus and the bare subgenus name, as taxonAlign's subgenus
#' matching expects, and ranks COL qualifies by code (`"section botany"`, `"series zoology"`) lose the
#' qualifier.
#'
#' @param version The COL release to load: a ChecklistBank dataset key (e.g. `316595`) or alias (e.g.
#'  `"COL26.10"`, `"COL26.10 XR"`). Defaults to the latest release (`"3LR"`, or `"3LXR"` with
#'  `extended = TRUE`): the first time, the latest release is downloaded from ChecklistBank; after that,
#'  that same release is used from the cache, without going online, until you ask for a newer one with
#'  `refresh_cache = TRUE`. A release already downloaded is never downloaded again.
#' @param extended Logical; load the Extended Release (XR) rather than the COL itself. Defaults to
#'  `FALSE`. Ignored when `version` names a release.
#' @param path Optional path to your own copy of a release's ColDP export (the zip, or its
#'  `NameUsage.tsv`), instead of downloading it. `version` is then ignored.
#' @param refresh_cache Logical; if `TRUE`, looks up the latest release online again (for `"3LR"`/`"3LXR"`),
#'  downloading it if it's new, and reshapes the release again. Defaults to `FALSE`.
#' @param cache_dir Directory the download and reshaped result are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A tibble in taxonAlign's reference format (see [taxonAlign::taxonomic_reference_schema()]),
#'  with `taxonomic_dataset = "CatalogueOfLife"`. Its `"version"` attribute is the release's alias (e.g.
#'  `"COL26.10"`), `"key"` its ChecklistBank key, `"doi"` its DOI, and `"citation"` how to cite it.
#'
#' @examples
#' \dontrun{
#' col <- load_CatalogueOfLife(316595)
#' col_xr_au <- load_CatalogueOfLife(extended = TRUE) |> filter_to_country("AU")
#' taxonAlign::create_taxonomic_update_lookup(c("Vanessa cardui", "Cynthia cardui"), col)
#' }
#'
#' @export
load_CatalogueOfLife <- function(version = NULL,
                                 extended = FALSE,
                                 path = NULL,
                                 refresh_cache = FALSE,
                                 cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                 quiet = FALSE) {
  if (is.null(version)) version <- if (isTRUE(extended)) "3LXR" else "3LR"
  if (!is.null(path)) {
    if (!file.exists(path)) stop("Couldn't find the COL export at \"", path, "\".", call. = FALSE)
    file <- path
    info <- file.info(path)
    meta <- list(key = paste0("file_", round(as.numeric(info$size)), "_", round(as.numeric(info$mtime))),
                 alias = NA_character_, doi = NA_character_, citation = NA_character_)
  } else {
    meta <- CoL_release_metadata(version, cache_dir, quiet, refresh_cache)
    file <- file.path(cache_dir, "CoL", meta$key, "coldp.zip")
    if (!quiet && (refresh_cache || !file.exists(file.path(cache_dir, "CoL", paste0("CatalogueOfLife_", meta$key, ".rds"))))) {
      message("Loading and formatting the Catalogue of Life taxonomy is slow the first time you load it ",
              "(a large download, then millions of names to reshape). Be patient and it will arrive ",
              "shortly; after this, it loads from your computer in seconds.")
    }
    # a release never changes once published, so one already downloaded is never downloaded again
    if (!file.exists(file)) {
      download_to_cache(paste0(taxonAlign_CoL_api, "/dataset/", meta$key, "/export.zip?format=ColDP"), file,
                        paste0("the Catalogue of Life release ", meta$alias, " (ChecklistBank key ", meta$key, ")"), quiet)
    }
  }

  # downloads stay in <cache_dir>/CoL/, where load_CoL() kept them; the reshaped result is named anew
  # (its taxonomic_dataset changed from "COL" to "CatalogueOfLife")
  cache_file <- file.path(cache_dir, "CoL", paste0("CatalogueOfLife_", meta$key, ".rds"))
  if (!refresh_cache && file.exists(cache_file)) {
    if (!quiet) message("Using cached Catalogue of Life reference (", meta$alias, ", key ", meta$key, ").")
    return(readRDS(cache_file))
  }

  if (!quiet) message("Reading and reshaping the Catalogue of Life...")
  usage_file <- if (grepl("\\.zip$", file, ignore.case = TRUE)) unz(file, CoL_name_table(file)) else file
  raw <- readr::read_tsv(
    usage_file, quote = "", na = "", progress = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )
  names(raw) <- sub("^col:", "", names(raw))
  reference <- reshape_CatalogueOfLife(raw)
  for (field in c("key", "doi", "citation")) attr(reference, field) <- meta[[field]]
  attr(reference, "version") <- meta$alias
  dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
  saveRDS(reference, cache_file)
  reference
}

# The name table in a ChecklistBank export: NameUsage.tsv in a ColDP export (the base releases), or,
# for an Extended Release, the flat "dataset-<key>.tsv" ChecklistBank serves instead (same `col:`
# columns, plus the classification, but no `extinct` flag) -- found loading COL26.10 XR, 2026-11-14.
#' @noRd
CoL_name_table <- function(zip) {
  files <- utils::unzip(zip, list = TRUE)$Name
  table <- intersect(c("NameUsage.tsv", grep("^dataset-\\d+\\.tsv$", files, value = TRUE)), files)
  if (length(table) == 0) {
    stop("Couldn't find the names in the Catalogue of Life export \"", zip, "\" (no NameUsage.tsv or ",
         "dataset-<key>.tsv). It holds: ", paste(files, collapse = ", "), ".", call. = FALSE)
  }
  table[1]
}

# NameUsage.tsv -> taxonAlign's format.
#' @noRd
reshape_CatalogueOfLife <- function(raw) {
  missing_cols <- setdiff(c("ID", "parentID", "status", "rank", "scientificName", "authorship"), names(raw))
  if (length(missing_cols) > 0) {
    stop("The COL export is missing expected column(s): ", paste(missing_cols, collapse = ", "),
         ". Is it a ColDP export?", call. = FALSE)
  }
  status <- ifelse(raw$status == "provisionally accepted", "accepted", raw$status)
  accepted <- status == "accepted"
  rank <- sub(" (botany|zoology)$", "", raw$rank)
  name <- raw$scientificName
  # genus: the first word of a name at genus rank or below; above genus rank, names are one word
  genus <- ifelse(rank == "genus" | grepl("\\s", name), extract_genus(name), NA_character_)
  # a subgenus, "Zyras (Craspa)" -> "Craspa" (its genus kept in `genus`)
  subgenus <- rank == "subgenus"
  name[subgenus] <- stringr::str_replace(name[subgenus], "^\\S+\\s+\\(([^()]+)\\)$", "\\1")
  out <- dplyr::tibble(
    canonical_name = name,
    scientific_name = stringr::str_squish(paste(raw$scientificName, dplyr::coalesce(raw$authorship, ""))),
    taxon_rank = rank,
    taxonomic_status = status,
    taxonomic_dataset = "CatalogueOfLife",
    genus = genus,
    taxon_ID = raw$ID,
    accepted_name_usage_ID = ifelse(accepted | is.na(raw$parentID), raw$ID, raw$parentID)
  )
  if ("extinct" %in% names(raw)) {
    flag <- tolower(raw$extinct)
    out$extinct <- dplyr::case_when(flag %in% c("true", "t", "1") ~ TRUE, flag %in% c("false", "f", "0") ~ FALSE)
  }
  out
}

# The release `version` names (key, alias, DOI, citation), from ChecklistBank, cached alongside the
# download as <cache_dir>/CoL/<key>/metadata.rds; `latest.rds` records which key "3LR" meant when it
# was last looked up online. Offline (with refresh_cache = TRUE, or a release not yet downloaded), an
# alias is looked up among the releases already downloaded ("3LR": the newest).
#' @noRd
CoL_release_metadata <- function(version, cache_dir, quiet, refresh_cache = FALSE) {
  version <- as.character(version)
  dir <- file.path(cache_dir, "CoL")
  cached_meta <- function() {
    files <- list.files(dir, pattern = "^metadata\\.rds$", recursive = TRUE, full.names = TRUE)
    metas <- lapply(files, readRDS)
    metas[order(vapply(metas, function(m) m$issued %||% "", character(1)), decreasing = TRUE)]
  }
  # a release already downloaded is used without going online -- by key, by alias, or, for "3LR", the
  # latest release (or latest XR, "3LXR") as it was when first downloaded (user's requirement, 2026-10-22: download from
  # ChecklistBank the first time, use the cached copy after that); `refresh_cache = TRUE` looks "3LR" up
  # online again
  if (grepl("^\\d+$", version) && file.exists(file.path(dir, version, "metadata.rds"))) {
    return(readRDS(file.path(dir, version, "metadata.rds")))
  }
  # which key each "latest" alias meant when last looked up online
  latest <- version %in% c("3LR", "3LXR")
  latest_file <- file.path(dir, if (version == "3LXR") "latest_XR.rds" else "latest.rds")
  if (!refresh_cache) {
    if (latest && file.exists(latest_file) &&
        file.exists(file.path(dir, readRDS(latest_file), "metadata.rds"))) {
      meta <- readRDS(file.path(dir, readRDS(latest_file), "metadata.rds"))
      if (!quiet) message("Using Catalogue of Life release ", meta$alias, " (ChecklistBank key ", meta$key,
                          "). To check for a newer release, use `refresh_cache = TRUE`.")
      return(meta)
    }
    by_alias <- Filter(function(m) identical(m$alias, version), cached_meta())
    if (length(by_alias) > 0) return(by_alias[[1]])
  }

  response <- try_fetch(paste0(taxonAlign_CoL_api, "/dataset/", utils::URLencode(version, reserved = TRUE)))
  if (is.null(response)) {
    metas <- cached_meta()
    is_xr <- function(m) grepl("XR$", m$alias %||% "")
    hit <- if (latest) Filter(function(m) is_xr(m) == (version == "3LXR"), metas)[1] else Filter(function(m) identical(m$alias, version) || identical(m$key, version), metas)
    if (length(hit) > 0 && !is.null(hit[[1]])) {
      if (!quiet && latest) message("Couldn't reach ChecklistBank; using the most recent Catalogue of Life release already downloaded, ", hit[[1]]$alias, ".")
      return(hit[[1]])
    }
    stop("Couldn't reach ChecklistBank to look up Catalogue of Life release \"", version, "\", and it isn't ",
         "cached. Check that you're online, and that the release exists (", taxonAlign_CoL_api,
         "/dataset?releasedFrom=3&origin=release lists them).", call. = FALSE)
  }
  d <- jsonlite::fromJSON(rawToChar(response$content))
  if (!identical(as.character(d$sourceKey), "3") && !identical(as.character(d$key), "3")) {
    stop("ChecklistBank dataset \"", version, "\" isn't a Catalogue of Life release (it's \"", d$title, "\").", call. = FALSE)
  }
  meta <- list(
    key = as.character(d$key), alias = d$alias %||% as.character(d$key), version = d$version %||% NA_character_,
    issued = d$issued %||% NA_character_, doi = d$doi %||% NA_character_,
    citation = format_CoL_citation(d)
  )
  dir.create(file.path(dir, meta$key), recursive = TRUE, showWarnings = FALSE)
  saveRDS(meta, file.path(dir, meta$key, "metadata.rds"))
  if (latest) {
    if (!quiet && refresh_cache) message("The latest Catalogue of Life release is ", meta$alias, " (ChecklistBank key ", meta$key, ").")
    saveRDS(meta$key, latest_file)
  }
  meta
}

# The release's citation, in the form ChecklistBank gives it as HTML ("Bánki, O., Roskov, Y., ... et al.
# (2026). Catalogue of Life (Version 2026-10-14). Catalogue of Life Foundation, Amsterdam, Netherlands.
# https://doi.org/..."), built from the metadata's own fields as plain text.
#' @noRd
format_CoL_citation <- function(d) {
  creators <- d$creator
  authors <- if (is.data.frame(creators) && nrow(creators) > 0) {
    initials <- vapply(strsplit(dplyr::coalesce(creators$given, ""), "[ -]+"), function(g) {
      paste0(substr(g[nzchar(g)], 1, 1), ".", collapse = " ")
    }, character(1))
    people <- ifelse(nzchar(initials) & initials != ".", paste0(creators$family, ", ", initials), creators$family)
    if (length(people) > 20) paste0(paste(people[1:19], collapse = ", "), ", et al.") else paste(people, collapse = ", ")
  }
  year <- substr(d$issued %||% "", 1, 4)
  publisher <- d$publisher
  where <- if (is.list(publisher)) paste(c(publisher$name, publisher$address), collapse = ", ")
  paste0(
    if (!is.null(authors)) paste0(authors, " "), if (nzchar(year)) paste0("(", year, "). "),
    d$title %||% "Catalogue of Life", if (!is.null(d$version)) paste0(" (Version ", d$version, ")"), ". ",
    if (length(where) > 0 && nzchar(where)) paste0(where, ". "),
    if (!is.null(d$doi)) paste0("https://doi.org/", d$doi)
  )
}
