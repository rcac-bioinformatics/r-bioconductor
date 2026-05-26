#!/usr/bin/env bash
##############################################################################
# detect_versions.sh — Query current upstream versions
#
# Helps maintainers determine the latest available versions of:
#   - Bioconductor (release and devel)
#   - R (current release)
#   - RStudio Desktop (latest stable)
#   - rocker/r-ver (available tags)
#
# Usage:
#   ./scripts/detect_versions.sh
#
# This script requires internet access and curl/wget.
##############################################################################
set -euo pipefail

echo "============================================================"
echo "Upstream Version Detection"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Current VERSION file
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_DIR}/VERSION" ]]; then
    echo "--- Current VERSION file ---"
    cat "${REPO_DIR}/VERSION"
    echo ""
fi

# ---------------------------------------------------------------------------
# Bioconductor version
# ---------------------------------------------------------------------------
echo "--- Bioconductor ---"
if command -v curl &>/dev/null; then
    BIOC_RELEASE=$(curl -sL "https://bioconductor.org/config.yaml" | grep "^release_version:" | awk '{print $2}' || echo "unknown")
    BIOC_DEVEL=$(curl -sL "https://bioconductor.org/config.yaml" | grep "^devel_version:" | awk '{print $2}' || echo "unknown")
    echo "  Release: ${BIOC_RELEASE}"
    echo "  Devel:   ${BIOC_DEVEL}"
else
    echo "  (curl not available — cannot query)"
fi
echo ""

# ---------------------------------------------------------------------------
# R version
# ---------------------------------------------------------------------------
echo "--- R ---"
if command -v curl &>/dev/null; then
    R_LATEST=$(curl -sL "https://cran.r-project.org/src/base/R-4/" | \
        grep -oP 'R-\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1 || echo "unknown")
    echo "  Latest R-4.x: ${R_LATEST}"
else
    echo "  (curl not available)"
fi
echo ""

# ---------------------------------------------------------------------------
# RStudio Desktop version
# ---------------------------------------------------------------------------
echo "--- RStudio Desktop ---"
if command -v curl &>/dev/null; then
    echo "  Check: https://posit.co/download/rstudio-desktop/"
    echo "  Or:    https://dailies.rstudio.com/rstudio/latest/index.json"
    # The RStudio download page does not have a simple API; manual check is
    # more reliable than scraping.
fi
echo ""

# ---------------------------------------------------------------------------
# rocker/r-ver tags
# ---------------------------------------------------------------------------
echo "--- rocker/r-ver Docker tags (recent) ---"
if command -v curl &>/dev/null; then
    # Query Docker Hub for recent tags
    TAGS=$(curl -sL "https://hub.docker.com/v2/repositories/rocker/r-ver/tags/?page_size=10&ordering=last_updated" | \
        grep -oP '"name"\s*:\s*"\K[^"]+' 2>/dev/null | head -10 || echo "unable to query")
    for tag in ${TAGS}; do
        echo "  ${tag}"
    done
else
    echo "  (curl not available)"
fi
echo ""

echo "============================================================"
echo "Update the VERSION file with the desired versions, then rebuild."
echo "============================================================"
