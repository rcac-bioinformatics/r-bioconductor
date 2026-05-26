# ThinLinc Integration

This document describes how to use the Bioconductor HPC container with
ThinLinc remote desktop sessions for RStudio Desktop access.

## Overview

ThinLinc provides remote desktop sessions on Linux servers. When a user
connects via ThinLinc, they get a full X11 desktop environment. RStudio
Desktop runs as a normal X11 application within this session — no port
forwarding, no web server, no special configuration.

This is the recommended way to run RStudio Desktop on HPC clusters that
have ThinLinc deployed.

## Prerequisites

- ThinLinc server configured on the HPC cluster
- ThinLinc client installed on the user's workstation
  (download from https://www.clulab.com/thinlinc/)
- Apptainer available on the ThinLinc session host
- The Bioconductor SIF image deployed to shared storage
- The modulefile installed (or users know the apptainer exec command)

## Connection Workflow

### Step 1: Connect via ThinLinc

1. Open the ThinLinc client
2. Enter the server address (e.g., `thinlinc.hpc.example.edu`)
3. Enter your HPC credentials
4. Click Connect

You will get a Linux desktop session. DISPLAY is automatically set.

### Step 2: Launch RStudio Desktop

Open a terminal in the ThinLinc desktop and run:

```bash
# Option A: Using the module system
module load bioconductor/3.21
rstudio

# Option B: Direct apptainer command
apptainer exec \
    --bind /apps/biocontainers/extras \
    --bind /scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    launch-rstudio
```

RStudio Desktop will open as a window in the ThinLinc session.

### Step 3: Work in RStudio

RStudio behaves exactly like a local installation:
- Open and edit R scripts
- Run code in the console
- Use the plot pane
- Install packages (to your user library)
- Use the terminal tab

## Running on Compute Nodes via SLURM

ThinLinc sessions typically run on login nodes. For compute-intensive work,
submit a SLURM job that runs on a compute node with X11 forwarding.

### Interactive Job with X11

```bash
# From the ThinLinc terminal:
srun --x11 --cpus-per-task=8 --mem=32G --time=4:00:00 \
    apptainer exec \
    --bind /apps/biocontainers/extras \
    --bind /scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    launch-rstudio
```

The `--x11` flag forwards the X11 display from the compute node back to
your ThinLinc session. RStudio opens in a window on your desktop but
actually runs on the compute node.

### Wrapper Script for Users

Save this as `~/bin/rstudio-hpc`:

```bash
#!/bin/bash
# Launch RStudio Desktop on a compute node via SLURM
#
# Usage:
#   rstudio-hpc                    # Default resources
#   rstudio-hpc --mem 64G          # More memory
#   rstudio-hpc --cpus-per-task 16 # More CPUs

# Default SLURM parameters (override via command line)
CPUS="${SLURM_CPUS:-4}"
MEM="${SLURM_MEM:-16G}"
TIME="${SLURM_TIME:-4:00:00}"
PARTITION="${SLURM_PARTITION:-}"

# Container configuration
IMAGE="/apps/biocontainers/images/bioconductor-hpc-3.21.sif"
BINDS="/apps/biocontainers/extras,/scratch"

echo "Requesting SLURM job: ${CPUS} CPUs, ${MEM} memory, ${TIME} walltime"
echo "RStudio will open when the job starts..."

srun --x11 \
    --cpus-per-task="${CPUS}" \
    --mem="${MEM}" \
    --time="${TIME}" \
    ${PARTITION:+--partition=${PARTITION}} \
    apptainer exec \
    --bind "${BINDS}" \
    "${IMAGE}" \
    launch-rstudio
```

Make it executable:

```bash
chmod +x ~/bin/rstudio-hpc
```

## Desktop Shortcut

For convenience, create a desktop shortcut that users can double-click:

### XFCE Desktop (common ThinLinc default)

Create `~/Desktop/RStudio-Bioconductor.desktop`:

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=RStudio (Bioconductor 3.21)
Comment=Launch RStudio Desktop with Bioconductor
Exec=bash -c 'module load bioconductor/3.21 && rstudio'
Icon=rstudio
Terminal=false
Categories=Development;Science;
```

Make it executable:

```bash
chmod +x ~/Desktop/RStudio-Bioconductor.desktop
```

### MATE Desktop

Same file format works. Place in `~/Desktop/`.

## Environment Variables

The ThinLinc session automatically provides:

| Variable | Value | Notes |
|----------|-------|-------|
| DISPLAY | `:1` or similar | Set by ThinLinc |
| HOME | `/home/username` | User's home directory |
| USER | `username` | Current user |

The container adds:

| Variable | Value | Notes |
|----------|-------|-------|
| QT_X11_NO_MITSHM | `1` | Disable shared memory (container compat) |
| QT_QPA_PLATFORM | `xcb` | Force X11 backend |
| R_LIBS_USER | `~/R/x86_64-pc-linux-gnu-library/4.5` | User R packages |
| R_LIBS_SITE | `/apps/.../4.5-bioconductor` | Shared R packages |
| TMPDIR | `/scratch/$USER/tmp` | Temp files on scratch |

## Performance Tips

### ThinLinc Display Quality

- For data visualization work, increase the ThinLinc display quality:
  - ThinLinc Client > Options > Screen > Quality: High
- For slower network connections, reduce quality for smoother interaction

### Large Plots

- RStudio renders plots locally (on the compute side). Only the display
  updates travel over the network.
- For very large plots (heatmaps of thousands of genes), consider saving
  to PDF/PNG instead of rendering in the plot pane.

### Session Persistence

- ThinLinc sessions persist when you disconnect
- Reconnect later to find your RStudio session still running
- This is a major advantage over X11 forwarding (ssh -X), which dies
  when the SSH connection drops

## Troubleshooting

### "Cannot open display" error

```
Error: cannot open display: :1
```

This means the DISPLAY variable is not propagating into the container.
Check:

```bash
# Verify DISPLAY is set
echo $DISPLAY

# Verify X11 works at all
xterm &

# If xterm works but RStudio doesn't, try:
export QT_X11_NO_MITSHM=1
apptainer exec --bind /apps/biocontainers/extras \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    launch-rstudio
```

### RStudio window appears but is blank/white

This is usually a Qt rendering issue:

```bash
# Disable GPU acceleration (common fix for VNC/ThinLinc)
export QTWEBENGINE_DISABLE_SANDBOX=1
apptainer exec ... launch-rstudio
```

### Fonts look wrong

```bash
# Rebuild fontconfig cache
apptainer exec /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    fc-cache -fv

# This creates the cache in ~/.cache/fontconfig (writable)
```

### Session hangs on reconnect

If you disconnect and reconnect to ThinLinc and RStudio is
unresponsive:

1. Open a new terminal in the ThinLinc session
2. Find the RStudio process: `ps aux | grep rstudio`
3. Kill it: `kill <PID>`
4. Relaunch: `module load bioconductor/3.21 && rstudio`

### X11 forwarding via SLURM not working

The `srun --x11` flag requires:
- The SLURM cluster is configured for X11 forwarding
- The compute nodes can connect back to the login/ThinLinc node
- xauth is available

If `--x11` is not supported, ask your HPC admin about alternatives:
- Some sites use `ssh -X` to the allocated node instead
- Some sites provide separate VNC-on-compute-node mechanisms
