# download_to_cache(): a failed download says why, and never leaves a file behind (issue #2) -- curl mocked.

test_that("an HTTP error gives the status and the server's message, and carries the status", {
  dest <- file.path(withr::local_tempdir(), "sub", "coldp.zip")
  local_mocked_bindings(curl_fetch_disk = function(url, path, ...) {
    writeLines('{"code":404,"message":"ColDP archive for dataset 317005 not found"}', path)
    list(status_code = 404L)
  }, .package = "curl")
  e <- tryCatch(download_to_cache("https://example.org/x.zip", dest, "the thing", quiet = TRUE), error = function(e) e)
  expect_s3_class(e, "taxonAlign_download_error")
  expect_equal(e$status, 404L)
  expect_match(conditionMessage(e), "the thing.*answered 404, \"ColDP archive for dataset 317005 not found\"")
  expect_false(grepl("online", conditionMessage(e)))
  expect_false(file.exists(dest))
  expect_false(file.exists(paste0(dest, ".part")))
})

test_that("not reaching the server says to check you're online; a cached copy is left alone", {
  dest <- file.path(withr::local_tempdir(), "coldp.zip")
  writeLines("cached", dest)
  local_mocked_bindings(curl_fetch_disk = function(url, path, ...) {
    writeLines("half", path)
    stop("Could not resolve host: example.org")
  }, .package = "curl")
  e <- tryCatch(download_to_cache("https://example.org/x.zip", dest, quiet = TRUE), error = function(e) e)
  expect_true(is.na(e$status))
  expect_match(conditionMessage(e), "Could not resolve host.*Check that you're online")
  expect_equal(readLines(dest), "cached")
  expect_false(file.exists(paste0(dest, ".part")))
})

test_that("a successful download lands at dest", {
  dest <- file.path(withr::local_tempdir(), "coldp.zip")
  local_mocked_bindings(curl_fetch_disk = function(url, path, ...) { writeLines("data", path); list(status_code = 200L) }, .package = "curl")
  expect_message(out <- download_to_cache("https://example.org/x.zip", dest, "the thing"), "Downloading the thing")
  expect_equal(out, dest)
  expect_equal(readLines(dest), "data")
})
