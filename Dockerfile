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
# BIOCONDUCTOR SYSTEM DEPENDENCIES:
#   The system libraries installed here match the official bioconductor_docker
#   "bioc_full" install script. This ensures that ANY Bioconductor package
#   can be compiled and installed by users — the same guarantee the official
#   image provides. Without these, packages like rhdf5, Rsamtools, mzR,
#   EBImage, sf, etc. would fail to compile.
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
ARG R_VERSION=4.6.0
ARG UBUNTU_VERSION=noble
ARG BIOC_VERSION=3.23
ARG RSTUDIO_VERSION=2026.05.0-218

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
# ---------------------------------------------------------------------------
ENV R_VERSION_SHORT=${R_VERSION%.*} \
    BIOC_VERSION=${BIOC_VERSION} \
    RSTUDIO_VERSION=${RSTUDIO_VERSION}

ENV R_LIBS_USER='~/R/x86_64-pc-linux-gnu-library/${R_VERSION_SHORT}' \
    R_LIBS_SITE='/apps/biocontainers/extras/r-package-site-library/${R_VERSION_SHORT}-bioconductor'

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# System dependencies — FULL Bioconductor compatibility
#
# These match the official bioconductor_docker "bioc_full" system deps.
# Every group is annotated with which Bioconductor/R packages need it.
# Without these, users cannot compile many Bioconductor packages.
#
# All apt operations are combined into a single RUN to minimize layers.
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-utils \
    #
    # ── Core build tools ──────────────────────────────────────────────────
    # Required for compiling any R package with C/C++/Fortran code
    && apt-get install -y --no-install-recommends \
        build-essential \
        gfortran \
        fortran77-compiler \
        cmake \
        automake \
        byacc \
        pkg-config \
        gdb \
    #
    # ── Basic R package system deps ───────────────────────────────────────
    # libxml2: XML, xml2
    # libz/liblzma/libbz2: Rsamtools, Rhtslib, ShortRead, rtracklayer
    # libpng: png, aplot
    # libgit2: git2r, usethis
    # python3-pip/dev/venv: reticulate, basilisk, packages using Python
    && apt-get install -y --no-install-recommends \
        libxml2-dev \
        libz-dev \
        liblzma-dev \
        libbz2-dev \
        libpng-dev \
        libgit2-dev \
        python3-pip \
        python3-dev \
        python3-venv \
    #
    # ── Networking and crypto ─────────────────────────────────────────────
    # libcurl: RCurl, httr, curl, BiocFileCache
    # libssl: openssl, httr2, git2r
    # libssh2: git2r SSH transport
    && apt-get install -y --no-install-recommends \
        libcurl4-openssl-dev \
        libssl-dev \
        libssh2-1-dev \
    #
    # ── Scientific computing libraries ────────────────────────────────────
    # libpcre2: stringi
    # libnetcdf: ncdf4, RNetCDF, mzR
    # libhdf5: HDF5Array, rhdf5, Rhdf5lib
    # libfftw3: EBImage, fftwtools
    # libopenbabel: ChemmineOB
    # libopenmpi: Rmpi, pbdMPI, BiocParallel MPI backend
    # libudunits2: units, sf
    # libgsl/libgslcblas: gsl, topGO, DirichletMultinomial
    # libglpk: igraph, RBGL
    # libeigen3: RcppEigen, many stats packages
    # liblz4: arrow, some compression
    && apt-get install -y --no-install-recommends \
        libpcre2-dev \
        libnetcdf-dev \
        libhdf5-serial-dev \
        libhdf5-dev \
        libfftw3-dev \
        libopenbabel-dev \
        libopenmpi-dev \
        libudunits2-dev \
        libgsl-dev \
        libgslcblas0 \
        libglpk-dev \
        libeigen3-dev \
        liblz4-dev \
    #
    # ── Spatial analysis ──────────────────────────────────────────────────
    # libgeos/libproj/libgdal: sf, terra, rgdal, rgeos, sp
    && apt-get install -y --no-install-recommends \
        libgeos-dev \
        libproj-dev \
        libgdal-dev \
    #
    # ── Graphics and imaging ──────────────────────────────────────────────
    # libcairo2: Cairo graphics device
    # libtiff: tiff, EBImage
    # libxt: X11 device, cairoDevice
    # libreadline: rline
    # libgtk2.0: gWidgets2tcltk, RGtk2
    # libgl1-mesa/libglu1-mesa: rgl, OpenGL-based packages
    # libxpm: X pixmap support
    # libmagick++: magick (image processing)
    && apt-get install -y --no-install-recommends \
        libcairo2-dev \
        libtiff5-dev \
        libxt-dev \
        libreadline-dev \
        libgtk2.0-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libxpm-dev \
        libmagick++-dev \
    #
    # ── Text and font rendering ───────────────────────────────────────────
    # libfontconfig/freetype: systemfonts, ragg, showtext
    # libharfbuzz/libfribidi: textshaping (required by ragg)
    # libpango: Cairo text rendering
    # libpoppler-cpp/glib: pdftools, qpdf
    && apt-get install -y --no-install-recommends \
        libfontconfig1-dev \
        libfreetype6-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        libpoppler-cpp-dev \
        libpoppler-glib-dev \
    #
    # ── Math and optimization ─────────────────────────────────────────────
    # libgmp: gmp, Rmpfr
    # libmpfr: Rmpfr
    # liblapack: Matrix, many linear algebra operations
    # coinor: lpsymphony, Rglpk (LP/MIP solvers for Bioc optimization)
    && apt-get install -y --no-install-recommends \
        libgmp3-dev \
        libmpfr-dev \
        liblapack-dev \
        coinor-libcgl-dev \
        coinor-libsymphony-dev \
        coinor-libsymphony-doc \
    #
    # ── Databases ─────────────────────────────────────────────────────────
    # libsqlite3: RSQLite, AnnotationDbi, ensembldb
    # libpq: RPostgres, RPostgreSQL
    # libmariadb-dev-compat: RMySQL, RMariaDB (provides libmysqlclient-dev
    #   on Noble; do NOT install both — they conflict)
    # libncurses: database CLI tools
    && apt-get install -y --no-install-recommends \
        libsqlite3-dev \
        libpq-dev \
        libmariadb-dev-compat \
        libncurses-dev \
    #
    # ── Serialization and IPC ─────────────────────────────────────────────
    # libprotobuf/libprotoc: RProtoBuf, cytolib
    # libv8: V8, cld2
    # librdf0: redland, rdflib (semantic web / ontology)
    # libarchive: archive
    # libhiredis: rredis
    # libzmq3: rzmq, pbdZMQ
    # libsecret-1: keyring
    # libsasl2: mongolite
    && apt-get install -y --no-install-recommends \
        libprotobuf-dev \
        libprotoc-dev \
        protobuf-compiler \
        libv8-dev \
        librdf0-dev \
        libarchive-dev \
        libhiredis-dev \
        libzmq3-dev \
        libsecret-1-dev \
        libsasl2-dev \
    #
    # ── Security / system ─────────────────────────────────────────────────
    # libapparmor: RAppArmor
    # libfuse: FUSE filesystem packages
    && apt-get install -y --no-install-recommends \
        libapparmor-dev \
        libfuse-dev \
    #
    # ── Java ──────────────────────────────────────────────────────────────
    # default-jdk: rJava, RJDBC, xlsx
    && apt-get install -y --no-install-recommends \
        default-jdk \
    #
    # ── Perl extensions ───────────────────────────────────────────────────
    # Various Bioconductor packages shell out to Perl tools
    && apt-get install -y --no-install-recommends \
        libperl-dev \
        libmodule-build-perl \
        libarchive-extract-perl \
        libfile-copy-recursive-perl \
        libcgi-pm-perl \
        libdbi-perl \
        libdbd-mysql-perl \
        libxml-simple-perl \
    #
    # ── Multimedia / specialized ──────────────────────────────────────────
    # libjpeg-turbo8/libjpeg: jpeg, EBImage, aplot
    # libavfilter: infinityFlow, video processing packages
    # mono-runtime: rawrr, MsBackendRawFileReader
    # ocl-icd-opencl: gpuMagic (GPU compute — needs GPU hardware)
    && apt-get install -y --no-install-recommends \
        libjpeg-dev \
        libjpeg-turbo8-dev \
        libjpeg8-dev \
        libavfilter-dev \
        mono-runtime \
        ocl-icd-opencl-dev \
    #
    # ── Command-line tools ────────────────────────────────────────────────
    # sqlite3: AnnotationDbi CLI access
    # openmpi-bin: MPI parallel execution
    # tcl/tk: tcltk R package, Shiny, gWidgets
    # imagemagick: magick package CLI backend
    # tabix: Rsamtools, VariantAnnotation (genomic index files)
    # ggobi: rggobi (interactive data visualization)
    # graphviz: Rgraphviz, DiagrammeR
    # jags: rjags (Bayesian modeling)
    && apt-get install -y --no-install-recommends \
        sqlite3 \
        openmpi-bin \
        mpi-default-bin \
        openmpi-common \
        openmpi-doc \
        tcl8.6-dev \
        tk-dev \
        imagemagick \
        tabix \
        ggobi \
        graphviz \
        jags \
    #
    # ── Systems biology / specialized science ─────────────────────────────
    # libsbml5: rsbml (systems biology markup language)
    # biber: BiocStyle, vignette building with biblatex
    # xfonts: plotting with specific X11 font sets
    && apt-get install -y --no-install-recommends \
        libsbml5-dev \
        biber \
        xfonts-100dpi \
        xfonts-75dpi \
    #
    # ── Python packages ───────────────────────────────────────────────────
    # Used by reticulate-based Bioconductor packages and basilisk
    && apt-get install -y --no-install-recommends \
        python3-pandas \
        python3-yaml \
        python3-sklearn \
    #
    # ── GTK development (gWidgets2, RGtk2) ────────────────────────────────
    && apt-get install -y --no-install-recommends \
        libgtkmm-2.4-dev \
    #
    # ── X11 and GUI libraries (required for RStudio Desktop) ──────────────
    # Runtime libraries RStudio Desktop needs for its Qt-based GUI under X11.
    && apt-get install -y --no-install-recommends \
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
    # ── D-Bus (needed by Qt/RStudio for IPC) ──────────────────────────────
        dbus \
        libdbus-1-3 \
    #
    # ── Fonts (rendering text in plots and RStudio) ───────────────────────
        fonts-dejavu-core \
        fonts-liberation \
        fontconfig \
    #
    # ── Utilities ─────────────────────────────────────────────────────────
        wget \
        curl \
        locales \
        file \
        git \
        procps \
        lsb-release \
    #
    # ── Cleanup ───────────────────────────────────────────────────────────
    && apt-get clean \
    && apt-get autoremove -y \
    && apt-get autoclean -y \
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
# Then install core infrastructure packages that most workflows need.
# Users install additional packages into their personal or site library.
#
# The full system dependency set installed above means ANY Bioconductor
# package can be compiled from source by users.
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
# Install preprocessCore with threading disabled
# https://github.com/Bioconductor/bioconductor_docker/issues/22
# ---------------------------------------------------------------------------
RUN R -e "\
    BiocManager::install('preprocessCore', \
        configure.args = c(preprocessCore = '--disable-threading'), \
        update = TRUE, force = TRUE, ask = FALSE, type = 'source')"

# ---------------------------------------------------------------------------
# R configuration files
# ---------------------------------------------------------------------------
COPY env/renviron.site /usr/local/lib/R/etc/Renviron.site
COPY env/rprofile.site /usr/local/lib/R/etc/Rprofile.site

# ---------------------------------------------------------------------------
# Shell environment configuration
# ---------------------------------------------------------------------------
COPY env/profile.d/bioc.sh /etc/profile.d/bioc.sh

# ---------------------------------------------------------------------------
# Launcher script for RStudio Desktop
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
# ---------------------------------------------------------------------------
CMD ["R"]
