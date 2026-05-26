#!/usr/bin/env bash
##############################################################################
# launch_rstudio.sh — Launch RStudio Desktop inside the container
#
# This wrapper configures the environment for running RStudio Desktop
# under X11 in HPC environments. It handles:
#   - TMPDIR redirection away from /tmp (often tiny on compute nodes)
#   - Qt/X11 configuration for container compatibility
#   - D-Bus session bus for Qt IPC
#   - User library directory creation
#
# Usage (inside container):
#   launch-rstudio
#
# Usage (from host via Apptainer):
#   apptainer exec --bind /scratch bioconductor-hpc.sif launch-rstudio
#
# Usage (in SLURM job):
#   srun --x11 apptainer exec bioconductor-hpc.sif launch-rstudio
#
##############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# DISPLAY check — RStudio Desktop requires X11
# ---------------------------------------------------------------------------
if [[ -z "${DISPLAY:-}" ]]; then
    echo "ERROR: DISPLAY is not set. RStudio Desktop requires an X11 display." >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  1. Use a ThinLinc session (recommended for HPC)" >&2
    echo "  2. Use an Open OnDemand interactive desktop" >&2
    echo "  3. SSH with X11 forwarding: ssh -X user@host" >&2
    echo "  4. Set DISPLAY manually if you know the X server address" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Version info
# ---------------------------------------------------------------------------
R_VERSION_SHORT="${R_VERSION_SHORT:-4.5}"
BIOC_VERSION="${BIOC_VERSION:-3.21}"

# ---------------------------------------------------------------------------
# TMPDIR — redirect to scratch storage
#
# HPC compute nodes often have /tmp as a small tmpfs (1-4 GB). RStudio
# and R create temp files during sessions, and large analyses (scRNA-seq,
# genome assembly) can easily fill /tmp.
#
# We try, in order:
#   1. User-specified TMPDIR (already set)
#   2. /scratch/$USER/tmp (common HPC scratch layout)
#   3. /tmp/$USER (fallback — at least per-user isolation)
# ---------------------------------------------------------------------------
if [[ -z "${TMPDIR:-}" ]]; then
    if [[ -d "/scratch/${USER:-$(whoami)}" ]]; then
        export TMPDIR="/scratch/${USER:-$(whoami)}/tmp"
    else
        export TMPDIR="/tmp/${USER:-$(whoami)}"
    fi
fi
mkdir -p "${TMPDIR}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Qt / X11 configuration
# ---------------------------------------------------------------------------

# QT_X11_NO_MITSHM: Disable MIT-SHM extension. Inside containers, the
# X client and X server do not share memory, so MIT-SHM causes crashes.
export QT_X11_NO_MITSHM=1

# QT_QPA_PLATFORM: Force xcb (X11) platform plugin. ThinLinc and VNC
# sessions are X11-based; Wayland is not used in HPC remote desktops.
export QT_QPA_PLATFORM=xcb

# Disable Qt accessibility bridge — it generates warnings when D-Bus
# accessibility services are not available (common in containers).
export QT_ACCESSIBILITY=0
export NO_AT_BRIDGE=1

# QT_QPA_PLATFORM_PLUGIN_PATH: Help Qt find its platform plugins.
# This is usually auto-detected but can fail in stripped containers.
if [[ -d "/usr/lib/rstudio/plugins/platforms" ]]; then
    export QT_QPA_PLATFORM_PLUGIN_PATH="/usr/lib/rstudio/plugins/platforms"
fi

# ---------------------------------------------------------------------------
# D-Bus session bus
#
# Qt applications (including RStudio) expect a D-Bus session bus.
# In containers, dbus-daemon may not be running. We start a private
# session bus if one is not already available.
# ---------------------------------------------------------------------------
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if command -v dbus-launch &>/dev/null; then
        eval "$(dbus-launch --sh-syntax 2>/dev/null)" || true
    fi
fi

# ---------------------------------------------------------------------------
# User R library — ensure it exists
# ---------------------------------------------------------------------------
USER_LIB="${R_LIBS_USER:-${HOME}/R/x86_64-pc-linux-gnu-library/${R_VERSION_SHORT}}"
# Expand ~ if present
USER_LIB="${USER_LIB/#\~/${HOME}}"
mkdir -p "${USER_LIB}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Font configuration — ensure fontconfig cache is writable
# ---------------------------------------------------------------------------
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-/etc/fonts}"
FC_CACHE_DIR="${HOME}/.cache/fontconfig"
mkdir -p "${FC_CACHE_DIR}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# XDG directories — ensure they point to writable locations
# RStudio uses XDG directories for configuration and cache.
# ---------------------------------------------------------------------------
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
mkdir -p "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_CACHE_HOME}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Launch RStudio Desktop
# ---------------------------------------------------------------------------
echo "Launching RStudio Desktop"
echo "  DISPLAY:     ${DISPLAY}"
echo "  TMPDIR:      ${TMPDIR}"
echo "  User lib:    ${USER_LIB}"
echo "  Bioconductor ${BIOC_VERSION} | R ${R_VERSION_SHORT}"

# Find the RStudio binary
RSTUDIO_BIN=""
for candidate in /usr/lib/rstudio/rstudio /usr/lib/rstudio/bin/rstudio /usr/bin/rstudio; do
    if [[ -x "${candidate}" ]]; then
        RSTUDIO_BIN="${candidate}"
        break
    fi
done

if [[ -z "${RSTUDIO_BIN}" ]]; then
    echo "ERROR: RStudio Desktop binary not found" >&2
    echo "Searched: /usr/lib/rstudio/rstudio, /usr/lib/rstudio/bin/rstudio, /usr/bin/rstudio" >&2
    exit 1
fi

exec "${RSTUDIO_BIN}" "$@"
