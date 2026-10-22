# Builds the files for a taxonAlign data release (taxonAlign issues #24, #26). For every dataset a
# release holds two kinds of file, both listed in `manifest.csv`:
#
# - "raw": each source export stored verbatim (every column as text, only empty fields missing), so
#   whatever a ready file says can be traced back to exactly what was supplied;
# - "ready": the dataset in taxonAlign's reference format (`<dataset>.parquet`, built from the raw
#   files with this package's loaders and checked with taxonAlign::check_taxonomic_reference()). This
#   is the only file taxonAlign::load_taxonomic_resources() downloads -- the hand-off between the
#   two packages -- so taxonAlign itself never needs the reshaping code.
#
# Run from this package's root:
#   Rscript data-raw/build_data_release.R <release_date> <out_dir> <nsl_source> <gbif_au_rds>...
#
# <nsl_source> is either
# - a directory holding the AFD's NSL-format export (the animals taxon/names files, supplied directly
#   by the AFD, not yet public on NSL): the four public NSL groups are then downloaded fresh; or
# - a directory holding an earlier release's raw `nsl_<group>_{taxon,names}.parquet` files and its
#   `manifest.csv`: every NSL group is then rebuilt from those, unchanged (to rebuild the ready files
#   without re-fetching anything).
#
# e.g.
#   Rscript data-raw/build_data_release.R 2026-10-07 data-raw/release/2026-10-07 \
#     data-raw/sources/AFD_NSL_export_20260929 data-raw/sources/gbif_au_animals_with_extinct.rds
#
# GBIF: the August 2026 GBIF Australia lists, built with generate_GBIF_taxonomic_reference_list(
# country = "AU"), all taxa kept with GBIF's `extinct` flag as a column (taxonAlign leaves extinct
# taxa out unless asked). Already in taxonAlign's format, so the ready file is the only file.

suppressMessages(library(dplyr))
devtools::load_all(".", quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 4) stop("usage: build_data_release.R <release_date> <out_dir> <nsl_source> <gbif_au_rds>...")
release <- args[1]
out_dir <- path.expand(args[2])
nsl_source <- args[3]
gbif_files <- args[-(1:3)]
stopifnot(grepl("^\\d{4}-\\d{2}-\\d{2}$", release))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

nsl_groups <- tibble::tribble(
  ~group, ~host, ~taxon_code, ~names_code, ~title,
  "algae", "algae", "AAL", "AANI", "Australian Algae",
  "bryophytes", "moss", "CAB", "ABNI", "Australian Mosses, Hornworts and Liverworts",
  "fungi", "fungi", "AFL", "AFNI", "Australian Fungi",
  "lichens", "lichen", "ALC", "ALNI", "Australian Lichens",
  "animals", NA, NA, NA, "Australian Faunal Directory"
)
nsl_licence <- "CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/)"

# Reads an export exactly as supplied: every column as text, only empty fields treated as missing.
read_verbatim <- function(file) {
  header <- readLines(file, n = 1, warn = FALSE)
  delim <- if (grepl("|", header, fixed = TRUE)) "|" else ","
  readr::read_delim(file, delim = delim, col_types = readr::cols(.default = readr::col_character()),
                    na = "", progress = FALSE)
}

manifest <- list()
add_asset <- function(asset, data, dataset, type, source, source_file, retrieved, licence, citation,
                      source_md5 = NULL) {
  arrow::write_parquet(data, file.path(out_dir, asset))
  if (is.null(source_md5)) {
    source_md5 <- if (file.exists(source_file)) unname(tools::md5sum(source_file)) else NA_character_
  }
  manifest[[length(manifest) + 1]] <<- tibble::tibble(
    asset = asset, dataset = dataset, type = type, source = source, source_file = source_file,
    retrieved = retrieved, rows = nrow(data), columns = ncol(data), source_md5 = source_md5,
    licence = licence, citation = citation
  )
  message(asset, ": ", format(nrow(data), big.mark = ","), " rows")
}

# A ready file: IDs as character (so every dataset combines without type clashes), checked against
# taxonAlign's format before it's written.
add_ready_asset <- function(data, dataset, ...) {
  data <- dplyr::mutate(data, taxon_ID = as.character(taxon_ID), accepted_name_usage_ID = as.character(accepted_name_usage_ID))
  taxonAlign::check_taxonomic_reference(data, dataset)
  add_asset(paste0(dataset, ".parquet"), data, dataset, "ready", ...)
}

# ---- NSL groups: raw files ----------------------------------------------------------------------------
previous_release <- file.exists(file.path(nsl_source, "manifest.csv"))
if (previous_release) {
  previous_manifest <- readr::read_csv(file.path(nsl_source, "manifest.csv"), col_types = readr::cols(.default = "c"))
}
today <- format(Sys.Date())

for (i in seq_len(nrow(nsl_groups))) {
  g <- nsl_groups[i, ]
  for (kind in c("taxon", "names")) {
    asset <- sprintf("nsl_%s_%s.parquet", g$group, kind)
    if (previous_release) {
      # carried forward unchanged, with the provenance recorded when it was first released
      prev <- previous_manifest[previous_manifest$asset == asset, ]
      stopifnot(nrow(prev) == 1)
      add_asset(asset, arrow::read_parquet(file.path(nsl_source, asset)), NA_character_, "raw",
                prev$source, prev$source_file, prev$retrieved, prev$licence, prev$citation,
                source_md5 = prev$source_md5)
    } else if (g$group == "animals") {
      marker <- if (kind == "taxon") "[-_]taxon[-_]" else "[-_]names?[-_]"
      file <- list.files(nsl_source, pattern = marker, full.names = TRUE)
      stopifnot(length(file) == 1)
      add_asset(
        asset, read_verbatim(file), NA_character_, "raw",
        source = "Australian Faunal Directory, NSL-format export supplied by the AFD (not yet public on NSL)",
        source_file = file, retrieved = format(as.Date(file.info(file)$mtime)), licence = nsl_licence,
        citation = sprintf("Australian Faunal Directory (ABRS), NSL-format %s export (%s), released with permission of the AFD.",
                           if (kind == "taxon") "taxa" else "names", basename(file))
      )
    } else {
      url <- sprintf("https://%s.biodiversity.org.au/nsl/services/export/%sCsv", g$host, kind)
      code <- if (kind == "taxon") g$taxon_code else g$names_code
      source_dir <- file.path(out_dir, "source_files")
      dir.create(source_dir, showWarnings = FALSE)
      file <- file.path(source_dir, sprintf("%s-%s-%s.csv", code, kind, today))
      utils::download.file(url, file, mode = "wb", quiet = TRUE)
      add_asset(
        asset, read_verbatim(file), NA_character_, "raw",
        source = url, source_file = file, retrieved = today, licence = nsl_licence,
        citation = sprintf("National Species List: %s (%s) %s export, %s, retrieved %s.",
                           g$title, code, if (kind == "taxon") "taxa" else "names", url, today)
      )
    }
  }
}

# ---- NSL groups: ready files, reshaped from the raw files just written ---------------------------------
for (g in nsl_groups$group) {
  raw_assets <- sprintf("nsl_%s_%s.parquet", g, c("taxon", "names"))
  # load_NSL() wants one group's pair of files on its own in a folder
  group_dir <- file.path(tempdir(), paste0("nsl_", g))
  dir.create(group_dir, showWarnings = FALSE)
  file.copy(file.path(out_dir, raw_assets), group_dir, overwrite = TRUE)
  raw_rows <- dplyr::bind_rows(manifest) |> dplyr::filter(asset %in% raw_assets)
  add_ready_asset(
    load_NSL(g, group_dir, refresh_cache = TRUE, cache_dir = tempfile(), quiet = TRUE),
    paste0("NSL_", g),
    source = paste0(raw_rows$source[1], "; reshaped by taxonAlign.dataprep::load_NSL() from ",
                    paste(raw_assets, collapse = " and ")),
    source_file = paste(raw_assets, collapse = "; "), retrieved = raw_rows$retrieved[1],
    licence = raw_rows$licence[1], citation = paste(unique(raw_rows$citation), collapse = " "),
    source_md5 = NA_character_
  )
}

# ---- GBIF Australia, animals --------------------------------------------------------------------------
gbif <- bind_rows(lapply(gbif_files, readRDS))
stopifnot("extinct" %in% names(gbif))
# Records with no canonical name can never be matched, and taxonAlign drops them (with a warning) on
# every load. Almost all are BOLD Barcode Index Numbers, which the GBIF backbone holds as "unranked"
# taxa named e.g. "BOLD:AAX6343" (47,787 of the 47,797 in the August 2026 lists), so they're left out
# of the ready file instead.
no_name <- is.na(gbif$canonical_name) | gbif$canonical_name == ""
message("GBIF_AU: leaving out ", format(sum(no_name), big.mark = ","), " records with no canonical name (",
        format(sum(no_name & grepl("^BOLD:", gbif$scientific_name)), big.mark = ","), " of them BOLD BINs)")
add_ready_asset(
  gbif[!no_name, ], "GBIF_AU",
  source = paste0("GBIF Backbone Taxonomy, animal taxa with occurrence records in Australia plus their synonyms, ",
                  "with GBIF's extinct flag. Built with taxonAlign.dataprep::generate_GBIF_taxonomic_reference_list(country = \"AU\"); ",
                  format(sum(no_name), big.mark = ","), " records with no canonical name (BOLD Barcode Index Numbers) left out"),
  source_file = paste(basename(gbif_files), collapse = "; "),
  retrieved = "2026-08 (GBIF backbone and occurrence records accessed via the GBIF API, August 2026)",
  licence = "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
  citation = "GBIF Secretariat. GBIF Backbone Taxonomy. Checklist dataset https://doi.org/10.15468/39omei accessed via GBIF.org, August 2026."
)

manifest <- bind_rows(manifest)
readr::write_csv(manifest, file.path(out_dir, "manifest.csv"), na = "")

ready <- manifest[manifest$type == "ready", ]
notes <- c(
  sprintf("taxonAlign data release %s.", release), "",
  paste0(
    "Load these datasets with `taxonAlign::load_taxonomic_resources()`, e.g. ",
    "`load_taxonomic_resources(c(\"NSL_animals\", \"GBIF_AU\"), version = \"", release, "\")`. ",
    "Each `<dataset>.parquet` file is the dataset in taxonAlign's reference format; the ",
    "`nsl_<group>_taxon`/`nsl_<group>_names` files are the National Species List exports it was built ",
    "from, stored verbatim (every column as text). `manifest.csv` records each file's source, retrieval ",
    "date, row count, source-file checksum, licence and citation."
  ), "",
  "| Dataset | Rows | Source | Retrieved |", "|---|---|---|---|",
  sprintf("| `%s` | %s | %s | %s |", ready$dataset, format(ready$rows, big.mark = ","), ready$source, ready$retrieved)
)
writeLines(notes, file.path(out_dir, "release_notes.md"))
message("Built ", nrow(manifest), " files in ", out_dir)

# ---- publishing (run by hand, after checking the files) ------------------------------------------------
# Create the release as a draft first; publish it as a separate step:
#   gh release create <release_date> --repo traitecoevo/taxonAlign.dataprep --draft \
#     --title "Data release <release_date>" --notes-file <out_dir>/release_notes.md \
#     <out_dir>/*.parquet <out_dir>/manifest.csv
#   gh release edit <release_date> --repo traitecoevo/taxonAlign.dataprep --draft=false
