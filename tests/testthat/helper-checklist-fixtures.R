# Small WCVP- and COL-shaped fixtures, in each source's own raw layout (column names and value
# vocabularies checked against WCVP version 16 and COL26.10), for test-load_WCVP.R/test-load_CoL.R.

sample_wcvp_names_raw <- function() {
  cols <- c("plant_name_id", "ipni_id", "taxon_rank", "taxon_status", "family", "genus_hybrid", "genus",
            "species_hybrid", "species", "infraspecific_rank", "infraspecies", "parenthetical_author",
            "primary_author", "publication_author", "place_of_publication", "volume_and_page", "first_published",
            "nomenclatural_remarks", "geographic_area", "lifeform_description", "climate_description", "taxon_name",
            "taxon_authors", "accepted_plant_name_id", "basionym_plant_name_id", "replaced_synonym_author",
            "homotypic_synonym", "parent_plant_name_id", "powo_id", "hybrid_formula", "reviewed")
  rows <- tibble::tribble(
    ~plant_name_id, ~taxon_rank, ~taxon_status, ~family, ~genus_hybrid, ~genus, ~taxon_name, ~taxon_authors, ~accepted_plant_name_id,
    "1", "Genus", "Accepted", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus", "L'Hér.", "1",
    "2", "Species", "Accepted", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus globulus", "Labill.", "2",
    "3", "Species", "Synonym", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus gigantea", "Dehnh.", "2",
    "4", "Species", "Illegitimate", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus cordata", "Miq.", "2",
    "5", "Species", "Unplaced", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus dubia", "Sm.", NA,
    "6", NA, "Synonym", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus globulus nana", NA, "2",
    "7", "Genus", "Artificial Hybrid", "Orchidaceae", "×", "Cleisocalpa", "× Cleisocalpa", "anon.", "7",
    "8", "Variety", "Orthographic", "Myrtaceae", NA, "Eucalyptus", "Eucalyptus globulus var. globulis", "Labill.", "2"
  )
  out <- as.data.frame(matrix(NA_character_, nrow(rows), length(cols), dimnames = list(NULL, cols)))
  out[names(rows)] <- rows
  tibble::as_tibble(out)
}

# writes the fixture the way Kew does (pipe-delimited, no quoting), optionally zipped as wcvp.zip
write_sample_wcvp <- function(dir = withr::local_tempdir(.local_envir = parent.frame()), zip_as = NULL) {
  csv <- file.path(dir, "wcvp_names.csv")
  readr::write_delim(sample_wcvp_names_raw(), csv, delim = "|", na = "", quote = "none")
  if (is.null(zip_as)) return(csv)
  zipfile <- file.path(dir, zip_as)
  withr::with_dir(dir, utils::zip(zipfile, "wcvp_names.csv", flags = "-q"))
  zipfile
}

sample_col_usage_raw <- function() {
  tibble::tribble(
    ~`col:ID`, ~`col:parentID`, ~`col:status`, ~`col:rank`, ~`col:scientificName`, ~`col:authorship`,
    "N", NA, "accepted", "kingdom", "Animalia", NA,
    "F1", "N", "accepted", "family", "Nymphalidae", "Rafinesque, 1815",
    "G1", "F1", "accepted", "genus", "Vanessa", "Fabricius, 1807",
    "SG1", "G1", "accepted", "subgenus", "Vanessa (Cynthia)", "Fabricius, 1807",
    "S1", "SG1", "accepted", "species", "Vanessa cardui", "(Linnaeus, 1758)",
    "S2", "S1", "synonym", "species", "Cynthia cardui", "(Linnaeus, 1758)",
    "S3", "G1", "provisionally accepted", "species", "Vanessa novus", "Smith, 2020",
    "S4", "S3", "ambiguous synonym", "species", "Pyrameis novus", "Smith, 1900",
    "SC1", "G1", "accepted", "section botany", "Vanessa sect. Testa", NA
  )
}

write_sample_col_tsv <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  tsv <- file.path(dir, "NameUsage.tsv")
  readr::write_tsv(sample_col_usage_raw(), tsv, na = "", quote = "none")
  tsv
}
