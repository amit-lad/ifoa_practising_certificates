# Spells ---------------------------------------------------------------------

test_that("a holder seen in every snapshot has one current spell", {
  spells <- build_spells(everyone())

  expect_equal(nrow(spells), 1)
  expect_equal(spells$first_date, days[1])
  expect_equal(spells$last_date, days[91])
  expect_true(spells$current)
  expect_true(is.na(spells$joined_after))
  expect_true(is.na(spells$left_before))
})

test_that("a long absence ends a spell and a return starts a new one", {
  spells <- ann_spells(person(days[c(1:20, 71:91)]))

  expect_equal(nrow(spells), 2)
  expect_equal(spells$last_date[1], days[20])
  expect_equal(spells$left_before[1], days[21])
  expect_false(spells$current[1])
  expect_equal(spells$first_date[2], days[71])
  expect_equal(spells$joined_after[2], days[70])
  expect_true(spells$current[2])
})

test_that("a short absence doesn't end a spell", {
  # Missing from 10 snapshots over 10 days: too few days.
  spells <- ann_spells(person(days[-(30:39)]))

  expect_equal(nrow(spells), 1)
  expect_equal(spells$first_date, days[1])
  expect_equal(spells$last_date, days[91])
})

test_that("an absence over few snapshots doesn't end a spell", {
  # Monthly snapshots. Missing from 2 snapshots over 3 months: too few
  # snapshots, however many days.
  months <- seq(as.Date("2024-01-01"), by = "month", length.out = 12)
  spells <-
    bind_rows(everyone(months), person(months[-(5:6)])) |>
    build_spells() |>
    filter(first_name == "Ann")

  expect_equal(nrow(spells), 1)
})

test_that("both thresholds are needed to end a spell", {
  # Missing from exactly 3 snapshots, seen 4 months apart: lapses.
  months <- seq(as.Date("2024-01-01"), by = "month", length.out = 12)
  lapsed <-
    bind_rows(everyone(months), person(months[-(5:7)])) |>
    build_spells() |>
    filter(first_name == "Ann")
  expect_equal(nrow(lapsed), 2)

  # Missing from 29 daily snapshots, seen 30 days apart: not enough days.
  kept <- ann_spells(person(days[-(31:59)]))
  expect_equal(nrow(kept), 1)

  # Missing from 30 daily snapshots, seen 31 days apart: lapses.
  ended <- ann_spells(person(days[-(31:60)]))
  expect_equal(nrow(ended), 2)
})

test_that("a recent absence isn't yet counted as leaving", {
  spells <- ann_spells(person(days[1:80]))

  expect_true(spells$current)
  expect_true(is.na(spells$left_before))
})

test_that("a long-finished spell records when the holder left", {
  spells <- ann_spells(person(days[1:40]))

  expect_false(spells$current)
  expect_equal(spells$last_date, days[40])
  expect_equal(spells$left_before, days[41])
})

test_that("joined_after is the snapshot before the first appearance", {
  spells <- ann_spells(person(days[10:91]))

  expect_equal(spells$first_date, days[10])
  expect_equal(spells$joined_after, days[9])
})

test_that("days with no data aren't treated as everyone leaving", {
  # Nobody appears from day 30 to day 70, eg because the site was down.
  outage <- days[-(30:70)]
  spells <- build_spells(bind_rows(everyone(outage), person(outage)))

  expect_equal(nrow(spells), 2)
  expect_true(all(spells$current))
})

# Certificates and details ---------------------------------------------------

test_that("each certificate a person holds gets its own spell", {
  spells <- ann_spells(
    person(days, certificate_types = "Scheme Actuary, Chief Actuary (Life)")
  )

  expect_setequal(
    spells$certificate,
    c("Scheme Actuary", "Chief Actuary (Life)")
  )
})

test_that("With-Profits matches with or without the hyphen", {
  hyphen <- ann_spells(
    person(days, certificate_types = "With-Profits Actuary")
  )
  space <- ann_spells(
    person(days, certificate_types = "With Profits Actuary")
  )

  expect_equal(hyphen$certificate, "With Profits Actuary")
  expect_equal(space$certificate, "With Profits Actuary")
})

test_that("Chief Actuary (Life) doesn't match the Non-Directive certificate", {
  spells <- ann_spells(
    person(days, certificate_types = "Chief Actuary (Life, Non-Directive)")
  )

  expect_equal(spells$certificate, "Chief Actuary (Life, Non-Directive)")
})

test_that("anyone ever shown as CERA counts as CERA", {
  spells <- ann_spells(
    person(days[1:10], status = "Fellow FIA CERA 2001"),
    person(days[11:91])
  )

  expect_true(spells$cera)
})

test_that("details come from the latest snapshot in a spell", {
  spells <- ann_spells(
    person(days[1:50], status = "Fellow FIA 2001"),
    person(days[51:91], status = "Fellow FFA 2003")
  )

  expect_equal(spells$fellow_type, "Fellow FFA")
  expect_equal(spells$qualification_year, 2003L)
})

test_that("a regulatory record is flagged only when there is one", {
  none <- ann_spells(person(days))
  record <- ann_spells(person(days, regulatory_record = "Reprimand (2020)"))

  expect_false(none$regulatory_record)
  expect_true(record$regulatory_record)
})

# Dashboard data -------------------------------------------------------------

test_that("the dashboard data uses short labels, and nulls for no date", {
  snapshots <- bind_rows(everyone(), person(days[1:40]))
  path <- withr::local_tempfile(fileext = ".json")
  write_dashboard_data(build_spells(snapshots), snapshot_dates(snapshots), path)
  data <- jsonlite::read_json(path)

  expect_equal(unlist(data$certs), certificates$label)
  expect_equal(length(data$snapshot_dates), 91)

  ann <- detect(data$spells, \(d) d$first_name == "Ann")
  expect_equal(ann$certificate, "Scheme")
  expect_equal(ann$fellow, "FIA")
  expect_null(ann$joined_after)
  expect_equal(ann$left_before, "2024-02-10")
})
