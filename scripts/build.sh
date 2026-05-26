#!/usr/bin/env bash
##############################################################################
# build.sh — Build the Bioconductor HPC Docker image
#
# Usage:
#   ./scripts/build.sh                    # Build with defaults from VERSION
#   ./scripts/build.sh --no-cache         # Force full rebuild
#   BIOC_VERSION=3.20 ./scripts/build.sh  # Override Bioconductor version
#
# This script reads version defaults from the VERSION file in the
# repository root, but any variable can be overridden via environment.
##############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Load defaults from VERSION file
# ---------------------------------------------------------------------------
if [[ -f "${REPO_DIR}/VERSION" ]]; then
    # shellcheck source=../VERSION
    source "${REPO_DIR}/VERSION"
fi

# ---------------------------------------------------------------------------
# Configurable variables (override via environment)
# ---------------------------------------------------------------------------
BIOC_VERSION="${BIOC_VERSION:-3.21}"
R_VERSION="${R_VERSION:-4.5.0}"
UBUNTU_VERSION="${UBUNTU_VERSION:-noble}"
RSTUDIO_VERSION="${RSTUDIO_VERSION:-2025.05.0-496}"
IMAGE_NAME="${IMAGE_NAME:-bioconductor-hpc}"
IMAGE_TAG="${IMAGE_TAG:-${BIOC_VERSION}}"

# ---------------------------------------------------------------------------
# Parse command-line options
# ---------------------------------------------------------------------------
DOCKER_BUILD_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-cache)
            DOCKER_BUILD_ARGS+=("--no-cache")
            shift
            ;;
        --push)
            PUSH_IMAGE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--no-cache] [--push]" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "============================================================"
echo "Building Bioconductor HPC container"
echo "============================================================"
echo "  Bioconductor: ${BIOC_VERSION}"
echo "  R:            ${R_VERSION}"
echo "  Ubuntu:       ${UBUNTU_VERSION}"
echo "  RStudio:      ${RSTUDIO_VERSION}"
echo "  Image:        ${IMAGE_NAME}:${IMAGE_TAG}"
echo "============================================================"

docker build \
    --build-arg R_VERSION="${R_VERSION}" \
    --build-arg UBUNTU_VERSION="${UBUNTU_VERSION}" \
    --build-arg BIOC_VERSION="${BIOC_VERSION}" \
    --build-arg RSTUDIO_VERSION="${RSTUDIO_VERSION}" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    -t "${IMAGE_NAME}:latest" \
    "${DOCKER_BUILD_ARGS[@]+"${DOCKER_BUILD_ARGS[@]}"}" \
    "${REPO_DIR}"

echo ""
echo "Build complete: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""

# ---------------------------------------------------------------------------
# Optional push
# ---------------------------------------------------------------------------
if [[ "${PUSH_IMAGE:-false}" == "true" ]]; then
    echo "Pushing ${IMAGE_NAME}:${IMAGE_TAG} ..."
    docker push "${IMAGE_NAME}:${IMAGE_TAG}"
    docker push "${IMAGE_NAME}:latest"
    echo "Push complete."
fi

# ---------------------------------------------------------------------------
# Post-build summary
# ---------------------------------------------------------------------------
echo ""
echo "Next steps:"
echo "  Test:      ./scripts/test_cli.sh ${IMAGE_NAME}:${IMAGE_TAG}"
echo "  Convert:   ./scripts/build_apptainer.sh ${IMAGE_NAME}:${IMAGE_TAG}"
