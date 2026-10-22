# The Catalogue of Life (COL), from ChecklistBank (https://api.checklistbank.org). COL publishes
# monthly releases and an annual one, each a ChecklistBank dataset with its own numeric key (316595 =
# COL26.10, 310463 = COL25); the alias "3LR" always means the latest release. A release's ColDP export
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
#' COL26.10, `310463` for the COL25 annual release) or alias (`"COL26.10"`). The default, `"3LR"`,
#' is the latest release (as of your first download; see `version`). `https://api.checklistbank.org/dataset?releasedFrom=3&origin=release`
#' lists every release.
#'
#' Each name becomes one record, read from the release's ColDP `NameUsage.tsv`: `canonical_name` is
#' the scientific name without authorship, and `accepted_name_usage_ID` the record's own ID for an
#' accepted name, or, for a synonym (`"synonym"`, `"ambiguous synonym"`, `"misapplied"`), the ID of
#' its accepted name. COL's `"provisionally accepted"` names (86,470 in COL26.10) become `"accepted"`:
#' they're the accepted names of their taxa in the COL, and taxonAlign's [taxonAlign::update_taxa()]
#' only reports an accepted name for a record labelled `"accepted"`. A subgenus (COL writes
#' `"Zyras (Craspa)"`) is split into its genus and the bare subgenus name, as taxonAlign's subgenus
#' matching expects, and ranks COL qualifies by code (`"section botany"`, `"series zoology"`) lose the
#' qualifier.
#'
#' @param version The COL release to load: a ChecklistBank dataset key (e.g. `316595`) or alias (e.g.
#'  `"COL26.10"`). Defaults to `"3LR"`, the latest release: the first time, the latest release is
#'  downloaded from ChecklistBank; after that, that same release is used from the cache, without going
#'  online, until you ask for a newer one with `refresh_cache = TRUE`. A release already downloaded is
#'  never downloaded again.
#' @param path Optional path to your own copy of a release's ColDP export (the zip, or its
#'  `NameUsage.tsv`), instead of downloading it. `version` is then ignored.
#' @param refresh_cache Logical; if `TRUE`, looks up the latest release online again (for `"3LR"`),
#'  downloading it if it's new, and reshapes the release again. Defaults to `FALSE`.
#' @param cache_dir Directory the download and reshaped result are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A tibble in taxonAlign's reference format (see [taxonAlign::taxonomic_reference_schema()]),
#'  with `taxonomic_dataset = "COL"`. Its `"version"` attribute is the release's alias (e.g.
#'  `"COL26.10"`), `"key"` its ChecklistBank key, `"doi"` its DOI, and `"citation"` how to cite it.
#'
#' @examples
#' \dontrun{
#' col <- load_CoL(316595)
#' taxonAlign::create_taxonomic_update_lookup(c("Vanessa cardui", "Cynthia cardui"), col)
#' }
#'
#' @export
load_CoL <- function(version = "3LR",
                     path = NULL,
                     refresh_cache = FALSE,
                     cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                     quiet = FALSE) {
  if (!is.null(path)) {
    if (!file.exists(path)) stop("Couldn't find the COL export at \"", path, "\".", call. = FALSE)
    file <- path
    info <- file.info(path)
    meta <- list(key = paste0("file_", round(as.numeric(info$size)), "_", round(as.numeric(info$mtime))),
                 alias = NA_character_, doi = NA_character_, citation = NA_character_)
  } else {
    meta <- CoL_release_metadata(version, cache_dir, quiet, refresh_cache)
    file <- file.path(cache_dir, "CoL", meta$key, "coldp.zip")
    if (!quiet && (refresh_cache || !file.exists(file.path(cache_dir, "CoL", paste0("CoL_", meta$key, ".rds"))))) {
      message("Loading and formatting the Catalogue of Life taxonomy is slow the first time you load it ",
              "(a ~170MB download, then ~5.5 million names to reshape). Be patient and it will arrive ",
              "shortly; after this, it loads from your computer in seconds.")
    }
    # a release never changes once published, so one already downloaded is never downloaded again
    if (!file.exists(file)) {
      download_to_cache(paste0(taxonAlign_CoL_api, "/dataset/", meta$key, "/export.zip?format=ColDP"), file,
                        paste0("the Catalogue of Life release ", meta$alias, " (ChecklistBank key ", meta$key, ")"), quiet)
    }
  }

  cache_file <- file.path(cache_dir, "CoL", paste0("CoL_", meta$key, ".rds"))
  if (!refresh_cache && file.exists(cache_file)) {
    if (!quiet) message("Using cached Catalogue of Life reference (", meta$alias, ", key ", meta$key, ").")
    return(readRDS(cache_file))
  }

  if (!quiet) message("Reading and reshaping the Catalogue of Life...")
  usage_file <- if (grepl("\\.zip$", file, ignore.case = TRUE)) unz(file, "NameUsage.tsv") else file
  raw <- readr::read_tsv(
    usage_file, quote = "", na = "", progress = FALSE,
    col_types = readr::cols(.default = readr::col_character())
  )
  names(raw) <- sub("^col:", "", names(raw))
  reference <- reshape_CoL(raw)
  for (field in c("key", "doi", "citation")) attr(reference, field) <- meta[[field]]
  attr(reference, "version") <- meta$alias
  dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
  saveRDS(reference, cache_file)
  reference
}

# NameUsage.tsv -> taxonAlign's format.
#' @noRd
reshape_CoL <- function(raw) {
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
  dplyr::tibble(
    canonical_name = name,
    scientific_name = stringr::str_squish(paste(raw$scientificName, dplyr::coalesce(raw$authorship, ""))),
    taxon_rank = rank,
    taxonomic_status = status,
    taxonomic_dataset = "COL",
    genus = genus,
    taxon_ID = raw$ID,
    accepted_name_usage_ID = ifelse(accepted | is.na(raw$parentID), raw$ID, raw$parentID)
  )
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
  # latest release as it was when first downloaded (user's requirement, 2026-10-22: download from
  # ChecklistBank the first time, use the cached copy after that); `refresh_cache = TRUE` looks "3LR" up
  # online again
  if (grepl("^\\d+$", version) && file.exists(file.path(dir, version, "metadata.rds"))) {
    return(readRDS(file.path(dir, version, "metadata.rds")))
  }
  latest_file <- file.path(dir, "latest.rds")
  if (!refresh_cache) {
    if (version == "3LR" && file.exists(latest_file) &&
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
    hit <- if (version == "3LR") metas[1] else Filter(function(m) identical(m$alias, version) || identical(m$key, version), metas)
    if (length(hit) > 0 && !is.null(hit[[1]])) {
      if (!quiet && version == "3LR") message("Couldn't reach ChecklistBank; using the most recent Catalogue of Life release already downloaded, ", hit[[1]]$alias, ".")
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
  if (version == "3LR") {
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
