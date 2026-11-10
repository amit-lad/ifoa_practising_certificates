# Spells for the snapshots up to and including `until`, and for all of them.
before_and_after <- function(snapshots, until) {
  list(
    old = build_spells(filter(snapshots, date <= until)),
    new = build_spells(snapshots),
    old_dates = snapshot_dates(filter(snapshots, date <= until)),
    new_dates = snapshot_dates(snapshots)
  )
}

test_that("an unchanged database has no changes", {
  spells <- build_spells(bind_rows(everyone(), person(days)))

  expect_false(has_changes(compare_databases(spells, spells)))
})

test_that("a new holder counts as gained", {
  db <- before_and_after(bind_rows(everyone(), person(days[91])), days[90])
  changes <- compare_databases(db$old, db$new)

  expect_equal(changes$gained$first_name, "Ann")
  expect_equal(nrow(changes$relinquished), 0)
  expect_equal(nrow(changes$details), 0)
})

test_that("a confirmed relinquishment counts as relinquished", {
  # Ann was last seen on day 60; the 30 days are up by day 91, not day 90.
  db <- before_and_after(bind_rows(everyone(), person(days[1:60])), days[90])
  changes <- compare_databases(db$old, db$new)

  expect_equal(changes$relinquished$first_name, "Ann")
  expect_equal(changes$relinquished$last_date, days[60])
  expect_equal(nrow(changes$gained), 0)
})

test_that("a changed detail is reported with its old and new values", {
  snapshots <- bind_rows(
    everyone(),
    person(days[1:90]),
    person(days[91], regulatory_record = "Reprimand (2026)")
  )
  db <- before_and_after(snapshots, days[90])
  changes <- compare_databases(db$old, db$new)

  expect_equal(changes$details$detail, "regulatory_record")
  expect_equal(changes$details$old, "FALSE")
  expect_equal(changes$details$new, "TRUE")
})

test_that("the email lists each kind of change", {
  snapshots <- bind_rows(
    everyone(),
    person(days[91], first_name = "Cat"),
    person(days[1:60]),
    person(days[1:90], first_name = "Dan"),
    person(days[91], first_name = "Dan", regulatory_record = "Reprimand")
  )
  db <- before_and_after(snapshots, days[90])
  email <- change_email(
    compare_databases(db$old, db$new),
    db$old_dates,
    db$new_dates
  )

  expect_equal(
    email$subject,
    "IFoA practising certificates: 1 gained, 1 relinquished, 1 other change"
  )

  # The text of each table row, without the inline styles.
  cells <- email$html |>
    str_extract_all("<tr>.*?</tr>") |>
    pluck(1) |>
    str_remove_all("<[^>]+>")
  expect_contains(
    cells,
    c(
      "NameCertificateFirst seen",
      "Cat SmithScheme31 Mar 2024",
      "Ann SmithScheme29 Feb 2024",
      "Dan SmithSchemeRegulatory record: no to yes"
    )
  )
  expect_no_match(email$html, "Current certificates")
  expect_match(
    email$html,
    "on 31 Mar 2024, since the last successful scrape on 30 Mar 2024"
  )
  expect_match(email$html, dashboard_url, fixed = TRUE)
})

test_that("there's no email when nothing changed", {
  spells <- build_spells(bind_rows(everyone(), person(days)))
  changes <- compare_databases(spells, spells)

  expect_null(change_email(changes, days, days))
})

test_that("writing no email removes an old one", {
  dir <- withr::local_tempdir()
  write_change_email(list(subject = "Old", html = "<p>Old</p>"), dir)
  expect_true(file.exists(file.path(dir, "email.html")))

  expect_false(write_change_email(NULL, dir))
  expect_false(file.exists(file.path(dir, "email.html")))
  expect_false(file.exists(file.path(dir, "subject.txt")))
})

test_that("names are escaped in the email", {
  table <- html_table(tibble(Name = "Ann <b>Smith</b> & Co"))

  expect_match(table, "Ann &lt;b&gt;Smith&lt;/b&gt; &amp; Co", fixed = TRUE)
})

test_that("there's no previous database to compare on a first run", {
  expect_null(read_database(withr::local_tempdir()))
})
