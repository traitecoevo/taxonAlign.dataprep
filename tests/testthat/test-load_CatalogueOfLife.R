# load_CatalogueOfLife(): reshaping a COL-shaped (ColDP NameUsage.tsv) fixture into taxonAlign's format, and
# which release gets used (ChecklistBank mocked) -- offline.

test_that("COL names become taxonAlign records: synonyms lead to their accepted name", {
  raw <- sample_col_usage_raw()
  names(raw) <- sub("^col:", "", names(raw))
  out <- reshape_CatalogueOfLife(raw)
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
  expect_true(all(out$taxonomic_dataset == "CatalogueOfLife"))
  # COL's extinct flag, as a logical
  expect_equal(out$extinct, c(NA, NA, NA, NA, FALSE, NA, TRUE, NA, NA))
})

test_that("load_CatalogueOfLife reads your own NameUsage.tsv, and the result aligns and updates names", {
  col <- load_CatalogueOfLife(path = write_sample_col_tsv(), cache_dir = withr::local_tempdir(), quiet = TRUE)
  lookup <- taxonAlign::create_taxonomic_update_lookup(c("Cynthia cardui", "Pyrameis novus", "Vanessa (Cynthia)"), col)
  expect_equal(lookup$suggested_name, c("Vanessa cardui", "Vanessa novus", "Vanessa (Cynthia) sp. [Vanessa (Cynthia)]"))
  expect_equal(lookup$taxon_rank[3], "subgenus")
})

test_that("a release named by its key, already downloaded, is used without going online", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "CoL", "316595"), recursive = TRUE)
  meta <- list(key = "316595", alias = "COL26.10", issued = "2026-10-14", doi = "10.48580/dgzh4", citation = "cite me")
  saveRDS(meta, file.path(cache, "CoL", "316595", "metadata.rds"))
  file.create(file.path(cache, "CoL", "316595", "coldp.zip"))
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
  file.create(file.path(cache, "CoL", "316595", "coldp.zip"))
  expect_message(again <- CoL_release_metadata("3LR", cache, FALSE), "Using Catalogue of Life release COL26.10.*refresh_cache = TRUE")
  expect_equal(again$key, "316595")
  # an alias already downloaded doesn't go online either
  expect_equal(CoL_release_metadata("COL26.10", cache, TRUE)$key, "316595")
  expect_equal(calls, 1)
  # refresh_cache = TRUE looks the latest release up again
  expect_message(CoL_release_metadata("3LR", cache, FALSE, refresh_cache = TRUE), "latest Catalogue of Life release is COL26.10")
  expect_equal(calls, 2)
})

test_that("the latest Extended Release (\"3LXR\") is tracked apart from the latest release", {
  cache <- withr::local_tempdir()
  json <- function(key, alias) sprintf('{"key": %s, "sourceKey": 3, "alias": "%s", "title": "Catalogue of Life", "issued": "2026-10-16"}', key, alias)
  local_mocked_bindings(try_fetch = function(url, ...) {
    list(content = charToRaw(if (grepl("3LXR", url)) json(316691, "COL26.10 XR") else json(316595, "COL26.10")))
  })
  expect_equal(CoL_release_metadata("3LXR", cache, TRUE)$key, "316691")
  expect_equal(CoL_release_metadata("3LR", cache, TRUE)$key, "316595")
  for (key in c("316691", "316595")) file.create(file.path(cache, "CoL", key, "coldp.zip"))
  local_mocked_bindings(try_fetch = function(...) stop("network used"))
  expect_equal(CoL_release_metadata("3LXR", cache, TRUE)$key, "316691")
  expect_equal(CoL_release_metadata("3LR", cache, TRUE)$key, "316595")
  # offline with nothing recorded as latest, "3LXR" is the newest XR already downloaded
  file.remove(file.path(cache, "CoL", "latest_XR.rds"))
  local_mocked_bindings(try_fetch = function(...) NULL)
  expect_equal(CoL_release_metadata("3LXR", cache, TRUE)$key, "316691")
})

test_that("extended = TRUE asks for the latest Extended Release", {
  asked <- NULL
  local_mocked_bindings(CoL_release_metadata = function(version, ...) { asked <<- version; stop("stop here") })
  expect_error(load_CatalogueOfLife(extended = TRUE, cache_dir = withr::local_tempdir(), quiet = TRUE), "stop here")
  expect_equal(asked, "3LXR")
  expect_error(load_CatalogueOfLife(cache_dir = withr::local_tempdir(), quiet = TRUE), "stop here")
  expect_equal(asked, "3LR")
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
  expect_message(load_CatalogueOfLife(316595, cache_dir = cache), "slow the first time you load it")
  expect_no_message(load_CatalogueOfLife(316595, cache_dir = cache, quiet = TRUE))
  msgs <- testthat::capture_messages(load_CatalogueOfLife(316595, cache_dir = cache))
  expect_false(any(grepl("slow the first time", msgs)))
})

test_that("\"3LR\" isn't pinned to a release whose download failed (issue #2)", {
  cache <- withr::local_tempdir()
  save_meta <- function(key, alias, issued) {
    dir.create(file.path(cache, "CoL", key), recursive = TRUE)
    saveRDS(list(key = key, alias = alias, issued = issued, doi = NA, citation = NA), file.path(cache, "CoL", key, "metadata.rds"))
  }
  # COL26.11 was looked up as the latest, but never downloaded; COL26.10 was
  save_meta("316595", "COL26.10", "2026-10-14")
  file.create(file.path(cache, "CoL", "316595", "coldp.zip"))
  save_meta("317005", "COL26.11", "2026-11-11")
  saveRDS("317005", file.path(cache, "CoL", "latest.rds"))
  # so "3LR" is looked up online again, rather than used from the cache
  local_mocked_bindings(try_fetch = function(...) stop("network used"))
  expect_error(CoL_release_metadata("3LR", cache, TRUE), "network used")
  # and offline, it's the newest release actually downloaded
  local_mocked_bindings(try_fetch = function(...) NULL)
  expect_equal(CoL_release_metadata("3LR", cache, TRUE)$key, "316595")
})

test_that("a release ChecklistBank has no download of comes from the COL's own copy (issue #2)", {
  file <- file.path(withr::local_tempdir(), "CoL", "317005", "coldp.zip")
  urls <- character(0)
  local_mocked_bindings(download_to_cache = function(url, dest, ...) {
    urls <<- c(urls, url)
    if (grepl("api.checklistbank.org", url)) download_error("not found", 404L)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.create(dest)
    dest
  })
  meta <- list(key = "317005", alias = "COL26.11", issued = "2026-11-11")
  expect_message(download_CoL_release(meta, file), "hasn't prepared a download of COL26.11")
  expect_equal(urls, c("https://api.checklistbank.org/dataset/317005/export.zip?format=ColDP",
                       "https://download.checklistbank.org/col/monthly/2026-11-11_coldp.zip"))
  expect_true(file.exists(file))
  # an annual release's copy is named by its year
  expect_equal(CoL_archive_url(list(alias = "COL25", issued = "2025-06-13")),
               "https://download.checklistbank.org/col/annual/2025_coldp.zip")
  # an Extended Release has no copy: a clear error, naming the release
  expect_null(CoL_archive_url(list(alias = "COL26.11 XR", issued = "2026-11-13")))
  expect_error(download_CoL_release(list(key = "317100", alias = "COL26.11 XR", issued = "2026-11-13"), file, quiet = TRUE),
               "COL26.11 XR.*doesn't publish its own copy of an Extended Release")
  # any other failure (offline, a server error) isn't hidden by trying elsewhere
  urls <- character(0)
  local_mocked_bindings(download_to_cache = function(url, ...) { urls <<- c(urls, url); download_error("server error", 500L) })
  expect_error(download_CoL_release(meta, file, quiet = TRUE), "server error")
  expect_length(urls, 1)
})

test_that("only the columns used are read, so the COL's wider NameUsage.tsv loads the same", {
  dir <- withr::local_tempdir()
  wide <- sample_col_usage_raw() |> dplyr::mutate(`col:remarks` = "a note", `col:nameID` = "x", .before = 1)
  readr::write_tsv(wide, file.path(dir, "NameUsage.tsv"), na = "", quote = "none")
  cache <- withr::local_tempdir()
  expect_equal(
    load_CatalogueOfLife(path = file.path(dir, "NameUsage.tsv"), cache_dir = cache, quiet = TRUE),
    load_CatalogueOfLife(path = write_sample_col_tsv(), cache_dir = cache, quiet = TRUE),
    ignore_attr = TRUE
  )
})
