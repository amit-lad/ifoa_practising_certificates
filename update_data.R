# Update the data: scrape today's snapshot, then rebuild the database.
# Run daily by GitHub Actions; Netlify renders the dashboard from the result.

message("Scraping the IFoA directory")
source("scrape_data.R")

message("Building the database")
source("build_database.R")
