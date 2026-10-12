#!/bin/bash
# Deploy a finished build as an environment module under DEPLOY_ROOT
# (default /usr/local/usrapps/brc/developer_tools) with container-mod.
#
# Usage: ./deploy.sh [--yes] builds/<NAME>/<VERSION_TAG>
#
#   --yes    deploy without asking (required when stdin is not a terminal)
#
# Gives module <name>/<VERSION_TAG> (name lowercased) with R, Rscript and
# <name> wrappers (`<name> --help` lists the packages and versions). The build directory is not changed: its .sif is copied, not moved.
# Run on a login node (copies one .sif and writes a few small files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '4,7s/^# \{0,1\}//p' "$0" >&2; exit "${1:-1}"; }

YES=0 BUILD=""
while (( $# )); do
    case "$1" in
        -y|--yes)  YES=1 ;;
        -h|--help) usage 0 ;;
        -*)        echo "ERROR: unknown option $1" >&2; usage ;;
        *)         [[ -z "$BUILD" ]] || usage; BUILD="$1" ;;
    esac
    shift
done
[[ -n "$BUILD" ]] || usage
source "$SCRIPT_DIR/site.sh"

### --- The build must be complete and intact ---
OUT_DIR="$(cd "$BUILD" 2>/dev/null && pwd)" || die "build dir not found: $BUILD"
PROV="$OUT_DIR/provenance"
DEF=$(find "$OUT_DIR" -maxdepth 1 -name '*.def')
[[ $(wc -l <<<"$DEF") -eq 1 && -f "$DEF" ]] || die "expected exactly one .def in $OUT_DIR"
SIF="${DEF%.def}.sif"
[[ -f "$SIF" ]] || die "no .sif in $OUT_DIR; the build did not finish"
for f in build_info.txt direct_packages.txt sif.sha256; do
    [[ -f "$PROV/$f" ]] || die "missing provenance/$f; the build did not finish"
done
[[ -f "$PROV/package_versions.tsv" ]] \
    || die "build predates the '<name> --help' command (no provenance/package_versions.tsv); rebuild it"
echo "Verifying $(basename "$SIF") checksum..." >&2
(cd "$OUT_DIR" && sha256sum --quiet -c provenance/sif.sha256) || die "checksum mismatch for $SIF"

info() { awk -v k="$1" '$1 == k {print $2; exit}' "$PROV/build_info.txt"; }
NAME=$(info name)
TAG=$(info version_tag)
[[ -n "$NAME" && -n "$TAG" ]] || die "could not read name/version_tag from provenance/build_info.txt"
MOD_NAME="${NAME,,}"
PACKAGES=$(paste -sd, "$PROV/direct_packages.txt" | sed 's/,/, /g')
DESCRIPTION=$( (source "$OUT_DIR/inputs/config.sh" >/dev/null 2>&1; echo "${DESCRIPTION:-}") )
[[ -n "$DESCRIPTION" ]] || DESCRIPTION="R $(info r_version) image (Bioconductor $(info bioc_version), package snapshot $(info snapshot_date)): $PACKAGES"
[[ "$DESCRIPTION" != *$'\n'* ]] || die "DESCRIPTION must be one line"

### --- Profile: tracked copy here, installed copy in container-mod ---
[[ -x "$CONTAINER_MOD" ]] || die "container-mod not found: $CONTAINER_MOD"
CM_DIR="$(dirname "$CONTAINER_MOD")"
TRACKED="$SCRIPT_DIR/profiles/$DEPLOY_PROFILE"
INSTALLED="$CM_DIR/profiles/$DEPLOY_PROFILE"
SHADOW="$HOME/container-apps/profiles/$DEPLOY_PROFILE"   # container-mod checks this first
[[ -e "$SHADOW" ]] && die "$SHADOW would override the $DEPLOY_PROFILE profile; remove it"
if [[ -f "$TRACKED" && ! -e "$INSTALLED" ]]; then
    cp "$TRACKED" "$INSTALLED" && chmod 644 "$INSTALLED"
    echo "Installed profile: $INSTALLED" >&2
fi
[[ -f "$INSTALLED" ]] || die "profile not found: $INSTALLED"
[[ ! -f "$TRACKED" ]] || cmp -s "$TRACKED" "$INSTALLED" \
    || die "$INSTALLED differs from $TRACKED; reconcile them first (diff the two)"
# The profile and DEPLOY_ROOT must agree, or the checks below look in the wrong place.
read -r p_mod p_img p_exec < <(source "$INSTALLED"; echo "$MOD_OUTDIR $PUBLIC_IMAGEDIR $EXEC_OUTDIR")
[[ "$p_mod $p_img $p_exec" == "$DEPLOY_ROOT/modules $DEPLOY_ROOT/images $DEPLOY_ROOT/tools" ]] \
    || die "profile $DEPLOY_PROFILE paths don't match DEPLOY_ROOT=$DEPLOY_ROOT"
for f in modules.config module_log.tcl; do
    [[ -f "$BRC_ENV_DIR/$f" ]] || die "shared module file missing: $BRC_ENV_DIR/$f"
done

### --- Never overwrite, never collide ---
MODFILE="$DEPLOY_ROOT/modules/$MOD_NAME/$TAG"
IMG="$DEPLOY_ROOT/images/$(basename "$SIF")"
TOOLS="$DEPLOY_ROOT/tools/$MOD_NAME/$TAG"
REPOS_FILE="$CM_DIR/repos/$MOD_NAME"
for p in "$MODFILE" "$IMG" "$TOOLS"; do
    [[ -e "$p" ]] && die "$p already exists; $MOD_NAME/$TAG is already deployed"
done
[[ -e "$BRC_MODULES_DIR/$MOD_NAME" ]] \
    && die "module name '$MOD_NAME' is already used in $BRC_MODULES_DIR; rebuild under another NAME"
if [[ -f "$REPOS_FILE" ]] && ! grep -qxF "Home Page: $REPO_URL" "$REPOS_FILE"; then
    die "$REPOS_FILE belongs to another tool (Home Page is not $REPO_URL); rebuild under another NAME"
fi

cat >&2 <<EOF

Deploy $OUT_DIR
  module       $MOD_NAME/$TAG   (profile $DEPLOY_PROFILE)
  image        $IMG
  modulefile   $MODFILE
  wrappers     $TOOLS/bin/{R,Rscript,$MOD_NAME}
  description  $DESCRIPTION

EOF
if (( ! YES )); then
    [[ -t 0 ]] || die "not a terminal; re-run with --yes"
    read -r -p "Deploy? [y/N]: " ans
    [[ "$ans" =~ ^[Yy] ]] || { echo "Not deployed." >&2; exit 0; }
fi

### --- Deploy; remove what this run created if any step fails ---
CREATED=()
rollback() {
    echo "Deploy FAILED; removing what this run created:" >&2
    local p
    for p in "${CREATED[@]}"; do echo "  rm -rf $p" >&2; rm -rf "$p"; done
}
trap rollback ERR

if [[ ! -f "$REPOS_FILE" ]]; then CREATED+=("$REPOS_FILE"); fi
printf 'Description: %s\nHome Page: %s\nPrograms: R,Rscript,%s\n' "$DESCRIPTION" "$REPO_URL" "$MOD_NAME" > "$REPOS_FILE"
chmod 644 "$REPOS_FILE"

mkdir -p "$DEPLOY_ROOT/images"
CREATED+=("$IMG")
cp "$SIF" "$IMG"
chmod 644 "$IMG"

CREATED+=("$MODFILE" "$TOOLS")
"$CONTAINER_MOD" pipe -t --profile "$DEPLOY_PROFILE" "$IMG" < <(printf '%s\n%s\n' "$MOD_NAME" "$TAG")
[[ -f "$MODFILE" && -x "$TOOLS/bin/R" && -x "$TOOLS/bin/Rscript" && -x "$TOOLS/bin/$MOD_NAME" ]] \
    || { echo "container-mod did not create $MODFILE and all three wrappers" >&2; false; }

# container-mod renders a "DockerHub: https://hub.docker.com/r//<local path>"
# link for local images; it is meaningless here, so drop it. Point
# `module help` at the package list instead. ModulesHelp must write to
# stderr: Environment Modules evaluates a modulefile's stdout as shell code,
# so container-mod's `puts stdout` makes `module help` print bash errors.
sed -i -e '\|hub\.docker\.com/r//|d' \
    -e "/^- Home page:/a - Packages:      run '$MOD_NAME --help' after module load" \
    -e '/^proc ModulesHelp/,/^}/s/puts stdout/puts stderr/' "$MODFILE"

# Only one R image module at a time (module load refuses a second one, with
# a "module unload R" hint), plus the shared load-logging hook.
cat >> "$MODFILE" <<EOF

#-- Only one R image at a time: each puts its own R/Rscript on PATH
family "R"

#-- Log module load (shared hook: edit $BRC_ENV_DIR/module_log.tcl)
source "$BRC_ENV_DIR/module_log.tcl"

#-- Tell users how to see what is inside
if { [module-info mode load] } {
    puts stderr "$MOD_NAME/$TAG: R $(info r_version) with a pinned package set. Run '$MOD_NAME --help' for packages and versions."
}
EOF
chmod 644 "$MODFILE"
[[ "$(stat -c %a "$IMG")" == 644 ]] || chmod 644 "$IMG"

### --- Check it loads and every requested package attaches ---
echo "Testing module load..." >&2
# shellcheck disable=SC1091
source /etc/profile.d/modules.sh 2>/dev/null || true
( set +eu
  module use "$DEPLOY_ROOT/modules"
  module load "$MOD_NAME/$TAG" || exit 1
  command -v Rscript | grep -qF "$TOOLS/bin/" || { echo "Rscript on PATH is not the module's wrapper" >&2; exit 1; }
  Rscript -e 'p <- readLines(commandArgs(TRUE)[1]); for (x in p) suppressPackageStartupMessages(library(x, character.only = TRUE)); cat("OK:", length(p), "packages load\n")' \
      "$PROV/direct_packages.txt"
  "$MOD_NAME" --help | grep -qF "$(info version_tag)" || { echo "$MOD_NAME --help failed" >&2; exit 1; }
) || { echo "module load test failed" >&2; false; }

trap - ERR
mkdir -p "$SCRIPT_DIR/logs"
printf '%s|%s|%s/%s|%s|%s\n' "$(date -Is)" "$USER" "$MOD_NAME" "$TAG" "$DEPLOY_PROFILE" "$OUT_DIR" \
    >> "$SCRIPT_DIR/logs/deploy.log"

cat >&2 <<EOF

Deployed $MOD_NAME/$TAG. Users load it with:
  module use $DEPLOY_ROOT/modules
  module load $MOD_NAME/$TAG
  $MOD_NAME --help        # packages and versions
  Rscript my_analysis.R
EOF
