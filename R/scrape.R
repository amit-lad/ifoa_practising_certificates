# Scrape the IFoA public directory for Fellows holding each practising
# certificate.

# The public directory is served by a Silverbear FetchXML JSON API.
api_url <- str_c(
  "https://my.actuaries.org.uk/DesktopModules/SilverbearCrm/",
  "FetchXMLSearch/Data/searchform.asmx/Send"
)

# Column names match the historic directory table, so every snapshot in
# data/raw/ has the same columns.
empty_snapshot <- tibble(
  `First name` = character(),
  Surname = character(),
  Status = character(),
  `Practising certificate type` = character(),
  `Regulatory record` = character()
)

#' Search the directory for every certificate type
#'
#' @param date Date to record against the results.
#' @returns One row per person and certificate list found. Searches that fail
#'   return no rows, so one failure doesn't stop the scrape;
#'   `build_spells()` allows for snapshots with missing people.
scrape_directory <- function(date = Sys.Date()) {
  # The API caps results per search, so split each search by first name.
  first_name_ranges <- c(
    "[A-C]", "[D-F]", "[G-J]", "[K-N]", "[O-R]", "[S-V]", "[W-Z]"
  )
  searches <- expand_grid(
    form_option = certificates$form_option,
    first_name_range = first_name_ranges
  )

  map2(searches$first_name_range, searches$form_option, search_directory) |>
    list_rbind(ptype = empty_snapshot) |>
    distinct() |>
    mutate(date = date)
}

#' Save a snapshot as `<dir>/raw_results_<date>.rds`
save_snapshot <- function(snapshot, date, dir = "data/raw") {
  write_rds(
    snapshot,
    file.path(dir, str_glue("raw_results_{date}.rds")),
    compress = "none",
    text = TRUE
  )
}

search_directory <- function(first_name_range, form_option) {
  response <- tryCatch(
    request(api_url) |>
      req_body_json(search_body(first_name_range, form_option)) |>
      req_headers(Accept = "application/json") |>
      req_user_agent("ifoa_practising_certificates (R httr2)") |>
      req_retry(max_tries = 3) |>
      req_perform(),
    error = \(e) NULL
  )
  if (is.null(response)) {
    return(empty_snapshot)
  }

  body <- tryCatch(
    resp_body_json(response, check_type = FALSE),
    error = \(e) NULL
  )
  results <- body$d$Results
  if (!isTRUE(body$d$Success) || !is.list(results) || length(results) == 0) {
    return(empty_snapshot)
  }

  results |>
    map(result_to_row) |>
    list_rbind()
}

search_body <- function(first_name_range, form_option) {
  token <- function(name, value) {
    list(token = str_glue("[token:{name}]"), value = value)
  }

  list(
    alltokens = list(
      token("firstname", first_name_range),
      token("lastname", ""),
      # Picklist code for "Fellow".
      token("sbifoa_subsetmembershiptype", "200000004"),
      token("sbifoa_concatenatedpractisingcertificatetypes", form_option)
    ),
    tabmoduleId = 404L,
    portalId = 0L,
    currentUserId = -1L,
    recaptchaResponse = "",
    fetchCount = 200L,
    pageNumber = 1L,
    numPages = 2L,
    locationSearch = FALSE,
    surnameSearch = FALSE,
    lastnameFieldExists = TRUE,
    # The server rejects JSON null here (HTTP 500); an empty string matches
    # what the browser sends.
    entityId = ""
  )
}

result_to_row <- function(result) {
  if (!is.list(result)) {
    return(empty_snapshot)
  }

  tibble(
    # The historic table's first column held forenames: first plus middle.
    `First name` = str_squish(
      str_c(as_text(result$firstname), " ", as_text(result$middlename))
    ),
    Surname = as_text(result$lastname),
    Status = str_c(
      as_text(result$sbifoa_subsetmembershiptype),
      as_text(result$sb_postnominal),
      as_text(result$ifoa_calculateddatejoined),
      sep = " "
    ),
    `Practising certificate type` = as_text(
      result$sbifoa_concatenatedpractisingcertificatetypes
    ),
    `Regulatory record` = as_text(result$sbifoa_concatenateddisciplinaries)
  )
}

# Missing fields come back as NULL or NA; treat both as empty text.
as_text <- function(x) {
  if (is.null(x) || (length(x) == 1 && is.na(x))) {
    return("")
  }
  as.character(x)
}
