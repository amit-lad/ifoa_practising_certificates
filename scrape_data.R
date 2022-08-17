library(tidyverse)
library(rvest)
library(magrittr)
library(httr)
library(readr)

# Definitions and global variables
url_directory <- "https://www.actuaries.org.uk/actuarial-directory/public-search"
pc_types_short <- c("CAL", "CLND", "CANL", "CAN", "SYND", "WPAC")


# Functions
build_form_query <- function(pc_type, form_id_session) {
  list(forename = "", surname = "", member_status = "FELLOW", 
       practising_cert_type = pc_type, op = "Search members", 
       form_build_id = form_id_session, 
       form_id = "apactuarialdirectory_public_search_form")
}

query_ifoa_website <- function(form_query) {
  POST(url_directory, body = form_query, encode = "form") %>%
    read_html() %>% html_node("table") %>% html_table()
}

# Extract an HTML Node that has the form_id_tag in it
form_id_session <- 
  GET(url_directory) %>%
  read_html() %>%
  html_nodes("input") %>%
  extract2(13) 

# Build vector of queries
form_queries <- lapply(pc_types_short, build_form_query, form_id_session = form_id_session)

# Build vector of people
results_raw <- 
  lapply(form_queries, query_ifoa_website) %>% 
  bind_rows() %>%
  unique() %>%
  mutate(date = Sys.Date())
  
# Write outputs of raw data
write_rds(
  x = results_raw,
  file = paste0("data_raw/raw_results_", Sys.Date(), ".rds"),
  compress = "none",
  text = TRUE
)
