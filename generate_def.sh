#!/bin/bash
# Generate a pinned Apptainer .def for an R image from config.sh + packages.txt.
#
# Usage: ./generate_def.sh [config.sh]
#
# Writes builds/<NAME>/<VERSION_TAG>/ containing:
#   <NAME>_<VERSION_TAG>.def   the generated definition
#   inputs/                     copies of the config and packages file used
# The summary and the sbatch command that builds it go to stderr; stdout is
# only the build directory path, so run.sh can capture it.
#
# Needs outbound internet (Docker Hub, bioconductor.org, p3m.dev) for a few
# small lookups only, so it is fine on a login node.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-$SCRIPT_DIR/config.sh}"
[[ -f "$CONFIG" ]] || { echo "ERROR: config not found: $CONFIG" >&2; exit 1; }
CONFIG="$(cd "$(dirname "$CONFIG")" && pwd)/$(basename "$CONFIG")"
source "$CONFIG"

die() { echo "ERROR: $*" >&2; exit 1; }

# Relative PACKAGES_FILE is resolved against the config's directory.
[[ "$PACKAGES_FILE" = /* ]] || PACKAGES_FILE="$(dirname "$CONFIG")/$PACKAGES_FILE"

# Blank or missing R_VERSION/BIOC_VERSION are resolved below; a missing
# DEFAULT_PACKAGES means tidyverse (set it to "" for none).
R_VERSION="${R_VERSION:-}"
BIOC_VERSION="${BIOC_VERSION:-}"
DEFAULT_PACKAGES="${DEFAULT_PACKAGES-tidyverse}"

### --- Validate scalar settings ---
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "NAME '$NAME' must be letters/digits/._- only"
[[ "$VERSION_TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "VERSION_TAG '$VERSION_TAG' must be letters/digits/._- only"
[[ -z "$R_VERSION" || "$R_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "R_VERSION must be X.Y.Z or blank (got '$R_VERSION'); minor-only tags like 4.6 move"
[[ -z "$BIOC_VERSION" || "$BIOC_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || die "BIOC_VERSION must be X.Y or blank (got '$BIOC_VERSION')"
[[ "$SNAPSHOT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "SNAPSHOT_DATE must be YYYY-MM-DD (got '$SNAPSHOT_DATE')"
date -d "$SNAPSHOT_DATE" >/dev/null 2>&1 || die "SNAPSHOT_DATE '$SNAPSHOT_DATE' is not a valid date"
[[ "$SNAPSHOT_DATE" < "$(date +%F)" ]] || die "SNAPSHOT_DATE must be in the past; today's snapshot is still changing"
[[ -f "$PACKAGES_FILE" ]] || die "PACKAGES_FILE not found: $PACKAGES_FILE"
[[ -f "$SCRIPT_DIR/template.def" ]] || die "template.def missing from $SCRIPT_DIR"

OUT_DIR="$BUILDS_DIR/$NAME/$VERSION_TAG"
DEF="$OUT_DIR/${NAME}_${VERSION_TAG}.def"
SIF="$OUT_DIR/${NAME}_${VERSION_TAG}.sif"
[[ -e "$SIF" ]] && die "$SIF already exists. Built images are never overwritten; set a new VERSION_TAG"

### --- Parse and validate package references ---
# Order is kept (DEFAULT_PACKAGES first), duplicates dropped.
declare -a PKGS=()
declare -A SEEN=()
add_ref() {
    local ref="$1" src="$2"
    local sha_re='@[0-9a-f]{7,40}$'
    local name_re='[A-Za-z][A-Za-z0-9.]*'
    if [[ "$ref" =~ ^${name_re}(@[0-9][0-9.-]*)?$ ]]; then
        :   # CRAN (optionally version-pinned)
    elif [[ "$ref" =~ ^bioc::${name_re}$ ]]; then
        :
    elif [[ "$ref" =~ ^(${name_re}=)?(github::)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?(@.*)?$ ]]; then
        [[ "$ref" =~ $sha_re ]] \
            || die "$src: GitHub ref '$ref' must be pinned to a commit SHA (owner/repo@<sha>), not a branch or tag"
    else
        die "$src: unsupported package reference '$ref' (see packages.txt header for accepted forms)"
    fi
    [[ -n "${SEEN[$ref]:-}" ]] && return 0
    SEEN[$ref]=1
    PKGS+=("$ref")
}
for ref in $DEFAULT_PACKAGES; do add_ref "$ref" "DEFAULT_PACKAGES"; done
lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    line="${line%%#*}"                       # strip comments
    line="$(echo "$line" | tr -d '[:space:]')"
    [[ -z "$line" ]] && continue
    add_ref "$line" "$(basename "$PACKAGES_FILE"):$lineno"
done < "$PACKAGES_FILE"
(( ${#PKGS[@]} > 0 )) || die "no packages given"

### --- Resolve blank R/Bioconductor versions, then check they match ---
# The .def always gets exact values; blanks only save looking them up by hand.
#   BIOC_VERSION: newest Bioconductor release out by SNAPSHOT_DATE (for
#                 R_VERSION's minor, if set). Devel is never picked.
#   R_VERSION:    newest rocker/r-ver X.Y.Z for that release's R minor.
bioc_yaml=$(curl -fsSL https://bioconductor.org/config.yaml) \
    || die "could not fetch bioconductor.org/config.yaml"
r_for_bioc() {
    sed -n '/^r_ver_for_bioc_ver:/,/^[^ ]/p' <<<"$bioc_yaml" \
        | grep -E "^ +\"$1\":" | sed -E 's/.*: *"([^"]+)".*/\1/' || true
}
AUTO=""
if [[ -z "$BIOC_VERSION" ]]; then
    while read -r v d; do
        [[ "$(date -d "$d" +%F)" > "$SNAPSHOT_DATE" ]] && continue
        [[ -n "$R_VERSION" && "$(r_for_bioc "$v")" != "${R_VERSION%.*}" ]] && continue
        BIOC_VERSION="$v"
    done < <(sed -n '/^release_dates:/,/^[^ ]/p' <<<"$bioc_yaml" \
        | sed -nE 's/^ +"([0-9]+\.[0-9]+)": *"([0-9/]+)".*/\1 \2/p' | sort -V)
    [[ -n "$BIOC_VERSION" ]] \
        || die "no Bioconductor release for R ${R_VERSION%.*} was out by $SNAPSHOT_DATE; set BIOC_VERSION"
    AUTO+=" BIOC_VERSION"
fi
bioc_r=$(r_for_bioc "$BIOC_VERSION")
[[ -n "$bioc_r" ]] || die "unknown Bioconductor release $BIOC_VERSION"
if [[ -z "$R_VERSION" ]]; then
    R_VERSION=$(curl -fsSL "https://hub.docker.com/v2/repositories/${BASE_IMAGE_REPO}/tags?page_size=100&name=${bioc_r}." \
        | jq -r '.results[].name' | grep -E "^${bioc_r//./\\.}\.[0-9]+$" | sort -V | tail -n1 || true)
    [[ -n "$R_VERSION" ]] || die "could not find a ${BASE_IMAGE_REPO}:${bioc_r}.x tag; set R_VERSION"
    AUTO+=" R_VERSION"
fi
[[ "$bioc_r" == "${R_VERSION%.*}" ]] || die "Bioconductor $BIOC_VERSION requires R $bioc_r.x, but R_VERSION is $R_VERSION"

### --- Check the snapshot exists on Posit Package Manager ---
for url in "https://p3m.dev/cran/$SNAPSHOT_DATE/src/contrib/PACKAGES" \
           "https://p3m.dev/bioconductor/$SNAPSHOT_DATE/packages/$BIOC_VERSION/bioc/src/contrib/PACKAGES"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -L "$url")
    [[ "$code" == 200 ]] || die "snapshot not available (HTTP $code): $url"
done

### --- Resolve the base image tag to an immutable digest ---
token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${BASE_IMAGE_REPO}:pull" | jq -r .token) \
    || die "Docker Hub token request failed"
digest=$(curl -fsSI -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json" \
    "https://registry-1.docker.io/v2/${BASE_IMAGE_REPO}/manifests/${R_VERSION}" \
    | tr -d '\r' | awk 'tolower($1) == "docker-content-digest:" {print $2}') \
    || die "tag ${BASE_IMAGE_REPO}:${R_VERSION} not found on Docker Hub"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "could not resolve digest for ${BASE_IMAGE_REPO}:${R_VERSION}"

### --- Render template ---
mkdir -p "$OUT_DIR/inputs"
pkg_block=$(printf '%s\n' "${PKGS[@]}")
tpl=$(<"$SCRIPT_DIR/template.def")
subst() { tpl="${tpl//"$1"/"$2"}"; }
subst @BASE_REF@         "${BASE_IMAGE_REPO}@${digest}"
subst @BASE_IMAGE_REPO@  "$BASE_IMAGE_REPO"
subst @BASE_DIGEST@      "$digest"
subst @NAME@             "$NAME"
subst @VERSION_TAG@      "$VERSION_TAG"
subst @R_VERSION@        "$R_VERSION"
subst @BIOC_VERSION@     "$BIOC_VERSION"
subst @SNAPSHOT_DATE@    "$SNAPSHOT_DATE"
subst @MAINTAINER@       "$MAINTAINER"
subst @GENERATED@        "$(date -u +%Y-%m-%dT%H:%M:%SZ) by $USER"
subst @PACKAGES@         "$pkg_block"
leftover=$(grep -oE '@[A-Z_]+@' <<<"$tpl" | sort -u | tr '\n' ' ' || true)
[[ -z "$leftover" ]] || die "unfilled template placeholders: $leftover"
printf '%s\n' "$tpl" > "$DEF"

cp "$CONFIG" "$OUT_DIR/inputs/config.sh"
cp "$PACKAGES_FILE" "$OUT_DIR/inputs/packages.txt"
# The copied config may have blanks; record what they resolved to.
printf 'R_VERSION=%s\nBIOC_VERSION=%s\nBASE_DIGEST=%s\nAUTO_RESOLVED=%s\n' \
    "$R_VERSION" "$BIOC_VERSION" "$digest" "${AUTO# }" > "$OUT_DIR/inputs/resolved.txt"

cat >&2 <<EOF
Generated: $DEF
  base      ${BASE_IMAGE_REPO}:${R_VERSION} @ ${digest}
  snapshot  ${SNAPSHOT_DATE} (CRAN + Bioconductor ${BIOC_VERSION})
${AUTO:+  auto      resolved${AUTO} (blank in config)
}  packages  ${PKGS[*]}

Review the .def, then build (run from $SCRIPT_DIR):
  sbatch build.sh $OUT_DIR
EOF
echo "$OUT_DIR"
