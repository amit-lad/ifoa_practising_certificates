#!/usr/bin/env bash
# Netlify build: install Quarto and render the dashboard to dashboard/_site/.
# The page has no R code (it loads dashboard_data.json), so only Quarto is
# needed. Run from the repository root.
set -euo pipefail

# Pinned so the site only changes when the dashboard changes. Check the
# dashboard (every page, and opening and closing the sidebar) when upgrading.
QUARTO_VERSION=1.11.9
QUARTO_DIR="$PWD/.quarto-dist"

if [ ! -x "$QUARTO_DIR/quarto-$QUARTO_VERSION/bin/quarto" ]; then
  mkdir -p "$QUARTO_DIR"
  curl -fsSL "https://github.com/quarto-dev/quarto-cli/releases/download/v$QUARTO_VERSION/quarto-$QUARTO_VERSION-linux-amd64.tar.gz" \
    | tar -xz -C "$QUARTO_DIR"
fi

"$QUARTO_DIR/quarto-$QUARTO_VERSION/bin/quarto" render dashboard
