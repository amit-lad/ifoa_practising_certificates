# ifoa_practising_certificates

Practising certificate dashboard: scrapes the IFoA public directory, builds a database, and renders a [Quarto dashboard](https://quarto.org/docs/dashboards/) site. Filters in the sidebar run in the browser (Observable JS), so the site is fully static.

The work is split in two:

- **GitHub Actions updates the data.** R scrapes the directory and builds the database, then commits `data_raw/` and `database/` to `main`.
- **Netlify renders the site.** Each push to `main` triggers a Netlify build (see `netlify.toml` and `netlify_build.sh`) that runs `quarto render` and publishes `_site/`. The dashboard has no R code, it loads `database/dashboard_data.json` in the browser, so the build needs only Quarto. `_site/` is not committed.

## Requirements

- **R 4.4.3** (see `renv.lock`), for the data pipeline
- **Quarto 1.4.549** (the version Netlify uses; it bundles Pandoc), for rendering

R packages are managed with `renv`. The `.Rprofile` activates `renv` automatically; install the locked dependencies with:

```bash
Rscript -e 'renv::restore(prompt = FALSE)'
```

## Update the data

From the repository root, scrape the directory and rebuild the database:

```bash
Rscript update_data.R
```

The scrape step needs **network access** (outbound HTTPS to `my.actuaries.org.uk`). Without it, the scrape returns no new rows, but the database is still rebuilt from the existing `data_raw/*.rds` snapshots.

To run only one step:

```bash
Rscript scrape_data.R
```

```bash
Rscript build_database.R
```

`build_database.R` writes `database/certificate_database.rds` (one row per spell of holding a certificate), `database/snapshot_dates.rds` (dates with a successful scrape) and `database/dashboard_data.json` (the same data prepared for the dashboard). A certificate only counts as relinquished once it has been missing from at least 3 successful snapshots spanning more than 30 days, so partial scrapes and brief drop-outs from the directory aren't counted as changes.

## Render and view the site locally

```bash
quarto render ifoa_practising_certificates.qmd --output-dir _site
```

The page loads its data, stylesheets and scripts from files next to `index.html`, so serve the folder over HTTP rather than opening the file directly:

```bash
cd _site && python3 -m http.server 8080
```

Then visit `http://localhost:8080/index.html`.

## Automated updates

The `automated_updates` GitHub Actions workflow updates the data daily on an `ubuntu-24.04` runner and commits it to `main` only when something changed; Netlify then rebuilds the site. The `manual_updates` workflow does the same on demand.
