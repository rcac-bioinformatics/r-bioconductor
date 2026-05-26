# Open OnDemand Integration

This document describes how to integrate the Bioconductor HPC container with
Open OnDemand (OOD) to provide RStudio Desktop as an interactive application.

## Overview

Open OnDemand's Interactive Apps framework can launch desktop sessions on
compute nodes. Within these sessions, the user has a full X11 desktop where
RStudio Desktop runs as a normal application.

There are two approaches:

1. **Desktop app + manual launch**: Users get an OOD desktop session, then
   launch RStudio themselves from a terminal.
2. **Custom interactive app**: A dedicated OOD app that launches RStudio
   directly.

## Approach 1: OOD Desktop Session

This is the simplest approach and requires no OOD app development.

### Prerequisites

- Open OnDemand with a working Interactive Desktop app (bc_desktop)
- Apptainer available on compute nodes
- The Bioconductor SIF image deployed to shared storage
- Bind mounts configured for the site library

### User Workflow

1. Log into Open OnDemand
2. Launch an Interactive Desktop session:
   - Select appropriate resources (CPUs, memory, time)
   - For typical Bioconductor work: 4+ CPUs, 16+ GB RAM
3. Open a terminal in the desktop session
4. Load the module and launch RStudio:

```bash
module load bioconductor/3.21
rstudio
```

Or without the module:

```bash
apptainer exec \
    --bind /apps/biocontainers/extras \
    --bind /scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    launch-rstudio
```

## Approach 2: Custom OOD Interactive App

For a more polished user experience, create a dedicated OOD app.

### App Directory Structure

Create the app under your OOD apps directory (typically
`/var/www/ood/apps/sys/` or a development sandbox):

```
bc_rstudio_bioconductor/
├── form.yml
├── manifest.yml
├── submit.yml.erb
└── template/
    ├── before.sh.erb
    └── script.sh.erb
```

### manifest.yml

```yaml
---
name: RStudio (Bioconductor)
category: Interactive Apps
subcategory: Genomics
role: batch_connect
description: |
  Launch RStudio Desktop with Bioconductor for genomics analysis.
  Provides R with BiocManager, GenomicRanges, and other core packages.
```

### form.yml

```yaml
---
cluster: "cluster_name"
attributes:
  bc_num_hours:
    value: 4
    min: 1
    max: 48
    step: 1
    label: "Number of hours"
  bc_num_slots:
    value: 4
    min: 1
    max: 32
    step: 1
    label: "Number of CPU cores"
  memory:
    widget: "number_field"
    value: 16
    min: 4
    max: 256
    step: 4
    label: "Memory (GB)"
  bioc_version:
    widget: "select"
    label: "Bioconductor version"
    options:
      - ["3.21 (R 4.5.0)", "3.21"]
      - ["3.20 (R 4.4.2)", "3.20"]
  partition:
    widget: "select"
    label: "Partition"
    options:
      - ["default", ""]
      - ["interactive", "interactive"]
      - ["gpu", "gpu"]

form:
  - bc_num_hours
  - bc_num_slots
  - memory
  - bioc_version
  - partition
  - bc_email_on_started
```

### submit.yml.erb

```yaml
---
batch_connect:
  template: "vnc"
script:
  native:
    - "-N"
    - "1"
    - "--cpus-per-task"
    - "<%= bc_num_slots %>"
    - "--mem"
    - "<%= memory %>G"
    - "--time"
    - "<%= bc_num_hours %>:00:00"
<% if partition.present? %>
    - "--partition"
    - "<%= partition %>"
<% end %>
```

### template/before.sh.erb

This runs before the VNC session starts:

```bash
#!/bin/bash

# Set Bioconductor version from form selection
export BIOC_VERSION="<%= bioc_version %>"

# Map version to image file
case "${BIOC_VERSION}" in
    3.21) IMAGE="bioconductor-hpc-3.21.sif" ;;
    3.20) IMAGE="bioconductor-hpc-3.20.sif" ;;
    *)    IMAGE="bioconductor-hpc-${BIOC_VERSION}.sif" ;;
esac

export APPTAINER_IMAGE="/apps/biocontainers/images/${IMAGE}"

# Verify image exists
if [[ ! -f "${APPTAINER_IMAGE}" ]]; then
    echo "ERROR: Container image not found: ${APPTAINER_IMAGE}" >&2
    exit 1
fi

# Bind mounts
export APPTAINER_BIND="/apps/biocontainers/extras,/scratch"

# TMPDIR on scratch
export TMPDIR="/scratch/${USER}/tmp"
mkdir -p "${TMPDIR}" 2>/dev/null || true

# Qt/X11
export QT_X11_NO_MITSHM=1
export QT_QPA_PLATFORM=xcb
export QT_ACCESSIBILITY=0
export NO_AT_BRIDGE=1

# Create user R library
R_VERSION_SHORT="4.5"  # Update when changing default version
mkdir -p "${HOME}/R/x86_64-pc-linux-gnu-library/${R_VERSION_SHORT}" 2>/dev/null || true
```

### template/script.sh.erb

This runs inside the VNC session to start RStudio:

```bash
#!/bin/bash

# Source the environment from before.sh
source "<%= staged_root %>/before.sh"

# Launch RStudio Desktop inside the container
apptainer exec \
    --bind "${APPTAINER_BIND}" \
    "${APPTAINER_IMAGE}" \
    launch-rstudio
```

### Installation

1. Copy the app directory to the OOD apps location:

```bash
sudo cp -r bc_rstudio_bioconductor /var/www/ood/apps/sys/
```

2. Restart the OOD web server:

```bash
sudo systemctl restart ondemand
```

3. The app should now appear under Interactive Apps in the OOD dashboard.

### Testing

1. Log into OOD
2. Navigate to Interactive Apps > RStudio (Bioconductor)
3. Fill in the form and launch
4. Wait for the session to start
5. Click "Launch RStudio (Bioconductor)" to connect
6. Verify: RStudio opens, R version is correct, BiocManager works

## Resource Recommendations

| Workflow | CPUs | Memory | Time |
|----------|------|--------|------|
| Light analysis (differential expression) | 2-4 | 8-16 GB | 2-4 hrs |
| scRNA-seq (Seurat/Bioconductor) | 8-16 | 32-64 GB | 4-8 hrs |
| Genome assembly / alignment | 8-32 | 64-128 GB | 8-24 hrs |
| Interactive exploration | 2-4 | 8-16 GB | 2-4 hrs |

## Troubleshooting

### RStudio window is blank or doesn't appear

This usually means the VNC session started but RStudio failed to launch.
Check the job's output log:

```bash
cat ~/ondemand/data/sys/dashboard/batch_connect/sys/bc_rstudio_bioconductor/output/<job_id>/output.log
```

Common causes:
- Container image not found: verify `APPTAINER_IMAGE` path
- Missing bind mounts: verify paths exist on the compute node
- Qt/X11 errors: check that `QT_X11_NO_MITSHM=1` is set

### Session starts but RStudio is slow

- Check TMPDIR is on fast storage (not NFS)
- Verify sufficient memory was allocated
- Check if fontconfig is rebuilding its cache (first launch is slow)

### Package installation fails

- User library path must be writable and on the bind-mounted home directory
- Site library requires admin access; users should use their personal library
- See docs/troubleshooting.md for detailed package installation help
