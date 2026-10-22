# load_WCVP(): reshaping a WCVP-shaped fixture into taxonAlign's format, and which version gets used
# (Kew's server mocked) -- offline.

test_that("WCVP names become taxonAlign records: statuses, links, ranks, hybrid genera", {
  out <- reshape_WCVP(sample_wcvp_names_raw())
  expect_silent(taxonAlign::check_taxonomic_reference(out))
  expect_equal(out$taxonomic_status, c("accepted", "accepted", "synonym", "illegitimate", "unplaced",
                                       "synonym", "artificial hybrid", "orthographic variant"))
  # an unplaced name, with no accepted name, leads to itself
  expect_equal(out$accepted_name_usage_ID[out$canonical_name == "Eucalyptus dubia"], "5")
  # a name with no rank in WCVP is an infraspecific name written without a marker
  expect_equal(out$taxon_rank[out$canonical_name == "Eucalyptus globulus nana"], "infraspecific name")
  # the hybrid sign stays on the genus, so it lines up with the genus record's own name
  expect_equal(out$genus[out$taxon_ID == "7"], "× Cleisocalpa")
  expect_equal(out$scientific_name[2], "Eucalyptus globulus Labill.")
  expect_true(all(out$taxonomic_dataset == "WCVP"))
  expect_equal(out$family[1], "Myrtaceae")
})

test_that("an unknown WCVP status is an error, not silently dropped", {
  raw <- sample_wcvp_names_raw()
  raw$taxon_status[1] <- "Doubtful"
  expect_error(reshape_WCVP(raw), "status\\(es\\) load_WCVP\\(\\) doesn't know: Doubtful")
})

test_that("load_WCVP reads your own wcvp_names.csv, and the result aligns and updates names", {
  out <- load_WCVP(path = write_sample_wcvp(), cache_dir = withr::local_tempdir(), quiet = TRUE)
  lookup <- taxonAlign::create_taxonomic_update_lookup(c("Eucalyptus gigantea", "Eucalyptus globulis", "Myrtaceae"), out)
  expect_equal(lookup$suggested_name[1:2], c("Eucalyptus globulus", "Eucalyptus globulus"))
  # WCVP has no family records; taxonAlign adds one from the family column
  expect_equal(lookup$taxon_rank[3], "family")
})

test_that("a named WCVP version already downloaded is used without going online", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "WCVP"))
  file.copy(write_sample_wcvp(zip_as = "wcvp.zip"), file.path(cache, "WCVP", "wcvp_v16.zip"))
  local_mocked_bindings(try_fetch = function(...) stop("network used"), download_to_cache = function(...) stop("network used"))
  out <- load_WCVP(16, cache_dir = cache, quiet = TRUE)
  expect_equal(nrow(out), nrow(sample_wcvp_names_raw()))
})

test_that("after the first download, the current WCVP is used from the cache without going online", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "WCVP"))
  file.copy(write_sample_wcvp(zip_as = "wcvp.zip"), file.path(cache, "WCVP", "wcvp_v15.zip"))
  write.dcf(data.frame(version = "15", modified = "Wed, 07 Jan 2026 12:36:01 GMT", downloaded = "2026-01-08"),
            file.path(cache, "WCVP", "current.dcf"))
  local_mocked_bindings(try_fetch = function(...) stop("network used"), download_to_cache = function(...) stop("network used"))
  expect_message(zip <- get_WCVP_zip(NULL, FALSE, cache, FALSE), "Using WCVP version 15, downloaded 2026-01-08.*refresh_cache = TRUE")
  expect_equal(attr(zip, "version"), "15")
})

test_that("refresh_cache = TRUE checks Kew, keeps an unchanged download, and falls back to it offline", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "WCVP"))
  file.copy(write_sample_wcvp(zip_as = "wcvp.zip"), file.path(cache, "WCVP", "wcvp_v15.zip"))
  write.dcf(data.frame(version = "15", modified = "Wed, 07 Jan 2026 12:36:01 GMT"), file.path(cache, "WCVP", "current.dcf"))
  checked <- FALSE
  local_mocked_bindings(
    try_fetch = function(...) { checked <<- TRUE; list(headers = charToRaw("HTTP/1.1 200 OK\r\nLast-Modified: Wed, 07 Jan 2026 12:36:01 GMT\r\n\r\n")) },
    download_to_cache = function(...) stop("downloaded again")
  )
  expect_message(zip <- get_WCVP_zip(NULL, TRUE, cache, FALSE), "still the current version")
  expect_true(checked)
  expect_equal(attr(zip, "version"), "15")

  local_mocked_bindings(try_fetch = function(...) NULL)
  expect_message(zip <- get_WCVP_zip(NULL, TRUE, cache, FALSE), "most recent WCVP version already downloaded, 15")
  # ...and with nothing cached, a clear error
  expect_error(get_WCVP_zip(NULL, FALSE, withr::local_tempdir(), TRUE), "no version is cached")
})
