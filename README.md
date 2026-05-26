# Bioconductor HPC Container

A production-ready container for running [Bioconductor](https://bioconductor.org)
with RStudio Desktop on HPC clusters via Apptainer/Singularity.

## Overview

This repository builds a container image that provides:

- **R** with full Bioconductor infrastructure
- **RStudio Desktop** (not Server) for interactive GUI analysis
- **HPC-native design**: works with SLURM, modules, ThinLinc, Open OnDemand
- **Clean package management**: layered user/site/container libraries

The image is designed to be deployed as a read-only Apptainer SIF file,
with user-installed R packages stored on the host filesystem.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    HPC Compute Node                     │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Apptainer Container (SIF)             │  │
│  │                   (read-only)                      │  │
│  │                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │ R 4.5.0      │  │ RStudio      │               │  │
│  │  │ BiocManager  │  │ Desktop      │               │  │
│  │  │ Core pkgs    │  │ (X11 app)    │               │  │
│  │  └──────────────┘  └──────────────┘               │  │
│  │                                                    │  │
│  │  R_HOME/library ← base R packages (in container)  │  │
│  └──────────┬──────────────────────────┬──────────────┘  │
│             │ bind mount               │ bind mount      │
│  ┌──────────▼──────────┐  ┌────────────▼─────────────┐  │
│  │  ~/R/.../4.5/       │  │  /apps/.../4.5-bioc/     │  │
│  │  (user library)     │  │  (site library)          │  │
│  │  per-user, writable │  │  shared, admin-managed   │  │
│  └─────────────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Why Not RStudio Server on HPC?

RStudio Server is a multi-user web application that:

- Runs as a **daemon** — conflicts with HPC job schedulers
- **Binds network ports** — security risk on shared compute nodes
- **Manages its own authentication** — conflicts with HPC auth (LDAP, Kerberos)
- Assumes it **controls user sessions** — breaks under container isolation

RStudio Desktop is a normal X11 application. It:

- Runs as the **user's process** — works with SLURM, PBS, LSF
- Requires **no ports or daemons** — just an X11 display
- Uses the **host's authentication** — no extra auth layer
- Works with **ThinLinc, Open OnDemand, and X11 forwarding**

### Two-Layer Design

```
┌──────────────────────────────────────┐
│         Layer 2: HPC Overlay         │
│  ┌─────────────┐ ┌────────────────┐  │
│  │ Bioconductor │ │ RStudio Desktop│  │
│  │ BiocManager  │ │ Qt/X11 libs    │  │
│  │ Core pkgs    │ │ launch-rstudio │  │
│  └─────────────┘ └────────────────┘  │
│  R library paths, Renviron, Rprofile │
├──────────────────────────────────────┤
│         Layer 1: rocker/r-ver        │
│  R, build tools, CRAN mirror config  │
│  Ubuntu, system libraries            │
└──────────────────────────────────────┘
```

**Why rocker/r-ver instead of bioconductor_docker?**

The official `bioconductor/bioconductor_docker` inherits from `rocker/rstudio`,
which bundles RStudio Server. Starting from `rocker/r-ver` gives us the same R
installation without server infrastructure to strip out.

## Quick Start

### Build

```bash
# Clone the repository
git clone https://github.com/YOUR_ORG/bioconductor-hpc-container.git
cd bioconductor-hpc-container

# Build Docker image
make build

# Run tests
make test

# Convert to Apptainer SIF
make apptainer
```

### Use

```bash
# Interactive R session
apptainer exec bioconductor-hpc-3.21.sif R

# Run a script
apptainer exec bioconductor-hpc-3.21.sif Rscript analysis.R

# Launch RStudio Desktop (requires X11)
apptainer exec bioconductor-hpc-3.21.sif launch-rstudio
```

### With Modules

```bash
module load bioconductor/3.21

R                      # Interactive R
Rscript script.R       # Run a script
rstudio                # Launch RStudio Desktop
bioc-shell             # Shell inside the container
```

## Version Configuration

All versions are controlled by the `VERSION` file:

```
BIOC_VERSION=3.21
R_VERSION=4.5.0
UBUNTU_VERSION=noble
RSTUDIO_VERSION=2025.05.0-496
```

To build with different versions, either edit `VERSION` or override via
environment:

```bash
BIOC_VERSION=3.20 R_VERSION=4.4.2 make build
```

Check available upstream versions:

```bash
make versions
```

## Docker Build

### Prerequisites

- Docker 20.10+ (or Podman)
- ~10 GB disk space for the build
- Internet access (to download R packages)

### Build Commands

```bash
# Default build (uses VERSION file)
make build

# Build without cache (full rebuild)
make build-no-cache

# Build with specific versions
BIOC_VERSION=3.20 R_VERSION=4.4.2 make build

# Build directly with docker
docker build \
    --build-arg R_VERSION=4.5.0 \
    --build-arg BIOC_VERSION=3.21 \
    --build-arg RSTUDIO_VERSION=2025.05.0-496 \
    -t bioconductor-hpc:3.21 .
```

### Testing the Docker Image

```bash
# CLI tests
make test

# RStudio dependency checks
make test-rstudio

# All tests
make test-all

# Manual verification
docker run --rm bioconductor-hpc:3.21 R --version
docker run --rm bioconductor-hpc:3.21 Rscript -e "BiocManager::version()"
docker run --rm bioconductor-hpc:3.21 Rscript -e "library(GenomicRanges)"
```

## Apptainer Conversion

### Method 1: From Docker Daemon (recommended)

Requires Docker on the build machine. Fastest method.

```bash
# Using the helper script
make apptainer

# Or directly
apptainer build bioconductor-hpc-3.21.sif docker-daemon://bioconductor-hpc:3.21
```

### Method 2: From Definition File

For HPC systems without Docker (e.g., login nodes).

```bash
# Using the helper script
make apptainer-def

# Or directly
apptainer build bioconductor-hpc-3.21.sif apptainer/apptainer.def
```

### Method 3: From Docker Registry

If the image is pushed to a registry:

```bash
apptainer build bioconductor-hpc-3.21.sif docker://registry.example.com/bioconductor-hpc:3.21
```

### Testing the SIF Image

```bash
# CLI tests
./scripts/test_cli.sh --apptainer bioconductor-hpc-3.21.sif

# Manual verification
apptainer exec bioconductor-hpc-3.21.sif R --version
apptainer exec bioconductor-hpc-3.21.sif Rscript -e "library(GenomicRanges)"
apptainer shell bioconductor-hpc-3.21.sif
```

## HPC Deployment

### 1. Deploy the Image

```bash
# Copy SIF to shared storage
sudo cp bioconductor-hpc-3.21.sif /apps/biocontainers/images/
sudo chmod 644 /apps/biocontainers/images/bioconductor-hpc-3.21.sif
```

### 2. Create the Site Library

```bash
sudo mkdir -p /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
sudo chmod 2775 /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
sudo chgrp biocontainer-admins /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
```

### 3. Install the Modulefile

```bash
# Auto-detect Lmod vs Tcl
sudo ./scripts/install_module.sh

# Or specify
sudo ./scripts/install_module.sh --lua --module-path /apps/modulefiles
```

### 4. Test

```bash
module load bioconductor/3.21
R --version
Rscript -e "BiocManager::version()"
```

See [docs/deployment.md](docs/deployment.md) for detailed deployment instructions.

## Module Setup

The module system provides `R`, `Rscript`, `rstudio`, and `bioc-shell` commands
that transparently invoke Apptainer.

### Lmod (Lua)

```bash
# Install
sudo ./scripts/install_module.sh --lua

# Verify
module avail bioconductor
module load bioconductor/3.21
module show bioconductor/3.21
```

### Tcl Modules

```bash
# Install
sudo ./scripts/install_module.sh --tcl

# Verify
module avail bioconductor
module load bioconductor/3.21
```

### Module Commands

After `module load bioconductor/3.21`:

| Command | Description |
|---------|-------------|
| `R` | Interactive R session |
| `Rscript` | Run R scripts |
| `rstudio` | Launch RStudio Desktop (needs X11) |
| `bioc-shell` | Bash shell inside the container |

### Customizing Bind Mounts

Edit the modulefile to add your site's data filesystems:

```lua
-- In the Lmod modulefile
local bind_paths = table.concat({
    "/apps/biocontainers/extras",
    "/scratch",
    "/data",        -- Add your data mount
    "/project",     -- Add your project mount
}, ",")
```

## Package Libraries

### Resolution Order

R searches for packages in this order:

```
1. R_LIBS_USER  →  ~/R/x86_64-pc-linux-gnu-library/4.5     (user, writable)
2. R_LIBS_SITE  →  /apps/.../4.5-bioconductor               (shared, read-only for users)
3. R_HOME/lib   →  /usr/local/lib/R/library                  (container, read-only)
```

User-installed packages override site packages, which override container packages.

### Installing Packages (Users)

```r
# CRAN packages
install.packages("Seurat")

# Bioconductor packages
BiocManager::install("DESeq2")

# Packages install to ~/R/x86_64-pc-linux-gnu-library/4.5
```

### Installing Site Packages (Admins)

```bash
# Install packages into the shared site library
apptainer exec \
    --bind /apps/biocontainers/extras \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    Rscript -e "
        install.packages('Seurat',
            lib = '/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor')
    "
```

### Important Notes

- The container filesystem is **read-only** under Apptainer
- Users **cannot** modify packages inside the container
- All user installs go to `~/R/.../4.5/` on the host filesystem
- Site installs go to the bind-mounted shared directory
- No writes occur inside the container

## ThinLinc Usage

ThinLinc provides remote desktop sessions. RStudio Desktop runs as a normal
window in the ThinLinc desktop.

```bash
# 1. Connect to HPC via ThinLinc client
# 2. Open a terminal
# 3. Load the module and launch RStudio

module load bioconductor/3.21
rstudio
```

For compute-intensive work, submit to a compute node:

```bash
srun --x11 --cpus-per-task=8 --mem=32G --time=4:00:00 \
    apptainer exec \
    --bind /apps/biocontainers/extras,/scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    launch-rstudio
```

See [docs/thinlinc_example.md](docs/thinlinc_example.md) for details.

## Open OnDemand Usage

Open OnDemand can launch RStudio Desktop in two ways:

1. **Interactive Desktop**: Launch an OOD desktop, then run RStudio from
   a terminal (simplest, no OOD app development needed)
2. **Custom Interactive App**: A dedicated OOD app form for RStudio
   (polished user experience, requires OOD app configuration)

See [docs/ood_example.md](docs/ood_example.md) for complete OOD app
configuration including `form.yml`, `submit.yml.erb`, and launch scripts.

## SLURM Examples

### Interactive R Session

```bash
srun --cpus-per-task=4 --mem=16G --time=2:00:00 --pty \
    apptainer exec \
    --bind /apps/biocontainers/extras,/scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    R
```

### Batch R Script

```bash
#!/bin/bash
#SBATCH --job-name=bioc-analysis
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=8:00:00
#SBATCH --output=analysis_%j.log

# Redirect temp files to scratch
export TMPDIR="/scratch/${USER}/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"

# Run analysis
apptainer exec \
    --bind /apps/biocontainers/extras \
    --bind /scratch \
    /apps/biocontainers/images/bioconductor-hpc-3.21.sif \
    Rscript analysis.R

# Clean up temp files
rm -rf "${TMPDIR}"
```

### BiocParallel with SLURM

```r
library(BiocParallel)

# Use SLURM-allocated cores
ncores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1"))
register(MulticoreParam(workers = ncores))

# Your parallel analysis
results <- bplapply(data_list, process_function)
```

## Upgrade Workflow

Upgrading to a new Bioconductor release requires changing 2-3 variables:

```bash
# 1. Check available versions
make versions

# 2. Edit VERSION file
#    BIOC_VERSION=3.22
#    R_VERSION=4.6.0
#    RSTUDIO_VERSION=<latest>

# 3. Rebuild and test
make build
make test-all

# 4. Convert and deploy
make apptainer
sudo cp bioconductor-hpc-3.22.sif /apps/biocontainers/images/
sudo ./scripts/install_module.sh

# 5. Create new site library
sudo mkdir -p /apps/biocontainers/extras/r-package-site-library/4.6-bioconductor
```

See [docs/updating.md](docs/updating.md) for the complete upgrade procedure.

## Troubleshooting

### RStudio Desktop Won't Start

```bash
# Check DISPLAY is set
echo $DISPLAY

# Test X11 connectivity
xterm &

# Try with explicit Qt settings
QT_X11_NO_MITSHM=1 QT_QPA_PLATFORM=xcb \
    apptainer exec bioconductor-hpc-3.21.sif launch-rstudio
```

### Package Installation Fails

```bash
# Verify user library directory exists
ls -la ~/R/x86_64-pc-linux-gnu-library/4.5/

# Create if missing
mkdir -p ~/R/x86_64-pc-linux-gnu-library/4.5

# Verify bind mounts include the site library
apptainer exec --bind /apps/biocontainers/extras ...
```

### /tmp Full During Analysis

```bash
# Set TMPDIR to scratch before running
export TMPDIR=/scratch/$USER/tmp
mkdir -p $TMPDIR
apptainer exec ... Rscript analysis.R
```

### Missing Shared Libraries

```bash
# Check what's missing
apptainer exec bioconductor-hpc-3.21.sif ldd /usr/lib/rstudio/rstudio | grep "not found"
```

See [docs/troubleshooting.md](docs/troubleshooting.md) for comprehensive
troubleshooting guidance.

## Security Considerations

- The SIF image is **read-only** — it cannot be modified at runtime
- Apptainer runs as the **invoking user** (no root, no setuid by default)
- **No network services** run inside the container (no listening ports)
- **No daemons** — everything runs as foreground processes
- UID/GID from the host are **passed through** — file permissions work normally
- Sensitive data (home directories, project files) is accessed via bind mounts
  with the user's own permissions

## Performance Considerations

- **TMPDIR**: Always redirect to scratch storage for data-intensive workflows.
  The default `/tmp` is often a small tmpfs that will fill during scRNA-seq or
  genome-scale analyses.
- **Memory**: R holds data in memory. Request sufficient SLURM memory for your
  dataset. Common sizes: 16 GB for small analyses, 32-64 GB for scRNA-seq,
  128+ GB for large genome assemblies.
- **Parallelism**: Use `BiocParallel::MulticoreParam()` with `SLURM_CPUS_PER_TASK`
  to match the allocated core count.
- **I/O**: Avoid reading/writing large files to NFS home directories in tight
  loops. Use scratch or local SSD (`/tmp` on some clusters) for intermediate
  files, then copy final results to permanent storage.

## Maintenance Philosophy

This repository is designed for **minimal-touch maintenance** across Bioconductor
release cycles:

1. **Version changes are centralized** in the `VERSION` file
2. **Upstream inheritance** means we get R and Ubuntu updates from rocker
3. **Bioconductor is installed via BiocManager**, not baked in — the version
   is controlled by a single variable
4. **No forking of upstream images** — we layer on top, not replace
5. **Scripts are parameterized** — they read from `VERSION`, not hardcoded values

The expected maintenance cadence is:
- **Every 6 months**: Update for new Bioconductor release (change 2-3 variables)
- **As needed**: Update RStudio Desktop version
- **Rarely**: Modify system dependencies (only when Bioconductor adds new
  package types that need system libraries)

## Repository Structure

```
.
├── README.md                  # This file
├── LICENSE                    # MIT License
├── .gitignore                 # Git ignore patterns
├── Dockerfile                 # Docker build definition
├── Makefile                   # Build automation
├── VERSION                    # Version configuration
├── scripts/
│   ├── build.sh               # Docker build script
│   ├── build_apptainer.sh     # Apptainer conversion
│   ├── test_cli.sh            # CLI test suite
│   ├── test_rstudio.sh        # RStudio dependency checks
│   ├── launch_rstudio.sh      # RStudio launcher (inside container)
│   ├── install_module.sh      # Module deployment
│   └── detect_versions.sh     # Upstream version checker
├── modulefiles/
│   └── bioconductor           # Example Tcl modulefile
├── apptainer/
│   ├── apptainer.def          # Apptainer definition file
│   └── environment.sh         # Host environment setup
├── env/
│   ├── renviron.site          # R environment variables
│   ├── rprofile.site          # R startup code
│   └── profile.d/
│       └── bioc.sh            # Shell environment
├── docs/
│   ├── architecture.md        # Architecture rationale
│   ├── deployment.md          # HPC deployment guide
│   ├── updating.md            # Upgrade procedures
│   ├── ood_example.md         # Open OnDemand integration
│   ├── thinlinc_example.md    # ThinLinc integration
│   └── troubleshooting.md     # Problem resolution
├── templates/
│   ├── modulefile.tcl         # Tcl modulefile template
│   └── modulefile.lua         # Lmod modulefile template
└── .github/
    └── workflows/
        └── build.yml          # CI/CD pipeline
```

## License

MIT License. See [LICENSE](LICENSE).
