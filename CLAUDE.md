# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`taxonAlign.dataprep` (repo `traitecoevo/taxonalign-dataprep`; R package names can't have a hyphen, so
it's dotted, traits.build-style) is the companion to [taxonAlign](https://github.com/traitecoevo/taxonAlign)
(sibling checkout `../taxonAlign`). taxonAlign matches and updates names against a reference in its
documented format (`taxonAlign::taxonomic_reference_schema()`); this package builds references in that
format and builds the dated data releases `taxonAlign::load_taxonomic_resources()` downloads. Split out
of taxonAlign on 2026-10-22 ([taxonAlign issue #26](https://github.com/traitecoevo/taxonAlign/issues/26),
Will Cornwell's suggestion) -- see taxonAlign's CLAUDE.md, "The package split", for the decisions made
then (don't re-litigate them). Everything here was copied from taxonAlign at commit `f6f691d`; git
history for it before the split is in that repo.

Exported functions, each returning one flat table in taxonAlign's format:
- `generate_GBIF_taxonomic_reference_list()` -- live GBIF backbone fetch (Architecture #1).
- `generate_taxadb_taxonomic_reference_list()` -- taxadb snapshot (Architecture #1b).
- `load_AFD(path)` -- the AFD's own CSV export, "AFD format" (Architecture #3; was
  `taxonAlign::load_taxonomic_resources("AFD")`). `path` is now required (no bundled copy).
- `load_APC()` -- thin `APCalign::load_taxonomic_resources()` wrapper (was
  `taxonAlign::load_taxonomic_resources("APC")`).
- `load_NSL(taxon_group, path)` -- an NSL export pair (Architecture #4; was
  `taxonAlign::load_NSL_resources()`). `path` is required; it reads the raw `.csv`/`.txt` exports *or*
  a release's verbatim `nsl_<group>_{taxon,names}.parquet` copies (`find_NSL_file()` accepts a `.` after
  the marker). The old `version =` release download is gone -- taxonAlign downloads *ready* files now,
  and dataprep users have the source files.
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
taxonAlign, `devtools::install("../taxonAlign")` before running these tests. `extract_genus()` and
`strip_subgenus_from_name()` are vendored in `R/utils.R` (taxonAlign keeps them internal); keep them
identical to taxonAlign's `R/match_taxa_helpers.R` copies.

Imports: `APCalign`, `arrow`, `dplyr`, `parallel` (ships with base R, but called via `::` for the
concurrent GBIF page fetch), `purrr`, `readr`, `rgbif`, `rlang`, `stats`, `stringr`, `taxonAlign`,
`tools`, `utils`. Suggests: `taxadb`, `duckdb`, `DBI` (only `generate_taxadb_taxonomic_reference_list()`
needs them), `testthat`, `tibble`, `withr`.

The default cache dir is deliberately still `tools::R_user_dir("taxonAlign", "cache")` -- the same as
taxonAlign's, so the large, resumable GBIF fetch cache already built there keeps working.

Large raw inputs aren't committed: `data-raw/sources/` and `data-raw/release/` are gitignored. The
real exports currently still sit in the taxonAlign checkout (`../taxonAlign/data/AFD_2026-10-07/`,
`../taxonAlign/data/AFD_NSL_export_20260929/`, `../taxonAlign/inst/extdata/`, untracked there), as do
the GBIF archives (`../taxonAlign/ignore/`, e.g. `gbif_au_animals_with_extinct.rds`) and the AFD format
vs NSL format comparison script (`../taxonAlign/ignore/AFD_export_comparison.R`).

### Testing

`tests/testthat/test-generate_GBIF_taxonomic_reference_list.R` covers `generate_GBIF_taxonomic_reference_list()`
and its internal helpers (`resolve_gbif_taxon()`, `fetch_gbif_taxon_tree()`, `fetch_gbif_country_keys()`,
`recycle_against_taxon_name()`, `cache_is_fresh()`) end to end, entirely offline: every `rgbif::` call
(`name_backbone`, `name_lookup`, `name_usage`, `occ_search`) is replaced with
`testthat::local_mocked_bindings(..., .package = "rgbif")`, with fixture builders in
`tests/testthat/helper-gbif-fixtures.R`.

`tests/testthat/test-generate_taxadb_taxonomic_reference_list.R` covers
`generate_taxadb_taxonomic_reference_list()`, also entirely offline -- the core reshape/filter tests
run against real data via `taxadb`'s own tiny bundled `"itis_test"` fixture, and the one
`country`-filtering test (`provider = "gbif"`) mocks `taxadb::td_create()`/`taxadb::taxa_tbl()`
alongside `rgbif::name_backbone()`/`rgbif::occ_search()`. Skipped if `taxadb` isn't installed.
`gbif_snapshot_url` (issue #23, see Architecture #1b) is covered both offline -- mocking the internal
`gbif_snapshot_tbl()` directly, plus a small local parquet file for the missing-column schema-check
error -- and with one real, live test against the actual source.coop URL, gated with
`skip_if_offline()`/`skip_on_cran()`.

`test-load_AFD.R` covers `load_AFD()` against a small AFD-shaped fixture (`helper-afd-fixtures.R`, see
Architecture #3), incl. `taxonAlign::check_taxonomic_reference()` on its output. `test-load_NSL.R`
covers `load_NSL()` against two hand-built NSL taxon/names fixture pairs (`helper-nsl-fixtures.R`) --
one plant-side camelCase-CSV, one animals pipe-delimited snake_case -- plus reading a release's
verbatim parquet copies (identical output to the original files). `test-build_taxonomic_reference.R`
covers `build_taxonomic_reference()` by supplying `user_responses` throughout (never a real
interactive session), mostly going on through `taxonAlign::prepare_taxonomic_resources()` (helper
`build_and_prepare()`), using a copy of taxonAlign's `sample_taxonomic_resources()` fixture
(`helper-align-taxa-fixtures.R`). All offline.

218 expectations, all passing as of the last `devtools::test()` run (2026-10-22), with `taxadb`/`duckdb` installed and network access available (so `gbif_snapshot_url`'s one live test ran too).

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

## Architecture

### 1. GBIF-backed reference list builder — `R/generate_GBIF_taxonomic_reference_list.R` (active, exported)

This is the one fully-built, documented, exported piece of the package.
`generate_GBIF_taxonomic_reference_list(taxon_name, ...)` builds a tibble of taxa sourced from the GBIF
backbone taxonomy (`gbif_backbone_dataset_key`), optionally filtered to a country's occurrence records
and/or a minimum taxonomic rank (`gbif_rank_order` defines the "this rank and below" ordering).

Key design points worth knowing before touching this file:
- **Name resolution**: `resolve_gbif_taxon()` calls `rgbif::name_backbone()` once per input name,
  follows synonym links to the accepted usage key, and deliberately errors (rather than silently
  fetching a huge clade) when GBIF returns a `"HIGHERRANK"` match — this happens when `taxon_name` is
  an unresolved homonym (e.g. a genus name shared by a plant and an unrelated animal) and GBIF backs
  off to their common ancestor.
- **Bulk fetch + disk cache**: `fetch_gbif_taxon_tree()` pages through `rgbif::name_lookup()` (1000
  rows/page) instead of one API call per taxon, and caches the combined result per root GBIF key under
  `cache_dir` (default: `tools::R_user_dir("taxonAlign", "cache")`). Cache freshness is time-based
  (`cache_is_fresh()`, `max_cache_age_days`); `refresh_cache = TRUE` forces a re-download. A second,
  independent size guard (`max_taxa`, default 50000; override with `force_large_fetch = TRUE`) protects
  against a homonym resolving broader than intended and triggering a very large/slow first fetch.
- **Country filtering**: `fetch_gbif_country_keys()` does one `rgbif::occ_search()` facet query per
  requested root taxon (not per descendant) to keep this cheap, and is cached the same way. `country`
  is validated as a 2-letter ISO 3166-1 alpha-2 code (regex `^[A-Za-z]{2}$`) up front -- a country
  *name* like `"Australia"` used to pass straight through to `rgbif::occ_search()`, which doesn't
  recognise it, silently returning a 0×0 facet result rather than erroring; accessing that result's
  `$name` then triggered an "Unknown or uninitialised column" warning and a silently-empty reference
  list rather than a clear error. `occ$facets$taxonKey$name` is also now guarded with
  `"name" %in% names(...)` rather than just `!is.null(...)`, since an empty facet result is *not*
  `NULL` (it's a valid 0-row/0-column tibble).
- Final output columns are a fixed, renamed subset of the raw GBIF fields (see the function's
  `@return` doc), named to match [APCalign](https://traitecoevo.github.io/APCalign/)'s taxonomic
  resource tables wherever an equivalent concept exists there (`taxon_ID`, `accepted_name_usage_ID`,
  `scientific_name`, `scientific_name_authorship`, `canonical_name`, `taxon_rank`, `taxonomic_status`,
  `taxonomic_dataset`) so a GBIF-derived reference list can eventually sit alongside an APC/APNI one —
  with `taxonomic_dataset` hardcoded to `"GBIF"`. `accepted_name_usage_ID` is filled in even for
  already-accepted rows (self-referential, pointing at their own `taxon_ID`), matching the convention
  used in real APC downloads, rather than left `NA` the way GBIF's own `acceptedKey` field is. This
  file only knows about GBIF; combining *multiple* taxonomic references (the package's stated goal #1)
  is not yet implemented here.
- `gbif_rank_order` (broadest-to-narrowest rank list used for `rank`-filtering) doesn't cover every
  value in GBIF's real `Rank` enum — e.g. `infraspecific_name`, `supragenericname`, `infragenus` are
  missing. A taxon actually carrying one of those ranks would silently drop out of `rank`-filtered
  output rather than being included. Flagged but not fixed (deliberately) — pin down GBIF's exact
  ordinal placement for the missing ranks before adding them, rather than guessing.
- **`country` can't narrow the fetch itself, only filter it afterwards** — found worth documenting
  explicitly after being asked directly whether the AU-occurrence filter could run *before* the
  (often much larger) full-tree download, to skip fetching taxa that don't even occur in the target
  country. It can't: GBIF's taxonomy-browsing endpoint (`name_lookup()`, what the tree fetch uses) has
  no country concept at all — only the *occurrence-record* endpoint (`occ_search()`, what
  `fetch_gbif_country_keys()` already uses) does, and occurrence records are normally tagged with a
  taxon's *accepted* usage, essentially never a synonym's own key. Filtering to occurrence-derived keys
  before fetching the tree would silently drop every synonym of an in-country taxon (a synonym itself
  has no occurrence records of its own to be found by). A tempting-looking alternative — use the
  (cheap) occurrence facet to get just the in-country *accepted* keys first, then fetch full detail
  (including synonyms) only for those via `rgbif::name_usage()` — was checked against real numbers
  before being ruled out too: AU-occurring Insecta alone has 105,178 distinct occurrence taxonKeys, and
  `name_usage()` doesn't accept more than one `key` at a time (confirmed: errors if you try) — that's
  105,178+ individual API calls, dramatically *more* than the ~1,800 calls (at 1000 rows/page) needed to
  page the whole global Insecta tree once. Fetching the whole tree first, then filtering, remains the
  right design; the genuine speedup opportunity is in how that full-tree fetch itself is paged (next
  bullet).
- **The full-tree fetch is paged concurrently, not one page at a time** — `parallel_requests` (default
  4) controls how many of `fetch_gbif_taxon_tree()`'s paginated `rgbif::name_lookup()` calls run at
  once, via `parallel::mclapply()` (fork-based, so Unix-alike only -- silently falls back to sequential
  on Windows, never incorrect, just not faster there). Chosen over adding a new async-HTTP dependency,
  since `rgbif::name_lookup()` itself has no batching/async option to hook into, and over the
  country-first alternative above. For a large clade (a GBIF-scale invertebrate phylum can mean
  thousands of 1000-row pages) this is where nearly all the wall-clock time goes, so this is a
  meaningful, not cosmetic, speedup — confirmed in practice fetching AU-occurring Arthropoda (2.17M
  global descendants, ~3,100 pages). Each page is retried up to 3 times with a short backoff
  (`fetch_page_with_retry()`) before being treated as a real failure — found necessary in the same
  real fetch: a single page occasionally fails with a transient network/TLS error (e.g. "LibreSSL
  SSL_read... bad decrypt") unrelated to the request itself, and without a retry this would fail the
  *entire* multi-thousand-page tree fetch (see the no-silent-partial-data check below) even after every
  other page already succeeded — wasteful to have to redo a very large, slow fetch from scratch over
  one flaky page. `parallel::mclapply()`'s own child-error handling is deliberately not relied on
  directly: each page is wrapped in its own `try()` inside `fetch_page_with_retry()` rather than letting
  a raw error propagate out of the forked worker, since `mclapply()` additionally emits its own
  "scheduled core N encountered error" warning for an uncaught child error, which would otherwise
  surface confusingly alongside (and before) this function's own clearer error message. If any page
  still fails after retries, the whole tree fetch errors clearly, naming how many of how many pages
  were lost — matching this package's existing "clear error over silent partial data" convention (e.g.
  the `country`-code / `canonical_name`-NA checks elsewhere in the package) — rather than silently
  returning an incomplete tree with no indication anything went wrong.
- **Every rgbif call gets an explicit timeout, and (outside the paginated-page path) a shared retry
  wrapper** (`gbif_curlopts`, `with_gbif_retry()`) -- found necessary after `fetch_page_with_retry()`
  alone still wasn't enough: a request occasionally *hangs* rather than erroring (observed directly on
  the real Arthropoda fetch -- worker processes sitting at ~0% CPU for 30+ minutes, no error, no
  further log output), and a hang can never trigger a retry, since a retry only runs after a request
  actually *fails*. `gbif_curlopts` (`timeout = 60`, passed to every `rgbif::name_backbone()`/
  `name_lookup()`/`name_usage()`/`occ_search()` call in the file via `curlopts`) turns a hang into an
  ordinary, retry-able error after the timeout (120s -- raised from an initial 60s after direct
  measurement showed GBIF's own deep-pagination legitimately taking up to 78s at high offsets under
  concurrent load; see `gbif_curlopts`'s own comment). `with_gbif_retry()` is the non-paginated sibling
  of `fetch_page_with_retry()` -- same retry-with-backoff policy, but raises on exhaustion instead of
  returning a try-error, since name resolution/root-usage/children-page/occurrence-facet calls have no
  cross-call aggregation to report into. Takes a zero-argument thunk (`function() ...`), not a bare
  expression -- an R promise argument is only ever evaluated once and its value cached, so a bare
  expression would silently *not* re-run the real network call on a second attempt. The very first
  `name_lookup()` call in `fetch_gbif_taxon_tree()` (the one that fetches `total`, deciding whether the
  clade needs splitting at all) was initially missed and left completely unwrapped -- found the hard
  way when it alone took down an entire ~5,400-children-deep recursive Insecta fetch on one transient
  failure, with no chance to retry. Now wrapped in `with_gbif_retry()` like everything else.
- **A clade bigger than 100,000 descendants can't be paged at all** — confirmed directly against the
  raw GBIF REST API (not just `rgbif`'s wrapper): `name_lookup()`'s underlying endpoint hard-refuses any
  page whose offset exceeds 100,000 (`"Max offset of 100000 exceeded."`), a fixed server-side limit, not
  a rate-limit or something retries fix. Found in practice fetching Arthropoda (~3.1M descendants,
  ~3,100 pages) and Mollusca (~484k, ~485 pages) — both fail once paging passes page 100, regardless of
  `parallel_requests` or `fetch_page_with_retry()`. `gbif_max_lookup_offset` (100000) is the threshold
  `fetch_gbif_taxon_tree()` checks `total` against; above it, the direct-paging path is skipped entirely
  in favour of `fetch_gbif_taxon_tree_by_children()`.
  - **Recursive split-into-children**: `fetch_gbif_taxon_tree_by_children()` fetches `root_key`'s
    immediate children (`fetch_gbif_taxon_children()`, paginated the same way via
    `rgbif::name_usage(key, data = "children")` — its `meta` has no `count` field, only `endOfRecords`,
    so it pages until that flag is set rather than computing a page count up front) and recurses into
    `fetch_gbif_taxon_tree()` for each one. A child can itself still be too large and need splitting
    again — every taxon's children are smaller than the taxon itself, so this always terminates, but a
    `.depth` guard (6 levels) errors clearly rather than trusting that invariant blindly forever, in case
    some corner of the backbone violates it. Children are fetched **sequentially, not in parallel**:
    each child's own fetch already parallelises across *its* pages internally (`parallel_requests`), and
    nesting `mclapply()` inside `mclapply()` would oversubscribe cores (e.g. 4 children × 4 pages each =
    16-way contention on what might be a 4-8 core machine) for no real benefit.
  - **This makes a huge fetch resumable for free, which matters a lot in practice for a fetch that can
    run for a long time unattended** (Arthropoda's full breakdown took multiple long-running sessions,
    including surviving a machine reboot partway through) — every recursive call caches its own result
    under its own GBIF key exactly like a directly-fetched tree, so there's no separate checkpointing
    mechanism to build or that can get out of sync: the disk cache *is* the checkpoint. Interrupted
    partway through fetching, say, 30 orders under a class, re-running the exact same top-level call
    later only re-fetches whichever orders aren't already cached — already-completed ones return
    instantly from `cache_is_fresh()`.
  - **A full-backbone bulk download exists as an alternative and was deliberately not used**
    (`https://hosted-datasets.gbif.org/datasets/backbone/current/backbone.zip`, confirmed via a direct
    HTTP HEAD request: ~971MB compressed, last modified over a year before this was investigated) — it
    would sidestep the offset limit entirely, but using it only for the huge clades would leave the
    combined reference with silently inconsistent currency (small phyla live/current via the API, huge
    ones years stale from a bulk snapshot) — a worse problem for a taxonomic alignment tool than being
    slower but uniformly live. Also a materially bigger architectural change (a new file-based ingestion
    path covering every kingdom, not a fetch scoped to one taxon) rather than a fix to the existing
    fetch. Worth reconsidering only if GBIF's API limits become more restrictive still.

### 1b. taxadb-backed reference list builder — `R/generate_taxadb_taxonomic_reference_list.R` (active, exported)

Companion to the function above, for the case that function's own docs now explicitly say it's *not*
suited to: a genuinely large clade (a phylum, a large class). Sources from
[taxadb](https://docs.ropensci.org/taxadb/) (rOpenSci) — a package that already downloads and locally
caches versioned, pre-built snapshots of several major taxonomic authorities (`gbif`, `itis`, `col`,
`ncbi`, `ott`, `iucn`, and some less-actively-maintained ones — see `taxadb::td_create()`'s own docs
for the current list), backed by DuckDB + parquet. Filtering to a taxon group (`generate_taxadb_taxonomic_reference_list(taxon_name, rank, provider)`)
is then an ordinary local database query regardless of how large the group is — no pagination limit,
no recursive splitting, no retry/timeout engineering needed, at the cost of the snapshot being up to a
few months stale rather than live (taxadb's own docs: snapshots are semi-annual). Investigated and
implemented per [issue #19](https://github.com/traitecoevo/taxonAlign/issues/19).

- **Measured, not just theorised, how close taxadb's GBIF snapshot actually is to a live fetch --
  and the first-pass explanation for the gap found was wrong.** Ran both
  `generate_GBIF_taxonomic_reference_list()` (this session's own, independently-fetched AU
  invertebrate reference, 358,496 rows across 28 phyla) and `generate_taxadb_taxonomic_reference_list()`
  (the same 28 phyla, `provider = "gbif"`, `country = "AU"`) and compared exact GBIF usageKeys (both
  sources use the same raw key -- ours bare, taxadb's `"GBIF:<key>"`-prefixed, so this is a precise
  key-set comparison, not just a name comparison). Result: **85.2% agreement overall (Jaccard),
  93.0% restricted to accepted names only** -- emphatically not "near perfect", and rightly challenged
  as such rather than accepted at face value.
  - **First hypothesis (wrong, but checked rather than assumed): duplicate/reassigned GBIF backbone
    keys for the same name.** A real, known GBIF quirk -- confirmed a handful of real cases (e.g.
    `"Nephthyidae"`/`"Ambo"` appearing on *both* "only in one side" lists under different keys) -- but
    only ~2-6% of the mismatches, not the main driver.
  - **Second hypothesis (also wrong): taxadb's GBIF provider has inherently thinner synonym
    coverage than the live API.** This is what got written up and reported *before* the actual root
    cause was found -- a real mistake, caught only because the resulting numbers were challenged
    directly rather than accepted as "a reasonable-sounding trade-off". Investigating *why* named
    records were missing (not just counting them) led to the real answer:
  - **Actual root cause: taxadb's cached "gbif" snapshot is stuck at version `"22.12"`
    (December 2022)** -- confirmed directly via `taxadb:::latest_version()` (returns `"22.12"`) and
    `taxadb:::available_versions()` (returns `"22.12"` for *every* provider it lists, not just
    `"gbif"` -- the whole package's underlying data pipeline appears to have stopped publishing new
    snapshots around that date, not something scoped to one provider). At the time this was measured
    (2026), that's roughly **four years stale**, not the "semi-annual" cadence taxadb's own
    `data-sources` vignette claims. Four years of new species descriptions, added synonyms, and
    backbone reclassifications for an actively-studied group like invertebrates plausibly explains a
    gap this size on its own, without needing "taxadb's methodology is less complete" as an
    explanation at all.
  - One phylum, `"Entoprocta"`, has zero rows under that exact name in taxadb's snapshot at all --
    plausibly a downstream symptom of the same staleness (a classification change since Dec 2022) or a
    genuine flattening difference; not separately resolved. Negligible in scale (78 rows in the live
    fetch either way).
  - **Practical implication, corrected**: don't recommend `generate_taxadb_taxonomic_reference_list()`
    as a reliably-current alternative to a live fetch right now -- its usefulness depends entirely on
    whether taxadb's maintainers resume publishing snapshots, which is outside this package's control.
    It may still be the right tool when a somewhat-stale worldwide slice is an acceptable trade for
    speed/reliability on a huge clade, but that trade-off is now known to be "up to ~4 years stale",
    not "up to a few months" -- say so plainly wherever this function is recommended, and don't soften
    it into a smaller-sounding caveat next time real numbers look wrong. Worth periodically re-checking
    `taxadb:::available_versions()` in case this changes.
  - **The raw ~15% dataset-level gap and the *practical* impact on a real alignment are two different
    numbers, and both are worth reporting together.** Ran the real, full AusInvertTraits name list
    (5,154 names) through `create_taxonomic_update_lookup()` twice -- `AFD + our own live-fetched
    GBIF` vs. `AFD + the taxadb-sourced equivalent`, same 28 phyla -- and compared `aligned_name`
    directly, not just raw usageKeys. Result: **5,143/5,154 (99.79%) identical; only 11 names
    differ**, and all 11 are cleanly explained by the same staleness cause, never the reverse (taxadb
    never resolved something the live fetch didn't): two species (`"Onthophagus bulga"`,
    `"Trioza melaleucae"`) and two genera (`"Austrocardiophorus"`, `"Trachytetra"`, the latter across
    6 rows) that the live fetch has and taxadb's snapshot doesn't. This isn't a contradiction of the
    85.2%/93.0% figures above -- it reconciles cleanly: AFD is checked first and resolves the large
    majority of names on its own, so only a small residual set of names ever reaches GBIF at all, and
    only a fraction of *that* residual happens to fall inside taxadb's specific staleness gap. Don't
    report the raw dataset-level comparison alone as "how bad is taxadb" without also checking what it
    actually costs on a real alignment task -- they can (and here do) tell very different stories.

- **`country` filtering is still GBIF-API-only**, not something `taxadb` can supply for *any*
  provider — `taxadb` has no occurrence data at all, only taxonomic backbone data. So `country` is
  only accepted when `provider = "gbif"`, and even then it's answered by reusing
  `resolve_gbif_taxon()`/`fetch_gbif_country_keys()` (the exact same internal helpers
  `generate_GBIF_taxonomic_reference_list()` already uses for its own `country` argument) rather than
  duplicating that logic — one small, live GBIF API call to resolve `taxon_name`'s key and one
  occurrence-facet query, on top of the otherwise-fully-local taxadb query.
- **A real bug found in `taxadb::filter_rank()` while investigating this (confirmed directly, not
  assumed from docs)**: `rank = "order"` throws a genuine DuckDB parser error
  (`"Parser Error: syntax error at or near \"order\""`) — `order` is a reserved SQL keyword, and
  `filter_rank()`'s internals build a raw `WHERE` clause without quoting the column name. Every other
  rank (`kingdom`/`phylum`/`class`/`family`/`genus`) works fine; only `order` collides. Not reported
  upstream yet. Worked around here by not depending on `filter_rank()` at all — this function queries
  `taxadb::taxa_tbl(provider)` directly via an ordinary `dplyr::filter()`, which goes through
  `dbplyr`'s own identifier-quoting and doesn't hit the bug, confirmed working for `"order"` too.
- **taxadb's schema has no separate authorship field** — confirmed against its own `taxonID`/
  `scientificName`/`acceptedNameUsageID`/... Darwin Core schema (identical across every provider,
  the whole point of `taxadb`'s normalisation) and directly against real data (`taxadb`'s own tiny
  bundled `itis_test` fixture, used for this package's own offline tests). `scientific_name` and
  `canonical_name` are therefore identical in this function's output, unlike
  `generate_GBIF_taxonomic_reference_list()`'s, where `scientific_name` includes authorship.
- **`taxonID`/`acceptedNameUsageID` are `"<PROVIDER>:<integer>"`-prefixed strings** (e.g.
  `"GBIF:2440935"`), confirmed against `taxadb`'s `data-sources` vignette and real `itis_test` data --
  `strip_taxadb_gbif_prefix()` strips this specifically for the `country`-filtering step, which needs
  the bare GBIF usageKey to compare against `fetch_gbif_country_keys()`'s result and to pass to
  `resolve_gbif_taxon()`'s underlying `rgbif` calls. The final output keeps the prefixed string form
  as `taxon_ID` (consistent with `taxadb`'s own convention, and harmless for combining with other
  sources since `prepare_taxonomic_resources()` already normalises `taxon_ID` to character regardless
  of the source column's type).
- **Investigated, and deliberately not (yet) used, as a way to shrink or replace this package's own
  bespoke GBIF pagination engineering**: `taxadb`'s own `gbif` snapshot could in principle make much of
  `fetch_gbif_taxon_tree_by_children()`'s recursive-splitting logic unnecessary for large clades, since
  the whole point is that `taxadb` already did that heavy lifting once, centrally, rather than every
  user re-paginating GBIF's live API themselves. This is *why* `generate_taxadb_taxonomic_reference_list()`
  exists as a genuine alternative, not a niche extra option — but `generate_GBIF_taxonomic_reference_list()`
  itself is deliberately left as-is (not rewritten to use `taxadb` internally) since it's still the
  right tool for a small clade needing a live, up-to-the-moment fetch, and this session's own real,
  independently-fetched worldwide GBIF invertebrate reference (Architecture #1's own numbers) remains
  useful precisely *because* it was fetched independently — a live cross-check against `taxadb`'s
  snapshot, not a redundant duplicate of it.
- **`taxadb` is a `Suggests`, not an `Imports`, dependency** — this function is the only thing in the
  package that needs it, guarded by an explicit `requireNamespace()` check with an install hint, so a
  user who never calls this function never needs to install `taxadb` (and its own heavier dependency,
  DuckDB) at all.
- **`gbif_snapshot_url` (issue #23, implemented): bypasses `taxadb`'s own frozen registry entirely for
  `provider = "gbif"`.** Following up directly with the maintainer (`cboettig`) on
  [ropensci/taxadb#123](https://github.com/ropensci/taxadb/issues/123) turned up something actionable:
  current-year GBIF snapshots are uploaded as raw Darwin-Core parquet files to `source.coop` well
  before they're wired into `taxadb`'s own `td_create()`/`taxa_tbl()` registry (which stays frozen at
  `"22.12"`, confirmed again directly via that registry's own GitHub commit history — one commit,
  2022-12-20, unchanged — even after the maintainer reported updating "his underlying files"; that
  update is real, but it's the source.coop parquet, not the R package's registry). `gbif_snapshot_url`,
  when supplied, queries that parquet URL directly instead — confirmed against real names known
  missing from the frozen `"22.12"` snapshot (`"Trachytetra"` + 5 species, `"Onthophagus bulga"`,
  `"Trioza melaleucae"`, `"Austrocardiophorus"`): all four now resolve via this path.
  - `gbif_snapshot_tbl()` (`@noRd`) does the actual work: opens/reuses `taxadb::td_connect()`'s own
    cached `duckdb` connection (an *exported* function -- deliberately not `taxadb:::duckdb_view()`,
    to avoid depending on an internal implementation detail that could change without notice and the
    `R CMD check` NOTE a `:::` call to another package triggers), creates a `CREATE VIEW IF NOT
    EXISTS` over the URL via `read_parquet()` (httpfs auto-installs/loads for an http(s) path in
    current DuckDB, but installed explicitly here too rather than relying on that default), and
    returns an ordinary lazy `dplyr::tbl()` -- so every downstream step in
    `generate_taxadb_taxonomic_reference_list()` (rank filtering, `include_synonyms`, `country`
    filtering, the final `transmute()`) works completely unchanged regardless of which source fed it.
    View names are keyed by a short hash of the URL so two different snapshot URLs used in the same
    session don't collide.
  - **Schema stability here isn't a guarantee `taxadb` itself is making** -- the maintainer's own
    caveat when confirming the upload ("I haven't had a chance to update the taxadb bindings
    themselves or verify we don't have breaking changes") -- so `gbif_snapshot_tbl()` explicitly checks
    the expected columns (`taxonAlign_gbif_snapshot_required_cols`) are present and errors clearly,
    naming what's missing, rather than failing confusingly deep inside the final `transmute()` if a
    future snapshot's schema drifts. A column being *renamed* rather than dropped could still slip
    through undetected -- not fully guarded against.
  - Deliberately **opt-in, not the default** -- passing nothing still uses `taxadb`'s own (stale)
    registry, unchanged from before this was added. `country` filtering, rank filtering (including the
    `order`-reserved-keyword case, confirmed unaffected -- `rank = "order"` against the real 2026
    snapshot returns 767,547 rows via ordinary `dplyr::filter()`), and `include_synonyms` all work
    identically whether the source is `taxadb`'s registry or a direct snapshot URL.
  - `duckdb`/`DBI` added to `DESCRIPTION`'s `Suggests` (both already transitive dependencies of
    `taxadb` itself, so no new install burden for anyone who already uses this function).
  - Test coverage: mocks `gbif_snapshot_tbl()` directly (a same-package internal function, so no
    `.package =` needed) to prove the bypass-taxadb assertion and exercise the full reshape pipeline
    offline; a small local parquet file written via `duckdb`'s own `COPY ... TO ... (FORMAT PARQUET)`
    covers the missing-column schema-check error, also offline; one real, live test against the actual
    source.coop URL (skipped unless online/not on CRAN, same gating `test-apc_equivalence.R` uses for
    its own live external dependency) confirms `"Trachytetra"` resolves for real, not just against a
    mock.

### 3. Known-source reference loaders — `R/load_AFD.R`, `R/load_APC.R` (exported: `load_AFD()`, `load_APC()`; internal helpers `@noRd`)

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
- Publish: `gh release create <date> --repo traitecoevo/taxonalign-dataprep --draft ...`; user agreed:
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
(gitignored). `vignettes/AFD-data-processing.qmd` is the curator-facing record of every AFD-format/NSL-format
transformation (Architecture #4) -- keep it in sync if either loader's rules change.
