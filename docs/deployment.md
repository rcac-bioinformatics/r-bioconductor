# Deploying Bioconductor HPC Container to a Cluster

Production deployment guide for HPC system administrators.

This document covers the full deployment lifecycle: building the container image,
placing it on shared storage, setting up the site R library, installing
modulefiles, configuring SLURM integration, and onboarding users.

The container provides R 4.5.0, Bioconductor 3.21, and RStudio Desktop as a
single Apptainer SIF image. R and Rscript run as standard CLI tools. RStudio
Desktop runs as an X11 application (no server daemon, no port binding).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Building the Image](#2-building-the-image)
3. [Deploying the SIF Image](#3-deploying-the-sif-image)
4. [Setting Up the Site R Library](#4-setting-up-the-site-r-library)
5. [Installing Modulefiles](#5-installing-modulefiles)
6. [Bind Mount Configuration](#6-bind-mount-configuration)
7. [SLURM Integration Examples](#7-slurm-integration-examples)
8. [User Onboarding](#8-user-onboarding)
9. [Multi-Version Management](#9-multi-version-management)
10. [Security Considerations](#10-security-considerations)

---

## 1. Prerequisites

### Required Software on the HPC Cluster

| Component | Minimum Version | Purpose |
|-----------|----------------|---------|
| Apptainer | 1.1+ | Container runtime (Singularity 3.8+ also works) |
| Lmod or Environment Modules (Tcl) | Lmod 8.0+ or Tcl modules 4.0+ | Module system for users |
| SLURM | 20.11+ | Job scheduler (PBS/LSF work too with minor adaptation) |

### Required Filesystems

| Path | Type | Capacity | Notes |
|------|------|----------|-------|
| `/apps/biocontainers/images/` | Shared (NFS, GPFS, Lustre) | 5 GB per version | Read by all compute nodes |
| `/apps/biocontainers/extras/` | Shared (NFS, GPFS, Lustre) | 10-50 GB per version | Site R library |
| `/apps/modulefiles/` | Shared | Minimal | Module system path |
| `/scratch/` | High-performance parallel FS | Per-user scratch | TMPDIR target for R sessions |
| `$HOME` | Shared | Per-user | Bound automatically by Apptainer |

### X11 Capabilities (for RStudio Desktop)

RStudio Desktop is a Qt-based X11 application. Users need one of:

- **ThinLinc** remote desktop sessions (recommended)
- **Open OnDemand** interactive desktop app
- **SSH X11 forwarding** (`ssh -X`) -- functional but slow for interactive use
- **VNC** sessions on compute nodes

If your site does not offer graphical sessions, users can still use `R` and
`Rscript` on the command line without X11. Only RStudio Desktop requires a
display.

### Build Machine Requirements (if building with Docker)

If you build the Docker image before converting to SIF, the build machine needs:

- Docker 20.10+ with BuildKit
- 8 GB RAM minimum (16 GB recommended)
- 20 GB free disk space
- Internet access (to pull base image and packages)

The build machine does not need to be a cluster node. A workstation, CI server,
or cloud VM works fine.

---

## 2. Building the Image

There are two methods. Choose based on what software is available.

### Method 1: Build with Docker, Then Convert to SIF (Recommended)

This is the fastest and most reproducible method. Use a build machine that has
Docker installed (a workstation, CI server, or cloud VM).

**Step 1: Clone the repository.**

```bash
git clone https://github.com/YOUR_ORG/bioconductor-hpc-container.git
cd bioconductor-hpc-container
```

**Step 2: Build the Docker image.**

```bash
./scripts/build.sh
```

This reads the `VERSION` file for defaults (Bioconductor 3.21, R 4.5.0, RStudio
2025.05.0-496) and produces the Docker image `bioconductor-hpc:3.21`.

To override versions:

```bash
BIOC_VERSION=3.20 R_VERSION=4.4.2 RSTUDIO_VERSION=2024.12.1-563 ./scripts/build.sh
```

To force a clean rebuild without Docker layer cache:

```bash
./scripts/build.sh --no-cache
```

The build takes 15-30 minutes depending on network speed and CPU.

**Step 3: Run tests.**

```bash
./scripts/test_cli.sh bioconductor-hpc:3.21
./scripts/test_rstudio.sh bioconductor-hpc:3.21
```

All 15 CLI tests and 6 RStudio dependency checks should pass.

**Step 4: Convert to Apptainer SIF.**

If Apptainer is available on the build machine:

```bash
./scripts/build_apptainer.sh
```

This reads from the local Docker daemon and produces
`bioconductor-hpc-3.21.sif` in the repository root.

If Apptainer is NOT on the build machine, export the Docker image as a tarball
and convert on the HPC:

```bash
# On the build machine
docker save bioconductor-hpc:3.21 -o bioconductor-hpc-3.21.tar

# Transfer to HPC
scp bioconductor-hpc-3.21.tar hpc-login:/scratch/$USER/

# On the HPC login node
apptainer build bioconductor-hpc-3.21.sif docker-archive://bioconductor-hpc-3.21.tar
```

**Step 5: Verify the SIF.**

```bash
apptainer exec bioconductor-hpc-3.21.sif R --version
apptainer exec bioconductor-hpc-3.21.sif Rscript -e "BiocManager::version()"
apptainer exec bioconductor-hpc-3.21.sif test -x /usr/lib/rstudio/rstudio && echo "RStudio OK"
```

### Method 2: Build Directly on the HPC from Definition File

Use this when Docker is not available. Requires Apptainer with build privileges
(fakeroot or root) on the HPC.

**Option A: Build from a registry.**

If the Docker image has been pushed to a registry (Docker Hub, GHCR, or a
private registry):

```bash
apptainer build bioconductor-hpc-3.21.sif docker://ghcr.io/YOUR_ORG/bioconductor-hpc:3.21
```

**Option B: Build from the definition file.**

The repository includes `apptainer/apptainer.def` which pulls from a Docker
registry. Edit the `From:` line to point to your registry, then build:

```bash
cd bioconductor-hpc-container

# Edit apptainer/apptainer.def if needed (change the From: line)
# Default: From: bioconductor-hpc:3.21

apptainer build bioconductor-hpc-3.21.sif apptainer/apptainer.def
```

Or use the helper script:

```bash
./scripts/build_apptainer.sh --def
```

**Note on fakeroot:** If your site does not grant fakeroot to users, build the
SIF as root on a dedicated build node or use the `--remote` flag with the
Sylabs Cloud builder:

```bash
apptainer build --remote bioconductor-hpc-3.21.sif apptainer/apptainer.def
```

---

## 3. Deploying the SIF Image

### Place the Image on Shared Storage

The SIF file must be readable by all compute nodes. The recommended path is
`/apps/biocontainers/images/`.

```bash
# Create the directory (once, as root or with sudo)
sudo mkdir -p /apps/biocontainers/images

# Copy the SIF
sudo cp bioconductor-hpc-3.21.sif /apps/biocontainers/images/

# Set permissions: owned by root, read-only for everyone
sudo chown root:root /apps/biocontainers/images/bioconductor-hpc-3.21.sif
sudo chmod 444 /apps/biocontainers/images/bioconductor-hpc-3.21.sif
```

### Verify Accessibility from a Compute Node

```bash
srun --ntasks=1 --time=00:05:00 \
  apptainer exec /apps/biocontainers/images/bioconductor-hpc-3.21.sif R --version
```

### Storage Considerations

| Concern | Guidance |
|---------|----------|
| Image size | A typical SIF is 3-5 GB. Budget 5 GB per Bioconductor version. |
| Filesystem choice | Place on a filesystem with good read throughput (GPFS, Lustre, BeeGFS). NFS works but is slower on first load. |
| Caching | Apptainer caches SIF metadata on first run. The default cache is `~/.apptainer/cache/`. On clusters where `$HOME` is on slow NFS, set `APPTAINER_CACHEDIR` to a faster location. |
| Retention | Keep at least the current and one previous version. Old images can be archived. |
| Integrity | After copying, verify the image: `apptainer verify bioconductor-hpc-3.21.sif` (if signed) or compare `sha256sum` against the build output. |

---

## 4. Setting Up the Site R Library

The site library is a shared directory where HPC admins install R packages that
all users can access. This avoids having every user compile the same packages
independently.

### Create the Site Library Directory

The path must match what the container expects. The container sets `R_LIBS_SITE`
to `/apps/biocontainers/extras/r-package-site-library/<R_major.minor>-bioconductor`.

For R 4.5.x / Bioconductor 3.21:

```bash
sudo mkdir -p /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
```

### Set Permissions

The directory should be:

- **Writable** by the admin group (so admins can install packages)
- **Readable** by all users (so R can load packages from it)

```bash
# Create an admin group if one does not already exist
# (or use your site's existing admin/staff group)
sudo groupadd -f bioc-admins

# Add admin users to the group
sudo usermod -aG bioc-admins adminuser1
sudo usermod -aG bioc-admins adminuser2

# Set ownership and permissions
sudo chown -R root:bioc-admins /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
sudo chmod 2775 /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor

# Set the setgid bit so new files inherit the group
sudo find /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor \
  -type d -exec chmod 2775 {} \;
```

### Pre-Install Packages into the Site Library

Use the container itself to install packages into the site library. This ensures
packages are compiled against the exact same R version and system libraries that
users will run.

**Interactive installation (on a login node):**

```bash
apptainer exec \
  --bind /apps/biocontainers/extras \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
  R
```

Then inside R:

```r
# Verify the site library path is in .libPaths()
.libPaths()
# Should include: /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor

# Install Bioconductor packages into the site library
BiocManager::install(
  c("DESeq2", "edgeR", "SingleCellExperiment", "Seurat",
    "clusterProfiler", "GenomicFeatures", "rtracklayer",
    "VariantAnnotation", "Rsamtools", "BSgenome"),
  lib = "/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor",
  Ncpus = 8
)

# Install CRAN packages into the site library
install.packages(
  c("Seurat", "ggplot2", "pheatmap", "circlize", "ComplexHeatmap"),
  lib = "/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor",
  Ncpus = 8
)
```

**Scripted installation (recommended for reproducibility):**

Create a file `site-packages.R`:

```r
site_lib <- "/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor"

# Bioconductor packages
BiocManager::install(
  c("DESeq2", "edgeR", "SingleCellExperiment", "scran", "scater",
    "GenomicFeatures", "rtracklayer", "VariantAnnotation",
    "Rsamtools", "BSgenome", "clusterProfiler", "org.Hs.eg.db",
    "org.Mm.eg.db", "TxDb.Hsapiens.UCSC.hg38.knownGene"),
  lib = site_lib,
  ask = FALSE,
  Ncpus = 8
)

# CRAN packages
install.packages(
  c("Seurat", "pheatmap", "circlize", "R.utils", "optparse",
    "future", "future.apply", "doParallel", "foreach"),
  lib = site_lib,
  Ncpus = 8
)

cat("Site library installation complete.\n")
cat("Packages installed:", length(list.dirs(site_lib, recursive = FALSE)), "\n")
```

Run it:

```bash
apptainer exec \
  --bind /apps/biocontainers/extras \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
  Rscript site-packages.R
```

For large compilations, submit this as a SLURM job to avoid tying up the login
node:

```bash
srun --cpus-per-task=8 --mem=32G --time=04:00:00 \
  apptainer exec \
    --bind /apps/biocontainers/extras \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    Rscript site-packages.R
```

### Verify the Site Library

```bash
apptainer exec \
  --bind /apps/biocontainers/extras \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
  Rscript -e "cat(.libPaths(), sep='\n'); cat('\nSite packages:', length(installed.packages(lib.loc='/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor')[,1]), '\n')"
```

---

## 5. Installing Modulefiles

The module system lets users load the containerized R/Bioconductor into their
environment with `module load bioconductor`. The modulefile creates shell
functions (Lmod) or aliases (Tcl) that wrap `apptainer exec` calls.

### Using install_module.sh (Recommended)

The provided `install_module.sh` script auto-detects Lmod vs Tcl, performs
variable substitution on the template, and installs the modulefile.

```bash
# Auto-detect module system, install to default path (/apps/modulefiles)
sudo ./scripts/install_module.sh

# Force Lua format (Lmod)
sudo ./scripts/install_module.sh --lua

# Force Tcl format (Environment Modules)
sudo ./scripts/install_module.sh --tcl

# Custom module path
sudo MODULE_PATH=/opt/modulefiles ./scripts/install_module.sh

# Override image location
sudo IMAGE_DIR=/shared/containers/bioconductor ./scripts/install_module.sh
```

The script creates:

- **Lmod:** `/apps/modulefiles/bioconductor/3.21.lua`
- **Tcl:** `/apps/modulefiles/bioconductor/3.21` (plus a `.version` file setting the default)

### Manual Installation for Lmod

If you prefer to install manually:

```bash
# Create the module directory
sudo mkdir -p /apps/modulefiles/bioconductor

# Copy the Lua template and substitute variables
sudo sed \
  -e 's|@@BIOC_VERSION@@|3.21|g' \
  -e 's|@@R_VERSION@@|4.5.0|g' \
  -e 's|@@R_VERSION_SHORT@@|4.5|g' \
  -e 's|@@IMAGE_DIR@@|/apps/biocontainers/images|g' \
  -e 's|@@IMAGE_FILE@@|bioconductor-hpc-3.21.sif|g' \
  templates/modulefile.lua > /apps/modulefiles/bioconductor/3.21.lua
```

### Manual Installation for Tcl

```bash
sudo mkdir -p /apps/modulefiles/bioconductor

sudo sed \
  -e 's|@@BIOC_VERSION@@|3.21|g' \
  -e 's|@@R_VERSION@@|4.5.0|g' \
  -e 's|@@R_VERSION_SHORT@@|4.5|g' \
  -e 's|@@IMAGE_DIR@@|/apps/biocontainers/images|g' \
  -e 's|@@IMAGE_FILE@@|bioconductor-hpc-3.21.sif|g' \
  templates/modulefile.tcl > /apps/modulefiles/bioconductor/3.21

# Set the default version
cat > /apps/modulefiles/bioconductor/.version <<'EOF'
#%Module1.0
set ModulesVersion "3.21"
EOF
```

### Customizing Bind Paths in the Modulefile

After installation, edit the modulefile to add your site-specific bind paths.
In the Lua modulefile, find the `bind_paths` variable:

```lua
local bind_paths = table.concat({
    "/apps/biocontainers/extras",
    "/scratch",
    -- Add your site paths here:
    -- "/data",
    -- "/project",
    -- "/work",
}, ",")
```

In the Tcl modulefile:

```tcl
set bind_paths "/apps/biocontainers/extras,/scratch"
# Change to:
set bind_paths "/apps/biocontainers/extras,/scratch,/data,/project"
```

### Ensure the Module Path is Registered

Verify that `/apps/modulefiles` (or your custom path) is in the module search
path:

```bash
# For Lmod, check MODULEPATH
echo $MODULEPATH

# If /apps/modulefiles is not listed, add it to the system module configuration.
# For Lmod, add to /etc/lmod/modulerc.lua or /apps/lmod/etc/lmodrc.lua:
#   prepend_path("MODULEPATH", "/apps/modulefiles")
#
# For Tcl modules, add to /etc/environment-modules/modulespath:
#   /apps/modulefiles
```

### Testing the Module

```bash
# Verify the module appears
module avail bioconductor

# Expected output:
# ------------ /apps/modulefiles ------------
# bioconductor/3.21

# Load the module
module load bioconductor/3.21

# Expected output:
# Bioconductor 3.21 loaded (R 4.5.0, RStudio Desktop)
#   Commands: R, Rscript, rstudio, bioc-shell

# Check what the module sets
module show bioconductor/3.21

# Test the wrapped commands
R --version
Rscript -e "BiocManager::version()"

# Test bioc-shell (drops into a bash shell inside the container)
bioc-shell -c "cat /etc/os-release"

# Unload
module unload bioconductor
```

---

## 6. Bind Mount Configuration

Apptainer runs with an isolated filesystem by default. Host directories must be
explicitly bound into the container for R to read and write data.

### How Bind Mounts Work

When a user runs `R` via the module, the underlying command is:

```
apptainer exec --bind /apps/biocontainers/extras,/scratch \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif R
```

The `--bind` paths are set in the modulefile. Additionally, the `APPTAINER_BIND`
environment variable adds bind paths globally.

### Required Bind Mounts

| Path | Purpose | Notes |
|------|---------|-------|
| `/apps/biocontainers/extras` | Site R library | Must be bound for shared packages to be visible |
| `/scratch` | Per-job scratch storage | Used as TMPDIR; R writes temp files here |

### Optional Bind Mounts

Add these based on your site's filesystem layout:

| Path | Purpose |
|------|---------|
| `/data` | Shared research data |
| `/project` | Project directories |
| `/work` | User work directories |
| `/reference` | Reference genomes, annotation databases |
| `/bulk` | Large dataset storage |

### Automatic Binds (Apptainer Defaults)

Apptainer automatically binds these without configuration:

- `$HOME` -- user's home directory
- `/tmp` -- temporary files (but we redirect TMPDIR to scratch)
- `/proc`, `/sys`, `/dev` -- system pseudo-filesystems
- `$PWD` -- current working directory

### Configuring APPTAINER_BIND System-Wide

To set bind mounts for all Apptainer invocations on the cluster (not just via
the module), configure `APPTAINER_BIND` in the Apptainer system configuration.

**Option A: Apptainer configuration file.**

Edit `/etc/apptainer/apptainer.conf`:

```
bind path = /apps/biocontainers/extras
bind path = /scratch
bind path = /data
bind path = /project
```

**Option B: Environment variable in the system profile.**

Create `/etc/profile.d/apptainer-binds.sh`:

```bash
export APPTAINER_BIND="/apps/biocontainers/extras,/scratch,/data,/project"
```

**Option C: Per-session via the environment.sh helper.**

The repository includes `apptainer/environment.sh` which can be sourced before
running Apptainer commands. Deploy it to a shared location:

```bash
sudo cp apptainer/environment.sh /apps/biocontainers/environment.sh
```

Users or SLURM scripts source it:

```bash
source /apps/biocontainers/environment.sh
apptainer exec ${APPTAINER_IMAGE} R
```

### Troubleshooting Bind Mounts

If users report "file not found" errors for files that exist on the host:

```bash
# Check what is actually bound inside the container
apptainer exec --bind /apps/biocontainers/extras,/scratch,/data \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
  ls /data/

# Check the effective bind list
apptainer exec --bind /apps/biocontainers/extras,/scratch \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
  cat /proc/mounts | grep -E '(scratch|data|apps)'
```

---

## 7. SLURM Integration Examples

### Interactive R Session

```bash
srun --ntasks=1 --cpus-per-task=4 --mem=16G --time=04:00:00 --pty \
  apptainer exec \
    --bind /apps/biocontainers/extras,/scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    R
```

If the module is loaded, this simplifies to:

```bash
srun --ntasks=1 --cpus-per-task=4 --mem=16G --time=04:00:00 --pty R
```

### Batch Job with Rscript

Create `deseq2_analysis.slurm`:

```bash
#!/bin/bash
#SBATCH --job-name=deseq2
#SBATCH --output=deseq2_%j.out
#SBATCH --error=deseq2_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --partition=compute

# Load the Bioconductor module
module load bioconductor/3.21

# Set TMPDIR to job-specific scratch (cleaned up after job)
export TMPDIR=/scratch/${USER}/slurm_${SLURM_JOB_ID}
mkdir -p ${TMPDIR}

# Run the analysis
Rscript analysis/deseq2_pipeline.R \
  --input data/counts.csv \
  --output results/deseq2_results.csv \
  --threads ${SLURM_CPUS_PER_TASK}

# Clean up
rm -rf ${TMPDIR}
```

Submit:

```bash
sbatch deseq2_analysis.slurm
```

Without using the module system (calling Apptainer directly):

```bash
#!/bin/bash
#SBATCH --job-name=deseq2
#SBATCH --output=deseq2_%j.out
#SBATCH --error=deseq2_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00

export TMPDIR=/scratch/${USER}/slurm_${SLURM_JOB_ID}
mkdir -p ${TMPDIR}

apptainer exec \
  --bind /apps/biocontainers/extras,/scratch,/data \
  /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
  Rscript analysis/deseq2_pipeline.R \
    --input /data/rnaseq/counts.csv \
    --output results/deseq2_results.csv \
    --threads ${SLURM_CPUS_PER_TASK}

rm -rf ${TMPDIR}
```

### Interactive Desktop Job (for RStudio Desktop)

RStudio Desktop requires an X11 display. There are several ways to provide one.

**Option A: ThinLinc or Open OnDemand desktop session.**

From within a ThinLinc or OOD desktop session, open a terminal and run:

```bash
module load bioconductor/3.21
srun --ntasks=1 --cpus-per-task=4 --mem=16G --time=08:00:00 --x11 --pty rstudio
```

The `--x11` flag forwards the X11 display from the compute node back to the
login node's X server.

**Option B: Direct SLURM interactive job with X11 forwarding.**

Requires `ssh -X` from the user's workstation to the login node, and SLURM
configured with X11 forwarding support (`PrologFlags=X11` in `slurm.conf`):

```bash
srun --ntasks=1 --cpus-per-task=4 --mem=16G --time=08:00:00 --x11 --pty \
  apptainer exec \
    --bind /apps/biocontainers/extras,/scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    launch-rstudio
```

**Option C: SLURM batch job that starts a VNC session.**

For sites with VNC infrastructure. This is a more complex setup -- contact HPC
support for site-specific instructions.

### Resource Allocation Recommendations

| Workload | CPUs | Memory | Time | Notes |
|----------|------|--------|------|-------|
| Interactive R (exploration) | 2-4 | 8-16 GB | 2-4 hours | Light analysis, plotting |
| RNA-seq differential expression (DESeq2, edgeR) | 4-8 | 16-32 GB | 1-4 hours | Memory scales with sample count |
| Single-cell RNA-seq (Seurat, scran) | 8-16 | 64-128 GB | 4-12 hours | Memory-intensive; 128 GB for >100K cells |
| Variant calling pipeline | 8-16 | 32-64 GB | 2-8 hours | I/O bound; place data on fast FS |
| RStudio Desktop (interactive) | 4 | 16 GB | 4-8 hours | Adjust up based on dataset size |
| Package installation (site library) | 8 | 32 GB | 2-4 hours | Compilation is CPU+memory intensive |

### BiocParallel Configuration for SLURM

R scripts using BiocParallel should detect SLURM resources automatically because
the container's `Rprofile.site` reads `SLURM_CPUS_PER_TASK`. Users can also
configure it explicitly:

```r
library(BiocParallel)

# Automatically use SLURM-allocated cores
ncores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1"))
register(MulticoreParam(workers = ncores))
```

---

## 8. User Onboarding

### What Users Need to Know

Provide users with this summary (adapt for your site):

> **Bioconductor on the HPC**
>
> We provide R 4.5.0 with Bioconductor 3.21 and RStudio Desktop as a
> container module. Your personal R packages are stored in your home
> directory, separate from the system installation.
>
> **Quick start:**
> ```
> module load bioconductor/3.21
> R                          # Interactive R session
> Rscript my_script.R        # Run a script
> rstudio                    # Launch RStudio (needs desktop session)
> ```
>
> **Install packages:** Inside R, use `BiocManager::install("PackageName")` for
> Bioconductor packages or `install.packages("PackageName")` for CRAN packages.
> They install to your personal library automatically.

### Sample .bashrc Additions

Users do NOT need to modify `.bashrc` for basic usage. The module handles
everything. However, some users prefer to auto-load the module:

```bash
# Add to ~/.bashrc (optional)
module load bioconductor/3.21
```

For users who work with multiple R versions or want to avoid automatic loading,
recommend using the module explicitly in job scripts instead.

### First-Time R Library Creation

The first time a user runs R after loading the module, the container
automatically creates their personal library directory at:

```
~/R/x86_64-pc-linux-gnu-library/4.5/
```

This is handled by the container's `Rprofile.site`. Users do not need to create
this directory manually. If they are prompted "Would you like to create a
personal library?", it means the automatic creation failed (likely a permissions
issue with their home directory). The fix is:

```bash
mkdir -p ~/R/x86_64-pc-linux-gnu-library/4.5
```

### User Package Installation

Users install packages into their personal library. This requires no special
privileges:

```r
# CRAN packages
install.packages("ggrepel")

# Bioconductor packages
BiocManager::install("DESeq2")

# GitHub packages
remotes::install_github("satijalab/seurat")
```

Some packages require compilation. The container includes development headers
for all common dependencies (libcurl, libxml2, libhdf5, libfftw3, libgsl, etc.).
If a user encounters a missing system library during compilation, the admin
should rebuild the container image with the additional `-dev` package.

### Checking Available Packages

Users can check what is already installed in the container and site library:

```r
# All available packages (container + site + personal)
installed.packages()[, c("Package", "Version", "LibPath")]

# Just site library packages
installed.packages(lib.loc = "/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor")[, "Package"]
```

---

## 9. Multi-Version Management

### Running Multiple Bioconductor Versions Side by Side

Each Bioconductor release gets its own:

- SIF image: `/apps/biocontainers/images/bioconductor-hpc-<version>.sif`
- Site library: `/apps/biocontainers/extras/r-package-site-library/<R_version>-bioconductor/`
- Module version: `bioconductor/<version>`

Example directory layout for two versions:

```
/apps/biocontainers/
  images/
    bioconductor-hpc-3.20.sif      # Bioconductor 3.20 / R 4.4
    bioconductor-hpc-3.21.sif      # Bioconductor 3.21 / R 4.5
  extras/
    r-package-site-library/
      4.4-bioconductor/            # Site packages for Bioc 3.20
      4.5-bioconductor/            # Site packages for Bioc 3.21

/apps/modulefiles/
  bioconductor/
    3.20.lua                       # (or 3.20 for Tcl)
    3.21.lua                       # (or 3.21 for Tcl)
```

### Building and Deploying a Second Version

```bash
# Build the older version
BIOC_VERSION=3.20 R_VERSION=4.4.2 RSTUDIO_VERSION=2024.12.1-563 ./scripts/build.sh
BIOC_VERSION=3.20 R_VERSION=4.4.2 ./scripts/build_apptainer.sh

# Deploy the SIF
sudo cp bioconductor-hpc-3.20.sif /apps/biocontainers/images/
sudo chown root:root /apps/biocontainers/images/bioconductor-hpc-3.20.sif
sudo chmod 444 /apps/biocontainers/images/bioconductor-hpc-3.20.sif

# Create the site library for the older version
sudo mkdir -p /apps/biocontainers/extras/r-package-site-library/4.4-bioconductor
sudo chown -R root:bioc-admins /apps/biocontainers/extras/r-package-site-library/4.4-bioconductor
sudo chmod 2775 /apps/biocontainers/extras/r-package-site-library/4.4-bioconductor

# Install the modulefile for the older version
sudo BIOC_VERSION=3.20 R_VERSION=4.4.2 ./scripts/install_module.sh
```

### Module Version Switching

Users switch between versions with standard module commands:

```bash
# See available versions
module avail bioconductor

# Load a specific version
module load bioconductor/3.21

# Switch versions (swap)
module swap bioconductor/3.21 bioconductor/3.20
# Or with Lmod shorthand:
module load bioconductor/3.20   # Lmod auto-swaps conflicting modules

# Check which version is loaded
module list
R -e "BiocManager::version()"
```

### Library Isolation Between Versions

Libraries are isolated by the R major.minor version in the path:

- Bioconductor 3.21 / R 4.5 uses `~/R/x86_64-pc-linux-gnu-library/4.5/`
- Bioconductor 3.20 / R 4.4 uses `~/R/x86_64-pc-linux-gnu-library/4.4/`

Because R enforces that packages compiled for one major.minor version cannot be
loaded by another, users' personal libraries are inherently isolated. They do not
need to do anything special.

The modulefile sets `conflict("bioconductor")` and `conflict("R")`, which
prevents loading two versions simultaneously.

### Setting a Default Version

**For Lmod:** Lmod uses the highest version number as the default unless
overridden. To set an explicit default, create a `.modulerc.lua` file:

```bash
cat > /apps/modulefiles/bioconductor/.modulerc.lua <<'EOF'
module_version("bioconductor/3.21", "default")
EOF
```

**For Tcl:** The `install_module.sh` script creates a `.version` file
automatically. To change the default:

```bash
cat > /apps/modulefiles/bioconductor/.version <<'EOF'
#%Module1.0
set ModulesVersion "3.21"
EOF
```

### Retiring Old Versions

When retiring an old Bioconductor version:

1. Notify users with a deprecation notice (set in the modulefile help text).
2. Keep the image and module available for at least one release cycle (6 months).
3. Remove the modulefile first; keep the SIF and site library for users who may
   reference them directly.
4. Archive the SIF to tape/cold storage before deleting from disk.

---

## 10. Security Considerations

### Read-Only Images

SIF files are read-only squashfs filesystems. Once built, the image cannot be
modified. This provides:

- **Tamper resistance:** Users cannot install system packages, modify binaries,
  or alter the container OS.
- **Reproducibility:** Every execution uses the identical software stack.
- **Auditability:** The Dockerfile and build scripts in the repository define
  exactly what is in the image.

Set file permissions to `444` (read-only) so even root cannot accidentally
overwrite the image:

```bash
sudo chmod 444 /apps/biocontainers/images/bioconductor-hpc-3.21.sif
```

### No Setuid

Apptainer runs in rootless (non-setuid) mode by default in modern versions
(1.1+). Verify your installation:

```bash
apptainer buildcfg | grep 'without suid'
# Expected: --without-suid
```

If your site still uses setuid Apptainer/Singularity, consider upgrading.
Non-setuid mode means:

- The container process runs entirely as the calling user.
- There is no privilege escalation path through the container runtime.
- No root-owned setuid binary is involved in execution.

### UID/GID Passthrough

Apptainer maps the host user's UID and GID into the container. Inside the
container:

- The user is the same UID as on the host.
- File ownership and permissions are enforced by the host kernel.
- There is no user namespace remapping (unless explicitly configured).
- Files created inside bind-mounted directories are owned by the host UID.

This means:

- Users cannot access other users' files via the container.
- File permissions on `/scratch`, `/data`, etc. are enforced normally.
- The container does not create files owned by root or other users.

Verify UID passthrough:

```bash
apptainer exec /apps/biocontainers/images/bioconductor-hpc-3.21.sif id
# Should match the output of `id` on the host
```

### Network Isolation

By default, Apptainer shares the host network namespace. The container has the
same network access as the user's shell. This is appropriate for:

- Downloading R packages from CRAN/Bioconductor mirrors.
- Accessing data APIs.

If your security policy requires network restriction, you can use Apptainer's
`--net` and `--network` flags or rely on the host firewall/iptables rules that
already apply to compute nodes.

The container does NOT run any network services. There is no RStudio Server, no
Shiny Server, no listening ports. RStudio Desktop is a local X11 application.

### Additional Hardening

**Disable container overlay and writable mode.**

In `/etc/apptainer/apptainer.conf`:

```
enable overlay = no
```

This prevents users from creating writable overlays on top of the read-only
image.

**Limit bind paths.**

If you do not want users to bind arbitrary host paths into the container, set
in `/etc/apptainer/apptainer.conf`:

```
mount hostfs = no
```

And use `bind path` directives to allow only specific directories.

**Restrict image sources.**

To prevent users from running untrusted container images, configure Apptainer's
ECL (Execution Control List) to only allow images signed by your organization
or located under `/apps/`:

```
allow container sif = yes
allow container encrypted = no
allow container dir = no
allow container squashfs = no
```

**Audit trail.**

Apptainer operations appear in the system audit log. All `apptainer exec` calls
run as the user's UID and are visible in process accounting. SLURM job logs
provide additional traceability for batch jobs.

---

## Appendix: File Reference

| Repository Path | Deployed Location | Purpose |
|----------------|-------------------|---------|
| `Dockerfile` | (used at build time) | Defines the container contents |
| `apptainer/apptainer.def` | (used at build time) | Apptainer definition file for direct builds |
| `apptainer/environment.sh` | `/apps/biocontainers/environment.sh` | Shell helper for setting bind mounts |
| `scripts/build.sh` | (admin tool) | Builds the Docker image |
| `scripts/build_apptainer.sh` | (admin tool) | Converts Docker image to SIF |
| `scripts/install_module.sh` | (admin tool) | Installs modulefile from template |
| `scripts/test_cli.sh` | (admin tool) | Tests container CLI functionality |
| `scripts/test_rstudio.sh` | (admin tool) | Tests RStudio dependencies |
| `templates/modulefile.lua` | `/apps/modulefiles/bioconductor/3.21.lua` | Lmod modulefile template |
| `templates/modulefile.tcl` | `/apps/modulefiles/bioconductor/3.21` | Tcl modulefile template |
| `env/renviron.site` | `/usr/local/lib/R/etc/Renviron.site` (inside image) | R environment variables |
| `env/rprofile.site` | `/usr/local/lib/R/etc/Rprofile.site` (inside image) | R startup code |
| `env/profile.d/bioc.sh` | `/etc/profile.d/bioc.sh` (inside image) | Shell environment for login shells |
| `scripts/launch_rstudio.sh` | `/usr/local/bin/launch-rstudio` (inside image) | RStudio Desktop launcher |

## Appendix: Quick Deployment Checklist

```
[ ] Build Docker image: ./scripts/build.sh
[ ] Run tests: ./scripts/test_cli.sh && ./scripts/test_rstudio.sh
[ ] Convert to SIF: ./scripts/build_apptainer.sh
[ ] Copy SIF to /apps/biocontainers/images/
[ ] Set SIF permissions: chmod 444
[ ] Create site library directory under /apps/biocontainers/extras/
[ ] Set site library permissions: chmod 2775, owned by bioc-admins group
[ ] Install site packages via container Rscript
[ ] Install modulefile: ./scripts/install_module.sh
[ ] Edit modulefile bind paths for your site
[ ] Test: module avail bioconductor
[ ] Test: module load bioconductor/3.21 && R --version
[ ] Test: srun R -e "BiocManager::version()" (on a compute node)
[ ] Test: srun --x11 rstudio (in a desktop session)
[ ] Notify users
```
