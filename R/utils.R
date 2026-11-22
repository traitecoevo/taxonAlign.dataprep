# A small string helper shared with taxonAlign, copied here (rather than imported) because taxonAlign
# keeps them internal -- the same reason taxonAlign vendors its own copies of APCalign's internal
# helpers. Keep it identical to taxonAlign's `R/match_taxa_helpers.R` version: a name reshaped here
# must split into genus/subgenus exactly the way taxonAlign splits it when matching.

## function for extracting the first "genus" - including with hybrids
#' @noRd
extract_genus <- function(taxon_name) {

  taxon_name <- APCalign::standardise_names(taxon_name)

  genus <- stringr::str_split_i(taxon_name, " |\\/", 1) |> stringr::str_to_sentence()

  # Deal with names that being with x,
  # e.g."x Taurodium x toveyanum" or "x Glossadenia tutelata"
  i <- !is.na(genus) & genus =="X"

  genus[i] <-
    paste("x", stringr::str_split_i(taxon_name[i], " |\\/", 2) |> stringr::str_to_sentence())

  genus
}

# Downloads `url` to `dest`, via a temporary file renamed only on success, so a failed download never
# leaves a partial file where a complete one is expected (or removes one already there). No overall
# time limit -- these are full-checklist downloads (~90MB-1GB), far past R's default 60 seconds -- but
# a connection that stalls (under 100 bytes/s for 2 minutes) is given up on.
# A failure says why (taxonAlign.dataprep issue #2: a 404 used to be reported as "Check that you're
# online"): an HTTP error gives the status and the server's own message, and the error carries the
# status (`e$status`, NA if the server was never reached), so a caller can try somewhere else.
#' @noRd
download_to_cache <- function(url, dest, what = basename(dest), quiet = FALSE) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  partial <- paste0(dest, ".part")
  on.exit(unlink(partial), add = TRUE)
  if (!quiet) message("Downloading ", what, "...")
  handle <- curl::new_handle(followlocation = TRUE, connecttimeout = 30, low_speed_limit = 100, low_speed_time = 120)
  response <- tryCatch(curl::curl_fetch_disk(url, partial, handle = handle), error = function(e) e)
  if (inherits(response, "error")) {
    download_error(paste0("Couldn't download ", what, " (", url, "): ", conditionMessage(response),
                          ". Check that you're online."), NA_integer_)
  }
  if (response$status_code != 200) {
    # the body of an error response is a short explanation (ChecklistBank: {"code":404,"message":...})
    body <- if (file.exists(partial) && file.size(partial) < 10000) paste(readLines(partial, warn = FALSE), collapse = " ") else ""
    detail <- tryCatch(jsonlite::fromJSON(body)$message, error = function(e) NULL) %||%
      if (grepl("^\\s*<", body)) "" else substr(body, 1, 200)
    download_error(paste0("Couldn't download ", what, " (", url, "): the server answered ", response$status_code,
                          if (nzchar(detail)) paste0(", \"", detail, "\""), "."), response$status_code)
  }
  if (!file.rename(partial, dest)) stop("Couldn't save ", what, " to \"", dest, "\".", call. = FALSE)
  dest
}

#' @noRd
download_error <- function(message, status) {
  stop(structure(class = c("taxonAlign_download_error", "error", "condition"),
                 list(message = message, call = NULL, status = status)))
}

# The result of a short web request (`curl`), or NULL if it fails or times out -- for the small
# metadata lookups that decide which version to use, so being offline falls back to a cached copy
# straight away rather than hanging.
#' @noRd
try_fetch <- function(url, nobody = FALSE) {
  tryCatch({
    handle <- curl::new_handle(connecttimeout = 5, timeout = 30, nobody = nobody, followlocation = TRUE)
    response <- curl::curl_fetch_memory(url, handle = handle)
    if (response$status_code != 200) NULL else response
  }, error = function(e) NULL)
}

#' @noRd
`%||%` <- function(a, b) if (is.null(a)) b else a
