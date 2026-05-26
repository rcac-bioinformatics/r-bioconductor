------------------------------------------------------------------------
-- Lmod modulefile for Bioconductor HPC Container
--
-- Provides R, Rscript, and RStudio Desktop via Apptainer.
--
-- Template variables (replaced by install_module.sh):
--   @@BIOC_VERSION@@   — Bioconductor version (e.g., 3.21)
--   @@R_VERSION@@      — Full R version (e.g., 4.5.0)
--   @@R_VERSION_SHORT@@— Short R version (e.g., 4.5)
--   @@IMAGE_DIR@@      — Path to SIF images
--   @@IMAGE_FILE@@     — SIF filename
------------------------------------------------------------------------

help([[
Bioconductor @@BIOC_VERSION@@ with R @@R_VERSION@@ and RStudio Desktop

This module provides R, Rscript, and RStudio Desktop from the
Bioconductor HPC container (@@IMAGE_FILE@@).

Usage:
  R                     Interactive R session
  Rscript script.R      Run an R script
  rstudio               Launch RStudio Desktop (requires X11)

Package libraries:
  User:   ~/R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@
  Site:   /apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor

Install packages:
  BiocManager::install("PackageName")    # Bioconductor
  install.packages("PackageName")        # CRAN
]])

whatis("Name:        Bioconductor")
whatis("Version:     @@BIOC_VERSION@@")
whatis("Description: Bioconductor @@BIOC_VERSION@@ with R @@R_VERSION@@ and RStudio Desktop for HPC")
whatis("URL:         https://bioconductor.org")

-- Only one Bioconductor version at a time
conflict("bioconductor")
conflict("R")

-- Image location
local image_dir  = "@@IMAGE_DIR@@"
local image_file = "@@IMAGE_FILE@@"
local image_path = pathJoin(image_dir, image_file)

-- Apptainer bind mounts — edit for your site
local bind_paths = table.concat({
    "/apps/biocontainers/extras",
    "/scratch",
}, ",")

-- Environment variables
setenv("BIOC_VERSION",    "@@BIOC_VERSION@@")
setenv("R_VERSION",       "@@R_VERSION@@")
setenv("R_VERSION_SHORT", "@@R_VERSION_SHORT@@")
setenv("R_LIBS_USER",     pathJoin(os.getenv("HOME"), "R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@"))
setenv("R_LIBS_SITE",     "/apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor")

-- Qt/X11 for RStudio Desktop
setenv("QT_X11_NO_MITSHM", "1")
setenv("QT_QPA_PLATFORM",  "xcb")

-- TMPDIR — redirect to scratch if available
local scratch = pathJoin("/scratch", os.getenv("USER") or "unknown", "tmp")
setenv("TMPDIR", scratch)

-- Shell functions that wrap apptainer exec
-- Using shell functions instead of aliases because:
--   1. Functions work in scripts (aliases only in interactive shells)
--   2. Functions propagate arguments correctly
--   3. Functions work with xargs, find -exec, etc.

local apptainer_exec = "apptainer exec --bind " .. bind_paths .. " " .. image_path

set_shell_function("R", apptainer_exec .. " R \"$@\"",
                        apptainer_exec .. " R $*")

set_shell_function("Rscript", apptainer_exec .. " Rscript \"$@\"",
                              apptainer_exec .. " Rscript $*")

set_shell_function("rstudio", apptainer_exec .. " launch-rstudio \"$@\"",
                              apptainer_exec .. " launch-rstudio $*")

set_shell_function("bioc-shell", apptainer_exec .. " bash \"$@\"",
                                 apptainer_exec .. " bash $*")

-- Inform user on load
if mode() == "load" then
    LmodMessage("Bioconductor @@BIOC_VERSION@@ loaded (R @@R_VERSION@@, RStudio Desktop)")
    LmodMessage("  Commands: R, Rscript, rstudio, bioc-shell")
end
