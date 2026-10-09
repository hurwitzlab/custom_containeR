# Site settings for custom_containeR, shared by every image. Tracked in git.
# Sourced by generate_def.sh (before the image's config.sh, which may
# override any of these) and by build.sh.

# Recorded in the image's labels. Defaults to whoever runs the generator.
MAINTAINER="${MAINTAINER:-$USER@ncsu.edu}"
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
