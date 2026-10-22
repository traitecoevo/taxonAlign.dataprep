# taxonAlign.dataprep

## What you can use these packages for

- **Align taxon names to any taxonomic reference you choose** -- correcting misspellings, updating
  synonyms to the currently accepted name, and matching names only identified to genus, family or any
  other rank. *([taxonAlign](https://github.com/traitecoevo/taxonAlign))*
- **Generate a taxonomic reference list for any taxon group, from any region** -- for example, as the
  taxonomic reference for a [traits.build](https://github.com/traitecoevo/traits.build) database -- from
  GBIF, the Catalogue of Life, the World Checklist of Vascular Plants, or your own table.
  *(taxonAlign.dataprep)*
- **Work directly with Australia's National Species Lists** for animals, fungi, vascular plants,
  bryophytes, lichens and algae -- both packages are designed around them. The animal, fungi,
  bryophyte, lichen and algae lists are published as dated, ready-to-use reference lists; vascular
  plants come from the Australian Plant Census. *(both)*

## Two packages

The work is split between two packages:

- **[taxonAlign](https://github.com/traitecoevo/taxonAlign)** aligns names and updates them to the
  currently accepted name. It also downloads the ready-made reference lists (the National Species
  Lists, and GBIF's list of Australian animals) from dated data releases. If your taxa are covered by
  one of those lists, or you already have a reference table in taxonAlign's format, it's all you need.
- **[taxonAlign.dataprep](https://github.com/traitecoevo/taxonAlign.dataprep)** builds reference
  lists -- from GBIF, the Catalogue of Life, the World Checklist of Vascular Plants, the Australian
  Plant Census, or your own table -- and builds taxonAlign's data releases.

## Installation

Neither package is on CRAN. To align and update names, install taxonAlign:

``` r
# install.packages("pak")
pak::pak("traitecoevo/taxonAlign")
```

To build your own reference lists as well, install taxonAlign.dataprep, which installs taxonAlign
along with it:

``` r
pak::pak("traitecoevo/taxonAlign.dataprep")
```

## About this package

| Function | What it does |
|---|---|
| `build_taxonomic_reference()` | Walk through turning your own reference table(s), whatever their column names, into taxonAlign's format, combining several in a chosen priority order. |
| `load_NSL()` | Reshape an Australian National Species List export -- `"animals"` (the Australian Faunal Directory), `"algae"`, `"bryophytes"`, `"fungi"` or `"lichens"` -- from the verbatim copy in a data release, or from your own download. |
| `load_APC()` | The Australian Plant Census, via `APCalign::load_taxonomic_resources()`. |
| `load_CoL()` | The Catalogue of Life, from ChecklistBank: a reference to every taxon in every kingdom -- the latest release, or a named one by its key (`316595` for COL26.10) or alias (`"COL25"`). |
| `load_WCVP()` | The World Checklist of Vascular Plants (Royal Botanic Gardens, Kew): every vascular plant name worldwide, current or a named version (`version = 16`). |
| `filter_to_country()` | Restrict any reference -- e.g. the WCVP or COL -- to the taxa GBIF has occurrence records of in one or more countries, linking GBIF's names to the reference's accepted names *or* synonyms. |
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

## Data releases

The data releases `taxonAlign::load_taxonomic_resources()` downloads are published on this repo's
GitHub Releases, tagged by date (`YYYY-MM-DD`). Each holds, for every dataset, the source exports
exactly as supplied, the dataset in taxonAlign's format (`<dataset>.parquet`), and a `manifest.csv`
recording each file's source, retrieval date, row count, checksum, licence and citation. They're built
by [`data-raw/build_data_release.R`](data-raw/build_data_release.R).

See [`vignettes/get-started.qmd`](vignettes/get-started.qmd) for a walkthrough, and
[`vignettes/AFD-data-processing.qmd`](vignettes/AFD-data-processing.qmd) for exactly how the
Australian Faunal Directory's exports are reshaped, and how its two formats compared.
