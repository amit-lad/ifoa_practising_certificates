# Compare the database before and after an update, and write an email
# listing what changed.

#' Read the database saved by the last successful update
#'
#' @returns A list of `spells` and `dates`, or `NULL` if there is no database
#'   yet.
read_database <- function(dir = "data/database") {
  spells_path <- file.path(dir, "certificate_database.rds")
  dates_path <- file.path(dir, "snapshot_dates.rds")
  if (!file.exists(spells_path) || !file.exists(dates_path)) {
    return(NULL)
  }

  list(spells = read_rds(spells_path), dates = read_rds(dates_path))
}

#' What changed between two versions of the database
#'
#' Spells are matched on name, certificate and first date.
#'
#' @returns A list of tibbles:
#'   - `gained`: spells that are new.
#'   - `relinquished`: spells that were current and now count as relinquished.
#'   - `details`: spells whose fellowship, qualification year, CERA or
#'     regulatory record changed, one row per change.
#'   - `removed`: spells that are no longer in the database. This only happens
#'     if snapshots were edited or removed.
compare_databases <- function(old_spells, new_spells) {
  key <- c("first_name", "last_name", "certificate", "first_date")
  detail_columns <- c(
    "fellow_type", "qualification_year", "cera", "regulatory_record"
  )

  both <- inner_join(
    old_spells,
    new_spells,
    by = key,
    suffix = c("_old", "_new")
  )

  details <-
    both |>
    select(all_of(key), ends_with("_old"), ends_with("_new")) |>
    mutate(across(-all_of(key), as.character)) |>
    pivot_longer(
      -all_of(key),
      names_to = c("detail", ".value"),
      names_pattern = "(.*)_(old|new)$"
    ) |>
    filter(detail %in% detail_columns, !identical_values(old, new))

  list(
    gained = anti_join(new_spells, old_spells, by = key),
    relinquished = both |>
      filter(current_old, !current_new) |>
      select(
        all_of(key),
        last_date = last_date_new,
        left_before = left_before_new
      ),
    details = details,
    removed = anti_join(old_spells, new_spells, by = key)
  )
}

has_changes <- function(changes) {
  some(changes, \(x) nrow(x) > 0)
}

# The dashboard on Netlify, linked from the email.
dashboard_url <- "https://practising-certificates.dashboards.amitlad.com/"

#' The email for an update
#'
#' @returns `list(subject, html)`, or `NULL` if nothing changed.
change_email <- function(changes, old_dates, new_dates) {
  if (!has_changes(changes)) {
    return(NULL)
  }

  label <- \(certificate) unname(certificate_labels()[certificate])
  name <- \(d) str_c(d$first_name, " ", d$last_name)
  yes_no <- \(x) recode_values(x, "TRUE" ~ "yes", "FALSE" ~ "no", default = x)
  n_other <- nrow(changes$details) + nrow(changes$removed)

  counts <- c(
    if (nrow(changes$gained) > 0) str_c(nrow(changes$gained), " gained"),
    if (nrow(changes$relinquished) > 0) {
      str_c(nrow(changes$relinquished), " relinquished")
    },
    if (n_other > 0) plural(n_other, "other change")
  )
  subject <- str_c("IFoA practising certificates: ", str_flatten_comma(counts))

  sections <- c(
    if (nrow(changes$gained) > 0) {
      gained <- in_dashboard_order(changes$gained)
      table <- html_table(tibble(
        Name = name(gained),
        Certificate = label(gained$certificate),
        `First seen` = format_date(gained$first_date)
      ))
      str_c("<h2>Gained</h2>", table)
    },
    if (nrow(changes$relinquished) > 0) {
      relinquished <- in_dashboard_order(changes$relinquished)
      table <- html_table(tibble(
        Name = name(relinquished),
        Certificate = label(relinquished$certificate),
        `Last seen` = format_date(relinquished$last_date)
      ))
      str_c(
        "<h2>Relinquished</h2>",
        "<p>A certificate counts as relinquished once its holder has been ",
        "missing from at least 3 snapshots spanning more than 30 days, so ",
        "these people were last seen some time ago.</p>",
        table
      )
    },
    if (nrow(changes$details) > 0) {
      details <- in_dashboard_order(changes$details)
      table <- html_table(tibble(
        Name = name(details),
        Certificate = label(details$certificate),
        Change = str_c(
          detail_names()[details$detail], ": ",
          yes_no(details$old), " to ", yes_no(details$new)
        )
      ))
      str_c("<h2>Other changes</h2>", table)
    },
    if (nrow(changes$removed) > 0) {
      str_c(
        "<p>Earlier records no longer in the database: ",
        nrow(changes$removed), ". That only happens if snapshots in data/raw/ ",
        "were edited or removed.</p>"
      )
    }
  )

  dashboard_link <- str_c("<a href=\"", dashboard_url, "\">dashboard</a>")
  html <- str_c(
    "<html><body style=\"font-family:sans-serif;\">",
    "<p>Changes found in the ",
    "<a href=\"https://my.actuaries.org.uk\">IFoA public directory</a> on ",
    format_date(max(new_dates)), ", since the last successful scrape on ",
    format_date(max(old_dates)), ". See all the data on the ",
    dashboard_link, ".</p>",
    str_c(sections, collapse = ""),
    "</body></html>"
  )
  list(subject = subject, html = html)
}

#' Write the email to `subject.txt` and `email.html` in `dir`
#'
#' Removes them if there is no email, so an old one is never sent.
#'
#' @returns `TRUE` if an email was written, invisibly.
write_change_email <- function(email, dir = "email") {
  files <- file.path(dir, c("subject.txt", "email.html"))
  unlink(files)
  if (is.null(email)) {
    return(invisible(FALSE))
  }

  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  write_lines(email$subject, files[1])
  write_lines(email$html, files[2])
  invisible(TRUE)
}

html_escape <- function(x) {
  x |>
    coalesce("") |>
    str_replace_all("&", "&amp;") |>
    str_replace_all("<", "&lt;") |>
    str_replace_all(">", "&gt;") |>
    str_replace_all('"', "&quot;")
}

format_date <- function(x) {
  coalesce(format(as.Date(x), "%d %b %Y"), "")
}

# An HTML table of the columns of x, headed by their names, with every cell
# escaped. Styles are inline because email apps ignore style sheets.
html_table <- function(x) {
  cell <- "border:1px solid #ccc;padding:4px 8px;text-align:left;"
  header <- str_c(
    "<th style=\"", cell, "background:#f2f2f2;\">", html_escape(names(x)),
    "</th>",
    collapse = ""
  )
  rows <- pmap_chr(map(x, html_escape), \(...) {
    str_c("<td style=\"", cell, "\">", c(...), "</td>", collapse = "")
  })
  str_c(
    "<table style=\"border-collapse:collapse;font-size:14px;\">",
    "<tr>", header, "</tr>",
    str_c("<tr>", rows, "</tr>", collapse = ""),
    "</table>"
  )
}

plural <- function(n, word, words = str_c(word, "s")) {
  str_c(n, " ", if (n == 1) word else words)
}

# Sorted by certificate in the dashboard's order, then by name.
in_dashboard_order <- function(spells) {
  arrange(
    spells,
    match(certificate, certificates$certificate),
    last_name,
    first_name
  )
}

identical_values <- function(x, y) {
  (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & x == y)
}

detail_names <- function() {
  c(
    fellow_type = "Fellowship",
    qualification_year = "Qualified",
    cera = "CERA",
    regulatory_record = "Regulatory record"
  )
}
