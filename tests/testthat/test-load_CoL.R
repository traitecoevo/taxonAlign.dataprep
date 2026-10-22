# load_CoL(): reshaping a COL-shaped (ColDP NameUsage.tsv) fixture into taxonAlign's format, and
# which release gets used (ChecklistBank mocked) -- offline.

test_that("COL names become taxonAlign records: synonyms lead to their accepted name", {
  raw <- sample_col_usage_raw()
  names(raw) <- sub("^col:", "", names(raw))
  out <- reshape_CoL(raw)
  expect_silent(taxonAlign::check_taxonomic_reference(out))
  # provisionally accepted names are COL's accepted names
  expect_equal(out$taxonomic_status, c(rep("accepted", 5), "synonym", "accepted", "ambiguous synonym", "accepted"))
  # an accepted name leads to itself, not to its parent taxon; a synonym to its accepted name
  expect_equal(out$accepted_name_usage_ID, c("N", "F1", "G1", "SG1", "S1", "S1", "S3", "S3", "SC1"))
  # subgenus: bare name, with its genus kept
  expect_equal(out$canonical_name[4], "Cynthia")
  expect_equal(out$genus[4], "Vanessa")
  # rank qualifiers dropped; no genus above genus rank
  expect_equal(out$taxon_rank[9], "section")
  expect_equal(out$genus[1:2], c(NA_character_, NA_character_))
  expect_equal(out$scientific_name[5], "Vanessa cardui (Linnaeus, 1758)")
})

test_that("load_CoL reads your own NameUsage.tsv, and the result aligns and updates names", {
  col <- load_CoL(path = write_sample_col_tsv(), cache_dir = withr::local_tempdir(), quiet = TRUE)
  lookup <- taxonAlign::create_taxonomic_update_lookup(c("Cynthia cardui", "Pyrameis novus", "Vanessa (Cynthia)"), col)
  expect_equal(lookup$suggested_name, c("Vanessa cardui", "Vanessa novus", "Vanessa (Cynthia)"))
  expect_equal(lookup$taxon_rank[3], "subgenus")
})

test_that("a release named by its key, already downloaded, is used without going online", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "CoL", "316595"), recursive = TRUE)
  meta <- list(key = "316595", alias = "COL26.10", issued = "2026-10-14", doi = "10.48580/dgzh4", citation = "cite me")
  saveRDS(meta, file.path(cache, "CoL", "316595", "metadata.rds"))
  local_mocked_bindings(try_fetch = function(...) stop("network used"))
  expect_equal(CoL_release_metadata(316595, cache, TRUE), meta)
  # offline, "3LR" is the newest release already downloaded, and an alias is looked up locally
  older <- list(key = "310463", alias = "COL25", issued = "2025-06-13", doi = NA, citation = NA)
  dir.create(file.path(cache, "CoL", "310463"))
  saveRDS(older, file.path(cache, "CoL", "310463", "metadata.rds"))
  local_mocked_bindings(try_fetch = function(...) NULL)
  expect_message(latest <- CoL_release_metadata("3LR", cache, FALSE), "COL26.10")
  expect_equal(latest$key, "316595")
  expect_equal(CoL_release_metadata("COL25", cache, TRUE)$key, "310463")
  expect_error(CoL_release_metadata("COL21", cache, TRUE), "isn't cached")
})

test_that("after the first lookup, the latest release (\"3LR\") is used from the cache without going online", {
  cache <- withr::local_tempdir()
  calls <- 0
  json <- '{"key": 316595, "sourceKey": 3, "alias": "COL26.10", "title": "Catalogue of Life", "version": "2026-10-14", "issued": "2026-10-14", "doi": "10.48580/dgzh4"}'
  local_mocked_bindings(try_fetch = function(...) { calls <<- calls + 1; list(content = charToRaw(json)) })
  expect_equal(CoL_release_metadata("3LR", cache, TRUE)$key, "316595")
  expect_message(again <- CoL_release_metadata("3LR", cache, FALSE), "Using Catalogue of Life release COL26.10.*refresh_cache = TRUE")
  expect_equal(again$key, "316595")
  # an alias already downloaded doesn't go online either
  expect_equal(CoL_release_metadata("COL26.10", cache, TRUE)$key, "316595")
  expect_equal(calls, 1)
  # refresh_cache = TRUE looks the latest release up again
  expect_message(CoL_release_metadata("3LR", cache, FALSE, refresh_cache = TRUE), "latest Catalogue of Life release is COL26.10")
  expect_equal(calls, 2)
})

test_that("a ChecklistBank dataset that isn't a COL release is refused", {
  local_mocked_bindings(try_fetch = function(...) list(content = charToRaw('{"key": 1000, "sourceKey": null, "title": "Some other checklist"}')))
  expect_error(CoL_release_metadata(1000, withr::local_tempdir(), TRUE), "isn't a Catalogue of Life release")
})

test_that("the COL citation is built from the release metadata, in COL's own form", {
  d <- list(
    creator = data.frame(given = c("Olaf", "Diana Raquel"), family = c("Bánki", "Hernández Robles")),
    issued = "2026-10-14", title = "Catalogue of Life", version = "2026-10-14",
    publisher = list(name = "Catalogue of Life Foundation", address = "Amsterdam, Netherlands"), doi = "10.48580/dgzh4"
  )
  expect_equal(
    format_CoL_citation(d),
    paste0("Bánki, O., Hernández Robles, D. R. (2026). Catalogue of Life (Version 2026-10-14). ",
           "Catalogue of Life Foundation, Amsterdam, Netherlands. https://doi.org/10.48580/dgzh4")
  )
})

test_that("the first load of a release warns that it's slow; a cached one doesn't", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "CoL", "316595"), recursive = TRUE)
  saveRDS(list(key = "316595", alias = "COL26.10", issued = "2026-10-14", doi = NA, citation = NA),
          file.path(cache, "CoL", "316595", "metadata.rds"))
  tsv <- write_sample_col_tsv()
  withr::with_dir(dirname(tsv), utils::zip(file.path(cache, "CoL", "316595", "coldp.zip"), "NameUsage.tsv", flags = "-q"))
  expect_message(load_CoL(316595, cache_dir = cache), "slow the first time you load it")
  expect_no_message(load_CoL(316595, cache_dir = cache, quiet = TRUE))
  msgs <- testthat::capture_messages(load_CoL(316595, cache_dir = cache))
  expect_false(any(grepl("slow the first time", msgs)))
})
