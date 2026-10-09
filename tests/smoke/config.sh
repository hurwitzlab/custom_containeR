# Smoke-test config: one of each package reference type. Tracked in git.

# ------------------------------------------------------------
# Per-image settings: edit these before each new image
# ------------------------------------------------------------

# Image name (letters, digits, '.', '_', '-'). Becomes builds/<NAME>/.
NAME="smoke_test"

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
# Site overrides (everything else comes from site.sh)
# ------------------------------------------------------------

# Keep test builds out of the real builds/ directory.
BUILDS_DIR="/share/brc/$USER/custom_containeR_tests/builds"
