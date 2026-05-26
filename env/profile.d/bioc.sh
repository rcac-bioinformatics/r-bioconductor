#!/bin/bash
##############################################################################
# bioc.sh — Shell environment for Bioconductor HPC container
#
# Placed in /etc/profile.d/ so it is sourced by login shells inside the
# container. Under Apptainer, this is sourced when using:
#   apptainer shell <image>
#   apptainer exec <image> bash -l -c '...'
#
# For non-login Apptainer exec calls, the apptainer.def %environment
# section handles the equivalent setup.
##############################################################################

# R version (major.minor) for path construction
export R_VERSION_SHORT="${R_VERSION_SHORT:-4.5}"
export BIOC_VERSION="${BIOC_VERSION:-3.21}"

# R library paths — these match Renviron.site but are also available to
# shell scripts that need to know where R packages live.
export R_LIBS_USER="${R_LIBS_USER:-${HOME}/R/x86_64-pc-linux-gnu-library/${R_VERSION_SHORT}}"
export R_LIBS_SITE="${R_LIBS_SITE:-/apps/biocontainers/extras/r-package-site-library/${R_VERSION_SHORT}-bioconductor}"

# TMPDIR — critical for HPC. Default /tmp is often a tiny tmpfs on compute
# nodes. Redirect to scratch storage if available. Jobs processing large
# genomics datasets (scRNA-seq, WGS) can generate gigabytes of temp files.
if [ -d "/scratch/${USER}" ]; then
    export TMPDIR="/scratch/${USER}/tmp"
    mkdir -p "${TMPDIR}" 2>/dev/null || true
elif [ -d "/tmp/${USER}" ]; then
    export TMPDIR="/tmp/${USER}"
    mkdir -p "${TMPDIR}" 2>/dev/null || true
fi

# Qt/X11 configuration for RStudio Desktop
# QT_X11_NO_MITSHM: Required when running inside containers where shared
#   memory segments between X client and server are not available.
# QT_QPA_PLATFORM: Explicitly use X11 (not Wayland) — HPC remote desktops
#   (ThinLinc, VNC) use X11.
export QT_X11_NO_MITSHM=1
export QT_QPA_PLATFORM=xcb

# Disable Qt accessibility bridge — it causes warnings when D-Bus
# is not fully configured (common in containers).
export QT_ACCESSIBILITY=0
export NO_AT_BRIDGE=1

# Informational message on interactive shells
if [ -t 0 ] && [ -z "${BIOC_QUIET}" ]; then
    echo "Bioconductor ${BIOC_VERSION} | R ${R_VERSION_SHORT} | RStudio Desktop"
    echo "  User library:  ${R_LIBS_USER}"
    echo "  Site library:  ${R_LIBS_SITE}"
    echo "  Launch RStudio: launch-rstudio"
fi
