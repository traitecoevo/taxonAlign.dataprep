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
  testthat::local_mocked_bindings(
    occ_search = function(...) {
      calls$occ <- calls$occ + 1
      calls$args <- list(...)
      list(facets = list(scientificName = tibble::tibble(
        name = c("Eucalyptus gigantea Dehnh.", "Racosperma dealbatum (Link) Pedley", "Eucalyptus L'Hér.", "Banksia serrata L.f."),
        count = 4:1
      )))
    },
    name_parse = function(scientificname, ...) data.frame(
      scientificname = scientificname,
      canonicalnamewithmarker = sub(" (L'Hér\\.|Dehnh\\.|\\(Link\\) Pedley|L\\.f\\.)$", "", scientificname)
    ),
    name_backbone = function(...) data.frame(usageKey = 7707728L, matchType = "EXACT", rank = "PHYLUM", status = "ACCEPTED"),
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
  expect_equal(calls$args$taxonKey, 7707728L)
  expect_true(file.exists(file.path(cache, "gbif_names_7707728_AU.rds")))
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

test_that("country must be ISO codes, and the reference in taxonAlign's format", {
  expect_error(filter_to_country(country_test_reference(), "Australia"), "two-letter ISO")
  expect_error(filter_to_country(dplyr::select(country_test_reference(), -genus), "AU"), "missing required column")
})
