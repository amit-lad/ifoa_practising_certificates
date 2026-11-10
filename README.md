# ifoa_practising_certificates

A dashboard of IFoA practising certificate holders over time. Each day the [IFoA public directory](https://my.actuaries.org.uk) is searched for Fellows holding each type of practising certificate, and the snapshots are combined into one record per spell of holding a certificate. The [Quarto dashboard](https://quarto.org/docs/dashboards/) filters the data in the browser (Observable JS), so the site is fully static.

## How it runs

- **GitHub Actions updates the data.** The `update_data` workflow runs `update_data.R` daily (and on demand from the Actions tab). It scrapes the directory, rebuilds the database and commits any changes to `main`. If the scrape finds no one, the workflow fails without committing anything.
- **GitHub Actions also runs the tests.** The `tests` workflow runs them on every pull request, and on pushes that change the R code, tests or packages.
- **Netlify renders the site.** Each push to `main` triggers a Netlify build (`netlify.toml`), which installs Quarto, renders `dashboard/` and publishes `dashboard/_site/`. The dashboard has no R code, so the build needs only Quarto. The rendered site is not committed.

## Repository layout

```
update_data.R        Scrape the directory, then rebuild the database
R/                   Functions used by update_data.R
  certificates.R     The certificate types: names, labels and search values
  scrape.R           Search the directory and save a snapshot
  database.R         Combine snapshots into spells; write the outputs
data/
  raw/               One snapshot per day: raw_results_<date>.rds
  database/          certificate_database.rds (spells) and snapshot_dates.rds
dashboard/
  index.qmd          The dashboard
  dashboard_data.json  The data the dashboard loads, written by update_data.R
  netlify_build.sh   Netlify's build: install Quarto and render
tests/
  testthat.R         Run the tests
  testthat/          Tests for the spell logic and the scraper
netlify.toml         Netlify settings
.github/workflows/   update_data (daily) and tests
```

## Requirements

- **R 4.6.2** (see `renv.lock`), for updating the data and running the tests
- **Quarto 1.11.9** (the version Netlify uses; it bundles Pandoc), for rendering

R packages are managed with `renv`. The `.Rprofile` activates `renv` automatically; install the locked packages with:

```bash
Rscript -e 'renv::restore(prompt = FALSE)'
```

## Update the data

From the repository root:

```bash
Rscript update_data.R
```

This needs **network access** to `my.actuaries.org.uk`. If a search fails, it's retried and then skipped, and the snapshot is saved without those people. If every search finds no one, the script stops with an error and saves nothing, since that means the directory is down or has changed.

To rebuild the database from the existing snapshots without scraping:

```bash
Rscript update_data.R --no-scrape
```

### How the database is built

`data/database/certificate_database.rds` has one row per spell of holding a certificate, and `data/database/snapshot_dates.rds` lists the dates with a successful scrape. A certificate only counts as relinquished once it has been missing from at least 3 successful snapshots spanning more than 30 days, so partial scrapes and brief drop-outs from the directory aren't counted as changes. Days with no snapshot, including empty snapshots saved before the scrape started failing on them, are treated as missing data, not as everyone leaving.

## Render and view the site locally

```bash
quarto render dashboard
```

The page loads its data, stylesheets and scripts from files next to `index.html`, so serve the folder over HTTP rather than opening the file directly:

```bash
python3 -m http.server 8080 --directory dashboard/_site
```

Then visit `http://localhost:8080/`.

## Tests

The tests check the spell logic (when a certificate counts as held, relinquished or held again), how each certificate is recognised, and how the scraper turns API results into rows. They use made-up snapshots and don't need network access:

```bash
Rscript tests/testthat.R
```

## Failure notifications

GitHub emails you when a scheduled workflow run fails, if your notification settings allow it: in GitHub, go to **Settings → Notifications → System → Actions** and choose email notifications (optionally for failed workflows only). The emails go to whoever last changed the workflow's schedule.

## Code style

The R code follows the [tidyverse style guide](https://style.tidyverse.org/). [styler](https://styler.r-lib.org/) and [lintr](https://lintr.r-lib.org/) are development tools only, so they aren't in `renv.lock`; install them with `renv::install(c("styler", "lintr"))`. Then format and check the code with:

```bash
Rscript -e 'styler::style_dir(exclude_dirs = "renv")'
```

```bash
Rscript -e 'lintr::lint_dir()'
```

## Licence

GPL-3.0; see [LICENSE](LICENSE).
