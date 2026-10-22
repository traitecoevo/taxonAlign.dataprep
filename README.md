# taxonAlign.dataprep

Companion to [taxonAlign](https://github.com/traitecoevo/taxonAlign). taxonAlign aligns and updates
raw taxon names against a taxonomic reference in its own documented format
(`taxonAlign::taxonomic_reference_schema()`), and downloads ready-made references from dated data
releases with `taxonAlign::load_taxonomic_resources()`. Most users need nothing else.

This package is for building a reference yourself, and for building those releases.

| Function | What it does |
|---|---|
| `build_taxonomic_reference()` | Walk through turning your own reference table(s), whatever their column names, into taxonAlign's format, combining several in a chosen priority order. |
| `load_NSL()` | Reshape an Australian National Species List export -- `"animals"` (the Australian Faunal Directory), `"algae"`, `"bryophytes"`, `"fungi"` or `"lichens"`. |
| `load_AFD()` | Reshape the Australian Faunal Directory's own CSV export (the "AFD format"). |
| `load_APC()` | The Australian Plant Census, via `APCalign::load_taxonomic_resources()`. |
| `generate_GBIF_taxonomic_reference_list()` | Build a reference from the *live* GBIF backbone taxonomy for a taxon (optionally filtered by country and/or minimum rank) -- best for a small clade. |
| `generate_taxadb_taxonomic_reference_list()` | Build a reference from [taxadb](https://docs.ropensci.org/taxadb/)'s pre-cached snapshot of GBIF, ITIS, or another supported authority -- fast for a large clade. |

Every function returns one table in taxonAlign's format, which goes straight into taxonAlign's
matching functions:

``` r
library(taxonAlign.dataprep)
library(taxonAlign)

aporocera <- generate_GBIF_taxonomic_reference_list("Aporocera", country = "AU")
create_taxonomic_update_lookup(c("Aporocera viridipennis", "Aporocera sp. 1"), aporocera)
```

## Installation

``` r
# install.packages("pak")
pak::pak("traitecoevo/taxonalign-dataprep")
```

## Data releases

The data releases `taxonAlign::load_taxonomic_resources()` downloads are published on this repo's
GitHub Releases, tagged by date (`YYYY-MM-DD`). Each holds, for every dataset, the source exports
exactly as supplied, the dataset in taxonAlign's format (`<dataset>.parquet`), and a `manifest.csv`
recording each file's source, retrieval date, row count, checksum, licence and citation. They're built
by [`data-raw/build_data_release.R`](data-raw/build_data_release.R).

See [`vignettes/get-started.qmd`](vignettes/get-started.qmd) for a walkthrough, and
[`vignettes/AFD-data-processing.qmd`](vignettes/AFD-data-processing.qmd) for exactly how the
Australian Faunal Directory's two export formats are reshaped, and how they compare.
