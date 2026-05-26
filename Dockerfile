##############################################################################
# Bioconductor + RStudio Desktop for HPC
#
# TWO-LAYER DESIGN:
#   Layer 1: rocker/r-ver provides R on Ubuntu with rocker infrastructure
#   Layer 2: This Dockerfile adds Bioconductor + RStudio Desktop
#
# WHY rocker/r-ver INSTEAD OF bioconductor_docker?
#   The official bioconductor/bioconductor_docker images inherit from
#   rocker/rstudio, which bundles RStudio Server — a multi-user web
#   application that is inappropriate for HPC:
#     - It runs as a daemon and expects to manage its own authentication
#     - It conflicts with HPC job schedulers (SLURM, PBS, LSF)
#     - It binds network ports, creating security concerns on shared nodes
#     - It assumes it controls user sessions
#
#   By starting from rocker/r-ver we get:
#     - The same R installation and CRAN mirror configuration
#     - The same Ubuntu base and system library handling
#     - No server infrastructure to strip out
#     - A clean base on which to install RStudio Desktop (a normal X11 app)
#
# BIOCONDUCTOR INSTALLATION:
#   We install BiocManager and the core Bioconductor infrastructure packages
#   identically to how the official image does it, ensuring compatibility.
#   We do NOT install every Bioconductor package — users install what they
#   need into their personal or site libraries.
#
# RSTUDIO DESKTOP:
#   Installed as a normal desktop application. It runs as an X11 client,
#   which integrates naturally with:
#     - ThinLinc remote desktop sessions
#     - Open OnDemand interactive desktop apps
#     - Direct X11 forwarding (ssh -X)
#
##############################################################################

# ---------------------------------------------------------------------------
# Build arguments — change these to target a different release
# ---------------------------------------------------------------------------
ARG R_VERSION=4.5.0
ARG UBUNTU_VERSION=noble
ARG BIOC_VERSION=3.21
ARG RSTUDIO_VERSION=2025.05.0-496

# ---------------------------------------------------------------------------
# Layer 1: rocker/r-ver base
# ---------------------------------------------------------------------------
FROM rocker/r-ver:${R_VERSION}

# Re-declare ARGs after FROM (Docker scoping rule)
ARG R_VERSION
ARG BIOC_VERSION
ARG RSTUDIO_VERSION

# ---------------------------------------------------------------------------
# OCI / Docker labels for provenance tracking
# ---------------------------------------------------------------------------
LABEL org.opencontainers.image.title="Bioconductor HPC (RStudio Desktop)" \
      org.opencontainers.image.description="Bioconductor ${BIOC_VERSION} with R ${R_VERSION} and RStudio Desktop for HPC environments" \
      org.opencontainers.image.version="${BIOC_VERSION}-r${R_VERSION}" \
      org.opencontainers.image.source="https://github.com/YOUR_ORG/bioconductor-hpc-container" \
      org.opencontainers.image.licenses="MIT" \
      org.bioconductor.version="${BIOC_VERSION}" \
      org.r-project.version="${R_VERSION}" \
      com.rstudio.version="${RSTUDIO_VERSION}" \
      com.hpc.target="apptainer"

# ---------------------------------------------------------------------------
# Environment: configure R library paths for HPC
#
# R_LIBS_USER: per-user writable library (on the host filesystem)
# R_LIBS_SITE: shared site library (bind-mounted from HPC shared storage)
#
# The site library path uses a Bioconductor-versioned directory so that
# different Bioconductor releases do not share incompatible packages.
#
# R_VERSION_SHORT is the major.minor version (e.g., "4.5") used in paths.
# ---------------------------------------------------------------------------
ENV R_VERSION_SHORT=${R_VERSION%.*} \
    BIOC_VERSION=${BIOC_VERSION} \
    RSTUDIO_VERSION=${RSTUDIO_VERSION}

ENV R_LIBS_USER='~/R/x86_64-pc-linux-gnu-library/${R_VERSION_SHORT}' \
    R_LIBS_SITE='/apps/biocontainers/extras/r-package-site-library/${R_VERSION_SHORT}-bioconductor'

# ---------------------------------------------------------------------------
# System dependencies
#
# Organized by purpose. Each group explains WHY these packages are needed.
# We combine all apt operations into a single layer to minimize image size.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    #
    # --- Core build tools (compiling R packages with C/C++/Fortran code) ---
    build-essential \
    gfortran \
    cmake \
    #
    # --- Common R package system dependencies ---
    # libcurl: RCurl, httr, curl packages
    libcurl4-openssl-dev \
    # libssl: openssl, httr2, git2r
    libssl-dev \
    # libxml2: XML, xml2 packages
    libxml2-dev \
    # libfontconfig/freetype: Cairo graphics, ragg, systemfonts
    libfontconfig1-dev \
    libfreetype6-dev \
    # libpng/libjpeg/libtiff: image I/O for plotting packages
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    # libcairo2: Cairo graphics device
    libcairo2-dev \
    # libharfbuzz/libfribidi: textshaping package (required by ragg)
    libharfbuzz-dev \
    libfribidi-dev \
    # libgit2: git2r package
    libgit2-dev \
    # libssh2: git2r SSH transport
    libssh2-1-dev \
    # zlib: data compression in many packages
    zlib1g-dev \
    # libbz2/liblzma: Rsamtools, Rhtslib, and other Bioconductor I/O packages
    libbz2-dev \
    liblzma-dev \
    # libhdf5: HDF5Array, rhdf5 packages
    libhdf5-dev \
    # libfftw3: EBImage, signal processing packages
    libfftw3-dev \
    # libgsl: gsl, topGO, and other statistical packages
    libgsl-dev \
    # libgeos/libproj: spatial analysis packages
    libgeos-dev \
    libproj-dev \
    # libsqlite3: RSQLite, AnnotationDbi
    libsqlite3-dev \
    # libpq: RPostgres
    libpq-dev \
    # libglpk: igraph (graph/network analysis)
    libglpk-dev \
    #
    # --- X11 and GUI libraries (required for RStudio Desktop) ---
    # These are the runtime libraries RStudio Desktop needs to display
    # its Qt-based GUI under X11.
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libxkbfile1 \
    libnss3 \
    libnspr4 \
    libasound2t64 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    #
    # --- D-Bus (needed by Qt/RStudio for IPC) ---
    dbus \
    libdbus-1-3 \
    #
    # --- Fonts (rendering text in plots and RStudio) ---
    fonts-dejavu-core \
    fonts-liberation \
    fontconfig \
    #
    # --- Utilities ---
    # wget/curl: downloading files in scripts
    wget \
    curl \
    # locales: UTF-8 locale support
    locales \
    # file: MIME type detection
    file \
    # git: version control (BiocManager::install from GitHub)
    git \
    # procps: ps/top (useful for debugging in containers)
    procps \
    # lsb-release: system identification
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Locale configuration
# Many R packages and Bioconductor expect UTF-8 locale
# ---------------------------------------------------------------------------
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# Install RStudio Desktop
#
# We download the .deb for Ubuntu and install it. RStudio Desktop is a
# normal X11 application — no server, no daemon, no port binding.
#
# The version is pinned via RSTUDIO_VERSION build arg for reproducibility.
# ---------------------------------------------------------------------------
RUN ARCH=$(dpkg --print-architecture) && \
    RSTUDIO_DEB="rstudio-${RSTUDIO_VERSION}-${ARCH}.deb" && \
    wget -q "https://download1.rstudio.org/electron/jammy/${ARCH}/${RSTUDIO_DEB}" \
         -O /tmp/rstudio.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/rstudio.deb && \
    rm -f /tmp/rstudio.deb && \
    rm -rf /var/lib/apt/lists/* && \
    # Verify RStudio was installed
    test -x /usr/lib/rstudio/rstudio || \
        (echo "ERROR: RStudio Desktop binary not found after installation" && exit 1)

# ---------------------------------------------------------------------------
# Install Bioconductor
#
# Strategy: Install BiocManager and use it to set the Bioconductor version.
# Then install only the core infrastructure packages that most workflows need.
# Users install additional packages into their personal or site library.
#
# This mirrors the official Bioconductor Docker image's approach but without
# the heavyweight default package set.
# ---------------------------------------------------------------------------
RUN R -e "\
    install.packages('BiocManager', repos='https://cloud.r-project.org'); \
    BiocManager::install(version = '${BIOC_VERSION}', ask = FALSE, update = FALSE); \
    BiocManager::install(c( \
        'BiocGenerics',      \
        'Biobase',           \
        'S4Vectors',         \
        'IRanges',           \
        'GenomeInfoDb',      \
        'GenomicRanges',     \
        'AnnotationDbi',     \
        'BiocParallel'       \
    ), ask = FALSE, update = FALSE); \
    # Verify Bioconductor version is correctly set \
    stopifnot(BiocManager::version() == '${BIOC_VERSION}'); \
    cat('Bioconductor', as.character(BiocManager::version()), 'installed successfully\n')"

# ---------------------------------------------------------------------------
# Install commonly needed CRAN packages
#
# These are packages that most R/Bioconductor users need and that benefit
# from being pre-compiled in the container image.
# ---------------------------------------------------------------------------
RUN R -e "\
    install.packages(c( \
        'devtools',     \
        'remotes',      \
        'tidyverse',    \
        'data.table',   \
        'Rcpp',         \
        'RcppArmadillo',\
        'Matrix',       \
        'rmarkdown',    \
        'knitr'         \
    ), repos = 'https://cloud.r-project.org', Ncpus = parallel::detectCores())"

# ---------------------------------------------------------------------------
# R configuration files
#
# Renviron.site: system-wide environment variables for R
# Rprofile.site: system-wide R startup code
#
# These are placed in R_HOME/etc/ where R reads them automatically.
# ---------------------------------------------------------------------------
COPY env/renviron.site /usr/local/lib/R/etc/Renviron.site
COPY env/rprofile.site /usr/local/lib/R/etc/Rprofile.site

# ---------------------------------------------------------------------------
# Shell environment configuration
#
# This script is sourced by login shells to set up PATH and environment
# variables for R, RStudio, and Bioconductor.
# ---------------------------------------------------------------------------
COPY env/profile.d/bioc.sh /etc/profile.d/bioc.sh

# ---------------------------------------------------------------------------
# Launcher script for RStudio Desktop
#
# This wrapper configures the environment for running RStudio Desktop
# under X11 in HPC environments (ThinLinc, OOD, X11 forwarding).
# ---------------------------------------------------------------------------
COPY scripts/launch_rstudio.sh /usr/local/bin/launch-rstudio
RUN chmod +x /usr/local/bin/launch-rstudio

# ---------------------------------------------------------------------------
# Final cleanup and verification
# ---------------------------------------------------------------------------
RUN R --version && \
    R -e "cat('BiocManager version:', as.character(BiocManager::version()), '\n')" && \
    R -e "cat('R library paths:\n'); cat(paste(.libPaths(), collapse='\n'), '\n')" && \
    test -x /usr/lib/rstudio/rstudio && echo "RStudio Desktop: OK"

# ---------------------------------------------------------------------------
# Default command: R interactive session
#
# Under Apptainer this is overridden by exec/shell/run semantics.
# For Docker testing, this drops into an R console.
# ---------------------------------------------------------------------------
CMD ["R"]
