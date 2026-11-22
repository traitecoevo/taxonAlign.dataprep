# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`taxonAlign.dataprep` (repo `traitecoevo/taxonAlign.dataprep` -- created as `taxonalign-dataprep`, renamed to match the
package on 2026-10-22; the local folder is still `../taxonalign-dataprep`. Dotted, traits.build-style,
since R package names can't have a hyphen) is the companion to [taxonAlign](https://github.com/traitecoevo/taxonAlign)
(sibling checkout `../taxonAlign`). taxonAlign matches and updates names against a reference in its
documented format (`taxonAlign::taxonomic_reference_schema()`); this package builds references in that
format and builds the dated data releases `taxonAlign::load_taxonomic_resources()` downloads. Split out
of taxonAlign on 2026-10-22 ([taxonAlign issue #26](https://github.com/traitecoevo/taxonAlign/issues/26),
Will Cornwell's suggestion) -- see taxonAlign's CLAUDE.md, "The package split", for the decisions made
then (don't re-litigate them). Everything here was copied from taxonAlign at commit `f6f691d`; git
history for it before the split is in that repo.

Exported functions, each returning one flat table in taxonAlign's format:
- `load_APC()` -- thin `APCalign::load_taxonomic_resources()` wrapper (was
  `taxonAlign::load_taxonomic_resources("APC")`).
- `load_NSL(taxon_group, path = NULL, version = NULL)` -- an NSL export pair (Architecture #4; was
  `taxonAlign::load_NSL_resources()`). By default it reads the verbatim
  `nsl_<group>_{taxon,names}.parquet` copies from a data release (via
  `taxonAlign::download_data_release_files()`), so -- like `taxonAlign::load_taxonomic_resources()` and
  APCalign -- no file of the user's own is needed (user's requirement); `path` reads raw `.csv`/`.txt`
  exports, or a folder of a release's parquet copies (`find_NSL_file()` accepts a `.` after the marker).
- **No `load_AFD()`** (removed 2026-10-22, user's decision): the AFD comes in through
  `load_NSL("animals")`. The AFD-format (CSV export) reader is kept, unexported, as the appendix chunk of
  `vignettes/AFD-data-processing.qmd` (defining `load_AFD()` and its helpers there), for continuing the
  AFD-format vs NSL-format comparisons for the curators. Architecture #3 below describes that code.
  Three of its helpers are shared with `load_NSL()` and live in `R/load_NSL.R`: `strip_name_quotes()`,
  `strip_afd_usage_markers()`, `afd_usage_status()`. Its ~200 offline tests went with it (recoverable
  from this repo's first commit, f7e4518); its output on the real 2026 and old AFD exports is
  identical to the pre-split loader's (see "Old vs new comparison" below).
- `load_WCVP(version = NULL, path = NULL)` -- the World Checklist of Vascular Plants (Kew), and
  `load_CatalogueOfLife(version = NULL, extended = FALSE, path = NULL)` -- the Catalogue of Life from
  ChecklistBank (was `load_CoL()`, renamed 2026-11-14: user wanted it spelled out "so people know").
  Both added 2026-10-22 at the user's request; see "Worldwide checklists" below.
- **No GBIF Backbone builders** (`generate_GBIF_taxonomic_reference_list()`,
  `generate_taxadb_taxonomic_reference_list()`, removed 2026-11-14 -- issue #1, user: "move to CoL"):
  GBIF replaced its Backbone with the Catalogue of Life Extended Release (rgbif 3.9.0), so
  `load_CatalogueOfLife(extended = TRUE) |> filter_to_country(...)` is the replacement. See
  Architecture #1.
- `filter_to_country(reference, country, gbif_taxon = NULL, ...)` -- restricts any reference (WCVP,
  COL, ...) to taxa GBIF has occurrence records of in one or more countries; see "Country filter" below.
- `build_taxonomic_reference()` -- the interactive on-ramp (was
  `taxonAlign::prepare_taxonomic_resources(interactive = TRUE)`); see "Interactive on-ramp" below.

Old names still appear in the historical notes below; read them through this mapping. Architecture
section numbers match taxonAlign's pre-split CLAUDE.md (#2, the matching engine, and #5's loader half
stayed in taxonAlign).

## Commands

```r
devtools::load_all()       # load the package for interactive development
devtools::document()       # regenerate NAMESPACE/man/*.Rd from roxygen comments
devtools::test()           # run the testthat suite
devtools::check()          # full R CMD check
```

Imports taxonAlign (`Remotes: traitecoevo/taxonAlign`, plus `traitecoevo/APCalign`). Tests call
`taxonAlign::prepare_taxonomic_resources()`/`create_taxonomic_update_lookup()`/
`check_taxonomic_reference()` end to end, against the *installed* taxonAlign -- after changing
taxonAlign, `devtools::install("../taxonAlign")` before running these tests. `extract_genus()` is
vendored in `R/utils.R` (taxonAlign keeps it internal); keep it identical to taxonAlign's
`R/match_taxa_helpers.R` copy.

Imports: `APCalign`, `arrow`, `curl`, `dplyr`, `jsonlite`, `purrr`, `readr`, `rgbif`, `rlang`,
`stats`, `stringr`, `taxonAlign (>= 0.0.0.9001)`, `tools`, `utils`. Suggests: `testthat`, `tibble`,
`withr`. (`parallel`, `taxadb`, `duckdb`, `DBI` went with the GBIF Backbone builders.)

The default cache dir is deliberately still `tools::R_user_dir("taxonAlign", "cache")` -- the same as
taxonAlign's, so the large, resumable GBIF fetch cache already built there keeps working.

Large raw inputs aren't committed: `data-raw/sources/` and `data-raw/release/` are gitignored. The
real exports currently still sit in the taxonAlign checkout (`../taxonAlign/data/AFD_2026-10-07/`,
`../taxonAlign/data/AFD_NSL_export_20260929/`, `../taxonAlign/inst/extdata/`, untracked there), as do
the GBIF archives (`../taxonAlign/ignore/`, e.g. `gbif_au_animals_with_extinct.rds`) and the AFD format
vs NSL format comparison script (`../taxonAlign/ignore/AFD_export_comparison.R`).

### Testing

`test-filter_to_country.R` covers `filter_to_country()` and `resolve_gbif_taxon()` offline, every
`rgbif::` call mocked with `testthat::local_mocked_bindings(..., .package = "rgbif")`.

`test-load_NSL.R` covers `load_NSL()` against two hand-built NSL taxon/names fixture pairs (`helper-nsl-fixtures.R`) --
one plant-side camelCase-CSV, one animals pipe-delimited snake_case -- plus reading a release's
verbatim parquet copies (identical output to the original files), the release default (taxonAlign's
download mocked), and the three AFD-marker helpers shared with the vignette's AFD-format reader. `test-build_taxonomic_reference.R`
covers `build_taxonomic_reference()` by supplying `user_responses` throughout (never a real
interactive session), mostly going on through `taxonAlign::prepare_taxonomic_resources()` (helper
`build_and_prepare()`), using a copy of taxonAlign's `sample_taxonomic_resources()` fixture
(`helper-align-taxa-fixtures.R`). All offline.

177 expectations, all passing as of the last `devtools::test()` run (2026-11-14), all offline (the removed GBIF/taxadb builders took ~90 with them).

Gotcha if you add more end-to-end tests: don't wrap a block of `local_mocked_bindings()` calls in a
plain helper function and call that helper from inside `test_that()` without forwarding `.env` — the
mock's lifetime is tied to `local_mocked_bindings()`'s *own calling frame*, so it gets undone the moment
that helper function returns, before the test body runs (this silently falls through to real network
calls rather than erroring). Give the helper a `.env = parent.frame()` argument and pass it through, as
`local_mock_gbif_end_to_end()` in the test file does.

## Interactive on-ramp — `R/build_taxonomic_reference.R` (exported: `build_taxonomic_reference()`)

`build_taxonomic_reference(taxonomic_resources = NULL, user_responses = NULL)` was
`taxonAlign::prepare_taxonomic_resources(interactive = TRUE)` before the split. It now returns one
combined flat table (each table's IDs made character, bound in the chosen priority order) instead of
prepared `resources`; pass that to taxonAlign. There's no `interactive` argument any more -- the
function only ever prompts for what's missing, and `user_responses` substitutes for every prompt. The
required columns and the Darwin Core rename map come from `taxonAlign::taxonomic_reference_schema()`
(not restated here). Pre-split design notes, with `prepare_taxonomic_resources(interactive = TRUE)`
meaning this function:

- `prepare_taxonomic_resources()`'s `interactive`/`user_responses` arguments (`R/prepare_taxonomic_resources_interactive.R`)
  are the "let a user bring their own reference table" on-ramp sketched in comments in
  `R/match_taxa_for_inverts_202500304-use this.R` — modelled directly on `traits.build`'s
  `metadata_add_traits()`/`metadata_add_locations()`/`metadata_add_contexts()`/`metadata_create_template()`
  (`traits.build`'s `R/setup.R`): `utils::menu()` for single-choice picks, a `readline()`-driven
  validated loop for ordered selections, and — critically for testing — every prompt has a
  `user_response`/`user_responses` escape hatch that substitutes a supplied value, so tests never open
  a real interactive session (see `test-prepare_taxonomic_resources_interactive.R`, all of which pass
  `user_responses` rather than prompting). `taxonomic_resources` now also accepts a file path or a
  (optionally named) list of tibbles/paths, one per source dataset to combine; when more than one is
  supplied, priority is expressed purely by row order in the bind_rows()'d result (since
  `match_taxa()`'s exact blocks use first-hit `match()` semantics) — `interactive = TRUE` prompts once
  for that order (or consults `user_responses$priority_order`), `interactive = FALSE` just uses
  supply-order with no prompt. **Each table's `taxon_ID`/`accepted_name_usage_ID` is normalised to
  character *before* that `bind_rows()`, not after** -- found necessary combining AFD (character UUID
  strings) with a `generate_GBIF_taxonomic_reference_list()`-derived table (integer `taxon_ID`, its own
  raw GBIF usageKey): `dplyr::bind_rows()` errors outright on a type mismatch across the tables being
  combined ("Can't combine `..1$taxon_ID` <character> and `..2$taxon_ID` <integer>") rather than
  coercing, and the existing single-table `as.character()` normalisation (kept for the interactive-input
  path) ran only *after* this combine step -- too late to prevent the crash. A table missing no required columns is never interrupted, even in
  `interactive = TRUE` mode — only genuinely-missing fields get prompted for, so
  `generate_GBIF_taxonomic_reference_list()`'s output (already complete) sails through untouched. When a
  table *is* missing something, it's first asked (once, `prompt_already_aligned()`) whether it's
  already fully aligned regardless (e.g. from an earlier `prepare_taxonomic_resources()`/
  `generate_GBIF_taxonomic_reference_list()` call, just under column names `column_rename` didn't
  recognise) — note this can only ever end in either a clear, specific error naming what's still
  missing (since reaching this prompt at all means something genuinely is absent by name) or "No",
  proceeding into the normal per-field prompts; there's no silent-success branch, by construction, and
  that's intentional — it exists to catch a wrong assumption early with a precise message, not as a
  bypass.
- Once every initially-supplied table is resolved, `interactive = TRUE` also loops asking "Do you have
  any additional taxonomic reference(s) to include?" (`prompt_yes_no()`) — repeating for as many as the
  user has — before the priority-order prompt. This is asked *unconditionally* (regardless of whether
  the initial table(s) needed any column mapping at all), unlike `prompt_already_aligned()` above,
  because its purpose is different: letting someone start with a single file (`taxonomic_resources`) and
  grow it into a combined set interactively, rather than requiring the whole set assembled up front.
  `user_responses$additional_tables` (an optionally-named list of further tables/paths) bypasses the
  real loop for tests/scripting — each entry still goes through the exact same `resolve_taxonomic_resources_table()`
  path as any other table, consulting `user_responses[[its own label]]` for its own missing fields.
- **`taxonomic_resources` is optional when `interactive = TRUE`**: if it's `NULL`, the *first* table is now
  obtained via the same prompt used for every *additional* one (`prompt_for_table_path()`, shared by
  both call sites) — asking for a file path via `readline()` — rather than requiring the caller to
  already have assembled a table before they can even start. `user_responses$initial_table` bypasses
  this for scripting/testing, the same way `additional_tables` already does for later ones. Before this,
  someone starting from scratch had to hand-assemble their own `list(...)` of tables in R code before
  ever calling the function at all, which is real friction for exactly the users this on-ramp is meant
  to help — found by re-reading the `get-started.qmd` vignette's own "combining multiple references"
  example.
- **`taxon_rank`/`taxonomic_status`/`taxonomic_dataset` share one prompt shape**
  (`prompt_column_or_fixed_value()`): "does the data have a column for this, or is every row the same
  value?" -- picking a column reads a per-row value, a fixed value applies the same one to every row.
  `taxonomic_dataset` used to be a plain free-text prompt (always one label for the whole table, no
  column option) until a real case surfaced it: a spreadsheet someone assembles by hand can just as
  easily mix rows sourced from several references (e.g. some rows from AFD, some from iNaturalist,
  with a column recording which) as have one uniform source. Moved onto the same
  `prompt_column_or_fixed_value()` path as the other two rather than keeping a separate, more limited
  mechanism — this also retired `prompt_free_text()` entirely (it had no other caller).

## Worldwide checklists — `R/load_WCVP.R`, `R/load_CatalogueOfLife.R` (exported: `load_WCVP()`, `load_CatalogueOfLife()`)

Both download their source directly (like `load_APC()`, not via a taxonAlign data release), cache the
download *and* the reshaped `.rds` under `<cache_dir>/WCVP/` and `<cache_dir>/CoL/`, can be pinned, and
attach `"version"`/`"citation"` attributes (COL also `"key"`/`"doi"`). Downloads go through
`download_to_cache()` (`R/utils.R`: temp file renamed on success; via `curl`, no overall time limit but
given up after 2 min under 100 B/s -- R's default 60s is far too short for these files; a failure
reports the HTTP status and the server's message, and is a `taxonAlign_download_error` carrying
`$status` (NA if never reached) -- it used to say "Check that you're online" for everything, which hid
issue #2's 404); version lookups through `try_fetch()` (5s connect / 30s), so being offline
falls back to a cached copy rather than hanging. Only the required 8 columns (+ WCVP's `family`) are
returned -- any other character column would be scanned as a hierarchy column by
`taxonAlign::prepare_taxonomic_resources()` and turned into bogus "taxa" (e.g. `ipni_id`, `powo_id`).

- **WCVP** (checked against version 16, 2026-06-04, 1,448,984 names): `https://sftp.kew.org/pub/data-repositories/WCVP/wcvp.zip`
  is always the current version; superseded ones move to `Archive/wcvp_v<N>.zip` (v10-v15 there in
  Oct 2026). The zip's `README_WCVP.xlsx` names its version (`Version "16"`) and citation; read by
  `WCVP_zip_readme()` from the xlsx's `sharedStrings.xml`, no xlsx dependency. **`version = NULL`
  downloads the current version the first time, then uses that cached version without going online**
  (user's requirement, 2026-10-22: "load off their respective APIs [the first time] and thereafter use
  a cached version"; recorded in `current.dcf`: version, Last-Modified, download date). Only
  `refresh_cache = TRUE` checks Kew (HEAD request, compare `Last-Modified`; downloads again only if
  changed; offline -> the cached version with a message). A named version is looked for in the cache,
  then the archive, then the current zip (whose README must match; this path does check online). `wcvp_names.csv` is pipe-delimited, no quoting (read with
  `quote = ""`). Mapping: `canonical_name = taxon_name`, `scientific_name` + `taxon_authors`,
  `accepted_name_usage_ID = accepted_plant_name_id`, else own ID (all 38,571 Unplaced + 8 others have
  none); every link resolves (checked). Statuses lower-cased, `Orthographic` -> `"orthographic
  variant"` (`taxonAlign_WCVP_status`; an unknown status errors). `Artificial Hybrid` (4,391) and `Local
  Biotype` (1,452) are self-referential names, kept as their own statuses -- so, like `"unplaced"`,
  update_taxa() gives them no accepted name (user confirmed, 2026-10-22). The 2,744 blank-rank names (unmarked trinomials, e.g.
  *Aquilegia vulgaris inversa*) get rank `"infraspecific name"`. `genus` = `genus_hybrid` + `genus`
  (`"× Cleisocalpa"`), matching the genus record's own `taxon_name`. No family records exist in WCVP;
  `family` is kept so prepare synthesises them.
- **COL** (checked against COL26.10, key 316595, 5,466,019 names): `GET /dataset/{key or alias}`
  gives the metadata (alias `"3LR"` = latest release); `GET /dataset/{key}/export.zip?format=ColDP`
  302-redirects to a *prepared* export zip (~169MB; prepared exports existed for COL22, COL25,
  COL26.10). **A release can have no prepared export** (issue #2, 2026-11-22): COL26.11 (key 317005,
  issued 2026-11-11) gave `404 "ColDP archive for dataset 317005 not found"` 11 days after release;
  ChecklistBank's exports are generated by its logged-in users (`POST /dataset/{key}/export`; 401
  anonymously), not on release: `GET /export?datasetKey=` listed six for COL26.10 from several
  accounts, the first 5 days after release, and none for COL26.11 in any format. So the loader had
  relied on some other user having made one -- and would have failed in COL26.10's first five days too.
  This says nothing about how much COL26.11 was used: most users get the COL's own release files.
  `download_CoL_release()` then falls back, on a 404 only, to the COL's own copy of the release (`CoL_archive_url()`): `https://download.checklistbank.org/col/monthly/<issued>_coldp.zip`
  (named by the metadata's `issued` date) or `annual/<year>_coldp.zip` (alias with no ".", e.g.
  `"COL25"`) -- ~1GB, since it also holds references, distributions, type material, etc.
  (`NameUsage.tsv` 2.3GB unpacked); the user chose this over falling back to the previous release
  ("latest" stays the latest). The Extended Releases have no such copy (`latest_xr_coldp.zip` 404s):
  an unprepared XR is a clear error suggesting `version =`. Only `CoL_columns_used` are read
  (`col_select`), so the wider table costs little memory. **Validated 2026-11-22**: the user's `load_CatalogueOfLife()` (COL26.11)
  fell back and loaded 5,468,883 names in 7.8 min, passing `check_taxonomic_reference()`; COL26.10
  loaded both ways gives identical results (5,466,019 rows, same IDs, every column equal) -- except that
  the COL's own copy has an `extinct` column (215,206 TRUE, 1,023,274 FALSE, the rest NA) that
  ChecklistBank's export lacks, so a release loaded via the fallback carries `extinct` and one from
  the export doesn't. The plain (non-extended) ColDP zip holds only `metadata.yaml` + `NameUsage.tsv` with six
  columns: `col:ID`, `col:parentID`, `col:status`, `col:rank`, `col:scientificName`, `col:authorship`.
  For a synonym (`synonym`/`ambiguous synonym`/`misapplied`), `parentID` is its accepted name (all
  2.75M checked: every one points at an accepted or provisionally accepted name); for an accepted name
  it's the parent *taxon*, so accepted rows are made self-referential. IDs are unique.
  **`"provisionally accepted"` -> `"accepted"`** (86,470 names, plus 12k synonyms leading to them):
  otherwise update_taxa() would never report their accepted name (user confirmed, 2026-10-22). Rank qualifiers dropped (`"section botany"` -> `"section"`, `"series zoology"` ->
  `"series"`); subgenus `"Zyras (Craspa)"` -> bare `"Craspa"`, genus `"Zyras"`; `genus` is the first
  word for genus rank and any multi-word name, else NA. ChecklistBank's citation is HTML only (no
  plain-text format: 406 for every Accept header tried), so `format_CoL_citation()` rebuilds it from
  the metadata (creators, year, title, version, publisher, DOI), in COL's own form (19 authors then
  "et al."). Metadata cached as `<cache_dir>/CoL/<key>/metadata.rds`. **Same cache-first rule as the
  WCVP**: `"3LR"` is looked up online the first time and recorded in `<cache_dir>/CoL/latest.rds`; later
  calls use that release without going online, until `refresh_cache = TRUE` looks it up again --
  **but only once that release is downloaded** (`CoL_downloaded()`: its zip or reshaped `.rds`). Issue
  #2's other half: `latest.rds` is written at lookup, before the download, so a failed download used to
  pin "3LR" to a release that never loaded, and every later call failed without going online; the
  offline "3LR"/"3LXR" fallback likewise only picks downloaded releases. A key or
  alias already cached never goes online; a release's zip, once downloaded, is never downloaded again
  (releases don't change). Offline with nothing usable cached: `"3LR"` -> the newest cached release,
  other aliases looked up in the cache, else a clear error.
- **The Extended Release comes as a flat table, not ColDP** (2026-11-14): ChecklistBank's
  `export.zip?format=ColDP` for COL26.10 XR (key 316691; 137MB zip) holds `dataset-316691.tsv` (1.5GB,
  same `col:` columns plus the classification, no `extinct`), not `NameUsage.tsv`; `CoL_name_table()`
  reads whichever is there. `load_CatalogueOfLife(extended = TRUE)` = alias `"3LXR"`, tracked in
  `latest_XR.rds` apart from `"3LR"`'s `latest.rds`.
- **Slow first time, by design**: COL26.10's first `load_CoL()` took ~23 min here (download slowed by
  other jobs; ~3 min alone) plus reshaping 5.5M names; a cached load ~20 s (reading the .rds). Both print
  a "slow the first time" message (user's wording, 2026-10-22) only when nothing is cached. Aligning 10
  names against the whole COL took ~10 min, nearly all `prepare_taxonomic_resources()` on 5.5M rows --
  hence the vignette's "prepare once and reuse / filter to a country first" advice.
- **Seen against the real COL, not a loader bug**: `"Cynthia cardui"` isn't in COL26.10 at all, so it
  falls to genus; COL has six homonymous genus records `"Cynthia"` (all synonyms, leading to
  *Halocynthia*, *Bithia*, *Siriella*, *Microcephalus*, *Vanessa*, *Krigia*) and taxonAlign's
  update_taxa() silently takes the first (`Halocynthia`). A genus synonym leading to several accepted
  genera gets no split/ambiguity flag (splits handling is species-synonyms-only, by the user's choice) --
  a taxonAlign question, raised with the user, not changed.
- Tests: `test-load_WCVP.R`, `test-load_CatalogueOfLife.R` against `helper-checklist-fixtures.R` (each source's own
  raw layout), network mocked.

## Country filter — `R/filter_to_country.R` (exported: `filter_to_country()`)

The user's design (2026-10-22): download a worldwide reference, then limit it with GBIF's country
occurrences, accepting that the taxonomies don't match -- a GBIF name recorded in the country can match
the reference's accepted name *or* a synonym; either way the reference's accepted name is kept, with
all of its synonyms. Deliberately *not* via WCVP's own TDWG distribution data or COL's patchy
distribution data (the user stopped that line of investigation): GBIF works the same for any reference.
- **GBIF's taxonomy is COL XR** (2026-11-14, issue #1): every query names `checklistKey =
  gbif_COL_XR_checklist_key`; names come back as the XR writes them. Cached as
  `gbif_names_COLXR_<key>_<cc>[_<hash of ...>][_nofossil].rds` -- old Backbone-era caches (no `COLXR`)
  are never reused. The names used are returned as `attr(x, "gbif_names")` (the release stores them).
- **Unranked names are kept only if recorded** (2026-11-14): `country_filter_records()` used to count
  any one-word, non-genus name as "above genus" (kept whole), so all 2.17M of the COL XR's `"unranked"`
  barcode clusters were kept whatever the country (2.8M of 8.5M records for AU animals). Ranks
  `"unranked"`/`"other"`/`"no rank"`/NA now count only if GBIF has records of them.
- **Validated 2026-11-14 on COL26.10 XR** (`load_CatalogueOfLife(316691)`: 8,504,545 names in 2.6 min,
  passes `check_taxonomic_reference()`): AU Animalia -> 220,416 GBIF names after 1,406 fossil-only ones,
  630,158 records kept (253k accepted, 366k synonym; 369k species, 132k genus -- 81k of them synonyms --
  and every family worldwide, by the "above genus kept whole" design), 119,777 of 124,696 species-level
  GBIF names matched; passes the check; 0 barcode clusters left after the fix above. Fossil exclusion is
  by `basisOfRecord`, so it's partial: genus *Diprotodon* stays (some of its records aren't labelled
  FOSSIL_SPECIMEN). The reporter's case: WCVP v16 for MY/BN/SG keeps 192,227 records (192,196 on the
  Backbone under rgbif 3.8.5).
- **`exclude_fossils = TRUE`** (2026-11-14): replaces `GBIF_AU`'s extinct flag, which the XR doesn't
  have. A second facet query on `basisOfRecord = "FOSSIL_SPECIMEN"`; a name whose total record count is
  no more than its fossil count is dropped (*Diprotodon*), one with any non-fossil record stays (the
  thylacine). Skipped when `...` has its own `basisOfRecord`. rgbif turns a vector `basisOfRecord` into
  separate queries (a list of results), hence the count comparison rather than one filtered query.

- **Names, not keys**: one `rgbif::occ_search(facet = "scientificName", scientificName.facetLimit =
  1e5, facetOffset paging)` per country (per `gbif_taxon` root) returns the names occurrences are
  identified to, with authorship (56,825 for AU Tracheophyta, one request) -- no backbone tree needed,
  unlike `generate_GBIF_taxonomic_reference_list()`'s key-based country filter. rgbif's default
  `occurrenceStatus = "PRESENT"` applies. Names are parsed with `rgbif::name_parse()` in batches of 1000
  (~3s each; ~3 min for AU plants), keeping `canonicalnamewithmarker`. Cached as
  `<cache_dir>/gbif_names_<rootkey|all>_<CC>[_<hash of extra filters>].rds`, cache-first like
  load_WCVP() (no age limit; `refresh_cache = TRUE` to refetch).
- **Matching** (`country_match_key()`): `APCalign::strip_names()` on both sides, hybrid sign always
  followed by a space (GBIF's parser writes `"Acaena ×ovina"`, WCVP `"Acaena × ovina"`), and on the GBIF
  side an autonym becomes its species (`"Cheilanthes sieberi subsp. sieberi"` -> `"cheilanthes
  sieberi"`; WCVP doesn't list autonyms). Exact only, no fuzzy matching (over-inclusion risk). These two
  fixes took AU matched species-level names from 49,826 to 50,653 of 52,330; the remaining 1,677 are
  spelling/gender variants (`"Cycnogeton procerum"`), informal names (`"Eucalyptus spec."`) and names
  WCVP lacks -- returned as `attr(x, "unmatched")`.
- **Retention** (`country_filter_records()`): species level = multi-word, not genus/subgenus rank;
  keep every record whose accepted ID is the accepted ID of a recorded name; `whole_species = TRUE`
  also keeps every accepted taxon sharing a binomial with a kept one (subspecies/varieties of a kept
  species, the species of a kept subspecies), with synonyms. Genera of kept taxa (and genera recorded at
  genus rank) kept with their synonyms; subgenera of kept genera; everything above genus kept whole;
  finally every record a kept record leads to, so the result passes `check_taxonomic_reference()`.
- `gbif_taxon` defaults by `taxonomic_dataset` (`taxonAlign_country_filter_default_taxon`: WCVP ->
  `"Tracheophyta"`, key 7707728); otherwise no taxon limit (every occurrence in the country). Extra
  `...` go to `occ_search()` (e.g. `basisOfRecord`), and into the cache key.
- Real run, WCVP 16 + AU (2026-10-22): 326,436 of 1,448,984 records kept, ~1.6 min first time.
  Real linking example (used in the vignette): GBIF's AU records use *Polypompholyx multifida*, a WCVP
  synonym of *Utricularia multifida*. (*Racosperma dealbatum* -> *Acacia dealbata* is a WCVP synonym but
  isn't in GBIF's AU names -- don't use it as the example.)
- Tests: `test-filter_to_country.R` (rgbif mocked).

## Old vs new comparison (2026-10-22)

After the split, the big compilations were rebuilt with the pre-split taxonAlign (`f6f691d`,
installed into a scratch library) and with the split packages, on identical inputs, and compared with
`all.equal()`: **all identical**. That covers each NSL group (old `load_NSL_resources()` vs `load_NSL()`
from the release's raw files vs the ready `NSL_<group>.parquet`); `GBIF_AU` (vs the old loader minus
its 47,796 extant no-name rows, which prepare dropped anyway); the AFD format (2026 export and old
`AFD.csv`, old loader vs the vignette's reader); the 28-phylum AU invertebrate GBIF reference rebuilt
from `ignore/gbif_cache_backup`; every prepared `resources` table (NSL animals, NSL animals + GBIF_AU,
AFD 2026, AFD + GBIF inverts, the four plant-side NSL groups); and the full 5,154-name
`create_taxonomic_update_lookup(full = TRUE)` against four of those references (all 40 columns). Only
difference in output: the old run's "missing (NA) canonical_name" warning, gone because `GBIF_AU` no
longer contains those rows. Scripts were in the session scratchpad, not kept. (Run before taxonAlign's
later 2026-10-22 split fix -- see its CLAUDE.md, "Synonym splits" -- which by design changes
`alternative_possible_names` for combined references, and for 6 duplicated valid names in each AFD
format.)

## Architecture

### 1. GBIF: the Backbone builders (removed) and COL XR — `R/gbif_helpers.R`

`generate_GBIF_taxonomic_reference_list()` (live GBIF Backbone fetch: name resolution, recursive
paginated `name_lookup()` tree fetch split by children past GBIF's 100,000-offset limit, a country
filter via an occurrence `taxonKey` facet, extinct flags) and `generate_taxadb_taxonomic_reference_list()`
(taxadb's GBIF/ITIS snapshots, and issue #23's `gbif_snapshot_url` for the 2026 GBIF snapshot) were
**removed 2026-11-14** (issue #1). rgbif 3.9.0 (CRAN 2026-10-05) made the Catalogue of Life Extended
Release (COL XR, checklist `7ddf754f-d193-4cc9-b351-99906754a03b`) its default taxonomy; GBIF calls the
Backbone out of date, and `name_lookup()`/`name_usage()` are deprecated. The user chose to replace them
with the Catalogue of Life, spelled out in names. Their code, tests and the long design notes (incl. the
multi-day 2026-08 Australia fetch and BOLD BIN handling) are in git history before that date.

What survives, in `R/gbif_helpers.R`, is what `filter_to_country()` uses: `gbif_COL_XR_checklist_key`,
`gbif_curlopts`, `with_gbif_retry()`, and `resolve_gbif_taxon()` -- `rgbif::name_backbone()` with
`checklistKey` = COL XR (passed explicitly so rgbif 3.8.5, which defaults to the Backbone, gives the
same keys; verified live under both), alphanumeric keys kept as character ("TP" Tracheophyta,
"N" Animalia), a synonym followed via `acceptedUsageKey`, and errors on `"NONE"` (homonyms come back
this way, with a `note`) and `"HIGHERRANK"` matches rather than filtering on a whole kingdom. The bug
that started this (issue #1): under 3.9.0 the old code's `as.integer("TP")` was `NA`, the facet query
ran with no taxon, and the empty result was cached as `gbif_names_NA_<cc>.rds`.

### 3. Known-source reference loaders — `R/load_APC.R` (exported: `load_APC()`); the AFD-format reader now lives in `vignettes/AFD-data-processing.qmd`'s appendix

`load_taxonomic_resources(taxonomic_dataset = ...)` (issue #6) fetches/reshapes a fixed set of *known*
taxonomic datasets into taxonAlign's flat, `prepare_taxonomic_resources()`-ready column schema
(`canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`, `taxonomic_dataset`, `genus`,
`taxon_ID`, `accepted_name_usage_ID`) — complementing (not replacing) `prepare_taxonomic_resources()`
the same way `generate_GBIF_taxonomic_reference_list()` does for GBIF, except `"AFD"`'s "fetch" is
reading+reshaping a local file rather than an API call, and `"APC"` is a thin wrapper around
`APCalign::load_taxonomic_resources()`. Always returns a *named list* of flat tibbles (one per
requested dataset, even for a single one), so a user combines any mix of known and their own
reference tables identically: `prepare_taxonomic_resources(load_taxonomic_resources(c("AFD", "APC")))`.
Errors immediately, naming the known datasets, on an unrecognised `taxonomic_dataset` value —
`taxonAlign_known_datasets` (top of the file) is the registry to extend as further sources are added.

- **`"AFD"` (Australian Faunal Directory)**: AFD only exists as a one-off raw CSV export (no public
  API, unlike GBIF) — `inst/extdata/AFD.csv` (~89MB, ~117k rows, one row per species/subspecies).
  `load_AFD()` ports the *approach* of the sibling `ausinvertraits.addons` repo's
  `scripts/02_AFD_checklist_clean.R` (confirmed the current, canonical version of that script —
  reimplemented directly against taxonAlign's schema, not translated line-by-line; deliberately
  excludes that repo's AusInvertTraits-specific GRIIS/WoRMS invasive-and-marine-species filtering and
  "improper name" removal, which are curation decisions about *which* taxa to include, not part of
  reshaping the data into taxonAlign's format):
  - **Accepted rows**: one per raw row, `canonical_name = FULL_NAME`, `scientific_name =
    COMPLETE_NAME`, `taxon_rank` derived from whether `SUB_SPECIES` is filled (`"species"` vs.
    `"subspecies"`), `taxon_ID = accepted_name_usage_ID = CONCEPT_GUID` (AFD's own stable UUID,
    self-referential -- the one rank level with a natural ID).
  - **Higher-rank rows**: one per distinct, non-blank value of every higher-rank column AFD provides
    (subgenus through phylum) -- mirroring the ported script's "one rank at a time, `distinct()` the
    column" approach. None of these have a natural stable ID (`CONCEPT_GUID` only exists at
    species/subspecies level), so `taxon_ID`/`accepted_name_usage_ID` fall back to the rank's own name,
    **namespaced by rank** (`"<rank>:<name>"`, e.g. `"genus:Agrilus"` vs. `"subgenus:Agrilus"`).
    `genus` is populated only for genus/subgenus rows (subgenus rows need their owning genus so
    `prepare_taxonomic_resources()` can build the bracketed `Genus (Subgenus)` convention
    automatically) -- every other higher rank leaves it `NA`, same as elsewhere in taxonAlign.
    **A real AFD-specific quirk found and fixed here**: family-and-above ranks (family, superfamily,
    order, ..., phylum) are exported ALL CAPS (`"BUPRESTIDAE"`), but subfamily-and-below (subfamily,
    tribe, subtribe) are normal title case (`"Agrilinae"`) -- inconsistent within the same file.
    `afd_higher_rank_rows()` normalises every rank to sentence case regardless (a no-op on the
    already-correctly-cased ones), since an ALL-CAPS reference value would otherwise never
    exact-match a normally-cased input name.
    **A second, more serious real bug found the same way (via a real end-to-end run against
    AusInvertTraits' full name list, not the hand-built fixture)**: `taxon_ID` used to fall back to the
    *bare* rank name with no rank qualifier at all. This collides across ranks whenever the same string
    is used at two different ranks -- and for genus/subgenus this isn't a rare coincidence but the norm:
    by nomenclatural convention, every genus that's been split into subgenera has one *nominotypical*
    subgenus sharing the genus's own name (e.g. genus `"Agrilus"` / its nominotypical subgenus
    `"Agrilus"`). In the real, full AFD.csv this affects 572 of 1725 distinct genus/subgenus pairs
    (~1180 higher-rank rows total, plus a handful more at family/order/subfamily/suborder/subtribe/
    superfamily/superorder/class). Since `update_taxa()`'s lookup is keyed on `taxon_ID` via `match()`
    (first-hit semantics, see the "single, rank-agnostic lookup" bullet in Architecture #2), a
    subgenus-rank match's `accepted_name_usage_ID` (self-referential, so also the bare rank name) would
    silently resolve to whichever colliding row bound first when `resources`' rank sublists were
    flattened -- the genus-rank row, since `genus` sorts before `subgenus` in `names(resources)` --
    discarding the subgenus and downgrading `taxon_rank`/`accepted_name`/`suggested_name` from subgenus
    to genus. `align_taxa()`'s own output was never affected (it builds `aligned_name` from
    `resources$subgenus_v2` directly, not via this ID lookup) -- only `update_taxa()`'s
    (and hence `create_taxonomic_update_lookup()`'s) forward-resolved columns were. Fixed by
    namespacing every higher-rank `taxon_ID` with its own rank, exactly as described above; regression
    test: `test-load_taxonomic_resources.R`'s `"namespaces taxon_ID by rank..."` test, using a fixture
    genus/subgenus pair that deliberately shares a name (`"Thirdgenus"`).
  - **Synonym rows**: AFD embeds every synonym of a taxon as one semicolon-joined free-text field
    (`SYNONYMS`), each entry mixing name + author + year with no separator between the name and its
    authorship (e.g. `"Cisseis fossicollis Kerremans, 1903"`). `afd_synonym_rows()` splits on `"; "`,
    drops entries identical to the row's own name (self-referential noise in the raw data), then
    strips authorship via `strip_afd_authorship()` -- ported from the same script's technique: build a
    regex from every distinct `AUTHOR` value present in the *whole* AFD file (a real, closed
    vocabulary of the taxonomists appearing in it) and strip a matching trailing `"<author>, <year>"`.
    A generic fallback (any capitalised author-like token(s) before a trailing year) catches entries
    whose author isn't in that dictionary for some reason; if neither matches, the entry is returned
    unchanged (including its authorship) rather than guessed at further -- verified against the real,
    full file this only affects ~3 of ~156k synonym rows (parenthetical multi-author combinations,
    lowercase author typos in the source data, and one very long `"in X, Y & Z"` author chain). `genus`
    is re-derived from each synonym's own (post-strip) name via the existing `extract_genus()` helper
    (`match_taxa_helpers.R`), not copied from the accepted row's `genus` -- a synonym can sit under a
    *different* genus than the name it's now a synonym of (e.g. `"Cisseis fossicollis"` as a synonym of
    accepted `"Aaaaba fossicollis"`). `taxon_ID` is synthesised per synonym row (`<CONCEPT_GUID>_syn<n>`);
    `accepted_name_usage_ID` is the accepted row's own `CONCEPT_GUID`, resolving the synonym forward.
  - **Caching**: the reshaped result (raw ~117k rows expand into ~310k output rows once every higher
    rank and every synonym gets its own row -- real work, ~14s uncached, ~0.5s cached) is cached as a
    single `.rds` in `cache_dir` (default `tools::R_user_dir("taxonAlign", "cache")`, the same
    convention `generate_GBIF_taxonomic_reference_list()` uses), keyed by the *source file's own
    size/mtime* rather than a time-based freshness window like the GBIF loader's -- deliberately
    different, since a local file (unlike a remote API) lets us detect a content change directly:
    swapping in an updated `AFD.csv` invalidates the cache automatically, without the user needing to
    remember `refresh_cache = TRUE`.
  - Every column is forced to character on read (`readr::cols(.default = readr::col_character())`) --
    several raw columns (`SUB_GENUS`, `SUB_SPECIES`, and others this function doesn't use) are sparsely
    populated enough that `readr`'s sample-based type-guessing can mis-infer them as logical, which
    would break every string operation the moment a real (non-blank) value showed up.
- **AFD's 2026 CSV export (`data/AFD_2026-10-07/Anamalia_all_ranks.csv`) is read by the same
  `load_AFD()`, not a second function** -- checked column-by-column against the old `AFD.csv` first:
  `FULL_NAME` renamed to `VALID_NAME` (renamed back on read), `SUBSPECIES_COUNT_IN_SPECIES`/
  `LAST_MODIFIED`/the distribution columns dropped (none used), still one row per species/subspecies
  despite the "all ranks" filename (no higher-rank rows), Animalia only (now incl. Chordata; no
  protists). Only ~20% of `CONCEPT_GUID`s carry over from the old file, so IDs aren't stable across
  AFD exports. Four new data quirks handled, all also harmless on the old file:
  - `COMPLETE_NAME`/`SYNONYMS` now write changed-combination authorship in parentheses
    (`"Otobothrium curtum (Linton, 1909)"`) -- `strip_afd_authorship()`'s patterns accept an optional
    `(...)`.
  - Multi-author/particle-prefixed citations where only the *last* author is in the `AUTHOR`
    dictionary left debris (`"Gymnothorax griffini Whitley &"`, `"Platydemus manokwari de"`) in ~2k
    synonyms -- `tidy_afd_authorship_debris()` cleans up afterwards (truncate at a capitalised token
    after a lowercase epithet; strip a residual year; strip trailing particles/`&`/commas).
  - Subsequent usages written with `"; "` between name and citation (`"Phalaena inquinalis; Swinhoe,
    1892"`) used to orphan `"Swinhoe, 1892"` as a bogus synonym -- `rejoin_afd_synonym_fragments()`
    re-attaches it (~176 cases new, 6 old). Also dropped: synonyms whose stripped name equals the
    accepted name (a self-reference with different authorship formatting).
  - Two kinds of "Unplaced" row (382 total): `"Unplaced Synonym(s)"` holders (`SPECIES`/`SUB_SPECIES =
    "Unplaced"`, 79) and species awaiting generic placement (`GENUS = "Unplaced"`, `VALID_NAME` e.g.
    `"Unplaced vetula"`, 303). Neither becomes an accepted row; their synonyms (510, for the latter
    usually the original combination, e.g. `"Tinea vetula"`) are kept as self-referential
    `taxonomic_status = "unplaced"` names (mirroring NSL's own "unplaced"). `"Unplaced"`/`"Unplaced to
    Family"` values in hierarchy columns are never turned into higher-rank rows. Stray control
    characters/tabs in names are squished out.
  - `VALID_NAME` keeps the subgenus in brackets (`"Pardalotus (Pardalotinus) striatus"`, 11,183
    accepted sp/ssp), kept as-is in `canonical_name` -- see the "Subgenus written into species-level
    names" bullet in Architecture #2 for how matching/output handle it. 3,305 SYNONYMS entries are just
    the accepted name minus its subgenus (`"Clivina tenuis"` under `"Clivina (Clivina) tenuis"`) and are
    dropped as self-listings (`strip_subgenus_from_name()` comparison).
- **Further CSV-loader fixes from the full name-level reconciliation against the NSL export**
  (`ignore/AFD_export_comparison.R`; goal: every name agrees, or each genuine discrepancy is listed in
  `vignettes/AFD-data-processing.qmd`):
  - `CHANGED_COMBINATION_NAMES` (~15k entries, never read before, in either export version) is now
    read as `taxonomic_status = "Generic combination"` (NSL's label for the same records) via the
    generalised `afd_synonym_rows(afd, column, status, id_suffix)`; a name in both columns is kept
    once, as a synonym.
  - Synonym `taxon_rank` was always `"species"`, so trinomial synonyms claimed a two-word `binomial`
    key in `prepare_taxonomic_resources()` (the real cause of `"Pardalotus striatus"` resolving via
    the synonym *P. s. kingi*). Now `"subspecies"` for 3+ words, ignoring a subgenus.
  - `clean_afd_name_annotations()` strips `[sic]`, leading `?`/`(?)`, whole-name `[...]`, quoted
    manuscript authors and stray quotes; `tidy_afd_authorship_debris()` also strips malformed trailing
    parenthesised authorship (`"(, )"`, `"(Milne Edwards, )"`, `"(1876, Bergh)"`, `"(Turner, 1908))"`,
    unclosed `"(Adams"`); `rejoin_afd_synonym_fragments()` allows a lowercase particle
    (`"; van Eecke, 1925"`).
  - `taxonAlign_taxonomic_status_priority` gained AFD's statuses (objective/primary synonym,
    "synonym", "Generic combination", replacement name, excluded variants) -- unknown statuses sorted
    after `"included"`, so an NSL names-file record could beat a real taxon-file record.
  - Latest full result: 237,885 of 242,163 species-level names identical (incl. 1,792 synonyms of
    more than one taxon, listed identically -- how to report that ambiguity is still open); 40 differ
    (listed in the qmd); 1,453 CSV-only, 2,785 NSL-only (mostly protists/vagrants/missing
    Tortricidae+Temnocephalidae). Not yet clean: ~193 CSV-only and 165 NSL-only still unexplained,
    some still formatting variants (`"Enicospilus? flavivenae"`, `"Carenum cyaneum non"`,
    `"Tinea lactella [Denis"`). `LITERATURE_NAMES` (misspellings/misidentifications as free text,
    CSV-only information) deliberately not read yet.
- **Rounds 2-4 of the AFD format vs NSL format reconciliation** (terminology: the user calls them
  the "AFD format" and the "NSL format" -- both are CSV-style files, so never "CSV export"):
  - `clean_afd_name_annotations()` now also handles uncertainty marks anywhere (`"Genus? sp"`,
    `"(Ceratia ?)"`), square brackets around part of a name (content kept, as NSL does), HTML tags,
    year outside the bracket, unbalanced doubled `"))"` (only when brackets don't balance -- a blanket
    collapse broke genuinely nested ones), and quote marks only at word edges (`strip_name_quotes()`,
    shared with the NSL loader; an apostrophe inside a word, `"d'arci"`, is kept). Accepted names
    (`VALID_NAME`) get the same quote stripping plus trailing `,`/`;` removal (not `.` -- that broke
    every `"Genus sp."` name; caught only because the comparison numbers got *worse*).
  - **Misapplication/part markers become statuses**: `strip_afd_usage_markers()`/`afd_usage_status()`
    read `sensu`, `auct.`/`auctt.`/`auctorum`, `non`/`nec`, `(part)`/`[pars]` -> "misapplied",
    "pro parte synonym", "pro parte misapplied" (added to the priority vector). The NSL format drops
    these markers and labels the same usages plain "synonym" (50 of 58) -- a curator item. The NSL
    loader (`clean_NSL_canonical_names()`) reads the few markers left in NSL canonical names too, but
    only to sharpen a plain "synonym".
  - `strip_subgenus_from_name()` now accepts any bracket content (`"Nassa (Alectryon, Aciculina) x"`).
  - Result (round 4): 238,009 of 241,998 names agree; 23 differ; 1,308 AFD-format-only (all
    explained: Temnocephalidae/Tortricidae, NSL names-file-only, 59 listed); 2,658 NSL-only (Protista,
    vagrants, 38 listed). Remaining one-sided names are mostly NSL `canonical_name` values with
    authorship left in (`"Conus complanatus Sowerby"`), reported, deliberately not "fixed" in the
    loader (user: only discrepancies in *their* lists should remain, so data errors are reported, not
    hidden).
  - **Names leading to more than one accepted name** (1,893): the comparison script now ranks each
    name's records by `taxonAlign_taxonomic_status_priority`. 997 resolve to themselves (accepted and
    also a synonym elsewhere), 54 resolve identically, 295 only via NSL's "primary synonym" vs
    "synonym" (AFD format has only "synonym"), 461 tie in both formats. User's position: without finer
    statuses there's no resolution -- flag ties with the curators (done, full lists in the qmd).
    taxonAlign's matching still silently picks the first record on a tie -- needs a flag in output
    (not yet designed). The placement of "primary synonym"/"synonym"/"Generic combination" in the
    priority vector is our assumption, awaiting curator confirmation (50 outcomes depend only on
    synonym > Generic combination).
- **Names leading to more than one accepted name ("splits") are now handled in `update_taxa()`**
  (`R/resolve_synonym_splits.R`, `build_split_table()`), following APCalign's `taxonomic_splits`
  convention at the user's request: `taxonomic_splits = "most_likely_species"` (default) suggests one
  name as `"X [alternative possible names: Y (status) | Z (status)]"` plus a new
  `alternative_possible_names` column (also in `create_taxonomic_update_lookup()`'s slim output);
  `"collapse_to_higher_taxon"` gives `"Genus sp. [collapsed names: ...]"` when all candidates share a
  genus. Order: status precedence, then (ties) shared epithet, same rank (word count), accepted name
  published no later than the synonym, oldest, then source order -- the last is APCalign's own final
  tie-break and is what keeps `test-apc_equivalence.R`'s "Justicia procumbens" ->
  "Rostellularia adscendens subsp. dallachyi" passing (alphabetical broke it). Epithet/older-than rules
  were chosen by testing against NSL's own resolutions (99%/93% agreement; "oldest" 57%, "newest"
  40%). Skipped when matched with authorship (`alignment_code` contains "with_authorship", e.g.
  homonyms), and for a species listed under its own nominotypical subspecies. **User's position:**
  remaining ties are curator data problems (467 are ties within the NSL format itself; the 295
  AFD-format-only ties vanish once the AFD publishes only the NSL format) -- the tie-break rules are a
  stopgap, don't keep refining them. 1,709 of 1,893 such names now get the same suggestion from both
  formats.
- **Real-name-list test done** (2026-10-07): the full AusInvertTraits name list
  (`ignore/AusInvertTraits_taxonomic_updates.csv`, 5,154 names) aligned against each format separately
  -- 5,116 (99.3%) get the same `suggested_name`; the 36 distinct names that differ are all explained
  and listed in `vignettes/AFD-data-processing.qmd`'s "Test against a real name list" (genus-level
  synonymy the AFD format lacks, subgenus placement disagreements, NSL-only names, fuzzy matches to
  names in neither). Scratch scripts for it are not in the repo; the run takes ~10 min. Fixes it
  forced: (1) `match_02b` required exactly two spaces, so every plain `"Genus sp."` skipped exact
  matching (APCalign's own rule is one space) -- now one or two; (2) splits (`build_split_table()`)
  narrowed, at the user's insistence, to species/infraspecific *synonyms* leading to 2+ accepted taxa
  only -- accepted names, genera and authorship matches never go through it ("don't go down rabbit
  holes with splits"); (3) `prepare_taxonomic_resources()`'s higher-rank synthesis: a value seen on an
  accepted row is accepted; a value seen only on synonym rows becomes a *synonym* of the accepted
  value(s) its rows lead to (e.g. genus "Conoderus" -> "Monocrepidus"; one synonym row per target);
  only an orphan with no links is "unplaced" (user: "synonyms should not be called unplaced... an
  unplaced name is a dead end"); bare rank words ("Genus") are never synthesised, and "Genus A"-style
  rank-word + placeholder-code names are dropped (narrowly -- APC phrase names like "Genus sp. Yalgoo
  (...)" are real); (4) the AFD loader treats "Incertae sedis" as a placeholder like "Unplaced".
  NSL's 675 genus records pointing to their own nominotypical subgenus (*Acritus* -> *Acritus
  (Acritus)*) are a curator question, not something to interpret.
- **`"APC"`**: `load_APC()` is a thin wrapper flattening `APCalign::load_taxonomic_resources()`'s
  several accepted/synonym/genus/family pieces into one combined table -- the exact combining logic
  originally prototyped inline in `test-apc_equivalence.R` (issue #10), now shared from here instead
  (that test calls `load_taxonomic_resources("APC")` too, rather than duplicating it). `family_accepted`
  is APC's one piece missing a `taxonomic_dataset` column, backfilled with `"APC"` to match every other
  piece. No caching needed -- `APCalign::load_taxonomic_resources()` already caches internally.
- Test coverage: `tests/testthat/test-load_taxonomic_resources.R` covers the `"AFD"` path end to end
  (accepted/subspecies rows, higher-rank dedup and case normalisation, subgenus pairing, synonym
  splitting/authorship-stripping, caching, and a full `prepare_taxonomic_resources()`→
  `create_taxonomic_update_lookup()` run) against a small, hand-built AFD-*shaped* fixture
  (`helper-afd-fixtures.R`) -- entirely offline, no need for the real 89MB file. The `"APC"` path is
  inherently network-dependent (like the rest of `test-apc_equivalence.R`), so its coverage lives there
  instead, gated the same way.

### 4. Australian National Species List (NSL) reference loader — `R/load_NSL.R` (exported: `load_NSL()`; internal helpers `@noRd`)

`load_NSL_resources(taxon_group, ...)` reads/reshapes the [National Species
List](https://www.anbg.gov.au/chah/nsl/)'s per-group export pairs -- `"animals"`, `"algae"`,
`"bryophytes"`, `"fungi"`, `"lichens"` -- into taxonAlign's
flat, `prepare_taxonomic_resources()`-ready schema. Complements `load_taxonomic_resources()`/
`generate_GBIF_taxonomic_reference_list()` the same way, for this source, but is a **standalone
exported function**, not wired into `load_taxonomic_resources()`'s `"AFD"`/`"APC"` switch -- it takes
one group at a time and returns a flat tibble directly (mirroring
`generate_GBIF_taxonomic_reference_list()`'s own contract), so combining several groups is just
`prepare_taxonomic_resources(list(load_NSL_resources("fungi"), load_NSL_resources("lichens")))`, the
same pattern as combining any other two sources. Revisit folding it into `load_taxonomic_resources()`'s
registry if that starts to feel like the wrong split in practice.

- **Two files per group, taxa always taking priority over names.** Each group ships as a *pair* of
  CSVs under `inst/extdata/Australian_<group>/`: a "taxon" file (one row per taxon concept, with real
  synonym-to-accepted resolution via `acceptedNameUsageID`) and a "names" file (a broader name-level
  index, including names never promoted to a full taxon concept, but carrying no
  `acceptedNameUsageID` of its own at all). Confirmed empirically, not assumed: every taxon-file row's
  `scientificNameID` is also present in the names file (100% overlap across all four groups checked),
  i.e. the names file is a strict superset at the name level. `load_NSL_resources()` combines them by
  dropping, from the names file's contribution, every row whose `scientificNameID` already appears in
  the taxon file, then binding taxon rows first -- so a name never enters the combined result twice,
  and the taxon file's real synonymy always wins over the names file's self-referential (no-forward-
  link) version of the same name. This mirrors how iNat's hardcoded `"accepted"` status is described
  elsewhere in `development-history.qmd`: the names file can only *widen* coverage, never resolve a
  synonym.
  - Files are located by filename *substring*, not a fixed prefix-to-group map (`find_NSL_file()`
    matches `"-taxon-"`/`"-names-"` in the basename) -- the raw export's own prefix varies per group
    (`AAL`/`AFL`/`ALC`/`CAB` for taxon; `AANI`/`AFNI`/`ALNI`/`ABNI` for names) but this substring
    doesn't, so this generalises automatically to a group not yet seen, including `"animals"`.
- **`genus` comes from two different places depending on the file**, since only the names file has a
  dedicated column for it: the names file's own `genericName` (blank whenever not applicable, `NA`'d
  via `dplyr::na_if()`); the taxon file has no equivalent column at all, so `genus` is derived via the
  existing `extract_genus()` helper (`match_taxa_helpers.R`) on the *raw* `canonicalName` -- NSL's own
  convention always prefixes an infrageneric/infraspecific name with its governing genus (e.g. the
  subgenus `"Agaricus subg. Homophron"`, the species `"Scutellinia badioberbis"`), so taking the first
  word recovers it correctly for genus rank and everything narrower. `genus` is forced to `NA` for
  family rank and broader (`taxonAlign_NSL_above_genus_ranks`, a small explicit list covering the
  botanical `"division"`/`"subdivision"` terminology this data uses that
  `taxonAlign_taxon_rank_specificity` doesn't, plus a real spelling quirk seen in the raw algae export,
  `"Subphyllum"`) -- a bespoke list rather than reusing `taxonAlign_taxon_rank_specificity`, since that
  vector is tuned to AFD/GBIF/APC's own rank vocabulary, not NSL's.
- **Subgenus rank needs one further correction, on top of `genus`**: NSL's `canonical_name` for a
  subgenus is the *full* `"Genus subg. Subgenusname"` string, not the bare subgenus name AFD's own
  convention uses (bare `"Podosemum"` alongside `genus = "Boronia"`) --
  `prepare_taxonomic_resources()`'s `subgenus_v2` construction
  (`genus_and_subgenus = paste0(genus, " (", canonical_name, ")")`) assumes the latter, so left
  unstripped it produces a doubled, unmatchable key (`"Hygrocybe (Hygrocybe subg. Cuphophyllus)"`).
  `strip_NSL_subgenus_marker()` strips the `"Genus subg. "` prefix down to the bare name for
  subgenus-rank rows specifically, in *both* files, applied after `genus` is already derived from the
  unstripped name (order matters -- `extract_genus()` needs the genus to still be the name's own first
  word). Recognising `"Genus subg. Subgenusname"` itself as an alternate *input* syntax when matching a
  query (rather than just fixing the resource side) is the other half of this, `match_02x` in
  `match_taxa.R` -- see Architecture #2 above and issue #25.
- **`taxonomic_dataset` is read straight off each row's own `datasetName` column** (e.g. `"AFL"` for
  fungi's taxon-file rows, `"AFNI"` for its names-file rows) rather than one hardcoded label for the
  whole group -- lets the two files within one group still be told apart in output (e.g.
  `align_taxa()`'s `taxonomic_dataset` column), consistent with how they're genuinely two different
  underlying datasets even though loaded together.
- **Caching**: keyed by *both* files' combined size/mtime (not a time-based window), the same
  size/mtime-keying convention `load_taxonomic_resources("AFD")` uses and for the same reason -- a
  local file lets a content change be detected directly, without the user needing to remember
  `refresh_cache = TRUE`.
- **Testing now vs. the planned release scheme (issue #24)**: `path` defaults to the bundled
  `system.file("extdata", paste0("Australian_", taxon_group), package = "taxonAlign")`, which resolves
  correctly under `devtools::load_all()` even though these folders are currently untracked in git (not
  yet part of the release scheme issue #24 is still planning) -- override `path` once these files are
  served from elsewhere (e.g. a downloaded, versioned GitHub release) instead of being bundled
  in-package. No download mechanism is implemented yet; that's issue #24's own scope, not this
  function's.
- **The `"animals"` export (AFD's own NSL export, `data/AFD_NSL_export_20260929/`) differs in shape,
  not concept, from the plant-side groups**: pipe-delimited `.txt`, snake_case columns, `_taxon_`/
  `_name_` filename markers. `read_NSL_file()` sniffs the delimiter from the header and
  `standardise_NSL_column_names()` converts camelCase to snake_case, so every reshaping step sees one
  schema; `find_NSL_file()` matches `[-_]taxon[-_]`/`[-_]names?[-_]`, `.csv` or `.txt`. Three further
  animals-specific differences:
  - Subgenus canonical names use the zoological `"Acanthiza (Geobasileus)"` form, not `"subg."` --
    `strip_NSL_subgenus_marker()` handles both.
  - The taxon file's `generic_name` is the *accepted* name's genus (a synonym under a different genus
    gets the wrong one), so genus is still derived from the name itself; `derive_NSL_genus()` also
    masks any single-word non-genus-rank name (zoological "Section" is above genus, botanical
    "sect." below) and the zoological ranks added to `taxonAlign_NSL_above_genus_ranks` (cohort,
    infra-/parv-/subter- ranks, "Higher Taxon", "Generic Aggregate" -- written `"Subtribe Clerina"`).
  - Excluded/vagrant/intercepted taxa (`taxonAlign_NSL_non_synonymy_statuses`) point
    `accepted_name_usage_id` at their *parent* genus/family (e.g. vagrant `"Pernis ptilorhynchus"` ->
    `"Accipitridae"`), so `update_taxa()` would "update" a valid species to a family -- made
    self-referential instead. The plant-side groups' "excluded" rows were already self-referential.
- **Independent cross-check of the two AFD formats** (the reason both loaders exist -- the user's
  stated goal is an independent check that the AFD team transferred data between formats correctly).
  Comparing `load_taxonomic_resources("AFD", path = <2026 CSV>)` against
  `load_NSL_resources("animals", ...)`, subgenus brackets removed from both sides' names first:
  accepted species/subspecies 129,749 shared, 345-350 CSV-only, 1,821 NSL-only (1,820 of those are
  Protista, which the CSV export doesn't include). Synonymy: 96,539 synonym names in both, 96,538
  resolving to the same accepted name (the one exception, `"Bathypallenopsis oscitans"`, is two
  different usages of the same name that NSL only partly carries). **Real transfer gaps found in the
  NSL export**: Temnocephalidae entirely missing (90 spp., 13 genera), and 32 Tortricidae genera
  (244 spp., e.g. *Epiphyas*, *Homona*, *Adoxophyes*) missing -- worth reporting to the AFD team.
  All of this (every transformation, with exact counts, plus a numbered list of data issues to raise)
  is written up for the AFD curators in `vignettes/AFD-data-processing.qmd` (same not-a-formal-vignette,
  `eval: false`, render-directly treatment as `development-history.qmd`) -- keep it in sync if either
  loader's rules change, since it's the record of "exactly what work is being done" that the user
  reports back to the curators. The curators already acknowledge that `CONCEPT_GUID` isn't stable
  across exports. Both raw exports currently live under `data/`, which isn't where R expects raw files (`data/` is for
  `.rda` datasets; `R CMD check` will complain) -- pass `path` explicitly until issue #24's release
  scheme settles where they go.
- Test coverage: `tests/testthat/test-load_NSL_resources.R` covers the combining rule, genus
  derivation, the subgenus-marker fix, caching, and a full `prepare_taxonomic_resources()` →
  `create_taxonomic_update_lookup()` run, against a small, hand-built NSL-*shaped* fixture pair
  (`helper-nsl-fixtures.R`) -- entirely offline, no need for the real, much larger
  `inst/extdata/Australian_*/` files.

### 5. Building the data releases (issues #24, #26) — `data-raw/build_data_release.R`

The download/caching half of this section (versions, offline fallback, `load_taxonomic_resources()`)
stayed in taxonAlign -- see its CLAUDE.md #5. Pre-split notes follow the post-split summary.

**From 2026-11-14** the last argument is `<col_xr_version>` (a ChecklistBank key, e.g. 316691 = COL26.10
XR): the script builds `CatalogueOfLife_AU` (`load_CatalogueOfLife(<key>) |> filter_to_country("AU",
gbif_taxon = "Animalia", refresh_cache = TRUE)`) in place of `GBIF_AU`, and stores
`gbif_au_animalia_names.parquet` (`attr(x, "gbif_names")`: the names GBIF had Australian animal records
of) as its raw file -- the XR itself stays citable by DOI on ChecklistBank, but the occurrence name
list changes daily. The XR has no extinct flag, so `CatalogueOfLife_AU` has no `extinct` column.

**Post-split layout (2026-10-22).** `Rscript data-raw/build_data_release.R <date> <out_dir> <nsl_source> <gbif_au_rds>...`
(run from this package's root; it `devtools::load_all()`s). For each NSL group it writes the raw
`nsl_<group>_{taxon,names}.parquet` (verbatim) and then the ready `NSL_<group>.parquet` (via `load_NSL()`
on those raw files), and `GBIF_AU.parquet` from the rds; every ready file gets character IDs and must
pass `taxonAlign::check_taxonomic_reference()` or the build stops. `manifest.csv` gains `dataset` and
`type` (`raw`/`ready`) columns -- taxonAlign reads it to learn which datasets a release has.
`<nsl_source>` is either the AFD's NSL-format export dir (the four public groups are then downloaded
fresh) or an earlier release's directory with its `manifest.csv` (every raw file carried forward
unchanged, with its original provenance -- this is how the ready files were rebuilt from the old draft
without re-fetching anything).
- **BOLD BINs left out of `GBIF_AU`**: 47,797 of the August 2026 archive's 419,088 records have no
  `canonical_name`; 47,787 of those are BOLD Barcode Index Numbers the GBIF backbone holds as
  `"unranked"` taxa (`scientific_name` e.g. `"BOLD:AAX6343"`), the other 10 genus/species/subspecies
  rows. taxonAlign already dropped them (with a warning) on every load; the ready file now leaves them
  out once, noted in the manifest's `source`. `GBIF_AU` ready file: 371,291 rows, passes the check.
- Every NSL ready file passed the check as-is: algae 21,408; bryophytes 9,170; fungi 27,731; lichens
  8,817; animals 319,337 rows.
- Releases are published on **this** repo's GitHub Releases. The old `2026-10-07` draft on
  `traitecoevo/taxonAlign` has the pre-split layout and is superseded. A rebuilt `2026-10-07` (same
  data, plus ready files; 16 files) was built locally but couldn't be created as a draft here until this
  repo has a pushed commit to tag.
- Publish: `gh release create <date> --repo traitecoevo/taxonAlign.dataprep --draft ...`; user agreed:
  draft -> review -> publish as **pre-release** for testers -> mark final.

**Pre-split notes** (asset names, function names as they were then):


Reference data taxonAlign doesn't fetch live is published as files on dated GitHub Releases of this
repo (bare `YYYY-MM-DD` tags, exactly as APCalign does), so an alignment is reproducible by naming
the release. Scope and confirmed decisions are in issue #24's latest plan comment (2026-10-07): the
five NSL lists (animals = the AFD's NSL-format export, supplied directly with permission; algae,
bryophytes, fungi, lichens from `https://{algae,moss,fungi,lichen}.biodiversity.org.au/nsl/services/export/{taxonCsv,namesCsv}`)
and GBIF Australia extant animals. One release covers all six; a new release only when a source
actually changes -- **no "outdated data" warning** (user: it implies laziness, and the GBIF backbone
often doesn't change for long periods).
- Assets: `nsl_<group>_{taxon,names}.parquet` -- each NSL export **verbatim** (every column as text,
  only empty fields missing), per the store-raw-data philosophy; `load_NSL_resources()` reshapes on
  load. `gbif_au_animals.parquet` -- the August 2026 GBIF Australia archive in taxonAlign's schema
  (user chose the existing archive over a fresh raw fetch), **all taxa kept, with an `extinct`
  column**; `load_GBIF_AU_resources(include_extinct = FALSE)` returns extant only by default (user's
  design, 2026-10-07). `manifest.csv` (source URL/file, retrieval date, rows, source md5, licence,
  citation).
- **GBIF's `extinct` flag doesn't distinguish fossils from recent extinctions** -- the thylacine,
  pig-footed bandicoot and paradise parrot are flagged exactly like *Diprotodon*. Hence keeping
  everything in the release with the column, rather than dropping. `generate_GBIF_taxonomic_reference_list()`
  likewise outputs an `extinct` column (a synonym takes its accepted taxon's flag) and has
  `exclude_extinct = TRUE` by default. Flags for the archive came from the raw fetch cache
  (`ignore/gbif_cache_backup/`, invertebrates: TRUE/FALSE) and, for vertebrates (no raw cache), from a
  `name_lookup(isExtinct = TRUE)` query per Australian vertebrate family (931 families, ~5 min; family
  keys from `ignore/gbif_vertebrates_worldwide.rds`) -- the first attempt, paging all of Chordata, was
  hopelessly slow (GBIF deep paging). Vertebrates therefore only have TRUE/NA. Combined table:
  `ignore/gbif_au_animals_with_extinct.rds` (419,088 records; 20,244 extinct).
- **Superseded 2026-11-14:** `GBIF_AU` is replaced by `CatalogueOfLife_AU` from the next release
  (Architecture #1; `<gbif_au_rds>` became `<col_xr_version>`), so the note below no longer applies.
- **Next GBIF_AU rebuild: try the 2026 GBIF snapshot first** (user, 2026-10-22: "I'll forget!").
  `generate_taxadb_taxonomic_reference_list("Animalia", rank = "kingdom", country = "AU",
  gbif_snapshot_url = "https://data.source.coop/cboettig/taxadb/2026/dwc_gbif_part_0.parquet",
  facet_limit = 3e5)` replaces the multi-day live backbone fetch (~99.9% name agreement with it,
  Architecture #1b). It existed (since 2026-09-18) when the first release was built but wasn't
  considered. The country filter is still GBIF's occurrence API either way; the snapshot has no
  extinct flag, so still flag extinct taxa per family as above; it's an unversioned file the
  maintainer hasn't validated, so diff the result against the previous release before publishing.
  Written up for humans in taxonAlign's `vignettes/development-history.qmd` ("A faster route that
  turned up afterward").
- **Offline behaviour** (user requirement, from APCalign's failure mode of searching for new versions
  when offline): a named release already downloaded never touches the network; without `version`,
  `data_release_versions()` asks GitHub once per session via `curl` with a 5s connect / 10s total
  timeout, any failure -> newest local release; `get_data_release_assets()` falls back to the newest
  complete local release if the latest can't be downloaded (never for an explicitly named version).
  Release tags are dates, never numbers. `curl` added to Imports.
- `data_release_versions()` (exported) lists published date-tagged releases (drafts excluded,
  pre-releases included); `download_data_release_asset()` caches under
  `<cache_dir>/data_release/<version>/`. `load_NSL_resources(path = NULL, version = NULL)` downloads
  from a release when no `path` is given; `read_NSL_file()` reads parquet too.
- `arrow`, `curl`, `jsonlite` are full Imports (user decision for arrow, as APCalign).
- `data-raw/build_data_release.R <date> <out_dir> <animals_dir> <gbif_au_rds>...` builds every
  asset + manifest + release notes (downloads the four public NSL groups fresh); publish with
  `gh release create <date> --draft ...`; user agreed: draft -> review -> publish as **pre-release** for
  testers -> mark final. `data-raw/` is build-ignored.
- **First release: `2026-10-07`, created as a draft** (all 12 assets, ~145MB). Not yet published;
  testers also need the loader code pushed. get-started.qmd's release examples are `eval: false`
  until it's published -- flip them on and re-render then.
- Tests: `test-data_release.R` (GitHub API and downloads mocked; release-parquet load equals
  original-file load).


### Vignettes

`vignettes/get-started.qmd` walks through every function here (it took over the "building a reference"
sections of taxonAlign's own get-started vignette at the split). Same treatment as taxonAlign's
vignettes: not a formal knitr vignette (`vignettes/` is build-ignored), rendered directly with `quarto
render vignettes/get-started.qmd` against the *installed* packages, with one small live GBIF call
(`"Aporocera"`, `country = "AU"`). Clean up the `*_files/`/`.knit.md`/`.html` leftovers afterwards
(gitignored). `vignettes/AFD-data-processing.qmd` is sent to the AFD curators as a single HTML file, so render it
self-contained: `quarto render vignettes/AFD-data-processing.qmd -M embed-resources:true` (a plain
render depends on a separate `_files/` folder, which an emailed file loses). It is the curator-facing record of every AFD-format/NSL-format
transformation (Architecture #4) -- keep it in sync if either loader's rules change.
