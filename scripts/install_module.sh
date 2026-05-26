#!/usr/bin/env bash
##############################################################################
# install_module.sh — Deploy modulefile to the HPC module system
#
# Copies the appropriate modulefile (Tcl or Lua) to the module path
# and creates the necessary directory structure.
#
# Usage:
#   ./scripts/install_module.sh                    # Auto-detect Lmod vs Tcl
#   ./scripts/install_module.sh --lua              # Force Lua/Lmod
#   ./scripts/install_module.sh --tcl              # Force Tcl
#   MODULE_PATH=/custom/path ./scripts/install_module.sh
#
# This script is idempotent — safe to run multiple times.
##############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -f "${REPO_DIR}/VERSION" ]]; then
    source "${REPO_DIR}/VERSION"
fi

BIOC_VERSION="${BIOC_VERSION:-3.21}"
R_VERSION="${R_VERSION:-4.5.0}"

# ---------------------------------------------------------------------------
# Configurable paths — adjust these for your HPC site
# ---------------------------------------------------------------------------
# Where the SIF image is stored
IMAGE_DIR="${IMAGE_DIR:-/apps/biocontainers/images}"
IMAGE_FILE="${IMAGE_FILE:-bioconductor-hpc-${BIOC_VERSION}.sif}"

# Where modules are installed
MODULE_PATH="${MODULE_PATH:-/apps/modulefiles}"
MODULE_NAME="${MODULE_NAME:-bioconductor}"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FORMAT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --lua|--lmod) FORMAT="lua"; shift ;;
        --tcl)        FORMAT="tcl"; shift ;;
        --module-path)
            MODULE_PATH="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Auto-detect module system
# ---------------------------------------------------------------------------
if [[ -z "${FORMAT}" ]]; then
    if command -v lmod &>/dev/null || [[ -n "${LMOD_CMD:-}" ]]; then
        FORMAT="lua"
    elif command -v modulecmd &>/dev/null; then
        FORMAT="tcl"
    else
        echo "WARNING: Cannot detect module system. Defaulting to Lua (Lmod)."
        FORMAT="lua"
    fi
fi

echo "============================================================"
echo "Installing modulefile"
echo "============================================================"
echo "  Format:      ${FORMAT}"
echo "  Module path: ${MODULE_PATH}/${MODULE_NAME}"
echo "  Version:     ${BIOC_VERSION}"
echo "  Image:       ${IMAGE_DIR}/${IMAGE_FILE}"
echo "============================================================"

# ---------------------------------------------------------------------------
# Select source template
# ---------------------------------------------------------------------------
if [[ "${FORMAT}" == "lua" ]]; then
    SOURCE_TEMPLATE="${REPO_DIR}/templates/modulefile.lua"
    DEST_DIR="${MODULE_PATH}/${MODULE_NAME}"
    DEST_FILE="${DEST_DIR}/${BIOC_VERSION}.lua"
else
    SOURCE_TEMPLATE="${REPO_DIR}/templates/modulefile.tcl"
    DEST_DIR="${MODULE_PATH}/${MODULE_NAME}"
    DEST_FILE="${DEST_DIR}/${BIOC_VERSION}"
fi

if [[ ! -f "${SOURCE_TEMPLATE}" ]]; then
    echo "ERROR: Template not found: ${SOURCE_TEMPLATE}" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Create module directory and install
# ---------------------------------------------------------------------------
mkdir -p "${DEST_DIR}"

# Perform variable substitution and write the modulefile
sed \
    -e "s|@@BIOC_VERSION@@|${BIOC_VERSION}|g" \
    -e "s|@@R_VERSION@@|${R_VERSION}|g" \
    -e "s|@@R_VERSION_SHORT@@|${R_VERSION%.*}|g" \
    -e "s|@@IMAGE_DIR@@|${IMAGE_DIR}|g" \
    -e "s|@@IMAGE_FILE@@|${IMAGE_FILE}|g" \
    "${SOURCE_TEMPLATE}" > "${DEST_FILE}"

echo ""
echo "Installed: ${DEST_FILE}"
echo ""

# ---------------------------------------------------------------------------
# Create .version file (Tcl) or default symlink (Lmod) for default version
# ---------------------------------------------------------------------------
if [[ "${FORMAT}" == "tcl" ]]; then
    cat > "${DEST_DIR}/.version" <<EOF
#%Module1.0
set ModulesVersion "${BIOC_VERSION}"
EOF
    echo "Set default version: ${BIOC_VERSION}"
fi

echo ""
echo "Test with:"
echo "  module avail ${MODULE_NAME}"
echo "  module load ${MODULE_NAME}/${BIOC_VERSION}"
echo "  module show ${MODULE_NAME}/${BIOC_VERSION}"
