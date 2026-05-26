# Troubleshooting Guide

This guide covers common problems when running the Bioconductor HPC container
(R, RStudio Desktop, Bioconductor via Apptainer) on HPC clusters, and provides
specific solutions for each.

---

## Table of Contents

- [1. RStudio Desktop Will Not Start](#1-rstudio-desktop-will-not-start)
- [2. X11 and Display Issues](#2-x11-and-display-issues)
- [3. R Package Installation Failures](#3-r-package-installation-failures)
- [4. Apptainer Issues](#4-apptainer-issues)
- [5. Performance Issues](#5-performance-issues)
- [6. Module Issues](#6-module-issues)
- [7. Common Error Messages](#7-common-error-messages)
- [8. Diagnostic Commands Reference](#8-diagnostic-commands-reference)

---

## 1. RStudio Desktop Will Not Start

### 1.1 DISPLAY Not Set

**Symptom:**

```
ERROR: DISPLAY is not set. RStudio Desktop requires an X11 display.
```

**Cause:** RStudio Desktop is an X11 application. It requires a running X
server and the `DISPLAY` environment variable to be set so that it knows where
to render its window. This variable is missing when you are connected through a
plain SSH session without X11 forwarding, or when running in a non-interactive
batch job.

**Solution:**

Use one of these methods to provide an X11 display:

1. **ThinLinc** (recommended): Connect to the cluster via a ThinLinc client.
   DISPLAY is set automatically when you open a ThinLinc desktop session.

2. **Open OnDemand**: Launch an interactive desktop session through Open
   OnDemand. The VNC session provides X11 and sets DISPLAY for you.

3. **SSH with X11 forwarding**: Connect with `ssh -X user@cluster` or
   `ssh -Y user@cluster`, then verify:

   ```bash
   echo $DISPLAY
   # Should print something like localhost:10.0
   ```

4. **SLURM with X11**: If your cluster supports it, use the `--x11` flag:

   ```bash
   srun --x11 --pty apptainer exec bioconductor-hpc-3.21.sif launch-rstudio
   ```

If you only need R without a GUI, use `R` or `Rscript` directly -- they do
not require X11.

### 1.2 Qt Platform Plugin Errors

**Symptom:**

```
qt.qpa.plugin: Could not find the Qt platform plugin "xcb" in ""
This application failed to start because no Qt platform plugin could be initialized.
```

Or:

```
qt.qpa.xcb: could not connect to display
```

**Cause:** RStudio Desktop uses Qt for its GUI. Qt needs the xcb (X C Binding)
platform plugin to render under X11. This error occurs when the
`QT_QPA_PLATFORM` variable is not set, when the plugin path is wrong, or when
the required X11 libraries are missing.

**Solution:**

The `launch-rstudio` wrapper script and the Apptainer `%environment` section
both set these variables automatically. If you are invoking RStudio directly
without the wrapper, set them manually:

```bash
export QT_QPA_PLATFORM=xcb
export QT_X11_NO_MITSHM=1
```

If the error persists, confirm the plugin path:

```bash
apptainer exec bioconductor-hpc-3.21.sif \
    find /usr/lib/rstudio -name 'libqxcb*' -o -name '*xcb*'
```

If the plugin exists but is not found at runtime, set the path explicitly:

```bash
export QT_QPA_PLATFORM_PLUGIN_PATH=/usr/lib/rstudio/plugins/platforms
```

Then retry launching RStudio.

### 1.3 D-Bus Errors

**Symptom:**

```
dbus[1234]: Failed to start message bus: ...
```

Or:

```
qt.dbus: Could not connect to D-Bus session bus
```

Or warnings containing `QDBusConnection` or `session bus`.

**Cause:** Qt applications expect a D-Bus session bus for inter-process
communication. Inside containers, the D-Bus daemon is typically not running.

**Solution:**

The `launch-rstudio` wrapper starts a private D-Bus session automatically. If
you are not using the wrapper, start one manually before launching RStudio:

```bash
eval "$(dbus-launch --sh-syntax)"
/usr/lib/rstudio/rstudio
```

If `dbus-launch` is not available, these warnings are usually non-fatal.
RStudio will still function. To suppress the warnings, set:

```bash
export QT_ACCESSIBILITY=0
export NO_AT_BRIDGE=1
```

These are set by default in the container environment and in the
`launch-rstudio` wrapper.

### 1.4 Font Issues

**Symptom:**

```
Fontconfig error: Cannot load default config file: No such file: (null)
```

Or: RStudio launches but text is rendered as empty boxes, or R plots show
missing glyphs.

**Cause:** The fontconfig cache directory is not writable, the fontconfig
configuration path is wrong inside the container, or the cache is stale.

**Solution:**

1. Ensure the fontconfig cache directory exists and is writable:

   ```bash
   mkdir -p ~/.cache/fontconfig
   ```

2. If the fontconfig configuration path is wrong, set it explicitly:

   ```bash
   export FONTCONFIG_PATH=/etc/fonts
   ```

3. Rebuild the fontconfig cache from within the container:

   ```bash
   apptainer exec bioconductor-hpc-3.21.sif fc-cache -fv
   ```

4. Verify fonts are available:

   ```bash
   apptainer exec bioconductor-hpc-3.21.sif fc-list | head -20
   ```

   You should see DejaVu and Liberation font families listed. If the output is
   empty, the fonts directory may not be accessible inside the container.

### 1.5 MIT-SHM / Shared Memory Errors

**Symptom:**

```
X Error: BadAccess (attempt to access private resource denied)
  Major opcode: 130 (MIT-SHM)
```

Or:

```
qt.qpa.xcb: X server does not support shared memory
```

**Cause:** The MIT-SHM (Shared Memory) X extension requires the X client and X
server to share the same memory space. Inside a container, client and server
are in different namespaces, so shared memory segments are not accessible.

**Solution:**

Disable MIT-SHM:

```bash
export QT_X11_NO_MITSHM=1
```

This is set automatically by the container environment (`%environment` in the
Apptainer definition), the `launch-rstudio` wrapper, and the module files. If
you see this error, you are likely bypassing these mechanisms. Use the
`launch-rstudio` command instead of calling the RStudio binary directly.

---

## 2. X11 and Display Issues

### 2.1 SSH X11 Forwarding Not Working

**Symptom:**

`DISPLAY` is empty after connecting with `ssh -X`, or X applications fail with
"cannot open display".

**Cause:** X11 forwarding can fail for several reasons:

- The server does not allow X11 forwarding.
- `xauth` is not installed or not generating cookies correctly.
- The connection was not established with `-X` or `-Y`.
- A firewall blocks the X11 back-channel.

**Solution:**

1. Verify you connected with X11 forwarding enabled:

   ```bash
   ssh -X user@cluster.example.edu
   ```

   Use `-Y` (trusted forwarding) if `-X` fails due to security restrictions:

   ```bash
   ssh -Y user@cluster.example.edu
   ```

2. Check the server-side SSH configuration. An HPC admin should confirm that
   `/etc/ssh/sshd_config` contains:

   ```
   X11Forwarding yes
   X11UseLocalhost yes
   ```

3. Verify `xauth` is working:

   ```bash
   xauth list
   # Should show at least one entry
   ```

   If `xauth list` is empty, `xauth` may not be in your PATH or the
   `.Xauthority` file may be corrupt. Remove and reconnect:

   ```bash
   rm -f ~/.Xauthority
   # Then disconnect and reconnect with ssh -X
   ```

4. Test X11 with a simple application:

   ```bash
   xeyes    # or xclock, or xterm
   ```

   If `xeyes` works but RStudio does not, the problem is container-specific
   (see Section 1 above).

5. X11 forwarding over multiple hops (login node to compute node) requires
   forwarding at each step. Use `ssh -X` for each hop, or use SLURM's
   `--x11` flag if supported.

### 2.2 ThinLinc Sessions

ThinLinc desktop sessions set `DISPLAY` automatically. If `DISPLAY` is not
set in a ThinLinc terminal:

1. Confirm you are in a ThinLinc desktop session (not a plain SSH connection
   to the same host).

2. Open a terminal emulator from within the ThinLinc desktop -- the DISPLAY
   variable will be inherited from the desktop environment.

3. Verify: `echo $DISPLAY` should print something like `:1` or `:2`.

If DISPLAY is set but RStudio fails, check that the DISPLAY value is still
valid. ThinLinc sessions can become disconnected, and the X server for the old
DISPLAY number may no longer be running. Reconnect to ThinLinc or start a new
session.

### 2.3 Open OnDemand Sessions

Open OnDemand interactive desktop sessions provide X11 through a VNC server.

- DISPLAY is set automatically within the VNC desktop.
- Launch RStudio from a terminal inside the OOD desktop session.
- If DISPLAY is not set, check that you launched an "Interactive Desktop"
  session, not a plain shell or Jupyter session.

### 2.4 Testing X11 Connectivity

Before debugging RStudio, confirm X11 itself works:

```bash
# Simple X11 test applications (run on the host, not in the container):
xeyes &
xclock &
xterm &

# Test X11 from inside the container:
apptainer exec bioconductor-hpc-3.21.sif xterm
```

If `xterm` works from inside the container but RStudio does not, the issue is
specific to RStudio or Qt configuration (see Section 1).

---

## 3. R Package Installation Failures

### 3.1 "Installation path not writable"

**Symptom:**

```
Warning in install.packages :
  'lib = "/usr/local/lib/R/site-library"' is not writable
```

Or R prompts you to create a personal library and the creation fails.

**Cause:** The container image is read-only under Apptainer. Packages cannot be
installed into the container's R library (`/usr/local/lib/R/library` or
`/usr/local/lib/R/site-library`). You must install into either the user library
or the site library, both of which reside on writable host filesystems.

**Solution:**

1. Ensure your user library directory exists:

   ```bash
   mkdir -p ~/R/x86_64-pc-linux-gnu-library/4.5
   ```

   The `launch-rstudio` wrapper and the container's `Rprofile.site` create this
   directory automatically. If it was not created, the home directory may not
   be writable or the path may be incorrect.

2. Install packages specifying the user library explicitly:

   ```r
   install.packages("ggplot2", lib = Sys.getenv("R_LIBS_USER"))
   ```

   Or with BiocManager:

   ```r
   BiocManager::install("DESeq2", lib = Sys.getenv("R_LIBS_USER"))
   ```

3. Verify your library paths in R:

   ```r
   .libPaths()
   ```

   The first path should be your user library (writable). If the user library
   is not listed, check that `R_LIBS_USER` is set:

   ```r
   Sys.getenv("R_LIBS_USER")
   ```

### 3.2 Missing System Libraries

**Symptom:**

```
ERROR: configuration failed for package 'some_package'
```

Or during compilation:

```
/usr/bin/ld: cannot find -lsomelib
```

Or:

```
some_header.h: No such file or directory
```

**Cause:** The R package requires a system-level C/C++ library that is not
installed in the container. While the container includes the most common
development libraries (curl, ssl, xml2, hdf5, cairo, fftw3, gsl, etc.), some
packages need libraries not included in the base image.

**Solution:**

1. Identify the missing library. The error message usually names it. Common
   mappings:

   | Error mentions       | Ubuntu package needed       |
   |---------------------|-----------------------------|
   | `-lcurl`            | `libcurl4-openssl-dev`      |
   | `-lssl`             | `libssl-dev`                |
   | `-lxml2`            | `libxml2-dev`               |
   | `-lhdf5`            | `libhdf5-dev`               |
   | `-lfftw3`           | `libfftw3-dev`              |
   | `-lgsl`             | `libgsl-dev`                |
   | `-lgdal`            | `libgdal-dev`               |
   | `-ludunits2`        | `libudunits2-dev`           |
   | `-lnetcdf`          | `libnetcdf-dev`             |
   | `-lmagick`          | `libmagick++-dev`           |
   | `jni.h`             | `default-jdk`               |

2. Since the container is read-only, you cannot `apt-get install` inside it.
   Options:

   - **Ask your HPC administrator** to rebuild the container with the
     additional library. Add the package to the `apt-get install` block in the
     `Dockerfile`.

   - **Use an overlay**: If your site supports Apptainer overlays, you can
     create a writable overlay and install the library there:

     ```bash
     apptainer overlay create --size 512 overlay.img
     apptainer exec --overlay overlay.img --fakeroot bioconductor-hpc-3.21.sif \
         apt-get update && apt-get install -y libgdal-dev
     ```

   - **Build a derived container**: Create a new Dockerfile that inherits from
     this image and adds the needed library.

3. For R packages that use the `configure` script to find system libraries,
   you can sometimes point them to an alternative location using `configure.args`
   or `configure.vars`:

   ```r
   install.packages("rgdal",
       configure.args = "--with-gdal-config=/path/to/gdal-config")
   ```

### 3.3 BiocManager Version Mismatch Warnings

**Symptom:**

```
Bioconductor version '3.21' is out-of-date; the current release version '3.22' is available.
```

Or:

```
'getOption("repos")' replaces Bioconductor standard repositories, see 'help("repositories", package = "BiocManager")' for details.
```

**Cause:** BiocManager detects that a newer Bioconductor release exists and
warns about it. This is informational, not an error. The container pins a
specific Bioconductor version to ensure reproducibility.

**Solution:**

These warnings are safe to ignore. The container is intentionally pinned to a
specific Bioconductor version (set during build). To suppress the warning:

```r
options(BiocManager.check_repositories = FALSE)
```

This is already set in the container's `Rprofile.site`. If you still see the
warning, it may be overridden by your personal `~/.Rprofile`. Check for and
remove any conflicting settings:

```bash
grep -n "BiocManager\|repos" ~/.Rprofile 2>/dev/null
```

Do not upgrade the Bioconductor version inside a pinned container -- package
binary compatibility depends on the R and Bioconductor versions matching.

---

## 4. Apptainer Issues

### 4.1 "Container is not writable"

**Symptom:**

```
WARNING: Skipping mount /some/path [binds]: destination does not exist in container
FATAL: container is not writable
```

Or trying to install software inside the container fails with permission
errors.

**Cause:** SIF images are read-only by design. This is expected behavior, not a
bug. The container filesystem cannot be modified at runtime.

**Solution:**

This is working as intended. Install R packages into your user library
(`~/R/x86_64-pc-linux-gnu-library/4.5`) or the shared site library
(`/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor`), both of
which are on writable host filesystems accessed via bind mounts.

If you need to install system-level software, ask your administrator to rebuild
the container image or use an Apptainer overlay (see Section 3.2).

### 4.2 Bind Mount Errors

**Symptom:**

```
WARNING: Skipping mount /scratch [binds]: /scratch doesn't exist in container
```

Or:

```
FATAL: container creation failed: mount /apps/biocontainers/extras->/apps/biocontainers/extras error: ...
```

**Cause:** Apptainer bind mounts require that the source path exists on the
host AND that the destination path exists inside the container. If either is
missing, the bind fails.

**Solution:**

1. Verify the source path exists on the host:

   ```bash
   ls -la /apps/biocontainers/extras
   ls -la /scratch
   ```

2. If the host path exists but the container path does not, create it using an
   overlay or ask your admin to add `mkdir -p /path` to the Dockerfile.

3. For the site library, ensure the directory exists and is writable:

   ```bash
   # As admin or with appropriate permissions:
   mkdir -p /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
   ```

4. Check the bind mount configuration. If using the module, inspect the bind
   paths:

   ```bash
   module show bioconductor/3.21
   ```

   If using the environment file, review `apptainer/environment.sh` and edit
   the bind paths for your site.

5. To add custom bind mounts:

   ```bash
   export APPTAINER_BIND="/data,/project,/work"
   apptainer exec bioconductor-hpc-3.21.sif R
   ```

   Or pass them directly:

   ```bash
   apptainer exec --bind /data --bind /project bioconductor-hpc-3.21.sif R
   ```

### 4.3 Permission Denied / UID Mapping

**Symptom:**

```
FATAL: while extracting ... : root mapping was not requested ...
```

Or files inside bind-mounted directories show wrong ownership or are
inaccessible.

**Cause:** Apptainer maps the host UID/GID into the container. Files owned by
root inside the container image are accessible, but bind-mounted files retain
their host permissions. If your host UID does not have permission to read a
file, it will not be readable inside the container either.

**Solution:**

1. Verify file permissions on the host:

   ```bash
   ls -la /apps/biocontainers/images/bioconductor-hpc-3.21.sif
   ```

   The SIF file must be readable by your user.

2. For fakeroot-related errors when building (not running) containers, the
   admin needs to configure `/etc/subuid` and `/etc/subgid` or enable
   unprivileged user namespaces:

   ```bash
   # Admin action:
   echo "username:100000:65536" >> /etc/subuid
   echo "username:100000:65536" >> /etc/subgid
   ```

3. For NFS-mounted home directories with `root_squash`, Apptainer may fail
   to access certain paths. Set the Apptainer cache and temp directories to
   local storage:

   ```bash
   export APPTAINER_CACHEDIR=/tmp/${USER}/apptainer-cache
   export APPTAINER_TMPDIR=/tmp/${USER}/apptainer-tmp
   mkdir -p "$APPTAINER_CACHEDIR" "$APPTAINER_TMPDIR"
   ```

### 4.4 /tmp Full

**Symptom:**

```
Error in file(file, "rt") : cannot open the connection
In addition: Warning message:
In file(file, "rt") : cannot open file '/tmp/RtmpXXXXXX/...': No space left on device
```

Or Apptainer itself fails with "no space left on device" during execution.

**Cause:** HPC compute nodes often mount `/tmp` as a small tmpfs (typically
1-4 GB). Large genomics workloads (scRNA-seq, WGS) can generate gigabytes of
temporary files and exhaust this space.

**Solution:**

Redirect TMPDIR to the scratch filesystem before running R or RStudio:

```bash
export TMPDIR=/scratch/${USER}/tmp
mkdir -p "$TMPDIR"
```

The container environment does this automatically if `/scratch/${USER}` exists.
To verify:

```bash
apptainer exec bioconductor-hpc-3.21.sif bash -c 'echo $TMPDIR'
```

In your SLURM job script, set TMPDIR early:

```bash
#!/bin/bash
#SBATCH --job-name=bioc_analysis
#SBATCH --tmp=50G

export TMPDIR=/scratch/${USER}/tmp/${SLURM_JOB_ID}
mkdir -p "$TMPDIR"

apptainer exec bioconductor-hpc-3.21.sif Rscript analysis.R

# Clean up
rm -rf "$TMPDIR"
```

Also redirect the Apptainer temporary directory:

```bash
export APPTAINER_TMPDIR=/scratch/${USER}/apptainer-tmp
mkdir -p "$APPTAINER_TMPDIR"
```

### 4.5 HOME Directory Issues

**Symptom:**

R cannot find `~/.Rprofile`, packages are not found despite being installed, or
RStudio configuration is missing.

**Cause:** By default, Apptainer bind-mounts the user's home directory into
the container. If the home directory is on NFS and the NFS mount is not
available on the compute node, or if the home directory path differs between
the login and compute nodes, the bind will silently fail or mount the wrong
location.

**Solution:**

1. Verify your home directory is accessible on the compute node:

   ```bash
   srun --pty bash -c "ls -la $HOME"
   ```

2. If the home directory is not available, set `HOME` to an accessible
   location and bind-mount it:

   ```bash
   export APPTAINER_HOME=/scratch/${USER}/home
   mkdir -p "$APPTAINER_HOME"
   apptainer exec bioconductor-hpc-3.21.sif R
   ```

3. If the home directory path differs, use explicit bind mounts:

   ```bash
   apptainer exec --bind /real/home/path:/home/user bioconductor-hpc-3.21.sif R
   ```

---

## 5. Performance Issues

### 5.1 Slow R Startup

**Symptom:** R or RStudio takes 10-60 seconds to start, with the delay
occurring before the prompt appears or the GUI is visible.

**Cause:** Several factors can cause slow startup:

- **Fontconfig cache rebuild**: The first time R or RStudio runs, fontconfig
  scans all available fonts and builds a cache. This is slow on NFS.
- **NFS home directory**: Loading `.Rprofile`, `.Renviron`, and the user
  library path from NFS adds latency.
- **Large `.Rprofile`**: A user `.Rprofile` that loads many packages at
  startup.
- **Site library on slow storage**: If the site library path is on a slow
  filesystem, R scans it at startup.

**Solution:**

1. Pre-build the fontconfig cache:

   ```bash
   apptainer exec bioconductor-hpc-3.21.sif fc-cache -fv
   ```

   The cache is stored in `~/.cache/fontconfig/` and persists across sessions.

2. Move R temporary files to fast local storage:

   ```bash
   export TMPDIR=/scratch/${USER}/tmp
   mkdir -p "$TMPDIR"
   ```

3. Audit your `~/.Rprofile` for expensive operations:

   ```bash
   # Time R startup with and without your profile:
   time apptainer exec bioconductor-hpc-3.21.sif R --no-init-file -e "q('no')"
   time apptainer exec bioconductor-hpc-3.21.sif R -e "q('no')"
   ```

   If the second command is significantly slower, your `~/.Rprofile` is the
   bottleneck. Avoid loading packages (like tidyverse) in your profile.

4. If the site library is causing delays, check its filesystem performance:

   ```bash
   time ls /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor/
   ```

### 5.2 Memory Limits

**Symptom:**

R is killed without warning (see "Killed (OOM)" in Section 7), or R reports
"cannot allocate vector of size X".

**Cause:** SLURM enforces memory limits per job. If R exceeds the allocated
memory, the OOM killer terminates the process.

**Solution:**

1. Request sufficient memory in your SLURM job:

   ```bash
   #SBATCH --mem=32G          # Total memory for the job
   #SBATCH --mem-per-cpu=8G   # Per-CPU memory (alternative)
   ```

2. Monitor memory usage inside R:

   ```r
   # Current memory usage:
   gc()

   # Peak memory:
   gc(reset = FALSE)

   # Object sizes:
   sort(sapply(ls(), function(x) object.size(get(x))), decreasing = TRUE)
   ```

3. For large datasets, use memory-efficient data structures:

   ```r
   # Use data.table instead of data.frame for large tables
   library(data.table)
   dt <- fread("large_file.csv")

   # Use HDF5 for very large matrices
   library(HDF5Array)
   ```

4. Force garbage collection in long-running scripts:

   ```r
   gc()
   ```

5. Check your job's memory usage from outside:

   ```bash
   sstat -j $SLURM_JOB_ID --format=MaxRSS
   ```

### 5.3 TMPDIR on Slow Filesystem

**Symptom:** Analyses that create many temporary files are unexpectedly slow
even though CPU and memory are not bottlenecks.

**Cause:** If TMPDIR points to NFS or a shared parallel filesystem, the
overhead of creating and deleting many small temporary files can dominate
runtime. R and Bioconductor packages create temp files for intermediate results,
package compilation, and data processing.

**Solution:**

Use local scratch storage for TMPDIR:

```bash
# In your SLURM script:
#SBATCH --tmp=50G

export TMPDIR=/scratch/${USER}/tmp/${SLURM_JOB_ID}
# Or if your cluster uses local /tmp:
# export TMPDIR=/tmp/${SLURM_JOB_ID}
mkdir -p "$TMPDIR"
```

Verify TMPDIR performance:

```bash
# Quick write test:
dd if=/dev/zero of=${TMPDIR}/test bs=1M count=100 2>&1 | tail -1
rm -f ${TMPDIR}/test
```

### 5.4 BiocParallel Configuration for SLURM

**Symptom:** Parallel Bioconductor operations use only one core, or they
attempt to use more cores than allocated and get killed.

**Cause:** BiocParallel needs to be configured to match the resources allocated
by SLURM. By default, it may detect all physical cores on the node rather than
the allocated subset.

**Solution:**

Configure BiocParallel to use the SLURM allocation:

```r
library(BiocParallel)

# Use the number of cores allocated by SLURM:
ncores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1"))

# For shared-memory parallelism within a single node:
register(MulticoreParam(workers = ncores))

# For multi-node parallelism across a SLURM allocation:
# register(BatchtoolsParam(workers = ncores, cluster = "slurm"))
```

In your SLURM script, request multiple cores:

```bash
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=4G
```

Do not use more workers than `SLURM_CPUS_PER_TASK`. Exceeding the allocation
causes processes to compete for CPU time and may violate cluster policies.

---

## 6. Module Issues

### 6.1 "Command not found" After Module Load

**Symptom:**

```bash
module load bioconductor/3.21
R
# bash: R: command not found
```

**Cause:** The module defines shell functions (Lmod) or aliases (Tcl modules)
rather than adding directories to PATH. This is because R, Rscript, and
rstudio are not standalone binaries on the host -- they run inside the
container via `apptainer exec`.

**Solution:**

1. Verify the module loaded successfully:

   ```bash
   module list
   ```

2. Check what the module provides:

   ```bash
   module show bioconductor/3.21
   ```

3. For Lmod: the module sets shell functions. Verify they exist:

   ```bash
   type R
   # Should show: R is a function
   ```

4. For Tcl modules: the module sets aliases. Verify:

   ```bash
   alias R
   # Should show: alias R='apptainer exec --bind ... bioconductor-hpc-3.21.sif R'
   ```

5. If `type R` shows nothing, try unloading and reloading:

   ```bash
   module purge
   module load bioconductor/3.21
   type R
   ```

6. Ensure you are not loading a conflicting R module. The bioconductor module
   conflicts with standalone R modules:

   ```bash
   module list 2>&1 | grep -i "^.*R/"
   ```

   Unload any standalone R module before loading bioconductor.

### 6.2 Shell Function vs Alias Issues in Scripts

**Symptom:**

R works at the interactive command line after `module load`, but fails inside
a bash script with "command not found".

**Cause:** Tcl modules create aliases, not shell functions. Aliases are only
expanded in interactive shells. In non-interactive scripts (including SLURM
batch scripts), aliases are not available.

**Solution:**

1. **Best fix**: Use the Lmod (Lua) modulefile instead of the Tcl modulefile.
   Lmod's `set_shell_function` creates real shell functions that work in both
   interactive and non-interactive contexts:

   ```bash
   # Lmod uses .lua modulefiles
   module load bioconductor/3.21    # Uses the .lua modulefile if Lmod is installed
   ```

2. **Workaround for Tcl modules**: In your SLURM script, call `apptainer exec`
   directly instead of relying on the alias:

   ```bash
   #!/bin/bash
   #SBATCH --job-name=bioc_analysis

   SIF=/apps/biocontainers/images/bioconductor-hpc-3.21.sif
   BINDS=/apps/biocontainers/extras,/scratch

   apptainer exec --bind "$BINDS" "$SIF" Rscript analysis.R
   ```

3. **Alternative workaround**: Enable alias expansion in your script (not
   recommended -- fragile):

   ```bash
   #!/bin/bash
   shopt -s expand_aliases
   source /etc/profile.d/modules.sh   # or wherever modules are initialized
   module load bioconductor/3.21
   R --no-save < script.R
   ```

### 6.3 Multiple R Versions Conflicting

**Symptom:**

After loading the bioconductor module, `R --version` shows a different R
version than expected, or R packages compiled for one version fail to load in
another.

**Cause:** Another module providing R (e.g., a standalone `R/4.4.2` module) is
loaded and its PATH entry takes precedence, or its shell function/alias
overrides the bioconductor module's definition.

**Solution:**

1. The bioconductor modulefile declares `conflict("R")`. If a conflicting
   module is loaded, you will see a message. Unload it first:

   ```bash
   module unload R
   module load bioconductor/3.21
   ```

2. Check which R is being called:

   ```bash
   type R
   which R 2>/dev/null
   ```

3. If the module system does not detect the conflict, purge all modules and
   load only what you need:

   ```bash
   module purge
   module load bioconductor/3.21
   ```

4. Verify the R version inside the container:

   ```bash
   apptainer exec bioconductor-hpc-3.21.sif R --version
   ```

   This bypasses the module system entirely and confirms what version the
   container provides.

---

## 7. Common Error Messages

### 7.1 "cannot open shared object file: No such file or directory"

**Full error:**

```
Error in dyn.load(file, DLLpath = DLLpath, ...) :
  unable to load shared object '/path/to/package/libs/package.so':
  libsomething.so.X: cannot open shared object file: No such file or directory
```

**Cause:** An R package was compiled against a shared library that is not
available at runtime. This happens when:

- A package was installed outside the container and depends on host libraries
  not present in the container.
- A package was installed in a previous container version with different
  libraries.
- A system library was removed from the container image.

**Solution:**

1. Identify the missing library:

   ```bash
   # The error message names it, e.g., libhdf5.so.103
   apptainer exec bioconductor-hpc-3.21.sif \
       find / -name 'libhdf5*' 2>/dev/null
   ```

2. If the library exists but with a different version number, the package needs
   to be reinstalled inside the container:

   ```r
   # Reinstall the package to relink against the container's libraries:
   install.packages("packagename", type = "source")
   ```

3. If the library does not exist at all, see Section 3.2 for options.

4. To check all shared library dependencies of a package:

   ```bash
   apptainer exec bioconductor-hpc-3.21.sif \
       ldd /home/user/R/x86_64-pc-linux-gnu-library/4.5/packagename/libs/packagename.so
   ```

   Any line containing "not found" identifies a missing dependency.

### 7.2 "BLAS/LAPACK routine 'DGEBAL' gave error code -3"

**Full error:**

```
Error in La.svd(x, nu, nv) :
  error code -3 from Lapack routine 'dgebal'
```

Or similar errors mentioning LAPACK/BLAS routines with negative error codes.

**Cause:** This typically indicates corrupted or invalid input data (NaN, Inf,
or extremely large values) being passed to linear algebra routines. Less
commonly, it indicates a BLAS/LAPACK library mismatch.

**Solution:**

1. Check your data for invalid values:

   ```r
   any(is.na(your_matrix))
   any(is.infinite(your_matrix))
   any(is.nan(your_matrix))
   range(your_matrix, na.rm = TRUE)
   ```

2. Clean the data before analysis:

   ```r
   your_matrix[is.na(your_matrix)] <- 0
   your_matrix[is.infinite(your_matrix)] <- 0
   ```

3. If the data is clean, check the BLAS library in use:

   ```r
   sessionInfo()
   # Look for the BLAS/LAPACK line
   ```

4. If the error occurs with a specific package (e.g., during PCA or SVD),
   try an alternative algorithm that is more robust to numerical issues:

   ```r
   # Instead of prcomp(), try:
   library(irlba)
   result <- irlba(your_matrix, nv = 10)
   ```

### 7.3 "caught segfault"

**Full error:**

```
 *** caught segfault ***
address 0x..., cause 'memory not mapped'

Traceback:
 ...
```

**Cause:** A segmentation fault indicates memory corruption or illegal memory
access. Common causes in R/Bioconductor:

- A C/C++ extension package has a bug.
- Memory exhaustion causing the stack or heap to overflow.
- Package compiled with a different R version or incompatible compiler flags.
- Corrupted package installation.

**Solution:**

1. Reinstall the package that appears in the traceback:

   ```r
   remove.packages("suspect_package")
   BiocManager::install("suspect_package")
   ```

2. If the crash occurs during a specific operation, try with a smaller dataset
   to rule out memory exhaustion:

   ```bash
   #SBATCH --mem=64G
   ```

3. Clear and rebuild all user-installed packages (nuclear option):

   ```bash
   rm -rf ~/R/x86_64-pc-linux-gnu-library/4.5/*
   ```

   Then reinstall only the packages you need.

4. Check for package version incompatibilities:

   ```r
   BiocManager::valid()
   ```

   This reports packages that are out of date or incompatible with the current
   Bioconductor version.

5. If the crash is reproducible with a minimal example, report it as a bug to
   the package maintainer.

### 7.4 libmpi Related Errors

**Symptom:**

```
libmpi.so.40: cannot open shared object file: No such file or directory
```

Or:

```
ORTE was unable to reliably start one or more daemons.
```

**Cause:** MPI libraries on the host do not match MPI libraries inside the
container, or MPI is not bind-mounted into the container. Bioconductor packages
rarely need MPI directly, but some HPC-aware packages (Rmpi, pbdMPI) do.

**Solution:**

1. If you do not need MPI, this error usually occurs because a package was
   installed with MPI support elsewhere and the `.so` file has a hard
   dependency. Reinstall the package without MPI:

   ```r
   install.packages("packagename", configure.args = "--without-mpi")
   ```

2. If you need MPI, bind-mount the host MPI libraries into the container. The
   exact path depends on your cluster:

   ```bash
   apptainer exec --bind /opt/openmpi:/opt/openmpi bioconductor-hpc-3.21.sif R
   ```

   You also need to set `LD_LIBRARY_PATH`:

   ```bash
   export APPTAINERENV_LD_LIBRARY_PATH=/opt/openmpi/lib:$LD_LIBRARY_PATH
   ```

3. Consult your HPC documentation for the recommended way to use MPI with
   Apptainer containers on your specific cluster.

### 7.5 Killed (OOM)

**Symptom:**

The R process or SLURM job terminates abruptly with just "Killed" on stderr, or
the SLURM job log shows:

```
slurmstepd: error: Detected 1 oom_kill event in StepId=12345.0. Some of the step tasks have been OOM Killed.
```

**Cause:** The process exceeded the memory limit set by SLURM (via cgroups) and
was terminated by the kernel Out-Of-Memory (OOM) killer.

**Solution:**

1. Request more memory:

   ```bash
   #SBATCH --mem=64G
   ```

2. Check how much memory your job actually used (after it finishes or is
   killed):

   ```bash
   sacct -j JOBID --format=JobID,MaxRSS,ReqMem,State
   ```

3. Profile memory usage before submitting large jobs:

   ```r
   # Use Rprof for memory profiling:
   Rprof("profile.out", memory.profiling = TRUE)
   # ... your analysis ...
   Rprof(NULL)
   summaryRprof("profile.out", memory = "both")
   ```

4. Reduce memory consumption:
   - Process data in chunks instead of loading everything into memory.
   - Use `data.table::fread()` instead of `read.csv()` (more memory-efficient).
   - Use on-disk data structures (HDF5Array, DelayedArray) for large matrices.
   - Remove large intermediate objects with `rm()` and call `gc()`.

5. Monitor in real time from another terminal:

   ```bash
   srun --jobid=JOBID --pty bash -c "top -u $USER"
   ```

---

## 8. Diagnostic Commands Reference

These commands help diagnose problems. Run them from the host unless noted
otherwise.

### Container and Image Information

```bash
# Show container metadata and help text:
apptainer inspect bioconductor-hpc-3.21.sif
apptainer run-help bioconductor-hpc-3.21.sif

# Check the image file integrity:
apptainer verify bioconductor-hpc-3.21.sif

# Get image size:
ls -lh bioconductor-hpc-3.21.sif

# Run the built-in self-test:
apptainer test bioconductor-hpc-3.21.sif
```

### R and Bioconductor

```bash
# R version:
apptainer exec bioconductor-hpc-3.21.sif R --version

# Bioconductor version:
apptainer exec bioconductor-hpc-3.21.sif Rscript -e "BiocManager::version()"

# Library paths:
apptainer exec bioconductor-hpc-3.21.sif Rscript -e ".libPaths()"

# List installed packages:
apptainer exec bioconductor-hpc-3.21.sif Rscript -e "installed.packages()[, c('Package', 'Version', 'LibPath')]"

# Check Bioconductor package validity:
apptainer exec bioconductor-hpc-3.21.sif Rscript -e "BiocManager::valid()"

# Session info (R version, platform, loaded packages, BLAS/LAPACK):
apptainer exec bioconductor-hpc-3.21.sif Rscript -e "sessionInfo()"
```

### Environment Variables

```bash
# Check all relevant environment variables inside the container:
apptainer exec bioconductor-hpc-3.21.sif bash -c '
    echo "DISPLAY:           ${DISPLAY:-NOT SET}"
    echo "TMPDIR:            ${TMPDIR:-NOT SET}"
    echo "HOME:              ${HOME}"
    echo "USER:              ${USER}"
    echo "R_LIBS_USER:       ${R_LIBS_USER:-NOT SET}"
    echo "R_LIBS_SITE:       ${R_LIBS_SITE:-NOT SET}"
    echo "QT_QPA_PLATFORM:   ${QT_QPA_PLATFORM:-NOT SET}"
    echo "QT_X11_NO_MITSHM:  ${QT_X11_NO_MITSHM:-NOT SET}"
    echo "LANG:              ${LANG:-NOT SET}"
    echo "BIOC_VERSION:      ${BIOC_VERSION:-NOT SET}"
    echo "R_VERSION_SHORT:   ${R_VERSION_SHORT:-NOT SET}"
'
```

### X11 and Display

```bash
# Check DISPLAY:
echo $DISPLAY

# Test X11 connectivity:
xdpyinfo | head -5

# Test with a simple X11 app:
xeyes &

# Test X11 from inside the container:
apptainer exec bioconductor-hpc-3.21.sif xterm

# Check X11 authentication:
xauth list
```

### Shared Libraries

```bash
# Check RStudio Desktop shared library dependencies:
apptainer exec bioconductor-hpc-3.21.sif ldd /usr/lib/rstudio/rstudio

# Find missing shared libraries (lines with "not found"):
apptainer exec bioconductor-hpc-3.21.sif \
    ldd /usr/lib/rstudio/rstudio 2>&1 | grep "not found"

# Check a specific R package's shared library dependencies:
apptainer exec bioconductor-hpc-3.21.sif \
    ldd ~/R/x86_64-pc-linux-gnu-library/4.5/PACKAGE/libs/PACKAGE.so

# Search for a specific shared library inside the container:
apptainer exec bioconductor-hpc-3.21.sif \
    find /usr/lib -name 'libcurl*' 2>/dev/null
```

### Fonts

```bash
# List available fonts:
apptainer exec bioconductor-hpc-3.21.sif fc-list

# Rebuild font cache:
apptainer exec bioconductor-hpc-3.21.sif fc-cache -fv

# Check fontconfig configuration:
apptainer exec bioconductor-hpc-3.21.sif fc-conflist 2>/dev/null || \
    apptainer exec bioconductor-hpc-3.21.sif ls /etc/fonts/
```

### Filesystem and Bind Mounts

```bash
# Check what is bind-mounted inside the container:
apptainer exec bioconductor-hpc-3.21.sif mount | grep -E '(bind|fuse)'

# Verify the site library is accessible:
apptainer exec bioconductor-hpc-3.21.sif \
    ls -la /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor/

# Check TMPDIR writability:
apptainer exec bioconductor-hpc-3.21.sif bash -c \
    'echo test > ${TMPDIR:-/tmp}/write_test && echo "TMPDIR writable" && rm ${TMPDIR:-/tmp}/write_test'

# Check disk space on relevant filesystems:
df -h /tmp /scratch/${USER} ~/
```

### SLURM Job Diagnostics

```bash
# Check current job resource usage:
sstat -j $SLURM_JOB_ID --format=JobID,MaxRSS,MaxVMSize,AveCPU

# Check completed job resource usage:
sacct -j JOBID --format=JobID,Elapsed,MaxRSS,ReqMem,State,ExitCode

# Check why a job failed:
sacct -j JOBID --format=JobID,State,ExitCode,DerivedExitCode,Comment

# Show job details:
scontrol show job JOBID
```

### Module System

```bash
# List loaded modules:
module list

# Show module details:
module show bioconductor/3.21

# Check for conflicts:
module avail R
module avail bioconductor

# Verify shell function/alias is set:
type R
type Rscript
type rstudio
```
