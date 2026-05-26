# Updating the Bioconductor HPC Container for New Releases

This guide covers the complete procedure for upgrading the Bioconductor HPC
container when a new Bioconductor release is published. It is written for HPC
system administrators who maintain this container across multiple release cycles.


## Overview

This repository is designed for minimal-touch upgrades. A new Bioconductor
release typically requires changes to exactly one file: `VERSION`. The
Dockerfile, build scripts, module templates, and test suite all read their
version numbers from that file, so a version bump propagates automatically
through the entire build pipeline.

The key variables are:

| Variable          | Example          | What it controls                        |
|-------------------|------------------|-----------------------------------------|
| `BIOC_VERSION`    | `3.21`           | Bioconductor release series             |
| `R_VERSION`       | `4.5.0`          | R version (must match Bioc requirements)|
| `UBUNTU_VERSION`  | `noble`          | Ubuntu codename in the rocker base      |
| `RSTUDIO_VERSION` | `2025.05.0-496`  | RStudio Desktop .deb version string     |

Everything else -- the Dockerfile stages, the apt package list, the R package
install commands, the Apptainer definition, the module templates -- stays the
same unless there is a specific reason to change it.


## When to Upgrade

Bioconductor follows a fixed release schedule:

- **April**: Spring release (odd minor version, e.g., 3.21)
- **October**: Fall release (even minor version, e.g., 3.22)

Each new Bioconductor release is paired with a new R version. The R project
typically releases a new minor version (e.g., R 4.5.0) in April, aligning
with the spring Bioconductor release. The fall Bioconductor release usually
pairs with a patch-level R update (e.g., R 4.5.1 or R 4.5.2).

**When to act:**

1. Watch for the Bioconductor release announcement at
   <https://bioconductor.org/news/>.
2. Confirm the required R version in the release announcement or at
   <https://bioconductor.org/install/>.
3. Verify that `rocker/r-ver` has published a Docker tag for the new R version
   at <https://hub.docker.com/r/rocker/r-ver/tags>.
4. Check that RStudio has a compatible release (the current stable release
   usually works; a new one is not strictly required).

Do not upgrade on release day. Wait 1-2 weeks for the initial round of
upstream bug fixes in Bioconductor and rocker images.


## Step-by-Step Upgrade Procedure

### 1. Check upstream versions

Run the version detection script to see what is currently available upstream
and what is currently configured in the repository:

```bash
./scripts/detect_versions.sh
```

This queries:
- The current Bioconductor release and devel versions from `bioconductor.org/config.yaml`
- The latest R version from CRAN
- Recent `rocker/r-ver` Docker Hub tags
- The RStudio Desktop download page URL

Compare the output against the current `VERSION` file to determine what needs
to change.

### 2. Update the VERSION file

Edit the `VERSION` file in the repository root. This is the single source of
truth for all version numbers.

**Before (Bioconductor 3.21):**

```
BIOC_VERSION=3.21
R_VERSION=4.5.0
UBUNTU_VERSION=noble
RSTUDIO_VERSION=2025.05.0-496
```

**After (Bioconductor 3.22, hypothetical):**

```
BIOC_VERSION=3.22
R_VERSION=4.5.1
UBUNTU_VERSION=noble
RSTUDIO_VERSION=2025.09.0-123
```

Notes on each variable:

- **BIOC_VERSION**: Increment by 0.01 (e.g., 3.21 to 3.22). The Bioconductor
  project determines the version number; match what they publish.
- **R_VERSION**: Use the full three-part version (e.g., `4.5.1`). This must
  be the exact version required by the Bioconductor release. Check
  <https://bioconductor.org/install/> for the mapping.
- **UBUNTU_VERSION**: This is the Ubuntu codename used in the `rocker/r-ver`
  base image. It rarely changes. Only update it when rocker moves to a new
  Ubuntu LTS base (e.g., `jammy` to `noble`). Check the rocker project's
  release notes if uncertain.
- **RSTUDIO_VERSION**: The full version-build string for the RStudio Desktop
  `.deb` package. See the "Updating RStudio Desktop" section below.

### 3. Verify rocker/r-ver availability

Before building, confirm that the `rocker/r-ver` Docker image exists for
the new R version:

```bash
docker pull rocker/r-ver:4.5.1
```

If this fails, the rocker project has not published the tag yet. Wait for it
or check <https://github.com/rocker-org/rocker-versioned2> for status.

### 4. Build the Docker image

```bash
make build
```

This runs `./scripts/build.sh`, which reads the `VERSION` file and passes
the version numbers as Docker build arguments. The build takes 15-30 minutes
depending on network speed and cache state.

For a completely clean build (recommended for release upgrades):

```bash
make build-no-cache
```

### 5. Run the test suite

```bash
make test-all
```

This runs two test scripts:

- `test_cli.sh`: Validates R version, BiocManager version, core package
  loading, library path configuration, locale settings, and the RStudio
  binary existence.
- `test_rstudio.sh`: Checks that RStudio Desktop's shared library
  dependencies are satisfied, Qt platform plugins are present, D-Bus
  libraries exist, and fontconfig is working.

All tests must pass before proceeding. If any test fails, see the "Common
Pitfalls" section at the end of this document.

### 6. Convert to Apptainer SIF

```bash
make apptainer
```

This converts the local Docker image to an Apptainer SIF file named
`bioconductor-hpc-<BIOC_VERSION>.sif` (e.g., `bioconductor-hpc-3.22.sif`).

Optionally, test the SIF image directly:

```bash
make test-apptainer
```

### 7. Deploy to HPC

Copy the SIF image to the shared image directory and install the module:

```bash
# Copy image to production path
cp bioconductor-hpc-3.22.sif /apps/biocontainers/images/

# Install the modulefile
make deploy
```

The `install_module.sh` script auto-detects whether your site uses Lmod (Lua)
or Environment Modules (Tcl), substitutes the version variables into the
template, and writes the modulefile to `MODULE_PATH`.

Verify the deployment:

```bash
module avail bioconductor
module load bioconductor/3.22
R --version
Rscript -e "BiocManager::version()"
```


## VERSION File Changes in Detail

The `VERSION` file uses shell variable syntax. It is sourced by both the
Makefile (`include VERSION`) and all shell scripts (`source VERSION`). Every
variable must be on its own line with no spaces around the `=` sign.

### Example: 3.20 to 3.21 (major R version bump)

This is the typical spring release pattern where R gets a new minor version:

```diff
-BIOC_VERSION=3.20
-R_VERSION=4.4.2
+BIOC_VERSION=3.21
+R_VERSION=4.5.0
 UBUNTU_VERSION=noble
-RSTUDIO_VERSION=2024.12.0-467
+RSTUDIO_VERSION=2025.05.0-496
```

### Example: 3.21 to 3.22 (R patch version bump)

This is the typical fall release pattern where R gets a patch release:

```diff
-BIOC_VERSION=3.21
-R_VERSION=4.5.0
+BIOC_VERSION=3.22
+R_VERSION=4.5.1
 UBUNTU_VERSION=noble
 RSTUDIO_VERSION=2025.05.0-496
```

### Example: Ubuntu base change

When rocker moves to a new Ubuntu LTS (happens roughly every 2 years):

```diff
 BIOC_VERSION=3.25
 R_VERSION=4.7.0
-UBUNTU_VERSION=noble
+UBUNTU_VERSION=plucky
 RSTUDIO_VERSION=2027.04.0-100
```

After an Ubuntu base change, review the apt package names in the Dockerfile
because package names occasionally change across Ubuntu releases (e.g.,
`libasound2-dev` became `libasound2t64` in Noble).


## Updating RStudio Desktop

### Finding the new version

RStudio Desktop releases are published by Posit at:

- **Download page**: <https://posit.co/download/rstudio-desktop/>
- **Release notes**: <https://docs.posit.co/ide/news/>

The version string format is `YYYY.MM.P-BUILD`, for example `2025.05.0-496`.

### Determining the download URL

The Dockerfile downloads the `.deb` from this URL pattern:

```
https://download1.rstudio.org/electron/jammy/<ARCH>/rstudio-<VERSION>-<ARCH>.deb
```

Where:
- `<ARCH>` is `amd64` (auto-detected via `dpkg --print-architecture`)
- `<VERSION>` is the `RSTUDIO_VERSION` value from the VERSION file

Note the URL path currently uses `jammy` even for newer Ubuntu bases because
Posit publishes a single Ubuntu `.deb` that is forward-compatible. If Posit
changes their URL scheme in the future, update the `wget` line in the
Dockerfile.

### Testing a new RStudio version

After building with a new `RSTUDIO_VERSION`:

1. Run `make test-rstudio` to verify shared library dependencies are met.
2. If you have an X11 session available, test an actual launch:
   ```bash
   docker run --rm -e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
       bioconductor-hpc:3.22 launch-rstudio
   ```
3. On the HPC system, test via the Apptainer SIF:
   ```bash
   apptainer exec --bind /apps/biocontainers/extras bioconductor-hpc-3.22.sif launch-rstudio
   ```

### When RStudio is not strictly required to update

RStudio Desktop is a self-contained Electron-based application. It does not
need to match the R or Bioconductor version. If no new RStudio release is
available at upgrade time, keep the existing `RSTUDIO_VERSION` value. Update
RStudio independently when a new stable version is released.


## Updating System Dependencies

The Dockerfile installs system packages in a single `apt-get install` layer,
organized by purpose. These packages fall into three categories:

1. **Build tools and -dev libraries**: Required to compile R packages from
   source (e.g., `libcurl4-openssl-dev`, `libhdf5-dev`, `libxml2-dev`).
2. **X11 and GUI libraries**: Required for RStudio Desktop (e.g.,
   `libxcomposite1`, `libnss3`, `libgbm1`).
3. **Utilities**: Runtime tools (e.g., `git`, `curl`, `locales`).

### When to change the apt package list

- **New Ubuntu base**: Package names may change. Run the build and check for
  `E: Unable to locate package` errors. Search <https://packages.ubuntu.com>
  for the replacement package name.
- **New R packages in the container**: If you add R packages to the Dockerfile
  that require a system library not already installed, add the corresponding
  `-dev` package. The R package's DESCRIPTION file or installation error
  message will tell you what is needed.
- **New RStudio version**: Major RStudio releases occasionally add new shared
  library dependencies. After building, run `make test-rstudio`. If the
  "Shared libraries resolved" check fails, run `ldd` inside the container
  to identify the missing library:
  ```bash
  docker run --rm bioconductor-hpc:3.22 \
      ldd /usr/lib/rstudio/rstudio | grep "not found"
  ```
  Install the missing library's package and rebuild.

### When NOT to change the apt package list

Do not add system libraries speculatively. The image is intentionally lean.
If a user's R package requires a system library not in the container, the
correct approach is to add it to the Dockerfile and rebuild, not to install
it at runtime (Apptainer containers are read-only).


## Testing the Upgrade

### Run the automated test suite

```bash
# Test the Docker image
make test-all

# Test the Apptainer SIF
make test-apptainer
```

The test suite covers:

| Test | What it verifies |
|------|------------------|
| R --version | R binary executes |
| Rscript arithmetic | Rscript works |
| R version match | R version matches VERSION file |
| BiocManager installed | BiocManager package is loadable |
| Bioconductor version match | BiocManager reports the expected version |
| Core Bioc packages | BiocGenerics, GenomicRanges, S4Vectors, IRanges, BiocParallel all load |
| CRAN packages | tidyverse and data.table load |
| R_LIBS_SITE configured | Site library path is in .libPaths() |
| RStudio binary | /usr/lib/rstudio/rstudio exists and is executable |
| launch-rstudio wrapper | /usr/local/bin/launch-rstudio exists and is executable |
| UTF-8 locale | Locale is correctly set to en_US.UTF-8 |

### Verify key packages load

Beyond the automated tests, manually verify a few additional packages that
are commonly used at your site:

```bash
docker run --rm bioconductor-hpc:3.22 Rscript -e "
    library(BiocManager)
    cat('Bioconductor:', as.character(BiocManager::version()), '\n')
    cat('Repositories:\n')
    print(BiocManager::repositories())

    # Test that BiocManager::install works for a small package
    BiocManager::install('Biostrings', ask = FALSE)
    library(Biostrings)
    cat('Biostrings loaded successfully\n')
"
```

### Test with representative user workflows

If your site has standard analysis pipelines, run a representative job
against the new container before announcing the upgrade:

```bash
apptainer exec bioconductor-hpc-3.22.sif Rscript /path/to/user_workflow.R
```

Focus on workflows that:
- Install packages from Bioconductor (tests BiocManager + network + compilation)
- Use compiled packages (tests system library availability)
- Generate plots (tests graphics device and font support)
- Read/write large files (tests bind mounts and TMPDIR configuration)

### Verify site library compatibility

The site library path includes the R version, so a new R minor version
(e.g., 4.4 to 4.5) creates a new, empty site library directory. If the
R version only changed at the patch level (e.g., 4.5.0 to 4.5.1), the
existing site library will be reused because the path uses only major.minor.

Check that the site library directory exists and is writable:

```bash
ls -la /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor/
```

If this is a new directory (new R minor version), pre-install any
site-wide packages your users depend on before announcing the upgrade.


## Rollback Procedure

If the new container has problems in production, roll back to the previous
version. The design supports this natively because each Bioconductor version
produces a separate SIF file and a separate modulefile.

### Immediate rollback (< 5 minutes)

1. **Set the default module back to the old version.**

   For Lmod, edit or remove the new modulefile:
   ```bash
   rm /apps/modulefiles/bioconductor/3.22.lua
   ```

   For Tcl modules, update the `.version` file:
   ```bash
   cat > /apps/modulefiles/bioconductor/.version <<'EOF'
   #%Module1.0
   set ModulesVersion "3.21"
   EOF
   ```

2. **Notify users** that the default version has reverted to the previous
   release.

The old SIF file (`bioconductor-hpc-3.21.sif`) should still be in
`/apps/biocontainers/images/`. The old modulefile should still be in
`/apps/modulefiles/bioconductor/`. Users who explicitly loaded the old
version (`module load bioconductor/3.21`) were never affected.

### Rebuild and retry

After identifying and fixing the issue:

1. Make corrections to the `VERSION` file or Dockerfile.
2. Rebuild: `make build-no-cache`
3. Re-test: `make test-all`
4. Re-convert: `make apptainer`
5. Re-deploy: copy SIF and run `make deploy`

### Preserving old images

Always keep at least the previous release's SIF file and modulefile. Users
may have ongoing analyses that depend on the old version. A safe retention
policy:

- **Current release**: Always available.
- **Previous release**: Keep until at least the next release cycle (6 months).
- **Older releases**: Remove at your discretion, with advance notice to users.


## Site Library Management During Upgrades

### How library paths work

The container configures two external library paths via `Renviron.site`:

```
R_LIBS_USER=~/R/x86_64-pc-linux-gnu-library/<R_major.minor>
R_LIBS_SITE=/apps/biocontainers/extras/r-package-site-library/<R_major.minor>-bioconductor
```

The `<R_major.minor>` component (e.g., `4.5`) means:

- **R minor version bump** (4.4 to 4.5): New directory. All packages must be
  reinstalled in both user and site libraries.
- **R patch version bump** (4.5.0 to 4.5.1): Same directory. Existing packages
  are reused. Some packages may need recompilation if the R ABI changed, but
  this is rare within a patch series.

### New Bioconductor version with new R minor version

This is the most common upgrade scenario (spring releases). Steps:

1. Create the new site library directory:
   ```bash
   mkdir -p /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
   ```

2. Set ownership and permissions so that the designated site library
   maintainer(s) can install packages:
   ```bash
   chown root:biocontainers /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
   chmod 2775 /apps/biocontainers/extras/r-package-site-library/4.5-bioconductor
   ```

3. Install site-wide packages into the new directory. Use the new container
   to ensure binary compatibility:
   ```bash
   apptainer exec --bind /apps/biocontainers/extras bioconductor-hpc-3.22.sif \
       Rscript -e "BiocManager::install(c('DESeq2', 'edgeR', 'Seurat'), lib='/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor')"
   ```

4. The old site library (`4.4-bioconductor`) remains intact for users still
   loading the old module version.

### New Bioconductor version with same R minor version

This is the typical fall release scenario. The site library directory is
shared. Packages compiled for the old Bioconductor version generally work
because the R ABI has not changed.

However, some Bioconductor packages may have updated dependencies. It is good
practice to update site-wide packages after upgrading:

```bash
apptainer exec --bind /apps/biocontainers/extras bioconductor-hpc-3.22.sif \
    Rscript -e "BiocManager::install(ask = FALSE, update = TRUE, lib='/apps/biocontainers/extras/r-package-site-library/4.5-bioconductor')"
```

### Cleaning up old libraries

Old site library directories can be removed after:

1. The old module version has been retired.
2. No users are still loading the old module (check with `module spider` logs
   if your site tracks usage).
3. Sufficient notice has been given (at least one release cycle / 6 months).

```bash
# Verify no one is using it first
ls -la /apps/biocontainers/extras/r-package-site-library/4.4-bioconductor/

# Remove when ready
rm -rf /apps/biocontainers/extras/r-package-site-library/4.4-bioconductor
```


## Upgrade Day Checklist

Copy this checklist and work through it for each release.

```
Pre-build:
  [ ] Run ./scripts/detect_versions.sh and record upstream versions
  [ ] Confirm required R version for the new Bioconductor release
  [ ] Confirm rocker/r-ver tag exists: docker pull rocker/r-ver:<R_VERSION>
  [ ] Check for a new RStudio Desktop stable release
  [ ] Edit VERSION file with new BIOC_VERSION, R_VERSION, RSTUDIO_VERSION

Build:
  [ ] make build-no-cache
  [ ] make test-all           (all tests pass)
  [ ] make apptainer
  [ ] make test-apptainer     (all tests pass)

Manual validation:
  [ ] Rscript -e "BiocManager::version()" shows correct version
  [ ] Install a test package: BiocManager::install("Biostrings")
  [ ] Load key packages used at your site
  [ ] Run a representative user workflow if available
  [ ] Test RStudio Desktop launch (if X11 session available)

Deploy:
  [ ] cp bioconductor-hpc-<VERSION>.sif /apps/biocontainers/images/
  [ ] Verify old SIF file is still present (do NOT overwrite or remove it)
  [ ] make deploy
  [ ] module avail bioconductor    (new version appears)
  [ ] module load bioconductor/<VERSION>
  [ ] R --version                  (correct R version)
  [ ] Rscript -e "BiocManager::version()"  (correct Bioc version)

Site library:
  [ ] Create new site library directory if R minor version changed
  [ ] Set permissions on new site library directory
  [ ] Install site-wide packages into new directory
  [ ] Verify old site library directory still exists for old module

Post-deploy:
  [ ] Update any site documentation or user-facing announcements
  [ ] Notify users of the new version availability
  [ ] Monitor support channels for the first week
```


## Common Pitfalls

### rocker/r-ver tag not yet available

**Symptom**: `docker build` fails at the `FROM rocker/r-ver:X.Y.Z` line
with an image-not-found error.

**Cause**: The rocker project has not published the new R version tag yet.
This can lag the official R release by a few days to a few weeks.

**Fix**: Wait. Monitor <https://hub.docker.com/r/rocker/r-ver/tags> or the
rocker GitHub repository. Do not attempt to work around this by changing the
base image.

### BiocManager reports the wrong version

**Symptom**: `BiocManager::version()` returns the old Bioconductor version
even after updating `BIOC_VERSION`.

**Cause**: Docker build cache. The R package installation layer was cached
from the previous build.

**Fix**: Rebuild without cache: `make build-no-cache`.

### RStudio Desktop shared library errors

**Symptom**: `make test-rstudio` fails on the "Shared libraries resolved"
check. Or RStudio launches but immediately crashes.

**Cause**: A new RStudio version introduced a dependency on a shared library
not installed in the container.

**Fix**: Identify the missing library:
```bash
docker run --rm bioconductor-hpc:3.22 ldd /usr/lib/rstudio/rstudio | grep "not found"
```
Find the Ubuntu package that provides the missing `.so` file using
`apt-file search` or <https://packages.ubuntu.com>, add it to the apt-get
layer in the Dockerfile, and rebuild.

### RStudio .deb download URL changed

**Symptom**: The Dockerfile build fails at the `wget` step for the RStudio
`.deb` with a 404 error.

**Cause**: Posit changed their download URL structure or moved to a different
CDN path.

**Fix**: Visit <https://posit.co/download/rstudio-desktop/> and inspect the
download link for the Ubuntu `.deb`. Update the URL template in the
Dockerfile's `RUN` block that installs RStudio Desktop.

### apt package renamed or removed in new Ubuntu

**Symptom**: `apt-get install` fails with `E: Unable to locate package`
during the Docker build after changing `UBUNTU_VERSION`.

**Cause**: Package names change across Ubuntu releases. For example,
`libasound2-dev` was renamed to `libasound2t64` in Ubuntu Noble (24.04).

**Fix**: Search <https://packages.ubuntu.com> for the package name in the
new Ubuntu release. Update the package name in the Dockerfile and add a
comment noting the rename.

### Site library packages fail to load

**Symptom**: Users report `Error in loadNamespace()` for packages that are
installed in the site library.

**Cause**: The packages were compiled against the old R version and are not
binary-compatible with the new R version. This happens when the R minor
version changes (e.g., 4.4 to 4.5).

**Fix**: Reinstall affected packages in the site library using the new
container. If this is a new R minor version, the site library path will be
a new directory and all site packages must be reinstalled from scratch (see
"Site Library Management During Upgrades").

### Apptainer conversion fails with disk space error

**Symptom**: `make apptainer` fails with a "no space left on device" error.

**Cause**: Apptainer uses `/tmp` for temporary files during SIF conversion.
HPC login nodes often have small `/tmp` partitions.

**Fix**: Set `APPTAINER_TMPDIR` to a location with sufficient space (at
least 2x the uncompressed image size, typically 8-10 GB):
```bash
export APPTAINER_TMPDIR=/scratch/$USER/apptainer_tmp
mkdir -p $APPTAINER_TMPDIR
make apptainer
```

### User R library directory conflicts

**Symptom**: Users see warnings about package version mismatches or cannot
load packages they previously installed.

**Cause**: The user's personal library (`~/R/x86_64-pc-linux-gnu-library/4.5`)
contains packages compiled against a different R patch version or a different
Bioconductor release.

**Fix**: Advise users to reinstall packages in their personal library:
```r
# Inside the new container
update.packages(ask = FALSE, checkBuilt = TRUE)
```
Or, for a clean start, rename the old library and let R create a fresh one:
```bash
mv ~/R/x86_64-pc-linux-gnu-library/4.5 ~/R/x86_64-pc-linux-gnu-library/4.5.bak
```
