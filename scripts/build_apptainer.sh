#!/usr/bin/env bash
##############################################################################
# build_apptainer.sh — Convert Docker image to Apptainer SIF
#
# Usage:
#   ./scripts/build_apptainer.sh                              # Use defaults
#   ./scripts/build_apptainer.sh bioconductor-hpc:3.21        # Specify image
#   ./scripts/build_apptainer.sh --def                        # Build from .def
#
# Two conversion methods are supported:
#
# Method 1 (default): docker-daemon:// conversion
#   Pulls from the local Docker daemon. Requires Docker installed.
#   Best for: development, CI, machines with Docker.
#
# Method 2 (--def): Build from Apptainer definition file
#   Uses apptainer/apptainer.def which pulls from a registry.
#   Best for: HPC systems without Docker.
#
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

BIOC_VERSION="${BIOC_VERSION:-3.21}"
R_VERSION="${R_VERSION:-4.5.0}"
IMAGE_NAME="${IMAGE_NAME:-bioconductor-hpc}"
IMAGE_TAG="${IMAGE_TAG:-${BIOC_VERSION}}"
SIF_NAME="${SIF_NAME:-bioconductor-hpc-${BIOC_VERSION}.sif}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_DIR}}"
USE_DEF=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
DOCKER_IMAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --def)
            USE_DEF=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --sif-name)
            SIF_NAME="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            DOCKER_IMAGE="$1"
            shift
            ;;
    esac
done

DOCKER_IMAGE="${DOCKER_IMAGE:-${IMAGE_NAME}:${IMAGE_TAG}}"

# ---------------------------------------------------------------------------
# Verify Apptainer is available
# ---------------------------------------------------------------------------
if ! command -v apptainer &>/dev/null; then
    if command -v singularity &>/dev/null; then
        echo "WARNING: 'apptainer' not found, falling back to 'singularity'"
        APPTAINER_CMD="singularity"
    else
        echo "ERROR: Neither 'apptainer' nor 'singularity' found in PATH" >&2
        echo "Install Apptainer: https://apptainer.org/docs/admin/main/installation.html" >&2
        exit 1
    fi
else
    APPTAINER_CMD="apptainer"
fi

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "============================================================"
echo "Building Apptainer SIF image"
echo "============================================================"
echo "  Method:    $(${USE_DEF} && echo 'Definition file' || echo 'Docker daemon')"
echo "  Source:    $(${USE_DEF} && echo "${REPO_DIR}/apptainer/apptainer.def" || echo "${DOCKER_IMAGE}")"
echo "  Output:    ${OUTPUT_DIR}/${SIF_NAME}"
echo "============================================================"

mkdir -p "${OUTPUT_DIR}"

if ${USE_DEF}; then
    # Method 2: Build from definition file
    DEF_FILE="${REPO_DIR}/apptainer/apptainer.def"
    if [[ ! -f "${DEF_FILE}" ]]; then
        echo "ERROR: Definition file not found: ${DEF_FILE}" >&2
        exit 1
    fi
    ${APPTAINER_CMD} build \
        "${OUTPUT_DIR}/${SIF_NAME}" \
        "${DEF_FILE}"
else
    # Method 1: Convert from local Docker daemon
    # Verify the Docker image exists locally
    if ! docker image inspect "${DOCKER_IMAGE}" &>/dev/null; then
        echo "ERROR: Docker image '${DOCKER_IMAGE}' not found locally" >&2
        echo "Build it first:  ./scripts/build.sh" >&2
        exit 1
    fi
    ${APPTAINER_CMD} build \
        "${OUTPUT_DIR}/${SIF_NAME}" \
        "docker-daemon://${DOCKER_IMAGE}"
fi

echo ""
echo "============================================================"
echo "SIF image built: ${OUTPUT_DIR}/${SIF_NAME}"
echo "============================================================"
echo ""
echo "Test commands:"
echo "  ${APPTAINER_CMD} exec ${OUTPUT_DIR}/${SIF_NAME} R --version"
echo "  ${APPTAINER_CMD} exec ${OUTPUT_DIR}/${SIF_NAME} Rscript -e 'BiocManager::version()'"
echo "  ${APPTAINER_CMD} shell ${OUTPUT_DIR}/${SIF_NAME}"
echo ""
echo "Deploy to HPC:"
echo "  cp ${OUTPUT_DIR}/${SIF_NAME} /apps/biocontainers/images/"
echo "  ./scripts/install_module.sh"
