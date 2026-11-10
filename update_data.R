# Update the data: scrape today's snapshot, then rebuild the database and the
# dashboard's data. Run daily by GitHub Actions; Netlify then renders the
# dashboard.
#
# Usage:
#   Rscript update_data.R              # scrape, then rebuild
#   Rscript update_data.R --no-scrape  # rebuild from the existing snapshots
#
# If the database changed, it also writes an email listing the changes to
# email/subject.txt and email/email.html, for the workflow to send.

library(dplyr)
library(httr2)
library(purrr)
library(readr)
library(stringr)
library(tibble)
library(tidyr)

walk(list.files("R", pattern = "\\.R$", full.names = TRUE), source)

args <- commandArgs(trailingOnly = TRUE)

# The database from the last successful update, to compare against.
previous <- read_database()

if (!"--no-scrape" %in% args) {
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

# No email on a first run, when there's nothing to compare with.
email <- if (!is.null(previous)) {
  change_email(
    compare_databases(previous$spells, spells),
    previous$dates,
    dates
  )
}

if (write_change_email(email)) {
  message("Email: ", email$subject)
} else {
  message("No changes to email")
}
