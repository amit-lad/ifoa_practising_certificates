test_that("an API result becomes a row like the historic directory table", {
  result <- list(
    firstname = "Ann",
    middlename = "Marie",
    lastname = "Smith",
    sbifoa_subsetmembershiptype = "Fellow",
    sb_postnominal = "FIA",
    ifoa_calculateddatejoined = "2001",
    sbifoa_concatenatedpractisingcertificatetypes = "Scheme Actuary",
    sbifoa_concatenateddisciplinaries = NULL
  )
  row <- result_to_row(result)

  expect_named(row, names(empty_snapshot))
  expect_equal(row$`First name`, "Ann Marie")
  expect_equal(row$Surname, "Smith")
  expect_equal(row$Status, "Fellow FIA 2001")
  expect_equal(row$`Practising certificate type`, "Scheme Actuary")
  expect_equal(row$`Regulatory record`, "")
})

test_that("missing names don't leave stray spaces", {
  row <- result_to_row(list(firstname = "Ann", middlename = NA))

  expect_equal(row$`First name`, "Ann")
})

test_that("a result that isn't a record gives no rows", {
  expect_equal(nrow(result_to_row("not a record")), 0)
})

test_that("the search uses the form's values for each certificate", {
  body <- search_body("[A-C]", "With-Profits Actuary")
  tokens <- set_names(
    map_chr(body$alltokens, "value"),
    map_chr(body$alltokens, "token")
  )

  expect_equal(tokens[["[token:firstname]"]], "[A-C]")
  expect_equal(
    tokens[["[token:sbifoa_concatenatedpractisingcertificatetypes]"]],
    "With-Profits Actuary"
  )
  expect_equal(body$entityId, "")
})

test_that("every certificate has a search value", {
  expect_false(anyNA(certificates$form_option))
  expect_true("With-Profits Actuary" %in% certificates$form_option)
})
