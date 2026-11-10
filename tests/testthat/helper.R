library(dplyr)
library(purrr)
library(readr)
library(stringr)
library(tibble)
library(tidyr)

walk(
  list.files(test_path("..", "..", "R"), pattern = "\\.R$", full.names = TRUE),
  source
)

# Snapshot rows for one person, in the shape read_snapshots() returns.
person <- function(dates,
                   first_name = "Ann",
                   last_name = "Smith",
                   certificate_types = "Scheme Actuary",
                   status = "Fellow FIA 2001",
                   regulatory_record = NA_character_) {
  tibble(
    first_name = first_name,
    last_name = last_name,
    status = status,
    certificate_types = certificate_types,
    regulatory_record = regulatory_record,
    date = as.Date(dates)
  )
}

# 91 daily snapshots, from 1 Jan to 31 Mar 2024.
days <- seq(as.Date("2024-01-01"), by = "day", length.out = 91)

# Someone in every snapshot, so each test controls the snapshot dates.
everyone <- function(dates = days) {
  person(dates, first_name = "Bob", last_name = "Jones")
}

ann_spells <- function(...) {
  bind_rows(everyone(), ...) |>
    build_spells() |>
    filter(first_name == "Ann")
}
