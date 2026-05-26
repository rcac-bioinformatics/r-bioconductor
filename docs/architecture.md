# Bioconductor HPC Container -- Architecture

This document describes the design, rationale, and implementation of the
Bioconductor HPC Container. It is intended for maintainers, HPC
administrators, and advanced users who need to understand how the
container is structured and why specific choices were made.

---

## Table of Contents

1. [Design Overview](#design-overview)
2. [Why Not bioconductor_docker](#why-not-bioconductor_docker)
3. [Why RStudio Desktop Over RStudio Server](#why-rstudio-desktop-over-rstudio-server)
4. [Two-Layer Image Architecture](#two-layer-image-architecture)
5. [Container Filesystem Layout](#container-filesystem-layout)
6. [R Package Library Resolution](#r-package-library-resolution)
7. [Apptainer Integration](#apptainer-integration)
8. [Module System Integration](#module-system-integration)
9. [HPC Job Data Flow](#hpc-job-data-flow)
10. [Build Pipeline](#build-pipeline)
11. [Environment Configuration Chain](#environment-configuration-chain)
12. [Security Considerations](#security-considerations)
13. [Version Management](#version-management)
14. [File Reference](#file-reference)

---

## Design Overview

The Bioconductor HPC Container packages R, Bioconductor, and RStudio
Desktop into a single container image optimized for high-performance
computing clusters. The design follows two core principles:

1. **No server processes inside the container.** HPC job schedulers
   (SLURM, PBS, LSF) manage resources and lifecycles. Containers that
   run their own daemons, bind ports, or manage authentication conflict
   with this model.

2. **Layered package libraries.** The container image is read-only at
   runtime (Apptainer SIF). Users install packages into their personal
   library on the host filesystem. Administrators curate a shared site
   library. The container provides only the base R installation and core
   Bioconductor infrastructure.

```
+------------------------------------------------------------------+
|                     USER INTERACTION                              |
|   module load bioconductor/3.21                                  |
|   R / Rscript / rstudio / bioc-shell                             |
+------------------------------------------------------------------+
         |                    |                    |
         v                    v                    v
+------------------+  +----------------+  +------------------+
|  Module System   |  |   Apptainer    |  |  X11 Display     |
|  (Lmod / Tcl)    |  |   Runtime      |  |  (ThinLinc/OOD/  |
|                  |  |                |  |   X forwarding)  |
|  Sets env vars,  |  |  Mounts host   |  |                  |
|  defines shell   |  |  filesystems,  |  |  Receives GUI    |
|  functions       |  |  passes UID    |  |  from RStudio    |
+------------------+  +----------------+  +------------------+
         |                    |                    |
         +--------------------+--------------------+
                              |
                              v
              +-------------------------------+
              |     Container Image (SIF)     |
              |                               |
              |   R 4.5.0                     |
              |   Bioconductor 3.21           |
              |   RStudio Desktop             |
              |   System libraries            |
              |                               |
              |   Read-only at runtime        |
              +-------------------------------+
```

---

## Why Not bioconductor_docker

The official Bioconductor Docker images
(`bioconductor/bioconductor_docker`) use the following inheritance
chain:

```
rocker/r-ver          Pure R on Ubuntu. No IDE, no server.
       |
       v
rocker/rstudio        Adds RStudio Server (daemon, web app, auth).
       |
       v
bioconductor/         Adds BiocManager and Bioconductor packages.
bioconductor_docker
```

RStudio Server, inherited from `rocker/rstudio`, is a multi-user web
application designed for standalone server or cloud deployments. It
includes:

| Component              | Purpose in Server Mode     | Problem on HPC                          |
|------------------------|----------------------------|-----------------------------------------|
| `rserver` daemon       | Manages R sessions         | Conflicts with SLURM/PBS job lifecycle  |
| Port binding (8787)    | Serves web interface       | Port conflicts on shared compute nodes  |
| PAM authentication     | Manages user login         | Conflicts with HPC auth (LDAP, Kerberos)|
| Session management     | Tracks user sessions       | Assumes it controls the user session    |
| Nginx proxy support    | Reverse proxy integration  | Unnecessary infrastructure overhead     |

Stripping RStudio Server out of `bioconductor_docker` after the fact is
fragile: init scripts, PAM configuration, supervisord entries, and
systemd units all reference it. It is cleaner to never include it.

**This project starts from `rocker/r-ver` instead.** We get:

- The same R binary, compiled with the same flags
- The same CRAN mirror and package management infrastructure
- The same Ubuntu base image and system library conventions
- No server components to remove or work around

We then add Bioconductor and RStudio Desktop ourselves in a controlled
layer, producing an image purpose-built for HPC.

```
    OFFICIAL BIOCONDUCTOR IMAGE         THIS PROJECT
    ========================         ================

    bioconductor_docker               (this Dockerfile)
           |                                |
           v                                v
    rocker/rstudio                    rocker/r-ver
    (includes rserver daemon,         (R only, no server,
     port 8787, PAM auth,             no daemon, no ports)
     session management)                    |
           |                                v
           v                          + Bioconductor core
    rocker/r-ver                      + RStudio Desktop (X11 app)
    (R on Ubuntu)                     + HPC environment config
```

---

## Why RStudio Desktop Over RStudio Server

RStudio Desktop and RStudio Server share the same R integration, editor,
and plotting capabilities. They differ in how they present the interface
to the user:

| Characteristic         | RStudio Server             | RStudio Desktop            |
|------------------------|----------------------------|----------------------------|
| Interface delivery     | Web browser (HTTP/WS)      | Native X11 window          |
| Process model          | Daemon + child sessions    | Single user process        |
| Port requirements      | Binds TCP port (8787)      | None                       |
| Authentication         | Own PAM/auth module        | Inherits HPC login         |
| Session management     | Server-managed             | User-managed               |
| Remote display         | Web browser on client      | X11 protocol               |
| HPC remote desktop     | Requires port forwarding   | Native (ThinLinc, OOD, X11)|
| Resource accounting    | Opaque to scheduler        | Transparent to scheduler   |

On HPC systems, users access graphical applications through one of
three mechanisms, all of which are X11-based:

1. **ThinLinc** -- A remote desktop solution common on HPC clusters.
   Users log in to a persistent Linux desktop session. X11 applications
   run natively.

2. **Open OnDemand (OOD)** -- A web portal that launches interactive
   desktop sessions on compute nodes via VNC. The VNC session provides
   an X11 display. Applications inside the session are normal X11
   clients.

3. **X11 Forwarding** -- Direct `ssh -X` from the user's workstation.
   X11 protocol is tunneled over SSH.

RStudio Desktop works with all three because it is a standard X11
client. It opens a window, renders into it, and the X11 transport
handles the rest. No port forwarding, no SSH tunnels to specific ports,
no proxy configuration.

RStudio Server, by contrast, requires the user to set up SSH port
forwarding to reach port 8787 inside the compute node, or requires the
HPC site to run a reverse proxy. Both approaches add operational
complexity and security surface area that are unnecessary when X11
infrastructure already exists.

---

## Two-Layer Image Architecture

The container image is built in two conceptual layers, both defined in
a single `Dockerfile`:

```
+===================================================================+
|                                                                   |
|  LAYER 2: HPC OVERLAY                                            |
|                                                                   |
|  +-------------------+  +------------------+  +----------------+  |
|  | Bioconductor 3.21 |  | RStudio Desktop  |  | HPC Config     |  |
|  |                   |  |                  |  |                |  |
|  | BiocManager       |  | /usr/lib/rstudio |  | Renviron.site  |  |
|  | BiocGenerics      |  | /rstudio         |  | Rprofile.site  |  |
|  | S4Vectors         |  |                  |  | profile.d/     |  |
|  | IRanges           |  | X11 libraries    |  |   bioc.sh      |  |
|  | GenomicRanges     |  | Qt dependencies  |  | launch-rstudio |  |
|  | GenomeInfoDb      |  | D-Bus            |  |                |  |
|  | AnnotationDbi     |  | Fonts            |  | TMPDIR config  |  |
|  | BiocParallel      |  |                  |  | Locale config  |  |
|  | Biobase           |  |                  |  |                |  |
|  +-------------------+  +------------------+  +----------------+  |
|                                                                   |
|  +-------------------------------------------------------------+ |
|  | Common CRAN packages                                         | |
|  | tidyverse, data.table, devtools, remotes, rmarkdown, knitr,  | |
|  | Rcpp, RcppArmadillo, Matrix                                  | |
|  +-------------------------------------------------------------+ |
|                                                                   |
|  +-------------------------------------------------------------+ |
|  | System dependencies (single apt layer)                       | |
|  | Build tools: gcc, g++, gfortran, cmake                       | |
|  | R package deps: libcurl, libssl, libxml2, libhdf5, libgsl,   | |
|  |   libcairo2, libharfbuzz, libfribidi, libgeos, libproj ...   | |
|  | X11 runtime: libxcomposite, libxcursor, libnss3, libgbm ...  | |
|  +-------------------------------------------------------------+ |
|                                                                   |
+===================================================================+
|                                                                   |
|  LAYER 1: rocker/r-ver:4.5.0                                     |
|                                                                   |
|  +-------------------------------------------------------------+ |
|  | Ubuntu Noble (24.04 LTS)                                     | |
|  | R 4.5.0 compiled from source                                 | |
|  | CRAN repository configuration                                | |
|  | Base R packages (base, utils, stats, methods, ...)           | |
|  +-------------------------------------------------------------+ |
|                                                                   |
+===================================================================+
```

### Layer 1: rocker/r-ver

`rocker/r-ver` is a Docker image maintained by the Rocker Project. It
provides R compiled from source on Ubuntu with:

- Pinned R version for reproducibility
- CRAN configured with the Posit Package Manager
- System libraries needed to compile base R
- No IDE, no server, no GUI components

The tag `rocker/r-ver:4.5.0` gives us R 4.5.0 on Ubuntu Noble. This is
the same base that `rocker/rstudio` and by extension
`bioconductor_docker` inherit from, so R binary compatibility is
maintained.

### Layer 2: HPC Overlay

On top of `rocker/r-ver`, this project adds three groups of components:

**Bioconductor core packages.** BiocManager is installed from CRAN and
used to set the Bioconductor version. Eight infrastructure packages
(BiocGenerics, Biobase, S4Vectors, IRanges, GenomeInfoDb, GenomicRanges,
AnnotationDbi, BiocParallel) are installed. These are the foundation
that most Bioconductor workflows depend on. The full Bioconductor
package set is intentionally omitted -- users install what they need
into their personal or site library.

**RStudio Desktop.** Downloaded as a `.deb` package from Posit and
installed with `apt`. It places the RStudio binary at
`/usr/lib/rstudio/rstudio`. The X11 runtime libraries it needs
(libxcomposite, libxcursor, libnss3, Qt platform plugins, etc.) are
installed in the same `apt` layer as other system dependencies.

**HPC environment configuration.** Custom `Renviron.site`,
`Rprofile.site`, and shell profile scripts configure library paths,
TMPDIR, locale, and Qt/X11 settings for container execution on HPC.

---

## Container Filesystem Layout

At runtime under Apptainer, the container filesystem is composed of
read-only image content overlaid with bind-mounted host directories:

```
CONTAINER (read-only SIF)              HOST (read-write bind mounts)
========================               ============================

/usr/local/lib/R/                      ~/
  library/                               R/x86_64-pc-linux-gnu-library/4.5/
    base/                                  (user-installed packages)
    utils/                               .config/rstudio/
    BiocGenerics/                          (RStudio preferences)
    GenomicRanges/                       .cache/
    tidyverse/                             (fontconfig, R caches)
    ...                                  projects/
  etc/                                     analysis.R
    Renviron.site                          data/
    Rprofile.site
                                       /apps/biocontainers/
/usr/lib/rstudio/                        extras/
  rstudio  (binary)                        r-package-site-library/
  resources/                                 4.5-bioconductor/
  plugins/                                     (admin-installed packages)
                                         images/
/usr/local/bin/                            bioconductor-hpc-3.21.sif
  launch-rstudio
  R                                    /scratch/<user>/
  Rscript                               tmp/
                                           (TMPDIR -- R temp files)
/etc/profile.d/                          job-12345/
  bioc.sh                                   (working data)
```

### Key directories explained

**`/usr/local/lib/R/library/`** (container, read-only) -- The R system
library inside the container. Contains base R packages plus the
Bioconductor core and CRAN packages installed at build time. This
directory is not writable at runtime. It serves as the fallback library
of last resort in the resolution chain.

**`~/R/x86_64-pc-linux-gnu-library/4.5/`** (host, read-write) -- The
per-user R package library. Located in the user's home directory on the
host filesystem, which Apptainer bind-mounts automatically. Users
install packages here with `install.packages()` or
`BiocManager::install()`. No root access or container modification
required. The directory is created automatically by `Rprofile.site` on
first R session.

**`/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor/`**
(host, read-write for admins) -- The shared site library. Bind-mounted
from HPC shared storage. HPC administrators install commonly needed
packages here so that individual users do not each need to compile them.
The path includes the R version and "bioconductor" suffix to prevent
version conflicts between different Bioconductor releases.

**`/scratch/<user>/tmp/`** (host, read-write) -- Temporary file
storage. The container redirects TMPDIR here because `/tmp` on compute
nodes is often a small tmpfs (1-4 GB). Bioinformatics workloads
(scRNA-seq, whole-genome sequencing) routinely generate gigabytes of
temporary files during sorting, alignment, and matrix operations.

---

## R Package Library Resolution

When R looks for a package, it searches directories returned by
`.libPaths()` in order, using the first copy it finds. This project
configures a three-tier resolution chain:

```
                    install.packages("DESeq2")
                              |
                              v
                  +------------------------+
                  | 1. USER LIBRARY        |     Highest priority.
                  |    ~/R/.../4.5/        |     User's own installs.
                  |                        |     Writable by user.
                  |    Found? ---> USE IT  |
                  +------------------------+
                              |
                          not found
                              |
                              v
                  +------------------------+
                  | 2. SITE LIBRARY        |     Shared installs by
                  |    /apps/.../          |     HPC administrators.
                  |    4.5-bioconductor/   |     Read-only for users.
                  |                        |
                  |    Found? ---> USE IT  |
                  +------------------------+
                              |
                          not found
                              |
                              v
                  +------------------------+
                  | 3. CONTAINER LIBRARY   |     Lowest priority.
                  |    /usr/local/lib/R/   |     Base + core packages
                  |    library/            |     baked into the image.
                  |                        |     Read-only (SIF).
                  |    Found? ---> USE IT  |
                  +------------------------+
                              |
                          not found
                              |
                              v
                    Error: package not found
                    (user runs install.packages
                     to add it to tier 1)
```

### How priority works in practice

- **User overrides site overrides container.** If a user needs a newer
  version of a package than what the site library provides, they install
  it into their personal library. R finds the user copy first and uses
  it. The site copy is shadowed but not removed.

- **Site library avoids redundant compilation.** Popular packages like
  Seurat, SingleCellExperiment, or DESeq2 take significant time to
  compile from source. By installing them once into the site library,
  all users benefit immediately.

- **Container library provides stability.** The core Bioconductor
  packages in the container are version-locked to the image build. They
  cannot be accidentally upgraded or removed. This ensures that the
  foundation packages are always available and consistent.

### Configuration mechanism

The resolution order is set by two environment variables in
`Renviron.site`:

```
R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/%v
R_LIBS_SITE=/apps/biocontainers/extras/r-package-site-library/%v-bioconductor
```

The `%v` token is expanded by R to the major.minor version (e.g.,
`4.5`). `R_LIBS` is intentionally not set because it overrides both
`R_LIBS_USER` and `R_LIBS_SITE`, collapsing the layered resolution into
a flat list.

The `Rprofile.site` script ensures the user library directory exists on
first use, avoiding the interactive "Would you like to create a personal
library?" prompt that would block non-interactive batch jobs.

---

## Apptainer Integration

Apptainer (formerly Singularity) is the standard container runtime for
HPC. Unlike Docker, it is designed for unprivileged multi-user
environments.

### Key Apptainer properties leveraged by this project

**Read-only image.** The SIF (Singularity Image Format) file is a
single read-only squashfs file. No writes go to the container
filesystem. This eliminates drift between runs and simplifies storage
(one file on a shared filesystem, used by all users).

**UID/GID passthrough.** Apptainer runs the container process as the
calling user, not as root. The user inside the container has the same
UID, GID, group memberships, and home directory as on the host. No user
mapping, no namespace remapping, no security elevation.

**Automatic home mount.** Apptainer bind-mounts the user's home
directory by default. This is where the user library
(`~/R/x86_64-pc-linux-gnu-library/4.5/`) resides, so package
persistence works without extra configuration.

**Explicit bind mounts for other paths.** Filesystems beyond the home
directory require explicit `--bind` flags or `APPTAINER_BIND`
environment variable. This project requires:

```
APPTAINER_BIND=/apps/biocontainers/extras,/scratch
```

The site library lives under `/apps/biocontainers/extras`. Scratch
storage at `/scratch` is needed for TMPDIR. Additional data filesystems
(`/data`, `/project`, `/work`) are site-specific and must be added per
cluster.

### Container execution model

```
  Host Process                         Container Process
  ============                         =================

  User shell (bash)
       |
       |  module load bioconductor/3.21
       |  (sets env vars, defines shell functions)
       |
       |  R --no-save < script.R
       |  (shell function expands to apptainer exec ...)
       |
       v
  apptainer exec \
    --bind /apps/biocontainers/extras \
    --bind /scratch \
    bioconductor-hpc-3.21.sif \
    R --no-save < script.R
       |
       |  Apptainer:
       |    - Mounts SIF as read-only root filesystem
       |    - Bind-mounts $HOME, /apps/..., /scratch
       |    - Sets UID/GID to calling user
       |    - Sources %environment from SIF
       |    - Executes: R --no-save
       |
       +--------------------------------------------+
                                                    |
                                                    v
                                           R process (as user)
                                             |
                                             | .libPaths():
                                             |   ~/R/.../4.5
                                             |   /apps/.../4.5-bioconductor
                                             |   /usr/local/lib/R/library
                                             |
                                             | Reads input from stdin
                                             | Writes output to stdout
                                             | Temp files -> /scratch/$USER/tmp
                                             | Installed packages -> ~/R/...
```

### No daemons, no services

The container runs no background processes. There is no init system, no
supervisord, no rserver. The `apptainer exec` command starts exactly one
process (R, Rscript, or rstudio) and exits when that process exits. The
exit code propagates back to the calling shell, which propagates to the
job scheduler. SLURM tracks exactly one process tree per job step, and
the container does not interfere with that model.

---

## Module System Integration

HPC clusters use environment module systems (Lmod or Tcl Environment
Modules) to manage software availability. This project provides
modulefiles for both systems.

### What the modulefile does

When a user runs `module load bioconductor/3.21`, the modulefile:

1. **Sets environment variables** for R library paths, Bioconductor
   version, TMPDIR, and Qt/X11 configuration.

2. **Defines shell functions** (Lmod) or **aliases** (Tcl) that wrap
   `apptainer exec` calls:

   | Command       | Expands to                                          |
   |---------------|-----------------------------------------------------|
   | `R`           | `apptainer exec --bind ... bioconductor-hpc.sif R`  |
   | `Rscript`     | `apptainer exec --bind ... bioconductor-hpc.sif Rscript` |
   | `rstudio`     | `apptainer exec --bind ... bioconductor-hpc.sif launch-rstudio` |
   | `bioc-shell`  | `apptainer exec --bind ... bioconductor-hpc.sif bash` |

3. **Declares conflicts** with other `bioconductor` or `R` modules to
   prevent loading incompatible versions simultaneously.

### Lmod vs Tcl differences

The Lmod modulefile (`templates/modulefile.lua`) uses `set_shell_function`
to define wrapper functions. Shell functions work in scripts, with
`xargs`, and in non-interactive contexts. The Tcl modulefile
(`templates/modulefile.tcl`) uses `set-alias`, which only works in
interactive shells. For non-interactive use with Tcl modules, users must
call `apptainer exec` directly.

### Modulefile deployment

The `scripts/install_module.sh` script:

1. Auto-detects whether the site uses Lmod or Tcl Environment Modules.
2. Reads the appropriate template (`templates/modulefile.lua` or
   `templates/modulefile.tcl`).
3. Substitutes version numbers and paths (`@@BIOC_VERSION@@`,
   `@@R_VERSION@@`, `@@IMAGE_DIR@@`, etc.).
4. Installs the result to `MODULE_PATH/bioconductor/<version>`.

```
Template                      install_module.sh              Installed modulefile
===========                   =================              ====================

templates/modulefile.lua  --> sed @@BIOC_VERSION@@=3.21  --> /apps/modulefiles/
                              sed @@R_VERSION@@=4.5.0        bioconductor/3.21.lua
                              sed @@IMAGE_DIR@@=/apps/...
                              sed @@IMAGE_FILE@@=...sif

templates/modulefile.tcl  --> (same substitutions)       --> /apps/modulefiles/
                                                             bioconductor/3.21
```

Multiple Bioconductor versions can coexist as separate modulefiles
(e.g., `bioconductor/3.20`, `bioconductor/3.21`), each pointing to its
own SIF image and using its own versioned library paths.

---

## HPC Job Data Flow

This diagram traces the complete flow of an HPC job using the
Bioconductor container, from SLURM submission to completion:

```
USER WORKSTATION                 LOGIN NODE                    COMPUTE NODE
================                 ==========                    ============

ssh user@hpc                     $ sbatch job.slurm
                                        |
                                        v
                                 SLURM schedules job
                                 on compute node
                                        |
                                 +------+------+
                                 |             |
                                 v             v
                          +-----------+  +-----------+
                          | job.slurm |  | SLURM     |
                          | runs on   |  | sets:     |
                          | compute   |  | SLURM_*   |
                          | node      |  | env vars  |
                          +-----------+  +-----------+
                                 |
     job.slurm contents:         v
     ====================
     #!/bin/bash               source environment.sh
     #SBATCH --cpus=8                |
     #SBATCH --mem=64G               v
     #SBATCH --time=4:00:00    APPTAINER_BIND set
                               TMPDIR set to /scratch
     source environment.sh           |
     apptainer exec \                v
       $APPTAINER_IMAGE \      apptainer exec ... Rscript analysis.R
       Rscript analysis.R            |
                                     v
                               +----------------------------------+
                               | CONTAINER EXECUTION              |
                               |                                  |
                               | R reads Renviron.site:           |
                               |   R_LIBS_USER -> ~/R/.../4.5    |
                               |   R_LIBS_SITE -> /apps/.../     |
                               |                                  |
                               | R reads Rprofile.site:           |
                               |   Creates ~/R/.../4.5 if needed |
                               |   Sets BiocManager repos        |
                               |   Ncpus = SLURM_CPUS_PER_TASK  |
                               |                                  |
                               | analysis.R runs:                 |
                               |   library(DESeq2)  -- from site |
                               |   library(MyPkg)   -- from user |
                               |   read("data.csv") -- from $HOME|
                               |   <computation>                  |
                               |   write("results/out.rds")      |
                               |                                  |
                               | Temp files -> /scratch/user/tmp  |
                               | Results -> ~/results/            |
                               +----------------------------------+
                                     |
                                     v
                               Job completes, SLURM records
                               exit code, walltime, memory usage
```

### SLURM resource accounting

Because the container runs no daemons and the R process is the only
child of the SLURM job step, resource accounting is accurate:

- **CPU time** reflects actual R computation.
- **Memory (RSS)** reflects R's working set, not inflated by server
  overhead.
- **Exit code** from R propagates through Apptainer to SLURM.
- `SLURM_CPUS_PER_TASK` is read by `Rprofile.site` and used to set
  `options(Ncpus = ...)` for parallel package compilation.

---

## Build Pipeline

The container is built in two stages: Docker image, then Apptainer SIF.

```
VERSION file          Dockerfile              Docker Image         Apptainer SIF
============          ==========              ============         =============

BIOC_VERSION=3.21     FROM rocker/r-ver       bioconductor-hpc     bioconductor-hpc
R_VERSION=4.5.0       + system deps             :3.21                -3.21.sif
RSTUDIO_VERSION=...   + RStudio Desktop              |
                      + Bioconductor core            v
        |             + CRAN packages          build_apptainer.sh
        |             + env config               (method 1: docker-daemon://)
        v                    |                   (method 2: apptainer.def)
    build.sh                 |                         |
        |                    v                         v
        +-----> docker build --build-arg ...     apptainer build
                    |                                   |
                    v                                   v
              test_cli.sh                         SIF deployed to
              test_rstudio.sh                     /apps/biocontainers/
                                                  images/
```

### Build commands

```
make build           # Docker image from Dockerfile
make apptainer       # SIF from local Docker image (docker-daemon://)
make apptainer-def   # SIF from apptainer.def (pulls from registry)
make test            # CLI tests (R, packages, versions)
make test-rstudio    # RStudio dependency verification
make deploy          # Install modulefile to module path
```

### CI pipeline

The GitHub Actions workflow (`.github/workflows/build.yml`) runs on
every push and pull request to `main`. It builds the Docker image, runs
the full test suite, and verifies RStudio shared library dependencies.
GUI testing is skipped in CI because there is no X11 display.

---

## Environment Configuration Chain

Multiple configuration files cooperate to set up the runtime
environment. They execute in a specific order depending on how the
container is invoked:

```
INVOCATION                            CONFIGURATION FILES SOURCED
==========                            ===========================

apptainer exec ... R                  1. %environment (from SIF)
                                      2. Renviron.site
                                      3. Rprofile.site
                                      4. ~/.Renviron (if exists)
                                      5. ~/.Rprofile (if exists)

apptainer exec ... Rscript            (same as above)

apptainer shell ...                   1. %environment (from SIF)
  then: R                             2. /etc/profile.d/bioc.sh (login shell)
                                      3. Renviron.site
                                      4. Rprofile.site
                                      5. ~/.Renviron, ~/.Rprofile

apptainer exec ... launch-rstudio     1. %environment (from SIF)
                                      2. launch-rstudio script
                                         (configures Qt, D-Bus, TMPDIR)
                                      3. RStudio starts R internally
                                      4. Renviron.site
                                      5. Rprofile.site

module load bioconductor/3.21         1. Modulefile sets env vars
  then: R                             2. Shell function calls apptainer exec
                                      3. %environment (from SIF)
                                      4. Renviron.site
                                      5. Rprofile.site
```

### Configuration file responsibilities

| File                   | Location in container         | Sets                                    |
|------------------------|-------------------------------|-----------------------------------------|
| `%environment`         | Embedded in SIF               | LANG, R_LIBS_USER, R_LIBS_SITE, TMPDIR, Qt vars |
| `Renviron.site`        | `/usr/local/lib/R/etc/`       | R_LIBS_USER, R_LIBS_SITE, CRAN mirror, locale |
| `Rprofile.site`        | `/usr/local/lib/R/etc/`       | User library creation, BiocManager repos, Ncpus |
| `bioc.sh`             | `/etc/profile.d/`             | Shell vars for R_LIBS, TMPDIR, Qt, login banner |
| `launch-rstudio`       | `/usr/local/bin/`             | TMPDIR, Qt/X11, D-Bus, font cache, XDG dirs |
| Modulefile             | Host `/apps/modulefiles/`     | Same vars as %environment, plus shell functions |

There is intentional overlap between `%environment`, `bioc.sh`, and the
modulefile. Each uses conditional defaults (`${VAR:-default}`) so that
earlier settings are not overwritten. This ensures correct behavior
regardless of whether the container is invoked via a modulefile, via
direct `apptainer exec`, or via `apptainer shell`.

---

## Security Considerations

### No privilege escalation

Apptainer does not grant root inside the container. The user runs as
themselves. There is no setuid binary, no user namespace remapping, and
no capability elevation. The SIF file is owned by root on the shared
filesystem and is not writable by users.

### No network listeners

The container opens no listening sockets. RStudio Desktop communicates
with its R session over internal pipes, not network ports. There is no
HTTP server, no WebSocket server, no port to firewall.

### No authentication bypass

Because there is no RStudio Server, there is no second authentication
layer that could conflict with or bypass the HPC site's LDAP/Kerberos
authentication. Users authenticate once via SSH or ThinLinc and that
identity carries through to the container.

### Read-only image

The SIF format is a read-only squashfs image. Users cannot modify the
container contents. Package installations go to the user or site library
on the host filesystem, which are subject to normal POSIX permissions
and quotas.

### TMPDIR isolation

TMPDIR is redirected to per-user scratch storage (`/scratch/$USER/tmp`)
rather than the shared `/tmp`. This prevents temp file collisions
between users on the same node and avoids filling the node's tmpfs.

---

## Version Management

All version numbers are centralized in the `VERSION` file at the
repository root:

```
BIOC_VERSION=3.21
R_VERSION=4.5.0
UBUNTU_VERSION=noble
RSTUDIO_VERSION=2025.05.0-496
```

These values propagate through the build system:

- **Makefile** includes `VERSION` and exports the variables.
- **build.sh** sources `VERSION` and passes values as Docker
  `--build-arg` flags.
- **Dockerfile** receives them as `ARG` directives and uses them in
  `FROM`, package installation, and label metadata.
- **install_module.sh** sources `VERSION` and substitutes them into
  modulefile templates.
- **apptainer.def** has hardcoded values that must be updated manually
  when the `VERSION` file changes (this is a known limitation of the
  Apptainer definition format).

The `scripts/detect_versions.sh` utility queries upstream sources
(Bioconductor, CRAN, Posit, Docker Hub) to help maintainers identify
when new versions are available.

### Version coupling

Bioconductor versions are coupled to R versions. Bioconductor 3.21
requires R 4.5.x. The `VERSION` file must specify a compatible pair. The
`Rprofile.site` verifies at container startup that `BiocManager::version()`
returns the expected value. The CI pipeline tests this automatically.

---

## File Reference

```
bioconductor-hpc-container/
|
+-- Dockerfile                     Container image definition (both layers)
+-- Makefile                       Build orchestration (build, test, deploy)
+-- VERSION                        Centralized version numbers
+-- LICENSE                        MIT license
+-- .gitignore                     Excludes SIF files, build artifacts, R artifacts
|
+-- apptainer/
|   +-- apptainer.def              Apptainer definition file (alternative build)
|   +-- environment.sh             Host-side env setup (source before apptainer exec)
|
+-- env/
|   +-- renviron.site              R environment variables (library paths, CRAN, locale)
|   +-- rprofile.site              R startup code (user lib creation, repos, Ncpus)
|   +-- profile.d/
|       +-- bioc.sh                Login shell setup (R paths, TMPDIR, Qt, banner)
|
+-- scripts/
|   +-- build.sh                   Build Docker image with version args
|   +-- build_apptainer.sh         Convert Docker image to SIF (two methods)
|   +-- test_cli.sh                CLI test suite (R, Rscript, packages, paths)
|   +-- test_rstudio.sh            RStudio dependency verification (ldd, Qt, fonts)
|   +-- install_module.sh          Deploy modulefile with variable substitution
|   +-- detect_versions.sh         Query upstream for latest versions
|   +-- launch_rstudio.sh          RStudio Desktop launcher (TMPDIR, Qt, D-Bus)
|
+-- templates/
|   +-- modulefile.lua             Lmod modulefile template (shell functions)
|   +-- modulefile.tcl             Tcl modulefile template (aliases)
|
+-- modulefiles/
|   +-- bioconductor               Ready-to-use Tcl modulefile (default paths)
|
+-- .github/
|   +-- workflows/
|       +-- build.yml              CI: build Docker image, run tests
|
+-- docs/
    +-- architecture.md            This document
```
