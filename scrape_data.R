# Scrape the IFoA public directory for Fellows holding each practising
# certificate, and save today's snapshot to data_raw/.

library(tidyverse)
library(httr2)

# The public directory is served by a Silverbear FetchXML JSON API.
api_url <- str_c(
  "https://my.actuaries.org.uk/DesktopModules/SilverbearCrm/",
  "FetchXMLSearch/Data/searchform.asmx/Send"
)
tabmodule_id <- 404L
# Picklist code for "Fellow" (sbifoa_subsetmembershiptype).
fellow_code <- "200000004"

# Values must match the <option value="..."> entries on the live search form.
certificate_options <- c(
  "Chief Actuary (Life)",
  "Chief Actuary (Life, Non-Directive)",
  "Chief Actuary (non-Life without Lloyd's)",
  "Chief Actuary (non-Life with Lloyd's)",
  "Lloyd's Syndicate Actuary",
  "With-Profits Actuary",
  "Scheme Actuary"
)

# The API caps results per search, so split each search by first name.
first_name_ranges <- c(
  "[A-C]", "[D-F]", "[G-J]", "[K-N]", "[O-R]", "[S-V]", "[W-Z]"
)

searches <- expand_grid(
  certificate = certificate_options,
  first_name_range = first_name_ranges
)

# Column names match the historic directory table, so every snapshot in
# data_raw/ has the same columns.
empty_results <- tibble(
  `First name` = character(),
  Surname = character(),
  Status = character(),
  `Practising certificate type` = character(),
  `Regulatory record` = character()
)

# Missing fields come back as NULL or NA; treat both as empty text.
as_text <- function(x) {
  if (is.null(x) || (length(x) == 1 && is.na(x))) {
    return("")
  }
  as.character(x)
}

search_body <- function(first_name_range, certificate) {
  token <- function(name, value) {
    list(token = str_glue("[token:{name}]"), value = value)
  }

  list(
    alltokens = list(
      token("firstname", first_name_range),
      token("lastname", ""),
      token("sbifoa_subsetmembershiptype", fellow_code),
      token("sbifoa_concatenatedpractisingcertificatetypes", certificate)
    ),
    tabmoduleId = tabmodule_id,
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
    return(empty_results)
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

# Returns no rows if the search fails, so one failed search doesn't stop the
# scrape. build_database.R allows for snapshots with missing people.
search_directory <- function(first_name_range, certificate) {
  response <- tryCatch(
    request(api_url) |>
      req_body_json(search_body(first_name_range, certificate)) |>
      req_headers(Accept = "application/json") |>
      req_user_agent("ifoa_practising_certificates (R httr2)") |>
      req_retry(max_tries = 3) |>
      req_perform(),
    error = \(e) NULL
  )
  if (is.null(response)) {
    return(empty_results)
  }

  body <- tryCatch(
    resp_body_json(response, check_type = FALSE),
    error = \(e) NULL
  )
  results <- body$d$Results
  if (!isTRUE(body$d$Success) || !is.list(results) || length(results) == 0) {
    return(empty_results)
  }

  results |>
    map(result_to_row) |>
    list_rbind()
}

scrape_date <- Sys.Date()

snapshot <-
  map2(searches$first_name_range, searches$certificate, search_directory) |>
  list_rbind(ptype = empty_results) |>
  distinct() |>
  mutate(date = scrape_date)

write_rds(
  snapshot,
  str_glue("data_raw/raw_results_{scrape_date}.rds"),
  compress = "none",
  text = TRUE
)
