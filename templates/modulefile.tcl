#%Module1.0
########################################################################
# Tcl modulefile for Bioconductor HPC Container
#
# Template variables (replaced by install_module.sh):
#   @@BIOC_VERSION@@    — Bioconductor version (e.g., 3.23)
#   @@R_VERSION@@       — Full R version (e.g., 4.6.0)
#   @@R_VERSION_SHORT@@ — Short R version (e.g., 4.6)
#   @@IMAGE_DIR@@       — Path to SIF images
#   @@IMAGE_FILE@@      — SIF filename
#
# NOTE: Tcl modules only support aliases (not shell functions). Aliases
# do not work in non-interactive scripts. For scripted use, invoke
# apptainer directly or use the Lmod (Lua) modulefile instead.
########################################################################

proc ModulesHelp { } {
    puts stderr "R @@R_VERSION@@ with Bioconductor @@BIOC_VERSION@@ and RStudio Desktop"
    puts stderr ""
    puts stderr "Usage:"
    puts stderr "  R                     Interactive R session"
    puts stderr "  Rscript script.R      Run an R script"
    puts stderr "  rstudio               Launch RStudio Desktop (requires X11)"
    puts stderr ""
    puts stderr "Package libraries:"
    puts stderr "  User:   ~/R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@"
    puts stderr "  Site:   /apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor"
}

module-whatis "R @@R_VERSION@@ with Bioconductor @@BIOC_VERSION@@ and RStudio Desktop for HPC"

conflict bioconductor R R-bioconductor Rstudio r rstudio r-rstudio r-rnaseq

# Image configuration
set image_dir  "@@IMAGE_DIR@@"
set image_file "@@IMAGE_FILE@@"
set image_path "$image_dir/$image_file"

# Container runtime
set singularity [exec which singularity 2>/dev/null || which apptainer 2>/dev/null]

# Container launch command
set container_launch "$singularity run $image_path"

# Aliases for R programs
set-alias R        "$container_launch R"
set-alias Rscript  "$container_launch Rscript"
set-alias rstudio  "$container_launch rstudio --no-sandbox"

# Bind mounts
append-path APPTAINER_BIND "/apps/biocontainers/extras" ","
append-path APPTAINER_BIND "/var/opt" ","
append-path APPTAINER_BIND "/run/user" ","
append-path APPTAINER_BIND "/usr/share/fonts" ","

# Environment variables
setenv BIOC_VERSION    "@@BIOC_VERSION@@"
setenv R_VERSION       "@@R_VERSION@@"
setenv R_VERSION_SHORT "@@R_VERSION_SHORT@@"
setenv R_LIBS_SITE     "/apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor"
setenv R_LIBS_USER     "$env(HOME)/R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@"

# Qt/X11 for RStudio Desktop
setenv QT_X11_NO_MITSHM "1"
setenv QT_QPA_PLATFORM  "xcb"

# Clear host compiler variables so R uses its internal compilers
setenv APPTAINERENV_CC  ""
setenv APPTAINERENV_CXX ""
setenv APPTAINERENV_FC  ""
setenv APPTAINERENV_F77 ""
setenv APPTAINERENV_F90 ""
setenv APPTAINERENV_F95 ""

# Thread defaults — prevent over-subscription in cgroup-limited jobs
if { ![info exists env(OMP_NUM_THREADS)] } {
    setenv OMP_NUM_THREADS "1"
}
if { ![info exists env(OPENBLAS_NUM_THREADS)] } {
    setenv OPENBLAS_NUM_THREADS "1"
}

# TMPDIR on scratch
if { [info exists env(USER)] } {
    setenv TMPDIR "/scratch/$env(USER)/tmp"
}

if { [module-info mode load] } {
    puts stderr "Bioconductor @@BIOC_VERSION@@ loaded (R @@R_VERSION@@, RStudio Desktop)"
    puts stderr "  Commands: R, Rscript, rstudio"
}
