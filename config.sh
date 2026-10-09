# Configuration for custom_containeR.
# Sourced by generate_def.sh and build.sh.

# ------------------------------------------------------------
# Per-image settings: edit these before each new image
# ------------------------------------------------------------

# Image name (letters, digits, '.', '_', '-'). Becomes builds/<NAME>/.
NAME="example_r"

# R version: an existing rocker/r-ver tag (X.Y.Z), or blank for the newest
# R patch release that BIOC_VERSION supports.
R_VERSION=""

# Bioconductor release (X.Y), or blank for the newest release out by
# SNAPSHOT_DATE (matching R_VERSION if that is set). If both are set they
# must match (R 4.6 -> 3.23 or 3.24; R 4.5 -> 3.21 or 3.22).
# generate_def.sh prints the resolved values and the .def pins them.
BIOC_VERSION=""

# Posit Package Manager snapshot date (YYYY-MM-DD). CRAN and Bioconductor
# packages come from the repos as they were on this date. Must be in the past
# (today's snapshot is still changing). Choosing one:
#   - New image, no constraints: a recent date, e.g. a few days ago.
#   - Matching an existing analysis or paper: the date that work was done, so
#     package versions match what was used.
#   - Need a specific package version or bug fix: a date when it was current.
#     For CRAN, ./snapshot_dates.sh dplyr@1.1.4 [...] finds the date range.
#   - Adding packages to an existing image: reuse that image's date (see its
#     provenance/build_info.txt) so shared packages stay identical.
#   - Older Bioconductor release: a date while it was the current release.
#     PPM drops a release's snapshots around when the next one comes out
#     (releases each spring and fall), and generate_def.sh reports a 404.
SNAPSHOT_DATE="2026-10-01"

# One package reference per line (see packages.txt for the accepted syntax).
PACKAGES_FILE="packages.txt"

# Packages always installed in addition to PACKAGES_FILE (space-separated).
# Set to "" for none.
DEFAULT_PACKAGES="tidyverse"

# Build tag. Defaults to today's date; set it explicitly (e.g. "20261008b")
# to build a second image with the same NAME on the same day.
VERSION_TAG="${VERSION_TAG:-$(date +%Y%m%d)}"

# ------------------------------------------------------------
# Site settings: rarely change
# ------------------------------------------------------------

MAINTAINER="sdweave2@ncsu.edu"
BASE_IMAGE_REPO="rocker/r-ver"

# Every build gets builds/<NAME>/<VERSION_TAG>/ with the .def, .sif,
# inputs and provenance.
BUILDS_DIR="${BUILDS_DIR:-/rs1/shares/brc/admin/containers/custom_containeR/builds}"

# Apptainer cache/tmp dirs. These MUST be on scratch, not $HOME (1 GB quota
# fills mid-pull and fails with a misleading exit 255).
APPTAINER_CACHEDIR="/share/brc/$USER/.apptainer/cache"
APPTAINER_TMPDIR="/share/brc/$USER/.apptainer/tmp"

# Per-job directory bound over /tmp and /var/tmp during builds, so nothing is
# written to the build node's local /tmp. Removed when the build job exits.
BUILD_TMP_ROOT="/share/brc/$USER/.apptainer/build-tmp"
