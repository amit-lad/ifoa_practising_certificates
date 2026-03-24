library(tidyverse)
library(httr)
library(readr)
library(purrr)

# Public directory moved to my.actuaries.org.uk (Silverbear FetchXML JSON API).
send_url <- "https://my.actuaries.org.uk/DesktopModules/SilverbearCrm/FetchXMLSearch/Data/searchform.asmx/Send"
tabmodule_id <- 404L
# Picklist code for "Fellow" from Load response (sbifoa_subsetmembershiptype).
fellow_picklist_code <- "200000004"

# Legacy short codes kept for traceability; values must match <option value="..."> on the live form.
pc_types <- tibble(
  pc_types_short = c("CAL", "CLND", "CANL", "CAN", "SYND", "WPAC", "SCHE"),
  practising_cert_option = c(
    "Chief Actuary (Life)",
    "Chief Actuary (Life, Non-Directive)",
    "Chief Actuary (non-Life without Lloyd's)",
    "Chief Actuary (non-Life with Lloyd's)",
    "Lloyd's Syndicate Actuary",
    "With-Profits Actuary",
    "Scheme Actuary"
  )
)

firstname_search <- tibble(firstname_search = c("[A-C]", "[D-F]", "[G-J]", "[K-N]", "[O-R]", "[S-V]", "[W-Z]"))

search_matrix <- pc_types |> cross_join(firstname_search)

nv <- function(x, default = "") {
  if (is.null(x)) {
    return(default)
  }
  if (length(x) == 1L && is.na(x)) {
    return(default)
  }
  as.character(x)
}

# Match historic Drupal table: first column was forename(s), i.e. first + middle when present.
forename_display <- function(first, middle) {
  str_squish(paste(nv(first), nv(middle)))
}

build_send_body <- function(forename_range, practising_cert_value) {
  list(
    alltokens = list(
      list(token = "[token:firstname]", value = forename_range),
      list(token = "[token:lastname]", value = ""),
      list(token = "[token:sbifoa_subsetmembershiptype]", value = fellow_picklist_code),
      list(token = "[token:sbifoa_concatenatedpractisingcertificatetypes]", value = practising_cert_value)
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
    # Server rejects JSON null for this parameter (HTTP 500); empty string matches browser behaviour.
    entityId = ""
  )
}

api_results_to_tibble <- function(items) {
  empty <- tibble(
    "First name" = character(),
    Surname = character(),
    Status = character(),
    "Practising certificate type" = character(),
    "Regulatory record" = character()
  )
  if (length(items) == 0L) {
    return(empty)
  }
  map_dfr(items, function(row) {
    if (!is.list(row)) {
      return(empty[0, , drop = FALSE])
    }
    status_txt <- paste(
      nv(row$sbifoa_subsetmembershiptype),
      nv(row$sb_postnominal),
      nv(row$ifoa_calculateddatejoined),
      sep = " "
    )
    tibble(
      "First name" = forename_display(row$firstname, row$middlename),
      Surname = nv(row$lastname),
      Status = status_txt,
      "Practising certificate type" = nv(row$sbifoa_concatenatedpractisingcertificatetypes),
      "Regulatory record" = nv(row$sbifoa_concatenateddisciplinaries)
    )
  })
}

query_ifoa_api <- function(forename_range, practising_cert_value) {
  body <- build_send_body(forename_range, practising_cert_value)
  resp <- tryCatch(
    POST(
      send_url,
      body = body,
      encode = "json",
      accept_json(),
      content_type_json(),
      user_agent("ifoa_practising_certificates / R httr")
    ),
    error = function(e) NULL
  )

  if (is.null(resp) || status_code(resp) != 200L) {
    return(api_results_to_tibble(list()))
  }

  parsed <- tryCatch(content(resp, as = "parsed", type = "application/json"), error = function(e) NULL)
  if (is.null(parsed) || is.null(parsed$d) || !isTRUE(parsed$d$Success)) {
    return(api_results_to_tibble(list()))
  }

  items <- parsed$d$Results
  if (is.null(items) || !is.list(items)) {
    return(api_results_to_tibble(list()))
  }

  api_results_to_tibble(items)
}

results_raw <- search_matrix |>
  pmap(function(pc_types_short, practising_cert_option, firstname_search) {
    query_ifoa_api(firstname_search, practising_cert_option)
  }) |>
  bind_rows() |>
  unique() |>
  mutate(date = Sys.Date())

write_rds(
  x = results_raw,
  file = paste0("data_raw/raw_results_", Sys.Date(), ".rds"),
  compress = "none",
  text = TRUE
)
