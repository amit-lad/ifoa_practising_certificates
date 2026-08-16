# AGENTS.md

## Cursor Cloud specific instructions

This repo is the **IFoA Practising Certificates dashboard** — an R batch pipeline (no long-running backend). It scrapes the IFoA public directory, builds an RDS database, and renders a static `flexdashboard` to `_site/index.html`. There is no server to keep running; the product is the rendered static site.

### Runtime / deps
- Uses **R 4.4.3** (installed via `rig`, on `PATH` as `R`/`Rscript`) and **Pandoc** (apt). R packages are managed by `renv` (`renv.lock`); the startup update script runs `renv::restore()`.
- The `.Rprofile` auto-activates `renv` on every R session, so `Rscript` picks up the project library automatically. If you hit "package not installed" errors, run `Rscript -e 'renv::restore(prompt = FALSE)'`.

### Run / build (see `README.md` and `Dockerfile` for the canonical commands)
- Full pipeline: `Rscript build_dashboard_github_actions.R` (scrape → `build_database.R` → render `ifoa_practising_certificates.Rmd` to `_site/index.html`).
- Run stages individually with `Rscript scrape_data.R` / `Rscript build_database.R` if needed.
- View the dashboard: `cd _site && python3 -m http.server 8080`, then open `http://localhost:8080/index.html`.

### Non-obvious caveats
- The **scrape** stage requires outbound HTTPS to `my.actuaries.org.uk`. It fails soft (returns empty tibbles) if the API is unreachable, so the pipeline won't crash offline — but it also won't add new rows that day.
- Even without network, stages 2–3 work against the ~772 existing `data_raw/*.rds` snapshots, so you can rebuild the DB and re-render the dashboard offline.
- Running the pipeline **regenerates tracked outputs** (`_site/index.html`, `database/certificate_database.rds`, and a dated `data_raw/raw_results_<date>.rds`). CI commits these daily; do not commit these regenerated artifacts in unrelated PRs unless the change is intentional.
- There is no separate lint/test suite; correctness is validated by successfully running the pipeline and confirming the dashboard renders and is interactive.
