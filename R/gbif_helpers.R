# What filter_to_country() needs from GBIF: resolving a taxon name to a key, and retrying calls.
#
# GBIF's taxonomy is the Catalogue of Life Extended Release (COL XR) -- the default in rgbif from 3.9.0
# (October 2026), replacing the GBIF Backbone Taxonomy, which GBIF now describes as out of date. Keys
# are alphanumeric ("TP" for Tracheophyta, "N" for Animalia), not the Backbone's integers. The
# checklist is named explicitly in every call, so results are the same under rgbif 3.8.5, which
# defaulted to the Backbone (checked live under both). taxonAlign.dataprep#1: under rgbif 3.9.0 the
# Backbone code turned "TP" into an NA key, queried GBIF with no taxon, and cached the empty result.
# The Backbone-based reference builders (generate_GBIF_taxonomic_reference_list(),
# generate_taxadb_taxonomic_reference_list()) were removed then, replaced by load_CatalogueOfLife(
# extended = TRUE) |> filter_to_country().
gbif_COL_XR_checklist_key <- "7ddf754f-d193-4cc9-b351-99906754a03b"

# `timeout = 120`: GBIF's occurrence facet queries over a large clade can take well over a minute.
gbif_curlopts <- list(http_version = 2, timeout = 120)

# Retries `thunk()` (a zero-argument function, so each attempt really re-executes the call) up to
# `max_attempts` times with a short backoff -- GBIF calls can hit a transient network/TLS/timeout issue.
with_gbif_retry <- function(thunk, max_attempts = 3) {
  for (attempt in seq_len(max_attempts)) {
    result <- try(thunk(), silent = TRUE)
    if (!inherits(result, "try-error")) return(result)
    if (attempt < max_attempts) Sys.sleep(2 * attempt)
  }
  stop(attr(result, "condition")$message, call. = FALSE)
}

# Resolves a taxon name (of any rank) to its key in GBIF's taxonomy (COL XR), following a synonym to
# its accepted name. Errors rather than carrying on with a key that would make GBIF search everything.
#' @noRd
resolve_gbif_taxon <- function(taxon_name, name_rank, name_kingdom) {
  match <- with_gbif_retry(function() {
    rgbif::name_backbone(
      name = taxon_name, rank = name_rank, kingdom = name_kingdom, verbose = FALSE,
      checklistKey = gbif_COL_XR_checklist_key, curlopts = gbif_curlopts
    )
  })

  if (is.null(match) || nrow(match) == 0 || isTRUE(match$matchType == "NONE")) {
    # a homonym across kingdoms (e.g. the plant and bird genera both named *Eremophila*) lands here,
    # and GBIF explains why in `note`
    note <- if ("note" %in% names(match) && length(match$note) == 1 && !is.na(match$note)) {
      paste0(" (", match$note, ")")
    } else {
      ""
    }
    stop(
      "Could not match `gbif_taxon` = \"", taxon_name, "\" to a taxon in GBIF's taxonomy", note, ". ",
      "If this name is a homonym, try passing `gbif_taxon_rank` and/or `gbif_kingdom` to disambiguate.",
      call. = FALSE
    )
  }

  # GBIF backs off to a broader rank ("HIGHERRANK") when it can't place a name -- carrying on would
  # filter on a whole kingdom or more, so fail loudly instead
  if (isTRUE(match$matchType == "HIGHERRANK")) {
    stop(
      "`gbif_taxon` = \"", taxon_name, "\" only matched as far as ", match$scientificName, " (",
      tolower(match$rank), ") in GBIF's taxonomy. Check https://www.gbif.org/species/search?q=",
      utils::URLencode(taxon_name, reserved = TRUE), " and refine it, or pass `gbif_taxon_rank`/`gbif_kingdom`.",
      call. = FALSE
    )
  }

  key <- match$usageKey
  if (isTRUE(tolower(match$status) == "synonym") && "acceptedUsageKey" %in% names(match) &&
      !is.na(match$acceptedUsageKey)) {
    key <- match$acceptedUsageKey
  }
  key <- as.character(key)
  if (length(key) != 1 || is.na(key) || !nzchar(key)) {
    stop("GBIF matched `gbif_taxon` = \"", taxon_name, "\" but returned no key for it.", call. = FALSE)
  }

  # the kingdom it's in, by name (`Animalia`, `Plantae`, ...), as the Catalogue of Life writes it
  kingdom <- if ("kingdom" %in% names(match) && length(match$kingdom) == 1) as.character(match$kingdom) else NA_character_
  list(key = key, rank = tolower(match$rank), kingdom = kingdom)
}
