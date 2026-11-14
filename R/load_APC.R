#' Load the Australian Plant Census (via APCalign)
#'
#' A thin wrapper around [APCalign::load_taxonomic_resources()]: combines APCalign's accepted, synonym,
#' genus and family tables into one table in taxonAlign's reference format, ready for
#' [taxonAlign::prepare_taxonomic_resources()], with each record's `subclass` and `taxon_distribution`
#' from APCalign's full APC table (so the lookup reports them, as APCalign's does).
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
  flat <- dplyr::bind_rows(
    APC$APC_accepted, APC$APC_synonyms,
    APC$genera_accepted, APC$genera_synonym,
    APC$family_accepted |> dplyr::mutate(taxonomic_dataset = "APC"),
    APC$family_synonym
  )
  # The records synonyms lead to that APCalign's split tables leave out -- excluded taxa (not native or
  # naturalised in Australia): "Achneria brevifolia" -> "Eriachne brevifolia" (excluded). APCalign
  # follows synonyms to them in its full `APC` table; without them 24 synonyms led nowhere and the
  # result failed taxonAlign::check_taxonomic_reference(). Only those: the rest of the full table
  # (e.g. 24 excluded "Eucalyptus sp." placeholders) would become names to match against, which
  # APCalign never matches.
  missing_targets <- setdiff(flat$accepted_name_usage_ID, flat$taxon_ID)
  flat <- dplyr::bind_rows(flat, APC$APC[APC$APC$taxon_ID %in% missing_targets, ] |> dplyr::mutate(taxonomic_dataset = "APC"))
  # `subclass` and `taxon_distribution` are only in APCalign's full `APC` table; APCalign's own lookup
  # reports them, so taxonAlign's should too (traitecoevo/taxonAlign.dataprep#1)
  extra <- APC$APC[, c("taxon_ID", "subclass", "taxon_distribution")]
  out <- flat |>
    dplyr::select(-dplyr::any_of(c("subclass", "taxon_distribution"))) |>
    dplyr::left_join(extra[!duplicated(extra$taxon_ID), ], by = "taxon_ID") |>
    # only taxonAlign's columns and APC's rank columns: taxonAlign reads any other character column as
    # a rank, so APC's own metadata (nomInval, parentNameUsageID, nameAccordingTo, license, ...) each
    # became a bogus "taxon" rank
    dplyr::select(dplyr::any_of(c(taxonAlign::taxonomic_reference_schema()$column, taxonAlign_APC_rank_cols)))
  # APCalign's data version, which taxonAlign records in aligned_reason (when APCalign gives one)
  attr(out, "version") <- attr(APC, "version", exact = TRUE)
  out
}

# APC's columns that are ranks (`genus` is a required column already)
taxonAlign_APC_rank_cols <- c("kingdom", "class", "subclass", "family")
