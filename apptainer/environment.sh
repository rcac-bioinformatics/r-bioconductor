#!/bin/bash
##############################################################################
# environment.sh — Source this BEFORE running Apptainer commands
#
# Sets up bind paths and environment for running the Bioconductor HPC
# container on a specific cluster. Edit the paths below to match your
# HPC site's filesystem layout.
#
# Usage:
#   source apptainer/environment.sh
#   apptainer exec ${APPTAINER_IMAGE} R
#
# Or in a SLURM script:
#   source /apps/biocontainers/environment.sh
#   srun apptainer exec ${APPTAINER_IMAGE} Rscript analysis.R
#
##############################################################################

# ---------------------------------------------------------------------------
# Image location
# ---------------------------------------------------------------------------
export APPTAINER_IMAGE="${APPTAINER_IMAGE:-/apps/biocontainers/images/bioconductor-hpc-3.21.sif}"

# ---------------------------------------------------------------------------
# Bind paths
#
# Apptainer needs explicit bind mounts to access host directories inside
# the container. These paths are site-specific — edit them for your cluster.
#
# Required binds:
#   /apps/biocontainers/extras — shared R site library
#   /scratch                   — per-job scratch storage (TMPDIR target)
#
# Optional binds:
#   /data, /project, /work     — shared data filesystems
#
# Home directory is bound by default in Apptainer.
# ---------------------------------------------------------------------------
export APPTAINER_BIND="${APPTAINER_BIND:-}"

# Site R library (required for shared packages)
APPTAINER_BIND="${APPTAINER_BIND:+${APPTAINER_BIND},}/apps/biocontainers/extras"

# Scratch filesystem (for TMPDIR and large temp files)
if [[ -d "/scratch" ]]; then
    APPTAINER_BIND="${APPTAINER_BIND},/scratch"
fi

# Common data mount points — uncomment and edit for your site
# APPTAINER_BIND="${APPTAINER_BIND},/data"
# APPTAINER_BIND="${APPTAINER_BIND},/project"
# APPTAINER_BIND="${APPTAINER_BIND},/work"

export APPTAINER_BIND

# ---------------------------------------------------------------------------
# TMPDIR — ensure it exists on scratch
# ---------------------------------------------------------------------------
if [[ -d "/scratch/${USER}" ]]; then
    export TMPDIR="/scratch/${USER}/tmp"
    mkdir -p "${TMPDIR}" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Qt/X11 — set before entering the container so they propagate
# ---------------------------------------------------------------------------
export QT_X11_NO_MITSHM=1
export QT_QPA_PLATFORM=xcb

echo "Bioconductor HPC environment loaded."
echo "  Image: ${APPTAINER_IMAGE}"
echo "  Binds: ${APPTAINER_BIND}"
echo "  TMPDIR: ${TMPDIR:-/tmp}"
