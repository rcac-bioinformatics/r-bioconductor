#!/usr/bin/env bash
##############################################################################
# test_cli.sh — Validate the container image (CLI functionality)
#
# Runs a series of non-interactive checks to verify:
#   - R starts and reports the expected version
#   - Rscript works
#   - BiocManager is installed and reports the correct version
#   - Core Bioconductor packages are loadable
#   - Library paths are configured correctly
#   - RStudio Desktop binary exists
#
# Usage:
#   ./scripts/test_cli.sh                                     # Test Docker
#   ./scripts/test_cli.sh bioconductor-hpc:3.21               # Specific tag
#   ./scripts/test_cli.sh --apptainer bioconductor-hpc.sif    # Test SIF
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed
##############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Load defaults
# ---------------------------------------------------------------------------
if [[ -f "${REPO_DIR}/VERSION" ]]; then
    source "${REPO_DIR}/VERSION"
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
USE_APPTAINER=false
IMAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apptainer|--singularity)
            USE_APPTAINER=true
            shift
            ;;
        *)
            IMAGE="$1"
            shift
            ;;
    esac
done

if [[ -z "${IMAGE}" ]]; then
    if ${USE_APPTAINER}; then
        IMAGE="bioconductor-hpc-${BIOC_VERSION:-3.21}.sif"
    else
        IMAGE="bioconductor-hpc:${BIOC_VERSION:-3.21}"
    fi
fi

# ---------------------------------------------------------------------------
# Runner function — abstracts Docker vs Apptainer
# ---------------------------------------------------------------------------
run_in_container() {
    if ${USE_APPTAINER}; then
        apptainer exec "${IMAGE}" "$@"
    else
        docker run --rm "${IMAGE}" "$@"
    fi
}

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

run_test() {
    local name="$1"
    shift
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -n "  TEST ${TESTS_TOTAL}: ${name} ... "
    if "$@" >/dev/null 2>&1; then
        echo "PASS"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "FAIL"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
echo "============================================================"
echo "Testing container: ${IMAGE}"
echo "Runtime: $(${USE_APPTAINER} && echo 'Apptainer' || echo 'Docker')"
echo "============================================================"

# Test 1: R is executable and reports a version
run_test "R --version" \
    run_in_container R --version

# Test 2: Rscript works
run_test "Rscript -e '1+1'" \
    run_in_container Rscript -e "stopifnot(1+1 == 2)"

# Test 3: R version matches expected
run_test "R version = ${R_VERSION}" \
    run_in_container Rscript -e "stopifnot(grepl('${R_VERSION:-4.5}', R.version.string))"

# Test 4: BiocManager is installed
run_test "BiocManager installed" \
    run_in_container Rscript -e "library(BiocManager)"

# Test 5: BiocManager reports correct version
run_test "Bioconductor version = ${BIOC_VERSION}" \
    run_in_container Rscript -e "stopifnot(as.character(BiocManager::version()) == '${BIOC_VERSION:-3.21}')"

# Test 6: Core Bioconductor packages load
run_test "Load BiocGenerics" \
    run_in_container Rscript -e "library(BiocGenerics)"

run_test "Load GenomicRanges" \
    run_in_container Rscript -e "library(GenomicRanges)"

run_test "Load S4Vectors" \
    run_in_container Rscript -e "library(S4Vectors)"

run_test "Load IRanges" \
    run_in_container Rscript -e "library(IRanges)"

run_test "Load BiocParallel" \
    run_in_container Rscript -e "library(BiocParallel)"

# Test 7: CRAN packages
run_test "Load tidyverse" \
    run_in_container Rscript -e "library(tidyverse)"

run_test "Load data.table" \
    run_in_container Rscript -e "library(data.table)"

# Test 8: Library paths are configured
run_test "R_LIBS_SITE configured" \
    run_in_container Rscript -e "stopifnot(any(grepl('r-package-site-library', .libPaths())))"

# Test 9: RStudio Desktop binary exists
run_test "RStudio Desktop binary exists" \
    run_in_container test -x /usr/lib/rstudio/rstudio

# Test 10: launch-rstudio wrapper exists
run_test "launch-rstudio wrapper exists" \
    run_in_container test -x /usr/local/bin/launch-rstudio

# Test 11: Locale is UTF-8
run_test "UTF-8 locale" \
    run_in_container Rscript -e "stopifnot(grepl('UTF-8', Sys.getlocale('LC_CTYPE')))"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "Results: ${TESTS_PASSED}/${TESTS_TOTAL} passed, ${TESTS_FAILED} failed"
echo "============================================================"

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo "SOME TESTS FAILED" >&2
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi
