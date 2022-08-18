library(tidyverse)
library(purrr)

# Read in the raw scraped data
raw_data_files <- list.files(path = "data_raw", pattern = "*.rds$", full.names = TRUE)
raw_data <- raw_data_files %>% map_df(read_rds) 

# Create PC type 
PC_types = tibble(
  certificate_regex = c("Chief Actuary \\(Life\\)", "With Profits Actuary", "Chief Actuary \\(Life, Non-Directive\\)", "Chief Actuary \\(non-Life without Lloyd's\\)", "Chief Actuary \\(non-Life with Lloyd's\\)", "Lloyd's Syndicate Actuary", "Scheme Actuary"),
  certificate = c("Chief Actuary (Life)", "With Profits Actuary", "Chief Actuary (Life, Non-Directive)", "Chief Actuary (non-Life without Lloyd's)", "Chief Actuary (non-Life with Lloyd's)", "Lloyd's Syndicate Actuary", "Scheme Actuary")
  )

# Clean data
cleaned_data_full_list <-
  raw_data %>%
  # Convert so there is one row for each PC type that a person has.
  full_join(PC_types, by = character()) %>%
  mutate(
    `Practising certificate type` = str_squish(`Practising certificate type`),
    PC_present = str_detect(string = `Practising certificate type`, pattern = certificate_regex)
  ) %>%
  filter(PC_present == TRUE) %>%
  # Capture key characteristics of each person
  replace_na(list(`Regulatory record` = "")) %>%
  mutate(
    fellow_type = str_extract(Status, "^[:alpha:]+[:space:][:alpha:]+"),
    qualification_year = as.integer(str_extract(Status, "[:digit:]{4}")),
    cera = str_detect(Status, "CERA"),
    regulatory_record = str_detect(`Regulatory record`, "[:alpha:]+")
  ) %>%
  # Keep selected fields.
  select(`First name`, Surname, date, certificate, fellow_type, qualification_year, cera, regulatory_record) %>%
  unique()
  
# Only want one record per person/ PC type.  Capture when the PC was issued/ rescinded.
# Some details (eg CERA) may change whilst having a PC certificate - only capture status on last record.
cleaned_data_start_end_dates <-
  cleaned_data_full_list %>%
  group_by(`First name`, Surname, certificate) %>%
  summarise(first_date = min(date), last_date = max(date), .groups = "drop") %>%
  left_join(cleaned_data_full_list, by = c("First name", "Surname", "certificate", "last_date" = "date")) %>%
  rename("first_name" = `First name`, "last_name" = Surname)

# Write outputs of raw data
write_rds(
  x = cleaned_data_start_end_dates,
  file = paste0("database/certificate_database.rds"),
  compress = "none",
  text = TRUE
)
