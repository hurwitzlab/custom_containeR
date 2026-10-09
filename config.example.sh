# Per-image settings for custom_containeR. TEMPLATE: don't edit this copy.
# Start a new image with ./new_image.sh <NAME>, which copies this file and
# packages.example.txt to recipes/<NAME>/ (not tracked in git). Site-wide
# settings (paths, maintainer) are in site.sh; any of them can be overridden
# here.

# Image name (letters, digits, '.', '_', '-'). Becomes builds/<NAME>/.
NAME=""

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
# (today's snapshot is still changing). new_image.sh fills in yesterday.
# Choosing one:
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
SNAPSHOT_DATE=""

# One package reference per line (see the file's header for the syntax).
# Relative paths are resolved against this config's directory.
PACKAGES_FILE="packages.txt"

# Packages always installed in addition to PACKAGES_FILE (space-separated).
# Set to "" for none.
DEFAULT_PACKAGES="tidyverse"

# Build tag. Defaults to today's date; set it explicitly (e.g. "20261008b")
# to build a second image with the same NAME on the same day.
VERSION_TAG="${VERSION_TAG:-$(date +%Y%m%d)}"

