# ifoa_practising_certificates

Practising certificate dashboard: scrapes the IFoA public directory, builds an RDS database, and renders a [Quarto dashboard](https://quarto.org/docs/dashboards/) site. Filters in the sidebar run in the browser (Observable JS), so the site is fully static.

## Requirements

- **R 4.4.3** (see `renv.lock`)
- **Quarto 1.4.549** (the version CI uses; it bundles Pandoc)

R packages are managed with `renv`. The `.Rprofile` activates `renv` automatically; install the locked dependencies with:

```bash
Rscript -e 'renv::restore(prompt = FALSE)'
```

## Run the pipeline

From the repository root, run the full pipeline (scrape → `build_database.R` → render `ifoa_practising_certificates.qmd` to `_site/index.html`):

```bash
Rscript build_dashboard_github_actions.R
```

The scrape step needs **network access** (outbound HTTPS to `my.actuaries.org.uk`). Without it, the scrape returns no new rows, but the database and dashboard are still rebuilt from the existing `data_raw/*.rds` snapshots.

To run only part of the pipeline:

```bash
Rscript scrape_data.R
```

```bash
Rscript build_database.R
```

```bash
quarto render ifoa_practising_certificates.qmd --output-dir _site
```

`build_database.R` writes `database/certificate_database.rds` (one row per spell of holding a certificate) and `database/snapshot_dates.rds` (dates with a successful scrape). A certificate only counts as relinquished once it has been missing from at least 3 successful snapshots spanning more than 30 days, so partial scrapes and brief drop-outs from the directory aren't counted as changes.

## View the site locally

The rendered page is self-contained. Open `_site/index.html` in a browser, or serve the folder over HTTP:

```bash
cd _site && python3 -m http.server 8080
```

Then visit `http://localhost:8080/index.html`.

## Automated updates

The `automated_updates` GitHub Actions workflow runs the pipeline daily on an `ubuntu-24.04` runner and commits the refreshed data, database and site to `main`. The `manual_updates` workflow does the same on demand.
