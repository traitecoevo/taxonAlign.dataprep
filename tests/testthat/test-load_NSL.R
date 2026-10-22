# Covers load_NSL() end to end against a small NSL-shaped fixture pair
# (helper-nsl-fixtures.R), entirely offline -- no need for the real, much larger
# inst/extdata/Australian_*/ files.

test_that("load_NSL errors clearly on an unknown taxon_group", {
  expect_error(
    load_NSL("not_a_real_group"),
    "`taxon_group` must be exactly one of"
  )
})

test_that("load_NSL errors clearly when the folder is missing", {
  expect_error(
    load_NSL("fungi", path = "/no/such/directory"),
    "Couldn't find the NSL reference folder"
  )
})

test_that("load_NSL returns a flat tibble with the required columns", {
  dir <- write_sample_nsl_dir()
  out <- load_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  expect_true(all(c(
    "canonical_name", "scientific_name", "taxon_rank", "taxonomic_status", "taxonomic_dataset",
    "genus", "taxon_ID", "accepted_name_usage_ID"
  ) %in% names(out)))
})

test_that("load_NSL: taxa take priority over names -- every duplicated name is dropped from the names file", {
  dir <- write_sample_nsl_dir()
  out <- load_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  # 5 taxon-file rows + exactly 1 names-only row ("Testusgenus informalis"), not 5 + 6
  expect_equal(nrow(out), 6)
  expect_equal(sum(out$canonical_name == "Testidae"), 1)
  expect_equal(sum(out$canonical_name == "Testusgenus alphus"), 1)

  # the surviving row for a name present in both files is the taxon-file version (real
  # taxon_ID/accepted_name_usage_ID resolution), never the names-file's self-referential one
  fam <- out |> dplyr::filter(canonical_name == "Testidae")
  expect_equal(fam$taxon_ID, "t-fam1")
  expect_equal(fam$taxonomic_dataset, "TFX")

  # the names-only row widens coverage but resolves to itself, having no accepted-name link of its own
  extra <- out |> dplyr::filter(canonical_name == "Testusgenus informalis")
  expect_equal(nrow(extra), 1)
  expect_equal(extra$taxon_ID, "n-extra1")
  expect_equal(extra$accepted_name_usage_ID, "n-extra1")
  expect_equal(extra$taxonomic_dataset, "NFX")
})

test_that("load_NSL derives genus correctly by rank, and strips the subgenus marker", {
  dir <- write_sample_nsl_dir()
  out <- load_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  fam <- out |> dplyr::filter(canonical_name == "Testidae")
  gen <- out |> dplyr::filter(canonical_name == "Testusgenus", taxon_rank == "Genus")
  subgen <- out |> dplyr::filter(taxon_rank == "Subgenus")
  sp <- out |> dplyr::filter(canonical_name == "Testusgenus alphus")
  syn <- out |> dplyr::filter(canonical_name == "Oldgenus alphus")

  expect_true(is.na(fam$genus))
  expect_equal(gen$genus, "Testusgenus")
  # the "Genus subg. Subgenusname" marker is stripped down to the bare subgenus name, matching AFD's
  # own bare-subgenus-name convention -- required for prepare_taxonomic_resources()'s subgenus_v2 to
  # build a correct, non-doubled "Genus (Subgenus)" key
  expect_equal(subgen$canonical_name, "Testussub")
  expect_equal(subgen$genus, "Testusgenus")
  expect_equal(sp$genus, "Testusgenus")
  # a synonym's genus is re-derived from its own name, not copied from the accepted row it resolves to
  expect_equal(syn$genus, "Oldgenus")
})

test_that("load_NSL caches the reshaped result, keyed by both files' mtime/size", {
  dir <- write_sample_nsl_dir()
  cache_dir <- withr::local_tempdir()

  expect_message(
    load_NSL("fungi", path = dir, cache_dir = cache_dir),
    "Reading and reshaping"
  )
  expect_message(
    load_NSL("fungi", path = dir, cache_dir = cache_dir),
    "Using cached"
  )
  expect_message(
    load_NSL("fungi", path = dir, cache_dir = cache_dir, refresh_cache = TRUE),
    "Reading and reshaping"
  )
})

test_that("prepare_taxonomic_resources(load_NSL(...)) runs end to end into align_taxa(), including the marker-form subgenus", {
  dir <- write_sample_nsl_dir()
  nsl <- load_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)
  resources <- taxonAlign::prepare_taxonomic_resources(nsl)

  # subgenus_v2 was built correctly from the stripped canonical_name + genus pairing
  expect_true("Testusgenus (Testussub)" %in% resources$subgenus_v2$genus_and_subgenus)

  out <- taxonAlign::create_taxonomic_update_lookup(
    c("Testusgenus alphus", "Oldgenus alphus", "Testusgenus subg. Testussub", "Testusgenus informalis"),
    resources
  )

  expect_equal(out$accepted_name[1:2], c("Testusgenus alphus", "Testusgenus alphus"))
  expect_equal(out$taxonomic_status_aligned[1:2], c("accepted", "taxonomic synonym"))
  # the marker-form subgenus query (match_02x, issue #25) resolves via the taxon-file-derived resource
  expect_equal(out$taxon_rank[3], "subgenus")
  # the names-file-only row is still findable (it only ever widens coverage), but its own status
  # ("unplaced") is never literally "accepted", so accepted_name stays NA by design (update_taxa() only
  # reports accepted_name when the resolved record's own status is "accepted") -- suggested_name is the
  # guaranteed fallback
  expect_true(is.na(out$accepted_name[4]))
  expect_equal(out$suggested_name[4], "Testusgenus informalis")
})

test_that("load_NSL(\"animals\") reads the pipe-delimited, snake_case AFD NSL export", {
  dir <- write_sample_nsl_animals_dir()
  out <- load_NSL("animals", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  # 9 taxon rows bound first, then the 2 names-file-only rows -- never the 3 duplicated names
  expect_equal(nrow(out), 11)
  expect_equal(out$taxonomic_dataset, c(rep("AFD", 9), rep("AFDNI", 2)))
  expect_equal(sum(out$canonical_name == "Oldavis alba"), 1)
})

test_that("load_NSL(\"animals\") strips the zoological \"Genus (Subgenus)\" form and derives genus by rank", {
  dir <- write_sample_nsl_animals_dir()
  out <- load_NSL("animals", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  subgen <- out |> dplyr::filter(taxon_rank == "Subgenus")
  expect_setequal(subgen$canonical_name, c("Avigenus", "Montavis", "Lowavis"))
  expect_true(all(subgen$genus == "Avigenus"))

  # above-genus ranks get no genus -- including a single-word zoological Section and a Generic
  # Aggregate written "Subtribe Testina" (whose first word is not a genus)
  expect_true(all(is.na(out$genus[out$taxon_rank %in% c("Family", "Section", "Generic Aggregate")])))
  # a synonym's genus comes from its own name, not the taxon file's (accepted-name) generic_name
  expect_equal(out$genus[out$canonical_name == "Oldavis alba"], "Oldavis")
})

test_that("load_NSL makes excluded/vagrant taxa self-referential rather than pointing at their parent", {
  dir <- write_sample_nsl_animals_dir()
  out <- load_NSL("animals", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  vag <- out |> dplyr::filter(canonical_name == "Vagrantia errans")
  expect_equal(vag$taxonomic_status, "vagrant species")
  expect_equal(vag$accepted_name_usage_ID, vag$taxon_ID)
  # an ordinary synonym still resolves forward
  expect_equal(out$accepted_name_usage_ID[out$canonical_name == "Oldavis alba"], "t-sp")
})

test_that("prepare_taxonomic_resources(load_NSL(\"animals\")) runs end to end", {
  dir <- write_sample_nsl_animals_dir()
  nsl <- load_NSL("animals", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)
  resources <- taxonAlign::prepare_taxonomic_resources(nsl)

  expect_true(all(c("Avigenus (Montavis)", "Avigenus (Avigenus)") %in% resources$subgenus_v2$genus_and_subgenus))

  out <- taxonAlign::create_taxonomic_update_lookup(
    c("Oldavis alba", "Avigenus (Montavis)", "Vagrantia errans"), resources
  )
  expect_equal(out$accepted_name[1], "Avigenus alba")
  expect_equal(out$taxon_rank[2], "subgenus")
  # a vagrant species stays itself, rather than being "updated" to its family
  expect_equal(out$suggested_name[3], "Vagrantia errans")
})

test_that("load_NSL(\"animals\") writes the subgenus back into zoological species-level names", {
  taxon <- sample_nsl_animals_taxon_raw()
  taxon$nomenclatural_code <- "ICZN"
  taxon$parent_name_usage_id <- NA_character_
  taxon$parent_name_usage_id[taxon$taxon_id == "t-sp"] <- "t-sg2"
  # a subspecies reaches its subgenus through its species
  taxon <- dplyr::bind_rows(taxon, tibble::tibble(
    taxon_id = "t-ssp", scientific_name_id = "n-ssp", accepted_name_usage_id = "t-ssp",
    taxonomic_status = "accepted", scientific_name = "Avigenus alba nana Green, 1920",
    canonical_name = "Avigenus alba nana", taxon_rank = "Subspecies", dataset_name = "AFD",
    generic_name = "Avigenus", nomenclatural_code = "ICZN", parent_name_usage_id = "t-sp"
  ))
  dir <- withr::local_tempdir()
  readr::write_delim(taxon, file.path(dir, "AFD_export_taxon_1.txt"), delim = "|", quote = "all", na = "")
  readr::write_delim(sample_nsl_animals_names_raw(), file.path(dir, "AFD_export_name_1.txt"), delim = "|", quote = "all", na = "")

  out <- load_NSL("animals", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_true("Avigenus (Montavis) alba" %in% out$canonical_name)
  expect_true("Avigenus (Montavis) alba nana" %in% out$canonical_name)
  # synonyms carry no parent link, so are left as written
  expect_true("Oldavis alba" %in% out$canonical_name)

  # and matching still works on the plain binomial, reporting the full name
  res <- taxonAlign::create_taxonomic_update_lookup(c("Avigenus alba", "Oldavis alba"), taxonAlign::prepare_taxonomic_resources(out))
  expect_equal(res$accepted_name, rep("Avigenus (Montavis) alba", 2))
})

test_that("NSL canonical names lose quote marks and misapplication markers, as AFD-format names do", {
  raw <- tibble::tibble(
    canonical_name = c("'Ochlerotatus' notoscriptus", "Allotria d'arci", "Saragus auctt. nec", "Plain name"),
    taxonomic_status = c("Generic combination", "synonym", "synonym", "synonym")
  )
  out <- clean_NSL_canonical_names(raw)
  expect_equal(out$canonical_name, c("Ochlerotatus notoscriptus", "Allotria d'arci", "Saragus", "Plain name"))
  expect_equal(out$taxonomic_status, c("Generic combination", "synonym", "misapplied", "synonym"))
})

test_that("load_NSL reads a data release's verbatim parquet copies the same as the original export files", {
  release <- withr::local_tempdir()
  arrow::write_parquet(sample_nsl_animals_taxon_raw(), file.path(release, "nsl_animals_taxon.parquet"))
  arrow::write_parquet(sample_nsl_animals_names_raw(), file.path(release, "nsl_animals_names.parquet"))

  from_release <- load_NSL("animals", path = release, cache_dir = withr::local_tempdir(), quiet = TRUE)
  from_files <- load_NSL("animals", path = write_sample_nsl_animals_dir(),
                         cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(from_release, from_files)
  expect_silent(taxonAlign::check_taxonomic_reference(from_release))
})

test_that("load_NSL reads the verbatim exports in a data release by default", {
  release <- withr::local_tempdir()
  arrow::write_parquet(sample_nsl_animals_taxon_raw(), file.path(release, "nsl_animals_taxon.parquet"))
  arrow::write_parquet(sample_nsl_animals_names_raw(), file.path(release, "nsl_animals_names.parquet"))
  asked <- NULL
  local_mocked_bindings(
    download_data_release_files = function(files, version, ...) {
      asked <<- list(files = files, version = version)
      stats::setNames(file.path(release, files), files)
    },
    .package = "taxonAlign"
  )
  out <- load_NSL("animals", version = "2026-10-07", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(asked$files, c("nsl_animals_taxon.parquet", "nsl_animals_names.parquet"))
  expect_equal(asked$version, "2026-10-07")
  expect_equal(out, load_NSL("animals", path = release, cache_dir = withr::local_tempdir(), quiet = TRUE))
})

test_that("the AFD's usage markers are read as statuses and removed from names", {
  marked <- c(
    "Dendrodoris fumata auctt. non Rüppell & Leuckart, 0", "Aulicus episcopalis sensu Smith",
    "Chelonia depressa (part.)", "Mopsea elegans [pars]", "Hammaticherus indutus auct., ",
    "Testus alphus"
  )
  expect_equal(
    afd_usage_status(marked, "synonym"),
    c("misapplied", "misapplied", "pro parte synonym", "pro parte synonym", "misapplied", "synonym")
  )
  expect_equal(
    strip_afd_usage_markers(marked),
    c("Dendrodoris fumata", "Aulicus episcopalis", "Chelonia depressa", "Mopsea elegans",
      "Hammaticherus indutus", "Testus alphus")
  )
  expect_equal(
    strip_name_quotes(c("'Ochlerotatus' notoscriptus", "\"Ziba\" flammea", "Allotria d'arci")),
    c("Ochlerotatus notoscriptus", "Ziba flammea", "Allotria d'arci")
  )
})
