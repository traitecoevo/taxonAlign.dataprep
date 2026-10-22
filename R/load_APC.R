#' Load the Australian Plant Census (via APCalign)
#'
#' A thin wrapper around [APCalign::load_taxonomic_resources()]: combines APCalign's accepted, synonym,
#' genus and family tables into one table in taxonAlign's reference format, ready for
#' [taxonAlign::prepare_taxonomic_resources()].
#'
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#' @param ... Passed to [APCalign::load_taxonomic_resources()] (e.g. `stable_or_current_data`,
#'  `version`).
#'
#' @return A tibble in taxonAlign's reference format (see [taxonAlign::taxonomic_reference_schema()]).
#'
#' @export
load_APC <- function(quiet = FALSE, ...) {
  APC <- APCalign::load_taxonomic_resources(quiet = quiet, ...)
  # `family_accepted` is the one piece without a `taxonomic_dataset` column. No caching here:
  # APCalign::load_taxonomic_resources() already caches internally.
  dplyr::bind_rows(
    APC$APC_accepted, APC$APC_synonyms,
    APC$genera_accepted, APC$genera_synonym,
    APC$family_accepted |> dplyr::mutate(taxonomic_dataset = "APC"),
    APC$family_synonym
  )
}
