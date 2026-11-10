#!/usr/bin/env bash
# Netlify build: install Quarto and render the dashboard to _site/.
# The page has no R code (it loads database/dashboard_data.json), so only Quarto is needed.
set -euo pipefail

# Pinned: the dashboard works around OJS quirks in this version.
QUARTO_VERSION=1.4.549
QUARTO_DIR="$PWD/.quarto-dist"

if [ ! -x "$QUARTO_DIR/quarto-$QUARTO_VERSION/bin/quarto" ]; then
  mkdir -p "$QUARTO_DIR"
  curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v$QUARTO_VERSION/quarto-$QUARTO_VERSION-linux-amd64.tar.gz" \
    | tar -xz -C "$QUARTO_DIR"
fi

"$QUARTO_DIR/quarto-$QUARTO_VERSION/bin/quarto" render ifoa_practising_certificates.qmd --output-dir _site
