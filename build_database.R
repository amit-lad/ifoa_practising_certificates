library(tidyverse)
library(purrr)

# A person is treated as having relinquished a certificate only once they are missing from at least this many
# consecutive successful snapshots, spanning at least this many days. This stops partial scrapes and
# listings that briefly drop out of the directory creating false leavers/joiners.
missing_snapshots_to_lapse <- 3
missing_days_to_lapse <- 30

# Read in the raw scraped data
raw_data_files <- list.files(path = "data_raw", pattern = "*.rds$", full.names = TRUE)
raw_data <- raw_data_files |> map_df(read_rds)

# Dates where the scrape returned data. Empty scrapes (eg site outages) are treated as missing, not as
# everyone relinquishing their certificate.
snapshot_dates <- raw_data |> distinct(date) |> arrange(date) |> pull(date)

# Create PC type
PC_types = tibble(
  certificate_regex = c("Chief Actuary \\(Life\\)", "With[- ]Profits Actuary", "Chief Actuary \\(Life, Non-Directive\\)", "Chief Actuary \\(non-Life without Lloyd's\\)", "Chief Actuary \\(non-Life with Lloyd's\\)", "Lloyd's Syndicate Actuary", "Scheme Actuary"),
  certificate = c("Chief Actuary (Life)", "With Profits Actuary", "Chief Actuary (Life, Non-Directive)", "Chief Actuary (non-Life without Lloyd's)", "Chief Actuary (non-Life with Lloyd's)", "Lloyd's Syndicate Actuary", "Scheme Actuary")
  )

# Clean data
cleaned_data_full_list <-
  raw_data |>
  # Convert so there is one row for each PC type that a person has.
  cross_join(PC_types) |>
  mutate(
    `Practising certificate type` = str_squish(`Practising certificate type`),
    PC_present = str_detect(string = `Practising certificate type`, pattern = certificate_regex)
  ) |>
  filter(PC_present == TRUE) |>
  # Capture key characteristics of each person
  replace_na(list(`Regulatory record` = "")) |>
  mutate(
    fellow_type = str_extract(Status, "^[:alpha:]+[:space:][:alpha:]+"),
    qualification_year = as.integer(str_extract(Status, "[:digit:]{4}")),
    cera = str_detect(Status, "CERA"),
    regulatory_record = str_detect(`Regulatory record`, "[:alpha:]+")
  ) |>
  # Keep selected fields.
  select(`First name`, Surname, date, certificate, fellow_type, qualification_year, cera, regulatory_record) |>
  unique()

# The current directory rarely shows CERA, so count anyone ever shown as CERA as CERA.
cleaned_data_full_list <-
  cleaned_data_full_list |>
  group_by(`First name`, Surname) |>
  mutate(cera = any(cera)) |>
  ungroup()

# One record per spell of holding a certificate. A new spell starts when a person reappears after being
# missing for at least `missing_snapshots_to_lapse` successful snapshots and `missing_days_to_lapse` days.
# Some details (eg CERA) may change whilst having a PC certificate - only capture status on last record.
cleaned_data_spells <-
  cleaned_data_full_list |>
  mutate(snapshot_index = match(date, snapshot_dates)) |>
  arrange(`First name`, Surname, certificate, date) |>
  group_by(`First name`, Surname, certificate) |>
  mutate(
    lapsed = snapshot_index - lag(snapshot_index) > missing_snapshots_to_lapse &
      date - lag(date) > missing_days_to_lapse,
    spell = cumsum(is.na(lag(snapshot_index)) | lapsed)
  ) |>
  group_by(`First name`, Surname, certificate, spell) |>
  summarise(
    first_index = min(snapshot_index),
    last_index = max(snapshot_index),
    across(c(fellow_type, qualification_year, cera, regulatory_record), last),
    .groups = "drop"
  ) |>
  mutate(
    first_date = snapshot_dates[first_index],
    last_date = snapshot_dates[last_index],
    # Not yet missing from enough snapshots to count as relinquished.
    current = last_index >= length(snapshot_dates) - missing_snapshots_to_lapse |
      max(snapshot_dates) - last_date <= missing_days_to_lapse,
    # The change happened somewhere between these dates; wide windows mean the scrape was down.
    joined_after = if_else(first_index > 1, snapshot_dates[pmax(first_index - 1, 1)], as.Date(NA)),
    left_before = if_else(current, as.Date(NA), snapshot_dates[pmin(last_index + 1, length(snapshot_dates))])
  ) |>
  rename("first_name" = `First name`, "last_name" = Surname) |>
  select(first_name, last_name, certificate, first_date, last_date, joined_after, left_before, current,
         fellow_type, qualification_year, cera, regulatory_record)

# Write outputs
write_rds(
  x = cleaned_data_spells,
  file = paste0("database/certificate_database.rds"),
  compress = "none",
  text = TRUE
)

# Successful snapshot dates, so the dashboard can count holders on each date and show gaps in coverage.
write_rds(
  x = snapshot_dates,
  file = paste0("database/snapshot_dates.rds"),
  compress = "none",
  text = TRUE
)
