# Small string helpers shared with taxonAlign, copied here (rather than imported) because taxonAlign
# keeps them internal -- the same reason taxonAlign vendors its own copies of APCalign's internal
# helpers. Keep them identical to taxonAlign's `R/match_taxa_helpers.R` versions: a name reshaped here
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

# Removes a bracketed subgenus from a species-level name: "Pardalotus (Pardalotinus) striatus" ->
# "Pardalotus striatus". Only the zoological "Genus (Subgenus) epithet..." shape is touched -- a
# bracket directly after the genus, followed by at least one more word (it may hold more than one
# subgenus, "Nassa (Alectryon, Aciculina) macrocephalus") -- so e.g. "Agaricia papillosa (pars)" or
# "Calodema (regale species group)" are left as they are.
#' @noRd
strip_subgenus_from_name <- function(x) {
  stringr::str_replace(x, "^(\\S+) \\([^()]+\\) (\\S.*)$", "\\1 \\2")
}
