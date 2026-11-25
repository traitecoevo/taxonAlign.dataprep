# filter_to_country(): linking the names GBIF has records of in a country to a reference's own
# records, through either taxonomy's synonyms -- GBIF mocked, offline.

country_test_reference <- function(dataset = "TEST") {
  tibble::tribble(
    ~taxon_ID, ~accepted_name_usage_ID, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~genus,
    "G1", "G1", "Eucalyptus", "genus", "accepted", "Eucalyptus",
    "S1", "S1", "Eucalyptus globulus", "species", "accepted", "Eucalyptus",
    "S2", "S1", "Eucalyptus gigantea", "species", "synonym", "Eucalyptus",
    "S3", "S3", "Eucalyptus globulus subsp. bicostata", "subspecies", "accepted", "Eucalyptus",
    "S4", "S4", "Eucalyptus regnans", "species", "accepted", "Eucalyptus",
    "G3", "G3", "Acacia", "genus", "accepted", "Acacia",
    "G2", "G3", "Racosperma", "genus", "synonym", "Racosperma",
    "S5", "S5", "Acacia dealbata", "species", "accepted", "Acacia",
    "S6", "S5", "Racosperma dealbatum", "species", "synonym", "Racosperma",
    "G4", "G4", "Quercus", "genus", "accepted", "Quercus",
    "S7", "S7", "Quercus robur", "species", "accepted", "Quercus",
    "S8", "S7", "Quercus pedunculata", "species", "synonym", "Quercus",
    "F1", "F1", "Myrtaceae", "family", "accepted", NA
  ) |> dplyr::mutate(scientific_name = canonical_name, taxonomic_dataset = dataset, .after = canonical_name)
}

# GBIF's names for Australia: a synonym of each of two reference taxa, a genus, and a name the
# reference doesn't have
local_mock_gbif_names <- function(.env = parent.frame()) {
  calls <- new.env()
  calls$occ <- 0
  calls$fossil <- 0
  testthat::local_mocked_bindings(
    occ_search = function(...) {
      args <- list(...)
      # the fossil-specimen query: Diprotodon is known only from fossils, Eucalyptus from both
      if (identical(args$basisOfRecord, "FOSSIL_SPECIMEN")) {
        calls$fossil <- calls$fossil + 1
        return(list(facets = list(scientificName = tibble::tibble(
          name = c("Eucalyptus L'Hér.", "Diprotodon Owen"), count = c(1L, 5L)
        ))))
      }
      calls$occ <- calls$occ + 1
      calls$args <- args
      list(facets = list(scientificName = tibble::tibble(
        name = c("Eucalyptus gigantea Dehnh.", "Racosperma dealbatum (Link) Pedley", "Eucalyptus L'Hér.", "Banksia serrata L.f.", "Diprotodon Owen"),
        count = c(4:1, 5L)
      )))
    },
    name_parse = function(scientificname, ...) data.frame(
      scientificname = scientificname,
      canonicalnamewithmarker = sub(" (L'Hér\\.|Dehnh\\.|\\(Link\\) Pedley|L\\.f\\.|Owen)$", "", scientificname)
    ),
    name_backbone = function(...) data.frame(usageKey = "TP", matchType = "EXACT", rank = "PHYLUM", status = "ACCEPTED"),
    .package = "rgbif", .env = .env
  )
  calls
}

test_that("a GBIF name matching a synonym keeps its accepted name, all its synonyms, and its genus", {
  calls <- local_mock_gbif_names()
  out <- filter_to_country(country_test_reference(), "AU", cache_dir = withr::local_tempdir(), quiet = TRUE)
  # E. gigantea -> E. globulus (and its subspecies); Racosperma dealbatum -> Acacia dealbata, whose
  # genus Acacia keeps its synonym Racosperma; ranks above genus kept whole
  expect_setequal(out$taxon_ID, c("G1", "S1", "S2", "S3", "G3", "G2", "S5", "S6", "F1"))
  expect_silent(taxonAlign::check_taxonomic_reference(out))
  expect_equal(attr(out, "unmatched")$canonical_name, "Banksia serrata")
  expect_equal(attr(out, "country"), "AU")
  # no GBIF taxon given, and none by default for this dataset: the whole country
  expect_null(calls$args$taxonKey)
  expect_equal(calls$args$country, "AU")
})

test_that("a genus homonym from another kingdom isn't kept with its namesake", {
  # "Acacia" is also the name of a synonym of an unrelated genus (as the fish Diploprion is of the plant
  # Medicago in the Catalogue of Life), which mustn't bring that genus and its synonyms along
  ref <- dplyr::bind_rows(
    country_test_reference(),
    tibble::tribble(
      ~taxon_ID, ~accepted_name_usage_ID, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~genus,
      "H1", "H2", "Acacia", "genus", "synonym", "Acacia",
      "H2", "H2", "Medicagoa", "genus", "accepted", "Medicagoa",
      "H3", "H2", "Kamiellus", "genus", "synonym", "Kamiellus",
      "H4", "H4", "Medicagoa sativa", "species", "accepted", "Medicagoa"
    ) |> dplyr::mutate(scientific_name = canonical_name, taxonomic_dataset = "TEST", .after = canonical_name)
  )
  local_mock_gbif_names()
  out <- filter_to_country(ref, "AU", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_false(any(c("H1", "H2", "H3", "H4") %in% out$taxon_ID))
  expect_true(all(c("G2", "G3") %in% out$taxon_ID))
  expect_silent(taxonAlign::check_taxonomic_reference(out))

  # the old genus name of a kept synonym species ("Racosperma dealbatum"), when the genus record of that
  # name leads to a genus none of the kept taxa belong to: neither is kept (the bird synonym Gallina
  # brought in the snail Obba this way)
  ref2 <- country_test_reference() |>
    dplyr::bind_rows(tibble::tibble(taxon_ID = "G9", accepted_name_usage_ID = "G9", canonical_name = "Othergenus",
                                    scientific_name = "Othergenus", taxonomic_dataset = "TEST", taxon_rank = "genus",
                                    taxonomic_status = "accepted", genus = "Othergenus")) |>
    dplyr::mutate(accepted_name_usage_ID = ifelse(.data$taxon_ID == "G2", "G9", .data$accepted_name_usage_ID))
  out2 <- filter_to_country(ref2, "AU", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_false(any(c("G2", "G9") %in% out2$taxon_ID))
  expect_true(all(c("S5", "S6", "G3") %in% out2$taxon_ID))
  expect_silent(taxonAlign::check_taxonomic_reference(out2))
})

test_that("every synonym of a kept genus is kept, whatever its name, rank or `genus` column", {
  # synonyms of the kept genus Acacia: a genus with an unrelated name, a subgenus with no `genus` (as
  # the Catalogue of Life's subgenus synonym Notamacropus has), and a genus synonym of a kept subgenus
  ref <- dplyr::bind_rows(
    country_test_reference(),
    tibble::tribble(
      ~taxon_ID, ~accepted_name_usage_ID, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~genus,
      "K1", "G3", "Senegalia", "genus", "synonym", "Senegalia",
      "K2", "G3", "Phyllodoce", "subgenus", "synonym", NA,
      "K3", "K3", "Juliflorae", "subgenus", "accepted", "Acacia",
      "K4", "K3", "Julifloria", "genus", "synonym", "Julifloria"
    ) |> dplyr::mutate(scientific_name = canonical_name, taxonomic_dataset = "TEST", .after = canonical_name)
  )
  local_mock_gbif_names()
  out <- filter_to_country(ref, "AU", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_true(all(c("G2", "G3", "K1", "K2", "K3", "K4") %in% out$taxon_ID))
  expect_silent(taxonAlign::check_taxonomic_reference(out))
})

test_that("a name of no rank is kept only if GBIF has records of it", {
  # the COL XR holds millions of "unranked" barcode clusters; they used to count as "above genus",
  # kept whole, whatever the country
  ref <- dplyr::bind_rows(
    country_test_reference(),
    tibble::tibble(taxon_ID = c("U1", "U2"), accepted_name_usage_ID = c("U1", "U2"),
                   canonical_name = c("BOLD:AAA0001", "BOLD:ZZZ9999"), scientific_name = canonical_name,
                   taxonomic_dataset = "TEST", taxon_rank = "unranked", taxonomic_status = "accepted", genus = NA)
  )
  calls <- local_mock_gbif_names()
  testthat::local_mocked_bindings(
    occ_search = function(...) list(facets = list(scientificName = tibble::tibble(name = c("Eucalyptus gigantea Dehnh.", "BOLD:AAA0001"), count = 2:1))),
    name_parse = function(scientificname, ...) data.frame(scientificname = scientificname, canonicalnamewithmarker = sub(" Dehnh\\.$", "", scientificname)),
    .package = "rgbif"
  )
  out <- filter_to_country(ref, "AU", exclude_fossils = FALSE, cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_true("U1" %in% out$taxon_ID)
  expect_false("U2" %in% out$taxon_ID)
  # ranks above genus are still kept whole
  expect_true("F1" %in% out$taxon_ID)
})

test_that("whole_species = FALSE keeps only the recorded taxa themselves", {
  local_mock_gbif_names()
  out <- filter_to_country(country_test_reference(), "AU", whole_species = FALSE, cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_false("S3" %in% out$taxon_ID)
  expect_true(all(c("S1", "S2") %in% out$taxon_ID))
})

test_that("the GBIF names are cached, and a WCVP reference defaults to vascular plants", {
  cache <- withr::local_tempdir()
  calls <- local_mock_gbif_names()
  ref <- country_test_reference("WCVP")
  out1 <- filter_to_country(ref, "AU", cache_dir = cache, quiet = TRUE)
  expect_equal(calls$args$taxonKey, "TP")
  expect_true(file.exists(file.path(cache, "gbif_names_COLXR_TP_AU_nofossil.rds")))
  expect_message(out2 <- filter_to_country(ref, "AU", cache_dir = cache), "Using the GBIF names recorded in AU")
  expect_equal(out2, out1)
  expect_equal(calls$occ, 1)
})

test_that("several countries combine their names, and extra filters reach GBIF", {
  calls <- local_mock_gbif_names()
  filter_to_country(country_test_reference(), c("au", "NZ"), basisOfRecord = "PRESERVED_SPECIMEN",
                    cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(calls$occ, 2)
  expect_equal(calls$args$basisOfRecord, "PRESERVED_SPECIMEN")
})

test_that("GBIF is asked for its own taxonomy (COL XR), whatever rgbif's default", {
  # rgbif 3.9.0 made COL XR the default and the Backbone code turned "TP" into an NA key, then cached
  # the empty result (traitecoevo/taxonAlign.dataprep#1); the checklist is now always named
  calls <- local_mock_gbif_names()
  out <- filter_to_country(country_test_reference("WCVP"), "AU", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(calls$args$checklistKey, gbif_COL_XR_checklist_key)
  # the GBIF names the filter used are returned with it
  expect_equal(nrow(attr(out, "gbif_names")), 4)
})

test_that("names known only from fossil specimens are left out, unless asked for", {
  calls <- local_mock_gbif_names()
  out <- filter_to_country(country_test_reference(), "AU", cache_dir = withr::local_tempdir(), quiet = TRUE)
  # Diprotodon: all 5 records fossils, left out; Eucalyptus: 1 of 2, kept
  expect_false("Diprotodon" %in% attr(out, "gbif_names")$canonical_name)
  expect_true("Eucalyptus" %in% attr(out, "gbif_names")$canonical_name)
  expect_equal(calls$fossil, 1)
  kept <- filter_to_country(country_test_reference(), "AU", exclude_fossils = FALSE, cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_true("Diprotodon" %in% attr(kept, "gbif_names")$canonical_name)
  expect_equal(calls$fossil, 1)
})

test_that("a name GBIF can't place stops, rather than querying GBIF with no taxon", {
  calls <- local_mock_gbif_names()
  testthat::local_mocked_bindings(
    name_backbone = function(...) data.frame(usageKey = "P", matchType = "HIGHERRANK", rank = "KINGDOM", status = "ACCEPTED", scientificName = "Plantae"),
    .package = "rgbif"
  )
  cache <- withr::local_tempdir()
  expect_error(filter_to_country(country_test_reference("WCVP"), "AU", cache_dir = cache, quiet = TRUE),
               "only matched as far as Plantae")
  expect_equal(calls$occ, 0)
  expect_length(list.files(cache), 0)
})

test_that("a synonym in GBIF's taxonomy is followed to its accepted key", {
  calls <- local_mock_gbif_names()
  testthat::local_mocked_bindings(
    name_backbone = function(...) data.frame(usageKey = "9CLWS", acceptedUsageKey = "LV7", matchType = "EXACT", rank = "GENUS", status = "SYNONYM"),
    .package = "rgbif"
  )
  filter_to_country(country_test_reference(), "AU", gbif_taxon = "Racosperma", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(calls$args$taxonKey, "LV7")
})

test_that("an empty GBIF result warns and isn't cached", {
  calls <- local_mock_gbif_names()
  testthat::local_mocked_bindings(
    occ_search = function(...) { calls$occ <- calls$occ + 1; list(facets = list()) },
    .package = "rgbif"
  )
  cache <- withr::local_tempdir()
  expect_warning(out <- filter_to_country(country_test_reference("WCVP"), "AU", cache_dir = cache, quiet = TRUE),
                 "no occurrence records in AU")
  expect_length(list.files(cache, pattern = "^gbif_names_"), 0)
})

test_that("country must be ISO codes, and the reference in taxonAlign's format", {
  expect_error(filter_to_country(country_test_reference(), "Australia"), "two-letter ISO")
  expect_error(filter_to_country(dplyr::select(country_test_reference(), -genus), "AU"), "missing required column")
})
