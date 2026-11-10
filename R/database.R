# Combine the daily snapshots into one record per spell of holding a
# practising certificate.

#' Read every snapshot in `dir`
#'
#' @returns One row per person and certificate list in each snapshot, with
#'   snake_case column names.
read_snapshots <- function(dir = "data/raw") {
  list.files(dir, pattern = "\\.rds$", full.names = TRUE) |>
    map(read_rds) |>
    list_rbind() |>
    rename(
      first_name = `First name`,
      last_name = Surname,
      status = Status,
      certificate_types = `Practising certificate type`,
      regulatory_record = `Regulatory record`
    )
}

#' Dates where the scrape returned data
#'
#' Empty scrapes (eg site outages) are treated as missing, not as everyone
#' relinquishing their certificate.
snapshot_dates <- function(snapshots) {
  snapshots |>
    distinct(date) |>
    arrange(date) |>
    pull(date)
}

#' One record per spell of holding a certificate
#'
#' A certificate counts as relinquished only once its holder has been missing
#' from at least `missing_snapshots` consecutive successful snapshots,
#' spanning more than `missing_days` days. This stops partial scrapes and
#' listings that briefly drop out of the directory creating false leavers and
#' joiners. A new spell starts when someone reappears after such a gap.
#'
#' Details that can change during a spell (eg CERA) are taken from its last
#' snapshot.
build_spells <- function(snapshots, missing_snapshots = 3, missing_days = 30) {
  dates <- snapshot_dates(snapshots)
  n_dates <- length(dates)

  holdings(snapshots) |>
    mutate(snapshot_index = match(date, dates)) |>
    arrange(first_name, last_name, certificate, date) |>
    mutate(
      lapsed = snapshot_index - lag(snapshot_index) > missing_snapshots &
        date - lag(date) > missing_days,
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
      first_date = dates[first_index],
      last_date = dates[last_index],
      # Not yet missing from enough snapshots to count as relinquished.
      current = last_index >= n_dates - missing_snapshots |
        max(dates) - last_date <= missing_days,
      # The change happened somewhere between these dates; wide windows mean
      # the scrape was down.
      joined_after = if_else(
        first_index > 1,
        dates[pmax(first_index - 1, 1)],
        as.Date(NA)
      ),
      left_before = if_else(
        current,
        as.Date(NA),
        dates[pmin(last_index + 1, n_dates)]
      )
    ) |>
    select(
      first_name, last_name, certificate,
      first_date, last_date, joined_after, left_before, current,
      fellow_type, qualification_year, cera, regulatory_record
    )
}

# One row per certificate held by each person in each snapshot.
holdings <- function(snapshots) {
  snapshots |>
    cross_join(select(certificates, certificate, pattern)) |>
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
}

#' Save the database: spells and successful snapshot dates
write_database <- function(spells, dates, dir = "data/database") {
  write_rds(
    spells,
    file.path(dir, "certificate_database.rds"),
    compress = "none",
    text = TRUE
  )
  write_rds(
    dates,
    file.path(dir, "snapshot_dates.rds"),
    compress = "none",
    text = TRUE
  )
}

#' Save the data the dashboard loads in the browser
#'
#' The dashboard has no R code, so Netlify can render it with Quarto alone.
#' Everything the page needs is prepared here.
write_dashboard_data <- function(spells,
                                 dates,
                                 path = "dashboard/dashboard_data.json") {
  certificate_labels <- deframe(select(certificates, certificate, label))

  dashboard_spells <-
    spells |>
    mutate(
      certificate = unname(certificate_labels[certificate]),
      fellow = recode_values(
        fellow_type,
        "Fellow FIA" ~ "FIA",
        "Fellow FFA" ~ "FFA",
        default = "Unknown"
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
      snapshot_dates = format(dates),
      certs = certificates$label
    ),
    path,
    dataframe = "rows",
    na = "null",
    auto_unbox = TRUE
  )
}
