# Configuration for custom_containeR.
# Sourced by generate_def.sh and build.sh.

# ------------------------------------------------------------
# Per-image settings: edit these before each new image
# ------------------------------------------------------------

# Image name (letters, digits, '.', '_', '-'). Becomes builds/<NAME>/.
NAME="example_r"

# R version, which must be an existing rocker/r-ver tag (X.Y.Z).
R_VERSION="4.6.1"

# Bioconductor release. Must match R_VERSION (checked against
# bioconductor.org/config.yaml). R 4.6 -> 3.23 or 3.24; R 4.5 -> 3.21 or 3.22.
BIOC_VERSION="3.23"

# Posit Package Manager snapshot date (YYYY-MM-DD). CRAN and Bioconductor
# packages come from the repos as they were on this date.
SNAPSHOT_DATE="2026-10-01"

# One package reference per line (see packages.txt for the accepted syntax).
PACKAGES_FILE="packages.txt"

# Packages always installed in addition to PACKAGES_FILE (space-separated).
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
