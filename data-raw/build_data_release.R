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
#   Rscript data-raw/build_data_release.R <release_date> <out_dir> <nsl_source> <col_xr_version>
#
# <nsl_source> is either
# - a directory holding the AFD's NSL-format export (the animals taxon/names files, supplied directly
#   by the AFD, not yet public on NSL): the four public NSL groups are then downloaded fresh; or
# - a directory holding an earlier release's raw `nsl_<group>_{taxon,names}.parquet` files and its
#   `manifest.csv`: every NSL group is then rebuilt from those, unchanged (to rebuild the ready files
#   without re-fetching anything).
#
# <col_xr_version> is the Catalogue of Life Extended Release to build CatalogueOfLife_AU from, as a
# ChecklistBank key (e.g. 316691 = COL26.10 XR) or alias.
#
# e.g.
#   Rscript data-raw/build_data_release.R 2026-11-14 data-raw/release/2026-11-14 \
#     data-raw/sources/AFD_NSL_export_20260929 316691
#
# CatalogueOfLife_AU replaces the 2026-10-07 release's GBIF_AU (built from the GBIF Backbone, which GBIF
# replaced with the Catalogue of Life Extended Release in October 2026 -- traitecoevo/
# taxonAlign.dataprep#1): the XR's animal names that GBIF has occurrence records of in Australia (via
# filter_to_country()), with their synonyms. The XR itself stays available, unchanged, from ChecklistBank
# by its DOI, so it isn't stored here; the list of names GBIF had records of in Australia when the
# release was built changes with every new occurrence record, so that's stored verbatim as the raw file.
# The XR has no extinct flag.

suppressMessages(library(dplyr))
devtools::load_all(".", quiet = TRUE)
# the NSL exports are tens of MB from a slow server: R's default 60 s download timeout cut the
# algae export off on 2026-11-14
options(timeout = max(1800, getOption("timeout")))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4) stop("usage: build_data_release.R <release_date> <out_dir> <nsl_source> <col_xr_version>")
release <- args[1]
out_dir <- path.expand(args[2])
nsl_source <- args[3]
col_xr_version <- args[4]
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

# ---- Catalogue of Life Extended Release, Australian animals --------------------------------------------
col_xr <- load_CatalogueOfLife(col_xr_version)
col_au <- filter_to_country(col_xr, "AU", gbif_taxon = "Animalia", refresh_cache = TRUE)
xr_label <- paste0(attr(col_xr, "version"), " (ChecklistBank key ", attr(col_xr, "key"), ", https://doi.org/", attr(col_xr, "doi"), ")")
# Barcode clusters aren't taxon names: the XR holds BOLD Barcode Index Numbers ("BOLD:AAX6343") and UNITE
# species hypotheses ("SH1234567.10FU") as "unranked" names (2.17 million in COL26.10 XR). Left out, as
# BOLD BINs were from GBIF_AU: two BINs one character apart would fuzzy-match each other.
barcode <- col_au$taxon_rank %in% "unranked" & grepl("^(BOLD:|SH\\d+\\.\\d+FU$)", col_au$canonical_name)
message("CatalogueOfLife_AU: leaving out ", format(sum(barcode), big.mark = ","), " barcode clusters (BOLD BINs, UNITE SHs)")
col_au_ready <- col_au[!barcode, ]
# whatever a kept record leads to must still be there
stopifnot(all(col_au_ready$accepted_name_usage_ID %in% col_au_ready$taxon_ID))
add_asset(
  "gbif_au_animalia_names.parquet", attr(col_au, "gbif_names"), NA_character_, "raw",
  source = paste0("GBIF occurrence search: every name (scientificName facet, in GBIF's taxonomy, ",
                  "Catalogue of Life Extended Release) of Animalia records in Australia, as GBIF writes it ",
                  "and as GBIF's name parser parses it"),
  source_file = "https://api.gbif.org/v1/occurrence/search?country=AU&facet=scientificName",
  retrieved = today, licence = "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
  citation = paste0("GBIF.org (", today, ") occurrence records of Animalia in Australia, GBIF Occurrence Search ",
                    "https://www.gbif.org/occurrence/search?country=AU&taxon_key=N"),
  source_md5 = NA_character_
)
add_ready_asset(
  col_au_ready, "CatalogueOfLife_AU",
  source = paste0("Catalogue of Life Extended Release ", xr_label, ", animal names GBIF has occurrence ",
                  "records of in Australia (gbif_au_animalia_names.parquet) with their accepted names and ",
                  "synonyms. Built with taxonAlign.dataprep::load_CatalogueOfLife() |> filter_to_country(\"AU\", ",
                  "gbif_taxon = \"Animalia\"), names known only from fossil specimens and ",
                  format(sum(barcode), big.mark = ","), " barcode clusters (BOLD BINs) left out"),
  source_file = paste0("https://api.checklistbank.org/dataset/", attr(col_xr, "key"), "/export.zip?format=ColDP; ",
                       "gbif_au_animalia_names.parquet"),
  retrieved = today, licence = "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
  citation = attr(col_xr, "citation"), source_md5 = NA_character_
)

manifest <- bind_rows(manifest)
readr::write_csv(manifest, file.path(out_dir, "manifest.csv"), na = "")

ready <- manifest[manifest$type == "ready", ]
notes <- c(
  sprintf("taxonAlign data release %s.", release), "",
  paste0(
    "Load these datasets with `taxonAlign::load_taxonomic_resources()`, e.g. ",
    "`load_taxonomic_resources(c(\"NSL_animals\", \"CatalogueOfLife_AU\"), version = \"", release, "\")`. ",
    "Each `<dataset>.parquet` file is the dataset in taxonAlign's reference format; the ",
    "`nsl_<group>_taxon`/`nsl_<group>_names` files are the National Species List exports it was built ",
    "from, stored verbatim (every column as text), and `gbif_au_animalia_names` the names GBIF had ",
    "Australian animal records of, which `CatalogueOfLife_AU` was filtered to. `manifest.csv` records each file's source, retrieval ",
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
