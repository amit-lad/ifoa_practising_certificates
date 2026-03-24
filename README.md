# ifoa_practising_certificates

Practising certificate dashboard: scrapes the IFoA public directory, builds an RDS database, and renders a [flexdashboard](https://rmarkdown.rstudio.com/flexdashboard/) site.

## Docker

The image uses **R 4.4.3** (see `renv.lock`), **Pandoc**, and `renv::restore()` for dependencies. The default command runs `build_dashboard_github_actions.R` (scrape → `build_database.R` → render `ifoa_practising_certificates.Rmd` to `_site/index.html`).

### Build the image

From the repository root:

```bash
docker build -t ifoa-dashboard .
```

### Run the full pipeline

Mount `data_raw`, `database`, and `_site` so outputs persist on your machine. The scrape step needs **network access** (outbound HTTPS).

```bash
docker run --rm \
  -v "$(pwd)/data_raw:/app/data_raw" \
  -v "$(pwd)/database:/app/database" \
  -v "$(pwd)/_site:/app/_site" \
  ifoa-dashboard
```

To use **your current** R scripts and Rmd without rebuilding the image (recommended while developing), mount them over `/app`:

```bash
docker run --rm \
  -v "$(pwd)/scrape_data.R:/app/scrape_data.R" \
  -v "$(pwd)/build_database.R:/app/build_database.R" \
  -v "$(pwd)/build_dashboard_github_actions.R:/app/build_dashboard_github_actions.R" \
  -v "$(pwd)/ifoa_practising_certificates.Rmd:/app/ifoa_practising_certificates.Rmd" \
  -v "$(pwd)/data_raw:/app/data_raw" \
  -v "$(pwd)/database:/app/database" \
  -v "$(pwd)/_site:/app/_site" \
  ifoa-dashboard
```

### View the site locally

After a successful run, open the generated HTML in a browser (paths shown for a typical clone location; adjust to your machine):

`file:///path/to/ifoa_practising_certificates/_site/index.html`

Or serve the folder and use HTTP, for example:

```bash
cd _site && python3 -m http.server 8080
```

Then visit `http://localhost:8080/index.html`.

### Run only part of the pipeline

Override the command, for example scrape only:

```bash
docker run --rm \
  -v "$(pwd)/scrape_data.R:/app/scrape_data.R" \
  -v "$(pwd)/data_raw:/app/data_raw" \
  ifoa-dashboard Rscript scrape_data.R
```
