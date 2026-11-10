# Combine the daily snapshots in data_raw/ into one record per spell of
# holding a practising certificate, and save the database and the dashboard's
# data to database/.

library(tidyverse)

# A certificate counts as relinquished only once its holder has been missing
# from at least this many consecutive successful snapshots, spanning at least
# this many days. This stops partial scrapes and listings that briefly drop
# out of the directory creating false leavers and joiners.
missing_snapshots_to_lapse <- 3
missing_days_to_lapse <- 30

# Each certificate type's full name and the short label the dashboard uses,
# in dashboard order.
certificates <- tribble(
  ~certificate,                               ~label,
  "Chief Actuary (Life)",                     "Life",
  "Chief Actuary (Life, Non-Directive)",      "Life (Non-Directive)",
  "With Profits Actuary",                     "With Profits",
  "Chief Actuary (non-Life with Lloyd's)",    "Non-Life with Lloyd's",
  "Chief Actuary (non-Life without Lloyd's)", "Non-Life ex Lloyd's",
  "Lloyd's Syndicate Actuary",                "Syndicate",
  "Scheme Actuary",                           "Scheme"
) |>
  # How to find each certificate in the directory's text. The directory has
  # spelt "With-Profits" both with and without the hyphen.
  mutate(
    pattern = if_else(
      label == "With Profits",
      "With[- ]Profits Actuary",
      str_escape(certificate)
    )
  )

# Read the snapshots --------------------------------------------------------

snapshots <-
  list.files("data_raw", pattern = "\\.rds$", full.names = TRUE) |>
  map(read_rds) |>
  list_rbind() |>
  rename(
    first_name = `First name`,
    last_name = Surname,
    status = Status,
    certificate_types = `Practising certificate type`,
    regulatory_record = `Regulatory record`
  )

# Dates where the scrape returned data. Empty scrapes (eg site outages) are
# treated as missing, not as everyone relinquishing their certificate.
snapshot_dates <- snapshots |>
  distinct(date) |>
  arrange(date) |>
  pull(date)

# One row per certificate held in each snapshot -----------------------------

holdings <-
  snapshots |>
  # One row for each certificate type a person holds.
  cross_join(certificates) |>
  filter(str_detect(str_squish(certificate_types), pattern)) |>
  mutate(
    fellow_type = str_extract(status, "^[:alpha:]+[:space:][:alpha:]+"),
    qualification_year = as.integer(str_extract(status, "[:digit:]{4}")),
    cera = str_detect(status, "CERA"),
    regulatory_record = str_detect(
      replace_na(regulatory_record, ""),
      "[:alpha:]+"
    )
  ) |>
  distinct(
    first_name, last_name, date, certificate,
    fellow_type, qualification_year, cera, regulatory_record
  ) |>
  # The current directory rarely shows CERA, so count anyone ever shown as
  # CERA as CERA.
  mutate(cera = any(cera), .by = c(first_name, last_name))

# One row per spell of holding a certificate --------------------------------

# A new spell starts when a person reappears after being missing for at least
# `missing_snapshots_to_lapse` successful snapshots and
# `missing_days_to_lapse` days. Details that can change during a spell (eg
# CERA) are taken from its last snapshot.
n_snapshots <- length(snapshot_dates)
latest_date <- max(snapshot_dates)

spells <-
  holdings |>
  mutate(snapshot_index = match(date, snapshot_dates)) |>
  arrange(first_name, last_name, certificate, date) |>
  mutate(
    lapsed = snapshot_index - lag(snapshot_index) > missing_snapshots_to_lapse &
      date - lag(date) > missing_days_to_lapse,
    spell = cumsum(is.na(lag(snapshot_index)) | lapsed),
    .by = c(first_name, last_name, certificate)
  ) |>
  summarise(
    first_index = min(snapshot_index),
    last_index = max(snapshot_index),
    across(c(fellow_type, qualification_year, cera, regulatory_record), last),
    .by = c(first_name, last_name, certificate, spell)
  ) |>
  arrange(first_name, last_name, certificate, spell) |>
  mutate(
    first_date = snapshot_dates[first_index],
    last_date = snapshot_dates[last_index],
    # Not yet missing from enough snapshots to count as relinquished.
    current = last_index >= n_snapshots - missing_snapshots_to_lapse |
      latest_date - last_date <= missing_days_to_lapse,
    # The change happened somewhere between these dates; wide windows mean the
    # scrape was down.
    joined_after = if_else(
      first_index > 1,
      snapshot_dates[pmax(first_index - 1, 1)],
      as.Date(NA)
    ),
    left_before = if_else(
      current,
      as.Date(NA),
      snapshot_dates[pmin(last_index + 1, n_snapshots)]
    )
  ) |>
  select(
    first_name, last_name, certificate,
    first_date, last_date, joined_after, left_before, current,
    fellow_type, qualification_year, cera, regulatory_record
  )

# Write outputs -------------------------------------------------------------

write_rds(
  spells,
  "database/certificate_database.rds",
  compress = "none",
  text = TRUE
)

# Successful snapshot dates, so the dashboard can count holders on each date
# and show gaps in coverage.
write_rds(
  snapshot_dates,
  "database/snapshot_dates.rds",
  compress = "none",
  text = TRUE
)

# The dashboard loads this in the browser. Netlify renders the dashboard with
# Quarto alone (no R), so everything the page needs is prepared here.
certificate_labels <- deframe(select(certificates, certificate, label))

dashboard_spells <-
  spells |>
  mutate(
    certificate = unname(certificate_labels[certificate]),
    fellow = case_match(
      fellow_type,
      "Fellow FIA" ~ "FIA",
      "Fellow FFA" ~ "FFA",
      .default = "Unknown"
    ),
    across(c(first_date, last_date, joined_after, left_before), format)
  ) |>
  select(
    first_name, last_name, certificate,
    first_date, last_date, joined_after, left_before, current,
    fellow, qualification_year, cera, regulatory_record
  )

jsonlite::write_json(
  list(
    spells = dashboard_spells,
    snapshot_dates = format(snapshot_dates),
    certs = certificates$label
  ),
  "database/dashboard_data.json",
  dataframe = "rows",
  na = "null",
  auto_unbox = TRUE
)
