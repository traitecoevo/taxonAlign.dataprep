# Restricting a worldwide reference (WCVP, Catalogue of Life, ...) to the taxa recorded in one or more countries,
# using GBIF occurrence records -- the user's design (2026-10-22): the names GBIF has records of in the
# country are linked to the reference's own records, whichever of its names they match (accepted or
# synonym), and each linked record's accepted name is kept, together with all of its synonyms. The
# two taxonomies needn't agree: a GBIF name that's a synonym in the reference still keeps that
# synonym's accepted name.

# GBIF taxon each reference's occurrence search is limited to, by `taxonomic_dataset`, when
# `gbif_taxon` isn't given -- just to keep the query to the relevant part of GBIF.
taxonAlign_country_filter_default_taxon <- c(WCVP = "Tracheophyta")

#' Restrict a reference to the taxa recorded in a country
#'
#' Keeps only the taxa of a taxonomic reference -- typically a worldwide one, such as [load_WCVP()] or
#' [load_CatalogueOfLife()] -- that GBIF has occurrence records of in one or more countries.
#'
#' The names GBIF's occurrence records in the country are identified to, in GBIF's taxonomy (the
#' Catalogue of Life Extended Release; fetched in a single facet query per country, then parsed to
#' canonical names by GBIF's name parser), are matched to the
#' reference's names, ignoring rank markers, punctuation and case. A GBIF name can match either an
#' accepted name or a synonym in the reference, since the two taxonomies needn't agree; either way, the
#' matched record's *accepted* name is kept, together with every synonym of it, so old names in a list
#' still update. With `whole_species = TRUE` (the default), every subspecies, variety, etc. of a kept
#' species is kept too (and the species itself, for a recorded subspecies), whether or not GBIF has
#' records under that name. Genera (and subgenera) of the kept taxa are kept, with their synonyms; ranks
#' above genus are kept whole, as they don't limit which species can match.
#'
#' GBIF's records include cultivated, captive and introduced occurrences as well as native ones, and,
#' for animals, fossils. A name known only from fossil specimens (*Diprotodon*, say) is left out by
#' default (`exclude_fossils`), since it would otherwise produce spurious matches against modern names;
#' a recently extinct species with museum specimens (the thylacine) stays. Pass further occurrence
#' filters through `...` (e.g. `basisOfRecord = "PRESERVED_SPECIMEN"`) to narrow them. The GBIF names are downloaded once per
#' country and group and cached, like [load_WCVP()]: later calls use the cached names, until
#' `refresh_cache = TRUE`.
#'
#' @param reference A taxonomic reference in taxonAlign's format (see
#'  [taxonAlign::taxonomic_reference_schema()]), e.g. from [load_WCVP()] or [load_CatalogueOfLife()].
#' @param country One or more two-letter ISO 3166-1 country codes, e.g. `"AU"` or `c("AU", "NZ")`.
#' @param gbif_taxon Optional GBIF taxon name(s) to limit the occurrence search to, e.g.
#'  `"Tracheophyta"` or `c("Animalia", "Fungi")`. Defaults to `"Tracheophyta"` for a WCVP reference;
#'  otherwise every occurrence record in the country is used.
#' @param gbif_taxon_rank,gbif_kingdom Optional rank and kingdom for `gbif_taxon`, to disambiguate a
#'  homonym in GBIF's taxonomy (e.g. `gbif_kingdom = "Plantae"` for the plant genus *Eremophila*).
#' @param whole_species Logical; keep every infraspecific taxon of a kept species, and the species of
#'  a kept infraspecific taxon. Defaults to `TRUE`.
#' @param exclude_fossils Logical; leave out names whose GBIF records in the country are all fossil
#'  specimens. Defaults to `TRUE`. Not applied when `...` includes a `basisOfRecord` filter.
#' @param refresh_cache Logical; if `TRUE`, fetches the GBIF names again. Defaults to `FALSE`.
#' @param cache_dir Directory the GBIF names are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#' @param ... Further GBIF occurrence search filters, passed to [rgbif::occ_search()].
#'
#' @return `reference`, with only the kept records (and its attributes, such as `"version"` and
#'  `"citation"`). Attributes added: `"country"`; `"gbif_names"`, a tibble of every name GBIF has
#'  records of in the country (`scientific_name` as GBIF writes it, `canonical_name` as parsed), the
#'  list the filter was based on; and `"unmatched"`, those of them at species rank or below that
#'  matched nothing in the reference (worth a look: names the reference lacks, or spells differently).
#'
#' @examples
#' \dontrun{
#' wcvp_au <- load_WCVP() |> filter_to_country("AU")
#' col_au_nz <- load_CatalogueOfLife(extended = TRUE) |>
#'   filter_to_country(c("AU", "NZ"), gbif_taxon = c("Animalia", "Plantae", "Fungi"))
#' }
#'
#' @export
filter_to_country <- function(reference,
                              country,
                              gbif_taxon = NULL,
                              gbif_taxon_rank = NULL,
                              gbif_kingdom = NULL,
                              whole_species = TRUE,
                              exclude_fossils = TRUE,
                              refresh_cache = FALSE,
                              cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                              quiet = FALSE,
                              ...) {
  taxonAlign::check_taxonomic_reference(reference, "reference")
  if (missing(country) || length(country) == 0 || !all(grepl("^[A-Za-z]{2}$", country))) {
    stop("`country` must be one or more two-letter ISO 3166-1 country codes, e.g. \"AU\".", call. = FALSE)
  }
  country <- toupper(country)
  if (is.null(gbif_taxon)) {
    datasets <- unique(reference$taxonomic_dataset)
    gbif_taxon <- unique(unname(taxonAlign_country_filter_default_taxon[datasets]))
    gbif_taxon <- gbif_taxon[!is.na(gbif_taxon)]
    if (length(gbif_taxon) == 0) gbif_taxon <- NULL
  }

  gbif_names <- fetch_gbif_country_names(country, gbif_taxon, gbif_taxon_rank, gbif_kingdom,
                                         refresh_cache, cache_dir, quiet, exclude_fossils, ...)
  keep <- country_filter_records(reference, gbif_names$canonical_name, whole_species)

  out <- reference[keep, ]
  for (a in setdiff(names(attributes(reference)), c("names", "row.names", "class"))) attr(out, a) <- attr(reference, a)
  ref_keys <- country_match_key(reference$canonical_name)
  species_level <- grepl("\\s", gbif_names$canonical_name)
  attr(out, "country") <- country
  attr(out, "gbif_names") <- gbif_names
  attr(out, "unmatched") <- gbif_names[species_level & !country_match_key(gbif_names$canonical_name, autonyms = TRUE) %in% ref_keys, ]
  if (!quiet) {
    n_matched <- sum(species_level) - nrow(attr(out, "unmatched"))
    message(
      "Kept ", format(nrow(out), big.mark = ","), " of ", format(nrow(reference), big.mark = ","), " records. ",
      format(n_matched, big.mark = ","), " of the ", format(sum(species_level), big.mark = ","),
      " species-level names GBIF has records of in ", paste(country, collapse = ", "),
      " matched the reference; the rest are in `attr(x, \"unmatched\")`."
    )
  }
  out
}

# The form names are compared in: no rank markers, punctuation or case (APCalign::strip_names()), with
# the hybrid sign always followed by a space (GBIF's parser writes "Acaena ×ovina", the WCVP "Acaena ×
# ovina"). With `autonyms = TRUE`, an autonym ("Cheilanthes sieberi subsp. sieberi") becomes its
# species ("cheilanthes sieberi"): GBIF's records use autonyms, but the WCVP doesn't list them as
# names of their own.
#' @noRd
country_match_key <- function(x, autonyms = FALSE) {
  key <- APCalign::strip_names(gsub("\u00d7\\s*", "\u00d7 ", x))
  if (autonyms) {
    words <- stringr::str_split(key, " ")
    key <- vapply(words, function(w) {
      if (length(w) == 3 && w[2] == w[3]) paste(w[1:2], collapse = " ") else paste(w, collapse = " ")
    }, character(1))
  }
  key
}

# Which records of `reference` to keep, given the canonical names GBIF has records of.
#' @noRd
country_filter_records <- function(reference, gbif_canonical, whole_species) {
  rank <- APCalign::standardise_taxon_rank(reference$taxon_rank)
  genus_level <- rank %in% c("genus", "subgenus")
  # a name of no stated rank -- e.g. the Catalogue of Life Extended Release's 2.17 million "unranked"
  # barcode clusters (BOLD BINs, UNITE species hypotheses) -- is kept only if GBIF has records of it,
  # with its accepted name; counting it as "above genus" (kept whole) kept every one worldwide
  unranked <- is.na(rank) | rank %in% c("unranked", "other", "no rank")
  species_level <- !genus_level & !unranked & grepl("\\s", reference$canonical_name)
  above <- !genus_level & !species_level & !unranked
  key <- country_match_key(reference$canonical_name)
  recorded <- key %in% country_match_key(gbif_canonical, autonyms = TRUE)
  id <- reference$taxon_ID
  accepted_of <- reference$accepted_name_usage_ID

  # species and below: the accepted names of every recorded name (accepted or synonym)
  kept_accepted <- unique(accepted_of[recorded & species_level])
  if (whole_species) {
    # ...and every accepted name sharing a species with one of them
    binomial <- stringr::word(APCalign::strip_names_extra(key), 1, 2)
    accepted_rows <- species_level & id == accepted_of
    kept_binomials <- unique(binomial[accepted_rows & id %in% kept_accepted])
    kept_accepted <- union(kept_accepted, id[accepted_rows & binomial %in% kept_binomials])
  }
  keep <- species_level & accepted_of %in% kept_accepted

  # genera: those of the kept taxa, and any recorded at genus rank, with their synonyms
  kept_genera <- unique(c(reference$genus[keep], reference$canonical_name[recorded & rank == "genus"]))
  genus_rows <- rank == "genus" & reference$canonical_name %in% kept_genera
  kept_genus_accepted <- unique(accepted_of[genus_rows])
  keep <- keep | (rank == "genus" & accepted_of %in% kept_genus_accepted) |
    (rank == "subgenus" & reference$genus %in% kept_genera) | above

  keep <- keep | (unranked & accepted_of %in% unique(accepted_of[recorded & unranked]))

  # whatever a kept record leads to stays too, so the result still passes check_taxonomic_reference()
  keep | id %in% accepted_of[keep]
}

# The names GBIF has occurrence records of in each country (within `gbif_taxon`, if given), as
# a tibble of scientific_name (as GBIF writes it, with authorship) and canonical_name (parsed by GBIF's
# name parser, rank markers kept). With `exclude_fossils`, a name all of whose records are fossil
# specimens is left out (a second facet query, on basisOfRecord = "FOSSIL_SPECIMEN", compared by record
# count): a name with both fossil and other records stays. Cached per country and taxon as
# <cache_dir>/gbif_names_COLXR_<key>_<country>[_nofossil].rds; once cached, used without going online
# until `refresh_cache = TRUE`.
#' @noRd
fetch_gbif_country_names <- function(country, gbif_taxon, gbif_taxon_rank, gbif_kingdom,
                                     refresh_cache, cache_dir, quiet, exclude_fossils = FALSE, ...) {
  roots <- if (is.null(gbif_taxon)) list(list(key = NULL, label = "all")) else {
    lapply(seq_along(gbif_taxon), function(i) {
      root <- resolve_gbif_taxon(gbif_taxon[i], gbif_taxon_rank[i], gbif_kingdom[i])
      list(key = root$key, label = as.character(root$key))
    })
  }
  extra <- list(...)
  # a basisOfRecord filter of the caller's own decides which records count; fossils aren't second-guessed
  exclude_fossils <- isTRUE(exclude_fossils) && !"basisOfRecord" %in% names(extra)
  extra_label <- paste0(if (length(extra) == 0) "" else paste0("_", substr(rlang::hash(extra), 1, 8)),
                        if (exclude_fossils) "_nofossil" else "")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  names <- lapply(country, function(cc) lapply(roots, function(root) {
    # "COLXR": names fetched under GBIF's taxonomy since rgbif 3.9.0, so a list cached under the old GBIF
    # Backbone (named without it) is never reused
    cache_file <- file.path(cache_dir, paste0("gbif_names_COLXR_", root$label, "_", cc, extra_label, ".rds"))
    if (!refresh_cache && file.exists(cache_file)) {
      if (!quiet) message("Using the GBIF names recorded in ", cc, " (", root$label, "), cached ",
                          format(as.Date(file.info(cache_file)$mtime)), ". To fetch them again, use `refresh_cache = TRUE`.")
      return(readRDS(cache_file))
    }
    if (!quiet) message("Fetching the names GBIF has occurrence records of in ", cc, " (", root$label, ")...")
    facet <- fetch_gbif_name_facet(root$key, cc, extra)
    if (nrow(facet) == 0) {
      # not cached: an empty result is more likely a failed query than a real absence, and a cached one
      # would be reused silently from then on (traitecoevo/taxonAlign.dataprep#1)
      warning("GBIF has no occurrence records in ", cc, " (", root$label, "). Nothing was cached, so the ",
              "next call asks GBIF again.", call. = FALSE)
      return(parse_gbif_names(character(0)))
    }
    if (exclude_fossils) {
      fossil <- fetch_gbif_name_facet(root$key, cc, c(extra, list(basisOfRecord = "FOSSIL_SPECIMEN")))
      fossil_count <- dplyr::coalesce(fossil$count[match(facet$name, fossil$name)], 0L)
      fossil_only <- facet$count <= fossil_count
      if (!quiet && any(fossil_only)) {
        message("Leaving out ", format(sum(fossil_only), big.mark = ","), " names known only from fossil specimens.")
      }
      facet <- facet[!fossil_only, ]
    }
    if (!quiet) message("Parsing ", format(nrow(facet), big.mark = ","), " names...")
    parsed <- parse_gbif_names(unique(facet$name))
    saveRDS(parsed, cache_file)
    parsed
  }))
  out <- dplyr::bind_rows(unlist(names, recursive = FALSE))
  out[!duplicated(out$scientific_name), ]
}

# Every name (scientificName facet) of the occurrence records in country `cc` below `key`, with its
# record count, paging through the facet 100,000 names at a time.
#' @noRd
fetch_gbif_name_facet <- function(key, cc, extra) {
  pages <- list()
  page <- 100000
  offset <- 0
  repeat {
    occ <- with_gbif_retry(function() {
      do.call(rgbif::occ_search, c(
        list(taxonKey = key, checklistKey = gbif_COL_XR_checklist_key, country = cc, limit = 0,
             facet = "scientificName",
             scientificName.facetLimit = page, scientificName.facetOffset = offset,
             curlopts = gbif_curlopts),
        extra
      ))
    })
    got <- occ$facets$scientificName
    if (is.null(got) || !"name" %in% names(got)) break
    pages[[length(pages) + 1]] <- dplyr::tibble(name = got$name, count = as.integer(got$count))
    offset <- offset + nrow(got)
    if (nrow(got) < page) break
  }
  dplyr::bind_rows(dplyr::tibble(name = character(0), count = integer(0)), pages)
}

# GBIF's name parser, in batches: scientific name with authorship -> canonical name with rank markers
# ("Eucalyptus globulus subsp. bicostata"). Names it can't parse to a canonical name (placeholders,
# BOLD BINs, ...) are dropped.
#' @noRd
parse_gbif_names <- function(scientific) {
  if (length(scientific) == 0) return(dplyr::tibble(scientific_name = character(0), canonical_name = character(0)))
  batches <- split(scientific, ceiling(seq_along(scientific) / 1000))
  parsed <- lapply(batches, function(batch) {
    p <- with_gbif_retry(function() rgbif::name_parse(batch, curlopts = gbif_curlopts))
    canonical <- if ("canonicalnamewithmarker" %in% names(p)) p$canonicalnamewithmarker else rep(NA_character_, nrow(p))
    dplyr::tibble(scientific_name = p$scientificname, canonical_name = canonical)
  })
  out <- dplyr::bind_rows(parsed)
  out[!is.na(out$canonical_name) & out$canonical_name != "", ]
}
