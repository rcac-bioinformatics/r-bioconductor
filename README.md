# Bioconductor HPC Container

A production-ready container for running [Bioconductor](https://bioconductor.org)
with RStudio Desktop on HPC clusters via Apptainer/Singularity.

## Overview

This repository builds a container image that provides:

- **R** with full Bioconductor infrastructure and system dependencies
- **RStudio Desktop** (not Server) for interactive GUI analysis
- **HPC-native design**: works with SLURM, modules, ThinLinc, Open OnDemand
- **Clean package management**: layered user/site/container libraries
- **Full Bioconductor compatibility**: all system libraries from `bioc_full`
  are included so any Bioconductor package can be compiled by users

The image is designed to be deployed as a read-only Apptainer SIF file,
with user-installed R packages stored on the host filesystem.

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│                    HPC Compute Node                     │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Apptainer Container (SIF)             │  │
│  │                   (read-only)                      │  │
│  │                                                    │  │
│  │  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │ R 4.6.0      │  │ RStudio      │               │  │
│  │  │ BiocManager  │  │ Desktop      │               │  │
│  │  │ Core pkgs    │  │ (X11 app)    │               │  │
│  │  └──────────────┘  └──────────────┘               │  │
│  │                                                    │  │
│  │  R_HOME/library ← base R packages (in container)  │  │
│  └──────────┬──────────────────────────┬──────────────┘  │
│             │ bind mount               │ bind mount      │
│  ┌──────────▼──────────┐  ┌────────────▼─────────────┐  │
│  │  ~/R/.../4.6/       │  │  /apps/.../4.6-bioc/     │  │
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

```text
┌──────────────────────────────────────┐
│         Layer 2: HPC Overlay         │
│  ┌─────────────┐ ┌────────────────┐  │
│  │ Bioconductor │ │ RStudio Desktop│  │
│  │ BiocManager  │ │ Qt/X11 libs    │  │
│  │ bioc_full    │ │ launch-rstudio │  │
│  │ sys deps     │ │                │  │
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
installation without server infrastructure to strip out. The full set of
Bioconductor system dependencies (from the official `bioc_full` script) is
installed in the Dockerfile, so any Bioconductor package can be compiled.

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
apptainer exec r-bioconductor_3.23-R-4.6.0.sif R

# Run a script
apptainer exec r-bioconductor_3.23-R-4.6.0.sif Rscript analysis.R

# Launch RStudio Desktop (requires X11)
apptainer exec r-bioconductor_3.23-R-4.6.0.sif rstudio --no-sandbox
```

### With Modules

```bash
module load bioconductor/3.23

R                      # Interactive R
Rscript script.R       # Run a script
rstudio                # Launch RStudio Desktop
```

The module automatically loads the Singularity/Apptainer module, detects
GPUs, clears host compiler variables, and sets safe thread defaults.

## Version Configuration

All versions are controlled by the `VERSION` file:

```ini
BIOC_VERSION=3.23
R_VERSION=4.6.0
UBUNTU_VERSION=noble
RSTUDIO_VERSION=2026.05.0-218
```

To build with different versions, either edit `VERSION` or override via
environment:

```bash
BIOC_VERSION=3.22 R_VERSION=4.5.1 make build
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
BIOC_VERSION=3.22 R_VERSION=4.5.1 make build

# Build directly with docker
docker build \
    --build-arg R_VERSION=4.6.0 \
    --build-arg R_VERSION_SHORT=4.6 \
    --build-arg BIOC_VERSION=3.23 \
    --build-arg RSTUDIO_VERSION=2026.05.0-218 \
    -t bioconductor-hpc:3.23 .
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
docker run --rm bioconductor-hpc:3.23 R --version
docker run --rm bioconductor-hpc:3.23 Rscript -e "BiocManager::version()"
docker run --rm bioconductor-hpc:3.23 Rscript -e "library(GenomicRanges)"
```

## Apptainer Conversion

### Method 1: From Docker Daemon (recommended)

Requires Docker on the build machine. Fastest method.

```bash
# Using the helper script
make apptainer

# Or directly
apptainer build r-bioconductor_3.23-R-4.6.0.sif docker-daemon://bioconductor-hpc:3.23
```

### Method 2: From Definition File

For HPC systems without Docker (e.g., login nodes).

```bash
# Using the helper script
make apptainer-def

# Or directly
apptainer build r-bioconductor_3.23-R-4.6.0.sif apptainer/apptainer.def
```

### Method 3: From Docker Registry

If the image is pushed to a registry:

```bash
apptainer build r-bioconductor_3.23-R-4.6.0.sif docker://registry.example.com/bioconductor-hpc:3.23
```

### Testing the SIF Image

```bash
# CLI tests
./scripts/test_cli.sh --apptainer r-bioconductor_3.23-R-4.6.0.sif

# Manual verification
apptainer exec r-bioconductor_3.23-R-4.6.0.sif R --version
apptainer exec r-bioconductor_3.23-R-4.6.0.sif Rscript -e "library(GenomicRanges)"
apptainer shell r-bioconductor_3.23-R-4.6.0.sif
```

## HPC Deployment

### 1. Deploy the Image

```bash
# Copy SIF to shared storage
sudo cp r-bioconductor_3.23-R-4.6.0.sif /apps/biocontainers/images/
sudo chmod 644 /apps/biocontainers/images/r-bioconductor_3.23-R-4.6.0.sif
```

### 2. Create the Site Library

```bash
sudo mkdir -p /apps/biocontainers/extras/r-package-site-library/4.6-bioconductor
sudo chmod 2775 /apps/biocontainers/extras/r-package-site-library/4.6-bioconductor
sudo chgrp biocontainer-admins /apps/biocontainers/extras/r-package-site-library/4.6-bioconductor
```

### 3. Install the Modulefile

```bash
# Auto-detect Lmod vs Tcl
sudo ./scripts/install_module.sh

# Or specify format and path
sudo ./scripts/install_module.sh --lua --module-path /apps/modulefiles
```

### 4. Test

```bash
module load bioconductor/3.23
R --version
Rscript -e "BiocManager::version()"
```

See [docs/deployment.md](docs/deployment.md) for detailed deployment instructions.

## Module Setup

The module provides `R`, `Rscript`, and `rstudio` commands that transparently
invoke Apptainer. It also handles:

- **Singularity/Apptainer auto-load**: loads the container runtime module
  unless `BIOC_SINGULARITY_MODULE=none` is set
- **GPU detection**: automatically passes `--nv` (NVIDIA) or `--rocm` (AMD)
  to the container runtime when GPUs are present
- **Compiler isolation**: clears host `CC`/`CXX`/`FC` variables so R uses its
  own internal compilers for source package builds
- **Thread safety**: defaults `OMP_NUM_THREADS` and `OPENBLAS_NUM_THREADS` to
  1, preventing thread over-subscription in cgroup-limited SLURM jobs
- **Bind mounts**: automatically binds the site library, ThinLinc paths
  (`/var/opt`, `/run/user`), and host X11 fonts

### Lmod (Lua)

```bash
# Install
sudo ./scripts/install_module.sh --lua

# Verify
module avail bioconductor
module load bioconductor/3.23
module show bioconductor/3.23
```

### Tcl Modules

```bash
# Install
sudo ./scripts/install_module.sh --tcl

# Verify
module avail bioconductor
module load bioconductor/3.23
```

### Module Commands

After `module load bioconductor/3.23`:

| Command    | Description                              |
| ---------- | ---------------------------------------- |
| `R`        | Interactive R session                    |
| `Rscript`  | Run R scripts                            |
| `rstudio`  | Launch RStudio Desktop (needs X11)       |

### Module Configuration

**Image location**: Set `BIOC_IMAGE_DIR` to override where the module looks
for the SIF image:

```bash
export BIOC_IMAGE_DIR=/my/custom/path
module load bioconductor/3.23
```

**Singularity module**: By default, the modulefile auto-loads a module named
`Singularity`. Override this with `BIOC_SINGULARITY_MODULE`:

```bash
# Use a different module name
export BIOC_SINGULARITY_MODULE=apptainer

# Skip auto-loading (apptainer is already in PATH)
export BIOC_SINGULARITY_MODULE=none
```

### Customizing Bind Mounts

The modulefile uses `append_path("APPTAINER_BIND", ...)` to add bind mounts.
To add your site's data filesystems, edit the modulefile or set
`APPTAINER_BIND` before loading:

```bash
export APPTAINER_BIND="/data,/project"
module load bioconductor/3.23
# The module appends its own paths (/apps/biocontainers/extras, etc.)
```

## Package Libraries

### Resolution Order

R searches for packages in this order:

```text
1. R_LIBS_USER  →  ~/R/x86_64-pc-linux-gnu-library/4.6     (user, writable)
2. R_LIBS_SITE  →  /apps/.../4.6-bioconductor               (shared, read-only for users)
3. R_HOME/lib   →  /usr/local/lib/R/site-library             (container, read-only)
4. R_HOME/lib   →  /usr/local/lib/R/library                  (container, read-only)
```

User-installed packages override site packages, which override container packages.

### Installing Packages (Users)

```r
# CRAN packages
install.packages("Seurat")

# Bioconductor packages
BiocManager::install("DESeq2")

# Packages install to ~/R/x86_64-pc-linux-gnu-library/4.6
```

All system libraries from the official Bioconductor `bioc_full` script are
pre-installed in the container, so any package that compiles from source will
find its C/C++/Fortran dependencies.

### Installing Site Packages (Admins)

```bash
# Install packages into the shared site library
apptainer exec \
    --bind /apps/biocontainers/extras \
    /apps/biocontainers/images/r-bioconductor_3.23-R-4.6.0.sif \
    Rscript -e "
        install.packages('Seurat',
            lib = '/apps/biocontainers/extras/r-package-site-library/4.6-bioconductor')
    "
```

### Important Notes

- The container filesystem is **read-only** under Apptainer
- Users **cannot** modify packages inside the container
- All user installs go to `~/R/.../4.6/` on the host filesystem
- Site installs go to the bind-mounted shared directory
- No writes occur inside the container

## ThinLinc Usage

ThinLinc provides remote desktop sessions. RStudio Desktop runs as a normal
window in the ThinLinc desktop.

```bash
# 1. Connect to HPC via ThinLinc client
# 2. Open a terminal
# 3. Load the module and launch RStudio

module load bioconductor/3.23
rstudio
```

For compute-intensive work, submit to a compute node:

```bash
srun --x11 --cpus-per-task=8 --mem=32G --time=4:00:00 \
    apptainer exec \
    --bind /apps/biocontainers/extras,/scratch \
    /apps/biocontainers/images/r-bioconductor_3.23-R-4.6.0.sif \
    rstudio --no-sandbox
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
    /apps/biocontainers/images/r-bioconductor_3.23-R-4.6.0.sif \
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
    /apps/biocontainers/images/r-bioconductor_3.23-R-4.6.0.sif \
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
#    BIOC_VERSION=3.24
#    R_VERSION=4.7.0
#    RSTUDIO_VERSION=<latest>

# 3. Rebuild and test
make build
make test-all

# 4. Convert and deploy
make apptainer
sudo cp r-bioconductor_3.24-R-4.7.0.sif /apps/biocontainers/images/
sudo ./scripts/install_module.sh

# 5. Create new site library
sudo mkdir -p /apps/biocontainers/extras/r-package-site-library/4.7-bioconductor
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
    apptainer exec r-bioconductor_3.23-R-4.6.0.sif rstudio --no-sandbox
```

### Package Installation Fails

```bash
# Verify user library directory exists
ls -la ~/R/x86_64-pc-linux-gnu-library/4.6/

# Create if missing
mkdir -p ~/R/x86_64-pc-linux-gnu-library/4.6

# Verify bind mounts include the site library
apptainer exec --bind /apps/biocontainers/extras ...
```

### Source Package Compilation Fails

If R packages fail to compile with compiler errors, host compiler variables
may be leaking into the container. The module clears these automatically,
but if running without the module:

```bash
# Clear host compilers before running
unset CC CXX FC F77 F90 F95
apptainer exec ... Rscript -e "install.packages('...')"
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
apptainer exec r-bioconductor_3.23-R-4.6.0.sif ldd /usr/lib/rstudio/rstudio | grep "not found"
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
- **Threads**: The module defaults `OMP_NUM_THREADS` and `OPENBLAS_NUM_THREADS`
  to 1 to prevent over-subscription. Override in your SLURM script when you
  have multiple cores allocated.
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
4. **Full system deps from bioc_full** — users can compile any Bioconductor package
5. **No forking of upstream images** — we layer on top, not replace
6. **Scripts are parameterized** — they read from `VERSION`, not hardcoded values

The expected maintenance cadence is:

- **Every 6 months**: Update for new Bioconductor release (change 2-3 variables)
- **As needed**: Update RStudio Desktop version
- **Rarely**: Modify system dependencies (only when Bioconductor adds new
  package types that need system libraries)

## Repository Structure

```text
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
│   └── bioconductor           # Example Lmod modulefile
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
