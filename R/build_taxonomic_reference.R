# Interactive on-ramp for a user's own taxonomic reference table(s) (issue #8): maps whatever columns
# a table has onto taxonAlign's reference format, combines several tables in a chosen priority order,
# and hands back one table that taxonAlign::prepare_taxonomic_resources() accepts as-is. Moved here
# from taxonAlign's own `prepare_taxonomic_resources(interactive = TRUE)` when the package was split
# (taxonAlign issue #26) -- taxonAlign now only takes tables already in its format.
#
# Modelled on `traits.build`'s `metadata_add_traits()`/`metadata_add_locations()`/
# `metadata_add_contexts()`/`metadata_create_template()` (see `traits.build`'s `R/setup.R`):
# `utils::menu()` for single-choice picks, a `readline()`-driven validated loop for ordered/multi
# selections, free-text `readline()` prompts where there's no column to pick, and -- critically for
# testability -- every prompt has a `user_response`/`user_responses` escape hatch that substitutes a
# supplied value for the real prompt, so tests never need a real interactive session.
#
# The format itself (required columns, the Darwin Core names they're renamed from) is taken from
# taxonAlign::taxonomic_reference_schema(), not restated here, so the two packages can't drift apart.

#' Build a taxonomic reference table from your own data, interactively
#'
#' Turns one or more of your own taxonomic reference tables -- whatever their column names -- into a
#' single table in taxonAlign's reference format (see [taxonAlign::taxonomic_reference_schema()]),
#' ready to pass to [taxonAlign::prepare_taxonomic_resources()] or to save for later.
#'
#' Columns with a recognised name (taxonAlign's own, or the Darwin Core equivalent, e.g.
#' `canonicalName`, `taxonRank`) are picked up automatically. For any required column a table is still
#' missing you're prompted (in the style of `traits.build`'s `metadata_add_traits()`) to pick one of
#' the table's columns, or for some fields a fixed value or an automatically generated one. A table
#' that's already complete is never interrupted; one that isn't is first asked, once, whether it's
#' already fully aligned regardless, before being walked through the per-field prompts.
#'
#' Once every table supplied is resolved, you're asked whether there are any additional references to
#' include -- repeating for as many as you have -- so a single file can grow into a combined set. When
#' the final set has more than one table, you're asked once for their priority order (most
#' authoritative first): rows are combined in that order, which is the order taxonAlign prefers them
#' in when a name appears in more than one.
#'
#' @param taxonomic_resources A tibble, a path to a CSV file, or a (optionally named) list of either --
#'  one element per reference table. Optional (`NULL`): you'll then be prompted for a path to the
#'  first table, the same way you're prompted for every additional one.
#' @param user_responses Optional named list bypassing the real prompts -- for scripting or testing.
#'  Keyed by table name (matching `taxonomic_resources`'s names, or `"table 1"`/`"table 2"`/... if
#'  unnamed), each holding the responses for that table's missing fields (`already_aligned` (logical),
#'  `taxonomic_dataset`, `canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`, `genus`,
#'  `taxon_ID`, `accepted_name_usage_ID`), plus three top-level elements: `initial_table` (a table/path
#'  bypassing the prompt for the first table, when `taxonomic_resources` is `NULL`),
#'  `additional_tables` (an optionally-named list of further tables/paths to add, bypassing the "any
#'  additional reference(s)?" prompt loop -- each is still resolved via its own entry in
#'  `user_responses`, keyed the same way) and `priority_order`, when the final set has more than one
#'  table.
#'
#' @return One tibble in taxonAlign's reference format, combining every table in priority order.
#'  `taxon_ID` and `accepted_name_usage_ID` are character.
#'
#' @examples
#' \dontrun{
#' my_reference <- build_taxonomic_reference("my_species_list.csv")
#' taxonAlign::create_taxonomic_update_lookup(c("Boronia serrulata"), my_reference)
#' }
#'
#' @export
build_taxonomic_reference <- function(taxonomic_resources = NULL, user_responses = NULL) {

  if (is.null(taxonomic_resources)) {
    taxonomic_resources <- prompt_for_table_path(
      "Enter the file path for your taxonomic reference: ", user_responses$initial_table
    )
  }

  tables <- normalise_taxonomic_resources_input(taxonomic_resources)
  resolved <- purrr::imap(
    tables,
    function(data, label) resolve_taxonomic_resources_table(data, label, user_responses[[label]])
  )

  # Keep asking for one more taxonomic reference until the user says there isn't one -- rather than
  # requiring every table to be assembled up front, this lets someone start with just the one file
  # they have open and add others as they think of them. `user_responses$additional_tables` bypasses
  # the real loop for scripting/testing.
  extra_tables <- user_responses$additional_tables
  extra_index <- 0
  repeat {
    if (!is.null(extra_tables)) {
      extra_index <- extra_index + 1
      if (extra_index > length(extra_tables)) break
      new_raw <- extra_tables[[extra_index]]
      new_label <- names(extra_tables)[extra_index]
    } else {
      if (!prompt_yes_no("\nDo you have any additional taxonomic reference(s) to include?")) break
      new_raw <- prompt_for_table_path("Enter the file path for the additional taxonomic reference: ")
      new_label <- NULL
    }

    if (is.null(new_label) || new_label == "") new_label <- paste("table", length(resolved) + 1)
    if (is.character(new_raw) && length(new_raw) == 1) new_raw <- read_taxonomic_resources_file(new_raw)

    resolved[[new_label]] <- resolve_taxonomic_resources_table(new_raw, new_label, user_responses[[new_label]])
  }

  # character IDs on each table *before* combining -- bind_rows() errors outright on a type mismatch
  # (e.g. generate_GBIF_taxonomic_reference_list()'s integer taxon_ID vs. AFD's UUID strings)
  resolved <- purrr::map(resolved, function(tbl) {
    dplyr::mutate(tbl, taxon_ID = as.character(taxon_ID), accepted_name_usage_ID = as.character(accepted_name_usage_ID))
  })

  order <- if (length(resolved) > 1) {
    prompt_priority_order(names(resolved), user_responses$priority_order)
  } else {
    names(resolved)
  }
  dplyr::bind_rows(resolved[order])
}

# Normalises `taxonomic_resources` (a data frame, a file path, or a list of either, optionally named) into
# a *named* list of data frames -- reading any file-path elements via readr::read_csv(). Unnamed (or
# partially named) lists get positional labels ("table 1", "table 2", ...) for prompts/error messages.
#' @noRd
normalise_taxonomic_resources_input <- function(taxonomic_resources) {

  if (is.data.frame(taxonomic_resources)) {
    tables <- list(taxonomic_resources)
  } else if (is.character(taxonomic_resources) && length(taxonomic_resources) == 1) {
    tables <- list(read_taxonomic_resources_file(taxonomic_resources))
  } else if (is.list(taxonomic_resources) && length(taxonomic_resources) > 0) {
    tables <- purrr::map(
      taxonomic_resources,
      function(x) if (is.character(x) && length(x) == 1) read_taxonomic_resources_file(x) else x
    )
  } else {
    stop(
      "`taxonomic_resources` must be a tibble/data frame, a path to a CSV file, or a (optionally named) ",
      "list of either.", call. = FALSE
    )
  }

  labels <- names(tables)
  if (is.null(labels)) labels <- rep("", length(tables))
  unnamed <- which(labels == "")
  labels[unnamed] <- paste("table", unnamed)
  names(tables) <- labels

  tables
}

#' @noRd
read_taxonomic_resources_file <- function(path) {
  if (!file.exists(path)) {
    stop("`taxonomic_resources` names a file that doesn't exist: ", path, call. = FALSE)
  }
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

# Renames recognised Darwin Core columns, then either returns the table as-is (already complete) or
# prompts for whatever's still missing.
#' @noRd
resolve_taxonomic_resources_table <- function(data, table_label, user_responses) {

  schema <- taxonAlign::taxonomic_reference_schema()
  darwin_core <- schema[!is.na(schema$darwin_core), ]
  data <- data |> dplyr::rename(dplyr::any_of(stats::setNames(darwin_core$darwin_core, darwin_core$column)))
  missing_cols <- setdiff(schema$column[schema$required], names(data))

  if (length(missing_cols) == 0) {
    return(data)
  }

  # Give the user a chance to assert the table is already fully aligned before launching into the
  # full per-field prompt sequence -- e.g. it may already be in taxonAlign's format just under column
  # names the automatic rename above doesn't recognise. Asking at all means something genuinely is
  # missing by name, so "Yes" always ends in a clear error naming it; the point is to catch a wrong
  # assumption early with a precise message, not to bypass anything.
  if (prompt_already_aligned(table_label, user_responses$already_aligned)) {
    stop(
      "`", table_label, "` was indicated as already fully aligned, but is still missing required ",
      "column(s): ", paste(missing_cols, collapse = ", "), ". Answer \"No\" (or omit ",
      "`user_responses$already_aligned`) if it still needs column mapping.",
      call. = FALSE
    )
  }

  map_missing_taxonomic_resources_columns(data, missing_cols, table_label, user_responses)
}

# extra, non-column choices offered alongside real column names in various prompts below
.taxonAlign_same_as_canonical <- "(same as canonical_name)"
.taxonAlign_not_available <- "(not available)"
.taxonAlign_generate_automatically <- "(generate automatically)"
.taxonAlign_already_accepted <- "(every row is already an accepted name)"

# generic Yes/No prompt; `user_response`, if supplied, is a plain logical bypassing the real
# `utils::menu()` prompt
prompt_yes_no <- function(title, user_response = NULL) {
  if (!is.null(user_response)) return(isTRUE(user_response))

  choice <- utils::menu(c("Yes", "No"), title = title)
  if (choice == 0) stop("No selection made.", call. = FALSE)
  choice == 1
}

# Prompts for a taxonomic reference table via a file path -- used both for the initial table (when
# `taxonomic_resources` wasn't supplied at all) and for every "additional
# reference" after it, so obtaining the first table feels identical to obtaining every later one,
# rather than requiring the caller to already have a table in hand just to get started. Someone who
# already has a table (a path, or a tibble they've loaded themselves) still just passes it as
# `taxonomic_resources`/an `additional_tables` entry directly, bypassing this prompt entirely.
# `user_response`, if supplied, is itself a table or path, substituting for the real prompt.
prompt_for_table_path <- function(prompt_text, user_response = NULL) {
  if (!is.null(user_response)) return(user_response)
  readline(prompt = prompt_text)
}

# The special "is this table already fully aligned?" gate asked once per table, before the per-field
# prompt sequence, when the automatic column_rename step didn't resolve everything on its own --
# e.g. the table may already be in taxonAlign's target shape (from an earlier
# build_taxonomic_reference()/generate_GBIF_taxonomic_reference_list() call) just under column names
# column_rename doesn't recognise. `user_response`, if supplied, is a plain logical.
prompt_already_aligned <- function(table_label, user_response = NULL) {
  prompt_yes_no(
    title = sprintf(
      paste0(
        "\n`%s` is missing some of the columns taxonAlign expects by name. Is it already fully ",
        "aligned regardless (e.g. produced by an earlier `build_taxonomic_reference()` or ",
        "`generate_GBIF_taxonomic_reference_list()` call, just under different column names)?"
      ),
      table_label
    ),
    user_response
  )
}

# single-choice pick from `names(data)` plus any `extra_choices`; `user_response`, if supplied,
# substitutes for the real `utils::menu()` prompt (and is validated against the same choice set)
prompt_select_column <- function(field, data, extra_choices = character(0), user_response = NULL) {
  choices <- c(names(data), extra_choices)

  if (!is.null(user_response)) {
    if (!user_response %in% choices) {
      stop(
        "`user_responses` value for `", field, "` (\"", user_response, "\") is not one of the ",
        "available choices: ", paste(choices, collapse = ", "), ".", call. = FALSE
      )
    }
    return(user_response)
  }

  i <- utils::menu(choices, title = sprintf("\nSelect a column (or option) for `%s`", field))
  if (i == 0) stop("No selection made for `", field, "`.", call. = FALSE)
  choices[i]
}

# the "does this table have a column for `field`, or is every row the same value?" pattern -- used
# for `taxon_rank`/`taxonomic_status`/`taxonomic_dataset` (a combined spreadsheet someone has
# assembled by hand can just as easily mix rows from several sources as have one uniform one).
# Returns list(column = ..., fixed_value = ...), exactly one non-NULL.
# `user_response`, if supplied, is itself that same list shape.
prompt_column_or_fixed_value <- function(field, data, example_value, user_response = NULL) {
  if (!is.null(user_response)) {
    if (!is.null(user_response$column)) return(list(column = user_response$column, fixed_value = NULL))
    return(list(column = NULL, fixed_value = user_response$fixed_value))
  }

  choice <- utils::menu(
    c("Select a column", "Every row has the same value"),
    title = sprintf("\nDoes the data have a column for `%s`, or is every row the same value?", field)
  )
  if (choice == 1) {
    list(column = prompt_select_column(field, data), fixed_value = NULL)
  } else if (choice == 2) {
    list(column = NULL, fixed_value = readline(
      prompt = sprintf("Enter the value for `%s` (e.g. \"%s\"): ", field, example_value)
    ))
  } else {
    stop("No selection made for `", field, "`.", call. = FALSE)
  }
}

# fills in whichever of `missing_cols` this table is missing, prompting (or consulting
# `user_responses`, a named list keyed by field) for each -- only ever called with a non-empty
# `missing_cols`, from `resolve_taxonomic_resources_table()`
map_missing_taxonomic_resources_columns <- function(data, missing_cols, table_label, user_responses = NULL) {

  if ("taxonomic_dataset" %in% missing_cols) {
    # a combined spreadsheet someone has assembled by hand (e.g. mixing rows sourced from AFD and
    # iNaturalist into one table, with a column recording which) needs the column option here just as
    # much as taxon_rank/taxonomic_status do -- not every table is from a single, uniform source.
    res <- prompt_column_or_fixed_value(
      "taxonomic_dataset", data, "AFD",
      user_responses$taxonomic_dataset
    )
    data$taxonomic_dataset <- if (!is.null(res$column)) data[[res$column]] else res$fixed_value
  }

  if ("canonical_name" %in% missing_cols) {
    col <- prompt_select_column("canonical_name", data, user_response = user_responses$canonical_name)
    data$canonical_name <- data[[col]]
  }

  if ("scientific_name" %in% missing_cols) {
    col <- prompt_select_column(
      "scientific_name", data,
      extra_choices = .taxonAlign_same_as_canonical, user_response = user_responses$scientific_name
    )
    data$scientific_name <- if (identical(col, .taxonAlign_same_as_canonical)) data$canonical_name else data[[col]]
  }

  if ("taxon_rank" %in% missing_cols) {
    res <- prompt_column_or_fixed_value("taxon_rank", data, "species", user_responses$taxon_rank)
    data$taxon_rank <- if (!is.null(res$column)) data[[res$column]] else res$fixed_value
  }

  if ("taxonomic_status" %in% missing_cols) {
    res <- prompt_column_or_fixed_value("taxonomic_status", data, "accepted", user_responses$taxonomic_status)
    data$taxonomic_status <- if (!is.null(res$column)) data[[res$column]] else res$fixed_value
  }

  if ("genus" %in% missing_cols) {
    col <- prompt_select_column(
      "genus", data,
      extra_choices = .taxonAlign_not_available, user_response = user_responses$genus
    )
    data$genus <- if (identical(col, .taxonAlign_not_available)) NA_character_ else data[[col]]
  }

  # taxon_ID before accepted_name_usage_ID: the "every row is already accepted" self-reference option
  # below needs taxon_ID to already exist on `data`.
  if ("taxon_ID" %in% missing_cols) {
    col <- prompt_select_column(
      "taxon_ID", data,
      extra_choices = .taxonAlign_generate_automatically, user_response = user_responses$taxon_ID
    )
    data$taxon_ID <- if (identical(col, .taxonAlign_generate_automatically)) {
      paste0(table_label, "_", seq_len(nrow(data)))
    } else {
      as.character(data[[col]])
    }
  }

  if ("accepted_name_usage_ID" %in% missing_cols) {
    col <- prompt_select_column(
      "accepted_name_usage_ID", data,
      extra_choices = c(.taxonAlign_already_accepted, .taxonAlign_not_available),
      user_response = user_responses$accepted_name_usage_ID
    )
    if (identical(col, .taxonAlign_already_accepted)) {
      data$accepted_name_usage_ID <- data$taxon_ID
    } else if (identical(col, .taxonAlign_not_available)) {
      data$accepted_name_usage_ID <- NA_character_
      warning(
        "`accepted_name_usage_ID` was left unavailable for `", table_label, "` -- synonym rows in ",
        "this table won't resolve to a current accepted name via `update_taxa()` (they'll still align ",
        "via `align_taxa()`).", call. = FALSE
      )
    } else {
      data$accepted_name_usage_ID <- as.character(data[[col]])
    }
  }

  data
}

# prompts for a priority order across multiple tables (most authoritative first) when more than one
# is supplied; `user_response`, if supplied (`user_responses$priority_order`), is a vector of
# `table_labels` (or their positions) in the desired order, bypassing the real prompt
prompt_priority_order <- function(table_labels, user_response = NULL) {
  if (!is.null(user_response)) {
    idx <- if (is.character(user_response)) match(user_response, table_labels) else as.integer(user_response)
    if (anyNA(idx) || !setequal(idx, seq_along(table_labels))) {
      stop(
        "`user_responses$priority_order` must name (or index) each of the supplied tables exactly ",
        "once: ", paste(table_labels, collapse = ", "), ".", call. = FALSE
      )
    }
    return(table_labels[idx])
  }

  txt <- sprintf(
    paste0(
      "\nMultiple taxonomic reference tables were supplied. Enter their priority order (most ",
      "authoritative first -- i.e. which to prefer when a name appears in more than one), by number, ",
      "separated by spaces (e.g. '2 1 3'):\n%s\n"
    ),
    paste(sprintf("%d: %s", seq_along(table_labels), table_labels), collapse = "\n")
  )

  success <- FALSE
  while (!success) {
    cat(txt)
    i <- readline("\nPriority order: ")
    i <- suppressWarnings(as.integer(strsplit(i, " ")[[1]]))
    if (length(i) == length(table_labels) && setequal(i, seq_along(table_labels)) && !anyNA(i)) {
      success <- TRUE
    } else {
      message("Invalid selection -- please enter each table's number exactly once, separated by spaces.\n")
    }
  }
  table_labels[i]
}
