# Update the data: scrape today's snapshot, then rebuild the database and the
# dashboard's data. Run daily by GitHub Actions; Netlify then renders the
# dashboard.
#
# Usage:
#   Rscript update_data.R              # scrape, then rebuild
#   Rscript update_data.R --no-scrape  # rebuild from the existing snapshots

library(dplyr)
library(httr2)
library(purrr)
library(readr)
library(stringr)
library(tibble)
library(tidyr)

walk(list.files("R", pattern = "\\.R$", full.names = TRUE), source)

if (!"--no-scrape" %in% commandArgs(trailingOnly = TRUE)) {
  message("Scraping the IFoA directory")
  today <- Sys.Date()
  snapshot <- scrape_directory(today)

  # An empty scrape means the directory or its API is down or has changed.
  # Stop without saving, so the workflow fails (and GitHub emails a failure
  # notice) rather than committing an empty snapshot.
  if (nrow(snapshot) == 0) {
    stop(
      "The scrape found no certificate holders, so no snapshot was saved. ",
      "Check that https://my.actuaries.org.uk is up and its search still ",
      "works.",
      call. = FALSE
    )
  }

  save_snapshot(snapshot, today)
}

message("Building the database")
snapshots <- read_snapshots()
spells <- build_spells(snapshots)
dates <- snapshot_dates(snapshots)

write_database(spells, dates)
write_dashboard_data(spells, dates)
