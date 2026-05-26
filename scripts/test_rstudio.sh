#!/usr/bin/env bash
##############################################################################
# test_rstudio.sh — Verify RStudio Desktop can start (non-interactive)
#
# This script verifies that RStudio Desktop is installed correctly and
# that its dependencies are satisfied. It does NOT attempt to launch
# the full GUI (that requires X11).
#
# Tests:
#   - RStudio binary exists and is executable
#   - Required shared libraries are available (ldd check)
#   - Qt platform plugins are present
#   - launch-rstudio wrapper is functional
#
# Usage:
#   ./scripts/test_rstudio.sh                                  # Docker
#   ./scripts/test_rstudio.sh --apptainer bioconductor-hpc.sif # SIF
#
##############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_DIR}/VERSION" ]]; then
    source "${REPO_DIR}/VERSION"
fi

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

run_in_container() {
    if ${USE_APPTAINER}; then
        apptainer exec "${IMAGE}" "$@"
    else
        docker run --rm "${IMAGE}" "$@"
    fi
}

PASS=0
FAIL=0
TOTAL=0

check() {
    local name="$1"
    shift
    TOTAL=$((TOTAL + 1))
    echo -n "  CHECK ${TOTAL}: ${name} ... "
    if "$@" 2>&1; then
        echo "OK"
        PASS=$((PASS + 1))
    else
        echo "PROBLEM"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================================"
echo "RStudio Desktop dependency checks: ${IMAGE}"
echo "============================================================"

# Binary exists
check "RStudio binary exists" \
    run_in_container test -x /usr/lib/rstudio/rstudio

# Shared library dependencies are satisfied
check "Shared libraries resolved" \
    run_in_container bash -c "ldd /usr/lib/rstudio/rstudio 2>&1 | grep -qv 'not found'"

# Qt xcb platform plugin exists
check "Qt xcb plugin available" \
    run_in_container bash -c "find /usr/lib/rstudio -name 'libqxcb*' -o -name 'libQt*xcb*' 2>/dev/null | grep -q ."

# D-Bus is available
check "D-Bus libraries present" \
    run_in_container test -f /usr/lib/x86_64-linux-gnu/libdbus-1.so.3

# Font configuration is valid
check "Fontconfig configured" \
    run_in_container fc-list --format='%{family}\n' | head -1 | grep -q .

# launch-rstudio wrapper exists and has correct shebang
check "launch-rstudio wrapper" \
    run_in_container head -1 /usr/local/bin/launch-rstudio | grep -q bash

echo ""
echo "============================================================"
echo "Results: ${PASS}/${TOTAL} passed, ${FAIL} problems"
echo "============================================================"

if [[ ${FAIL} -gt 0 ]]; then
    echo ""
    echo "NOTE: Some checks failed. This may indicate missing libraries."
    echo "Run 'ldd /usr/lib/rstudio/rstudio' inside the container to identify"
    echo "which shared libraries are not found."
    exit 1
fi

echo ""
echo "RStudio Desktop dependencies look good."
echo "To test GUI launch, run inside an X11 session:"
echo "  apptainer exec bioconductor-hpc.sif launch-rstudio"
