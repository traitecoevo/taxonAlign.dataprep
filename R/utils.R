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
# leaves a partial file where a complete one is expected (or removes one already there). A generous
# time limit: these are full-checklist downloads (~90-170MB), far past R's default 60 seconds.
#' @noRd
download_to_cache <- function(url, dest, what = basename(dest), quiet = FALSE) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  partial <- paste0(dest, ".part")
  old <- options(timeout = max(3600, getOption("timeout")))
  on.exit(options(old), add = TRUE)
  if (!quiet) message("Downloading ", what, "...")
  ok <- tryCatch(
    utils::download.file(url, partial, mode = "wb", quiet = TRUE) == 0,
    error = function(e) FALSE, warning = function(w) FALSE
  )
  if (ok) ok <- file.rename(partial, dest)
  if (!ok) {
    unlink(partial)
    stop("Couldn't download ", what, " (", url, "). Check that you're online.", call. = FALSE)
  }
  dest
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
