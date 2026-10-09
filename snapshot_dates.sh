#!/bin/bash
# Find SNAPSHOT_DATEs at which given CRAN package versions were current.
#
# Usage: ./snapshot_dates.sh pkg@version [pkg@version ...]
#
# Prints each version's window (released -> replaced) and, for several
# packages, the overlap. It suggests the latest date in the overlap (newest
# everything else) and checks that PPM's snapshot for that date really
# serves every requested version. Release dates come from crandb.r-pkg.org.
# CRAN only: Bioconductor versions follow BIOC_VERSION.
#
# Login node is fine: a few small HTTP lookups plus one PACKAGES file.
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
usage() { sed -n '4p' "$0" | sed 's/^# //' >&2; exit 1; }
(( $# )) || usage

YESTERDAY=$(date -d yesterday +%F)
PPM_FIRST="2017-10-10"   # earliest CRAN snapshot on Posit Package Manager
day_before() { date -d "$1 -1 day" +%F; }

START="" END=""
declare -A WANT=()
for ref in "$@"; do
    [[ "$ref" == bioc::* ]] && die "$ref: Bioconductor versions come from BIOC_VERSION, not the snapshot date"
    [[ "$ref" =~ ^([A-Za-z][A-Za-z0-9.]*)@([0-9][0-9.-]*)$ ]] || die "'$ref' is not pkg@version (e.g. dplyr@1.1.4)"
    pkg="${BASH_REMATCH[1]}" ver="${BASH_REMATCH[2]}"
    WANT[$pkg]="$ver"

    json=$(curl -fsSL "https://crandb.r-pkg.org/$pkg/all" 2>/dev/null) || die "$pkg: not found on CRAN (crandb lookup failed)"
    # timeline: {version: ISO date}; sort by date to find the next release.
    timeline=$(jq -r '.timeline | to_entries | sort_by(.value)[] | "\(.key) \(.value[0:10])"' <<<"$json")
    released=$(awk -v v="$ver" '$1 == v {print $2}' <<<"$timeline")
    if [[ -z "$released" ]]; then
        echo "ERROR: $pkg $ver was never on CRAN. Versions:" >&2
        awk '{printf "  %-12s %s\n", $1, $2}' <<<"$timeline" >&2
        exit 1
    fi
    replaced=$(awk -v d="$released" '$2 > d {print $2; exit}' <<<"$timeline")
    if [[ -z "$replaced" ]] && [[ "$(jq -r '.archived' <<<"$json")" == true ]]; then
        replaced=$(jq -r '.timeline.archived // empty | .[0:10]' <<<"$json")
    fi

    # A snapshot taken on the release day may predate the upload, so start a
    # day later; end the day before the next version appeared.
    s=$(date -d "$released +1 day" +%F)
    e="${replaced:+$(day_before "$replaced")}"
    e="${e:-$YESTERDAY}"
    [[ "$e" > "$YESTERDAY" ]] && e="$YESTERDAY"
    status="still current"
    [[ -n "$replaced" ]] && status="replaced $replaced"
    printf '%-24s released %s, %s\n' "$pkg $ver" "$released" "$status"
    [[ "$s" > "$e" ]] && die "$pkg $ver was current for less than a full day; no snapshot reliably has it"
    [[ "$e" < "$PPM_FIRST" ]] && die "$pkg $ver was replaced before PPM snapshots begin ($PPM_FIRST)"

    [[ -z "$START" || "$s" > "$START" ]] && START="$s"
    [[ -z "$END"   || "$e" < "$END"   ]] && END="$e"
done

[[ "$START" < "$PPM_FIRST" ]] && START="$PPM_FIRST"
echo
[[ "$START" > "$END" ]] && die "no single date has all of these versions; they were never current at the same time"
echo "SNAPSHOT_DATE range: $START .. $END"

# Check the suggestion against what PPM actually serves.
SUGGEST="$END"
pkgs=$(curl -fsSL "https://p3m.dev/cran/$SUGGEST/src/contrib/PACKAGES") \
    || die "could not fetch the PPM snapshot for $SUGGEST"
ok=1
for pkg in "${!WANT[@]}"; do
    got=$(awk -v p="$pkg" '$1 == "Package:" {f = ($2 == p)} f && $1 == "Version:" {print $2; exit}' <<<"$pkgs")
    if [[ "$got" != "${WANT[$pkg]}" ]]; then
        echo "  PPM $SUGGEST has $pkg ${got:-<missing>}, not ${WANT[$pkg]}" >&2
        ok=0
    fi
done
(( ok )) || die "PPM disagrees with crandb for $SUGGEST; try an earlier date in the range"
echo "Suggested:  SNAPSHOT_DATE=\"$SUGGEST\"   (verified on PPM)"
echo
echo "Then put that date in recipes/<NAME>/config.sh and list the packages in its"
echo "packages.txt without @version."
echo "If you leave BIOC_VERSION blank, it resolves to the release current on that date."
