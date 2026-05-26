#%Module1.0
########################################################################
# Tcl modulefile for Bioconductor HPC Container
#
# Provides R, Rscript, and RStudio Desktop via Apptainer.
#
# Template variables (replaced by install_module.sh):
#   @@BIOC_VERSION@@   — Bioconductor version (e.g., 3.21)
#   @@R_VERSION@@      — Full R version (e.g., 4.5.0)
#   @@R_VERSION_SHORT@@— Short R version (e.g., 4.5)
#   @@IMAGE_DIR@@      — Path to SIF images
#   @@IMAGE_FILE@@     — SIF filename
########################################################################

proc ModulesHelp { } {
    puts stderr "Bioconductor @@BIOC_VERSION@@ with R @@R_VERSION@@ and RStudio Desktop"
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

module-whatis "Bioconductor @@BIOC_VERSION@@ with R @@R_VERSION@@ and RStudio Desktop for HPC"

# Only one Bioconductor version at a time
conflict bioconductor
conflict R

# Image configuration
set image_dir  "@@IMAGE_DIR@@"
set image_file "@@IMAGE_FILE@@"
set image_path "$image_dir/$image_file"

# Bind mounts — edit for your site
set bind_paths "/apps/biocontainers/extras,/scratch"

# Environment variables
setenv BIOC_VERSION    "@@BIOC_VERSION@@"
setenv R_VERSION       "@@R_VERSION@@"
setenv R_VERSION_SHORT "@@R_VERSION_SHORT@@"
setenv R_LIBS_USER     "$env(HOME)/R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@"
setenv R_LIBS_SITE     "/apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor"

# Qt/X11 for RStudio Desktop
setenv QT_X11_NO_MITSHM "1"
setenv QT_QPA_PLATFORM  "xcb"

# TMPDIR — redirect to scratch if available
if { [info exists env(USER)] } {
    setenv TMPDIR "/scratch/$env(USER)/tmp"
} else {
    setenv TMPDIR "/tmp"
}

# Wrapper scripts via aliases
# NOTE: Tcl modules only support aliases (not functions). For scripts
# that need to work non-interactively, users should call apptainer
# directly or use the Lmod modulefile instead.
set apptainer_exec "apptainer exec --bind $bind_paths $image_path"

set-alias R        "$apptainer_exec R"
set-alias Rscript  "$apptainer_exec Rscript"
set-alias rstudio  "$apptainer_exec launch-rstudio"
set-alias bioc-shell "$apptainer_exec bash"

# Inform user
if { [module-info mode load] } {
    puts stderr "Bioconductor @@BIOC_VERSION@@ loaded (R @@R_VERSION@@, RStudio Desktop)"
    puts stderr "  Commands: R, Rscript, rstudio, bioc-shell"
}
