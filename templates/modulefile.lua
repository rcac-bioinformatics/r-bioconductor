-- The MIT License (MIT)
--
-- Copyright (c) 2021 Purdue University
-- Copyright (c) 2020 NVIDIA Corporation
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.

------------------------------------------------------------------------
-- Template variables (replaced by install_module.sh):
--   @@BIOC_VERSION@@    — Bioconductor version (e.g., 3.23)
--   @@R_VERSION@@       — Full R version (e.g., 4.6.0)
--   @@R_VERSION_SHORT@@ — Short R version (e.g., 4.6)
--   @@IMAGE_DIR@@       — Path to SIF images
--   @@IMAGE_FILE@@      — SIF filename
------------------------------------------------------------------------

help([==[

Description
===========

R is a system for statistical computation and graphics.

This is an R/@@R_VERSION@@ Apptainer image with Bioconductor @@BIOC_VERSION@@
and RStudio Desktop installed.

RStudio is an integrated development environment (IDE) for the R statistical
computation and graphics system. This module provides RStudio Desktop (not
Server), which runs as a normal X11 application inside ThinLinc or Open
OnDemand desktop sessions.

Usage
=====
  R                     Interactive R session
  Rscript script.R      Run an R script
  rstudio               Launch RStudio Desktop (requires X11 display)

Package libraries
=================
  User:   ~/R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@
  Site:   /apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor

Install packages
================
  BiocManager::install("PackageName")    # Bioconductor
  install.packages("PackageName")        # CRAN

More information
================
 - Bioconductor: https://bioconductor.org/
 - R project:    https://www.r-project.org/
 - RStudio:      https://www.rstudio.com/products/rstudio/
]==])

whatis("Name:         r-bioconductor")
whatis("Version:      @@BIOC_VERSION@@")
whatis("Description:  R @@R_VERSION@@ with Bioconductor @@BIOC_VERSION@@ and RStudio Desktop IDE for HPC")
whatis("URL:          https://bioconductor.org/")
whatis("URL:          https://www.r-project.org/")

-- =========================================================================
-- Singularity/Apptainer module auto-load
--
-- Loads the container runtime module if not already loaded.
-- Set BIOC_SINGULARITY_MODULE="none" to skip auto-loading (e.g., if
-- apptainer is available system-wide without a module).
-- =========================================================================
if not (os.getenv("BIOC_SINGULARITY_MODULE") == "none") then
   local singularity_module = os.getenv("BIOC_SINGULARITY_MODULE") or "Singularity"
   if not (isloaded(singularity_module)) then
      load(singularity_module)
   end
end

-- =========================================================================
-- Conflicts — only one R/Bioconductor/RStudio environment at a time
-- =========================================================================
conflict(myModuleName(), "R", "R-bioconductor", "Rstudio", "r", "rstudio", "r-rstudio", "r-rnaseq")

-- =========================================================================
-- Container image
-- =========================================================================
local image = "@@IMAGE_FILE@@"
local uri = ""

-- The absolute path to the container runtime is needed so it can be
-- invoked on remote nodes without the module necessarily being loaded.
local singularity = capture("which singularity 2>/dev/null || which apptainer 2>/dev/null | head -c -1")

if (os.getenv("BIOC_IMAGE_DIR")) then
   image = pathJoin(os.getenv("BIOC_IMAGE_DIR"), image)

   if not (isFile(image)) then
      -- Image not found in the container directory
      if (mode() == "load") then
         LmodMessage("file not found: " .. image)
         LmodMessage("The container image will be pulled upon first use to the Singularity cache")
      end
      image = uri
   end
else
   -- Default image directory
   image = pathJoin("@@IMAGE_DIR@@", "@@IMAGE_FILE@@")

   if not (isFile(image)) then
      if (mode() == "load") then
         LmodMessage("file not found: " .. image)
         LmodMessage("Set BIOC_IMAGE_DIR to the directory containing " .. "@@IMAGE_FILE@@")
      end
      image = uri
   end
end

-- =========================================================================
-- GPU detection — pass --nv or --rocm to the container runtime
-- =========================================================================
local run_args = {}
if (capture("nvidia-smi -L 2>/dev/null") ~= "") then
   if (mode() == "load") then
      LmodMessage("BIOC: Enabling Nvidia GPU support in the container.")
   end
   table.insert(run_args, "--nv")
end
if (capture("/opt/rocm/bin/rocm-smi -i 2>/dev/null | grep ^GPU") ~= "") then
   if (mode() == "load") then
      LmodMessage("BIOC: Enabling AMD GPU support in the container.")
   end
   table.insert(run_args, "--rocm")
end

-- =========================================================================
-- Assemble the container launch command
-- =========================================================================
local container_launch = singularity .. " run " .. table.concat(run_args, " ") .. " " .. image

-- =========================================================================
-- Shell functions for CLI programs
--
-- Using shell functions (not aliases) because:
--   1. Functions work in non-interactive scripts
--   2. Functions propagate arguments correctly
--   3. Functions work with xargs, find -exec, etc.
-- =========================================================================
local programs = {"R", "Rscript"}
for _,program in pairs(programs) do
    set_shell_function(program, container_launch .. " " .. program .. " \"$@\"",
                                container_launch .. " " .. program .. " $*")
end

-- RStudio Desktop: use --no-sandbox to avoid Chromium/Electron sandbox
-- issues inside containers where user namespaces may be restricted.
set_shell_function("rstudio", container_launch .. " rstudio --no-sandbox \"$@\"",
                              container_launch .. " rstudio --no-sandbox $*")

-- =========================================================================
-- Bind mounts via APPTAINER_BIND
--
-- The container's Renviron.site references the site library and expects
-- it to be visible inside the container.
-- =========================================================================

-- Site R library (required for shared packages)
append_path("APPTAINER_BIND", "/apps/biocontainers/extras", ",")

-- ThinLinc X11 session support
append_path("APPTAINER_BIND", "/var/opt",  ",")
append_path("APPTAINER_BIND", "/run/user", ",")

-- X11 fonts — RStudio needs host fonts for readable terminal/editor text
append_path("APPTAINER_BIND", "/usr/share/fonts", ",")

-- =========================================================================
-- Environment variables
-- =========================================================================
setenv("BIOC_VERSION",    "@@BIOC_VERSION@@")
setenv("R_VERSION",       "@@R_VERSION@@")
setenv("R_VERSION_SHORT", "@@R_VERSION_SHORT@@")

-- R library paths
-- R_LIBS_SITE: shared site library (admin-managed, bind-mounted)
-- R_LIBS_USER: per-user writable library (on host home directory)
setenv("R_LIBS_SITE", "/apps/biocontainers/extras/r-package-site-library/@@R_VERSION_SHORT@@-bioconductor")
setenv("R_LIBS_USER", pathJoin(os.getenv("HOME") or "", "R/x86_64-pc-linux-gnu-library/@@R_VERSION_SHORT@@"))

-- Qt/X11 for RStudio Desktop inside containers
setenv("QT_X11_NO_MITSHM", "1")
setenv("QT_QPA_PLATFORM",  "xcb")

-- =========================================================================
-- Compiler environment — clear host compiler variables
--
-- R builds source packages with its own internal CC/CXX/FC settings
-- (configured at R compile time inside the container). If host compiler
-- variables leak in, source package compilation fails with mismatched
-- compilers or missing flags.
-- =========================================================================
pushenv("APPTAINERENV_CC",  "")
pushenv("APPTAINERENV_CXX", "")
pushenv("APPTAINERENV_FC",  "")
pushenv("APPTAINERENV_F77", "")
pushenv("APPTAINERENV_F90", "")
pushenv("APPTAINERENV_F95", "")

-- =========================================================================
-- Thread defaults — prevent over-subscription in cgroup-limited SLURM jobs
--
-- When a SLURM job is allocated 1 core but the node has 128 cores,
-- nproc still reports 128. Libraries like OpenBLAS will spawn 128 threads
-- on that single core, destroying performance. Default to 1 thread;
-- users or job scripts can override when they have allocated more cores.
-- =========================================================================
if (mode() == "load") then
    if os.getenv("OMP_NUM_THREADS") == nil then
        setenv("OMP_NUM_THREADS", "1")
    end
    if os.getenv("OPENBLAS_NUM_THREADS") == nil then
        setenv("OPENBLAS_NUM_THREADS", "1")
    end
end

-- =========================================================================
-- TMPDIR — redirect to scratch storage
--
-- Default /tmp is often a tiny tmpfs on compute nodes. Large genomics
-- workflows (scRNA-seq, WGS) can generate gigabytes of temp files.
-- =========================================================================
local user = os.getenv("USER") or "unknown"
local scratch = pathJoin("/scratch", user, "tmp")
setenv("TMPDIR", scratch)

-- =========================================================================
-- Load message
-- =========================================================================
if (mode() == "load") then
    LmodMessage("Bioconductor @@BIOC_VERSION@@ loaded (R @@R_VERSION@@, RStudio Desktop)")
    LmodMessage("  Commands: R, Rscript, rstudio")
end
