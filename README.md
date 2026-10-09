# custom_containeR

Build reproducible [Apptainer](https://apptainer.org/) images for R from a
plain list of packages. You write a package list; the pipeline produces a
pinned `.def`, the `.sif`, and a full record of every version installed
(including an `renv.lock`).

Sibling of `../custom_container_module` (generic tools from GitHub). This one
needs no LLM step: all R images share one template.

## Quick start

```bash
cd /rs1/shares/brc/admin/containers/custom_containeR

# 1. Start a recipe: creates recipes/<NAME>/config.sh + packages.txt
./new_image.sh my_image
# 2. List packages in recipes/my_image/packages.txt; review its config.sh
#    (SNAPSHOT_DATE is set to yesterday; R_VERSION/BIOC_VERSION can stay blank)
# 3. Generate the .def, review it, and submit the build (from a login node)
./run.sh recipes/my_image/config.sh     # asks before submitting; [v] views the .def
```

`run.sh [--yes] [--wait] recipes/<NAME>/config.sh` chains the two steps below. `--yes`
skips the prompt (required when not on a terminal), and `--wait` blocks until
the job ends, exiting non-zero if no `.sif` was produced. The steps also run
on their own:

```bash
./generate_def.sh recipes/<NAME>/config.sh   # validate + render .def (login node is fine: small HTTP lookups only)
sbatch build.sh builds/<NAME>/<VERSION_TAG>    # build on the xfer partition
```

Running them separately is useful for retrying a failed build without
regenerating (the resolved digest stays the same) or for building a `.def`
you edited by hand.

A tidyverse + a few Bioconductor packages builds in about 5–10 minutes
because Posit Package Manager serves pre-compiled binaries.

Builds write nothing to the xfer node's local `/tmp`. Apptainer's cache,
its working rootfs, and a per-job directory bound over `/tmp` and `/var/tmp`
all live on scratch (`/share/brc/$USER/.apptainer/`; see `site.sh`). The per-job directory is deleted when the build ends.

## Where settings live

| File | Tracked | Holds |
|---|---|---|
| `site.sh` | yes | site settings shared by every image: `BUILDS_DIR`, scratch paths, base image repo, `MAINTAINER` (defaults to `$USER@ncsu.edu`) |
| `config.example.sh`, `packages.example.txt` | yes | templates; never edited directly |
| `recipes/<NAME>/config.sh`, `packages.txt` | **no** (gitignored) | one image's recipe (what to build), made by `new_image.sh` |

A recipe is the editable input; `builds/<NAME>/<TAG>/` is the read-only
output of each build, so one recipe yields a new build folder every time it
is built. The repo is one shared checkout on `/rs1`, so a folder per recipe lets
several admins prepare images at once without editing the same file, and
keeps `git status` clean. An image's config is sourced after `site.sh`, so
it can override any site setting (the smoke test overrides `BUILDS_DIR`).
To change an image later, edit its folder and regenerate with a new
`VERSION_TAG` (or on a new day). Nothing is lost by not tracking `recipes/`:
each build keeps a read-only copy of `site.sh`, the config and the package
list in `builds/<NAME>/<TAG>/inputs/`.

## packages.txt syntax

One reference per line ([pak](https://pak.r-lib.org/) syntax), `#` for comments:

| Line | Source |
|---|---|
| `dplyr` | CRAN, version as of `SNAPSHOT_DATE` |
| `bioc::DESeq2` | Bioconductor `BIOC_VERSION`, as of `SNAPSHOT_DATE` |
| `github::owner/repo@<commit-sha>` | GitHub at an exact commit |
| `pkgname=github::owner/repo@<sha>` | same, when the R package name differs from the repo name |
| `dplyr@1.1.4` | CRAN at an exact version. Last resort; see below |

GitHub refs **must** be commit SHAs; branches and tags are rejected because
they can move. To get the SHA for a branch's current head:

```bash
curl -s https://api.github.com/repos/<owner>/<repo>/commits/HEAD | jq -r .sha
```

### Wanting a specific version: pick a date, not a pin

The snapshot date pins **every** package, including all dependencies, to a
set that was on CRAN together, and PPM serves them as pre-compiled binaries.
A `pkg@version` pin fixes only that one package. Its dependencies still come
from the snapshot date, the old version is usually compiled from source
(slower, and may fail against the newer compilers and libraries in the base
image), and pak may find no solution if the pinned version conflicts with
the snapshot's dependencies.

So to get a version, find a date when it was current:

```bash
./snapshot_dates.sh dplyr@1.1.4 ggplot2@3.5.1
# dplyr 1.1.4              released 2023-11-17, replaced 2026-02-03
# ggplot2 3.5.1            released 2024-04-23, replaced 2025-04-09
#
# SNAPSHOT_DATE range: 2024-04-24 .. 2025-04-08
# Suggested:  SNAPSHOT_DATE="2025-04-08"   (verified on PPM)
```

Put that date in the image's `config.sh` and list the packages in `packages.txt` without
`@version`. The suggestion is the latest date in the range, so everything
else is as new as possible, and it is checked against PPM. The helper is
CRAN-only (Bioconductor versions follow `BIOC_VERSION`) and fails clearly if
the versions never overlapped or predate PPM (2017-10-10).

Use a `pkg@version` pin only when one package must be old and everything
else current. The exact versions installed are always recorded in
`provenance/renv.lock` either way.

`DEFAULT_PACKAGES` in the image's `config.sh` (default: `tidyverse`; `""` for none) is added to every image.

## Default R and Bioconductor versions

Leave `R_VERSION` and/or `BIOC_VERSION` blank and `generate_def.sh` fills them in:

| Blank | Resolved to |
|---|---|
| `BIOC_VERSION` | newest Bioconductor **release** (never devel) out by `SNAPSHOT_DATE`, restricted to `R_VERSION`'s minor if that is set |
| `R_VERSION` | newest `rocker/r-ver` X.Y.Z tag for that Bioconductor release's R minor |

The resolved values are printed, pinned in the `.def`, and recorded in
`inputs/resolved.txt`. Builds stay reproducible because the saved `.def`
never contains a blank. PPM keeps serving a Bioconductor release's snapshots
only until roughly the next release comes out. To use an older release, also
use an older `SNAPSHOT_DATE`; the generator reports a 404 otherwise.

## How reproducibility works

| Layer | Pinned by |
|---|---|
| OS + R | `rocker/r-ver:<R_VERSION>`, resolved to its **sha256 digest** at generate time (Rocker rebuilds tags) |
| CRAN | Posit Package Manager snapshot `p3m.dev/cran/__linux__/<codename>/<SNAPSHOT_DATE>` |
| Bioconductor | `BIOC_VERSION` (checked against the R version) **and** the PPM Bioconductor snapshot of the same date |
| GitHub | commit SHA |
| pak, renv | installed from the same CRAN snapshot |
| apt system libs (installed automatically by pak) | not pinned, **logged** in `dpkg_packages.tsv` |

Rebuilding the saved `.def` later gives the same R package versions. Only
the apt libraries can drift (Ubuntu security updates).

## Output

Each build gets its own directory; nothing is ever overwritten:

```
builds/<NAME>/<VERSION_TAG>/
├── <NAME>_<VERSION_TAG>.def      generated definition
├── <NAME>_<VERSION_TAG>.sif      the image
├── inputs/                       site.sh, config.sh, packages.txt used; resolved.txt
└── provenance/                   (also inside the image at /opt/provenance)
    ├── renv.lock                 every package: version, repo, GitHub SHA
    ├── installed_packages.tsv    flat table of the same
    ├── sessionInfo.txt           with all requested packages attached
    ├── dpkg_packages.tsv         OS packages
    ├── build_info.txt            base digest, repo URLs, dates
    ├── requested_packages.txt / direct_packages.txt
    ├── install.R                 the exact install script that ran
    ├── labels.txt, apptainer_version.txt, slurm_job_id.txt
    └── sif.sha256
```

After a successful build the directory is made read-only (`chmod -R a-w`).
To delete a build on purpose: `chmod -R u+w builds/<NAME>/<TAG> && rm -r ...`.

`VERSION_TAG` defaults to today's date. Set it explicitly in the image's `config.sh` to
build a second image with the same name on the same day.

## Using an image

```bash
module load apptainer
apptainer exec builds/<NAME>/<TAG>/<NAME>_<TAG>.sif Rscript analysis.R
apptainer run  builds/<NAME>/<TAG>/<NAME>_<TAG>.sif          # interactive R
apptainer exec <image>.sif cat /opt/provenance/renv.lock      # what's inside
```

The image ignores host R libraries. `~/R/...` (visible through the `/home`
bind mount) and any `R_LIBS*` from a host R module are kept off
`.libPaths()`, so host-compiled packages can't mix in. `%test` checks this.

## Deploying as a module

```bash
./deploy.sh builds/<NAME>/<TAG>       # login node; asks before deploying
```

This publishes the image as module `<name>/<TAG>` (name lowercased) under
`/usr/local/usrapps/brc/developer_tools`, using container-mod with the
`developer_tools` profile. Users then run:

```bash
module use /usr/local/usrapps/brc/developer_tools/modules
module load microbial_ecology/20261009
Rscript my_analysis.R          # R and Rscript wrappers run inside the image
```

`deploy.sh`:

1. verifies the build (the `.sif` matches `provenance/sif.sha256`)
2. refuses to overwrite a deployed version, to reuse a module name that
   exists in `brc_modules`, or to overwrite another tool's container-mod
   `repos/` entry
3. writes `repos/<name>` (Description, Home Page, `Programs: R,Rscript`).
   The description is `DESCRIPTION` from the recipe's `config.sh`, or one
   built from the R/Bioc versions and package list
4. copies the `.sif` to `developer_tools/images/` (the build keeps its copy)
   and runs `container-mod pipe`
5. appends `family "R"` to the modulefile (so a second R image can't be loaded
   alongside, with a "module unload R" hint) and the shared logging hook
6. loads the module and attaches every requested package, then logs to
   `logs/deploy.log`. If any step fails, it removes what it created.

The container-mod profile is tracked here as `profiles/developer_tools`
(container-mod's own repo is TuftsRT's). `deploy.sh` installs it into
container-mod's `profiles/` if missing and refuses to run if the two differ.

Shared by all BRC module trees, in `/usr/local/usrapps/brc/env/`:

| File | Sourced by modulefiles for |
|---|---|
| `modules.config` | bind paths (`/rs1`, `/share`, `/gpfs_common`, `/rsstu`) |
| `module_log.tcl` | load logging to `brc_modules/logs/module_loads.log`, as `timestamp\|user\|group\|tool\|version\|tree`, where tree is `brc_modules` or `developer_tools` |

Change bind paths or logging there, once, for every module.

## Recreating the library outside the container

```r
renv::restore(lockfile = "builds/<NAME>/<TAG>/provenance/renv.lock")
```

## Validation done by generate_def.sh

- `NAME`/`VERSION_TAG` charset, `R_VERSION` is X.Y.Z or blank (no floating `4.6`)
- blank `R_VERSION`/`BIOC_VERSION` resolved (see above)
- `BIOC_VERSION` matches the R version (from `bioconductor.org/config.yaml`)
- `SNAPSHOT_DATE` is valid, in the past, and exists on PPM for CRAN and Bioc
- the rocker tag exists (digest lookup)
- every package line is a supported form; GitHub refs are SHA-pinned
- refuses if the target `.sif` already exists

## Files

| File | Purpose |
|---|---|
| `new_image.sh` | start an image: copy the templates to a new recipe, `recipes/<NAME>/` with `NAME` and `SNAPSHOT_DATE` filled in |
| `config.example.sh` | per-image settings template |
| `packages.example.txt` | package list template (syntax in its header) |
| `site.sh` | site settings, sourced before the image config and by `build.sh` |
| `recipes/` | per-image recipes: config + package list (gitignored) |
| `template.def` | the single R template; `@PLACEHOLDER@`s filled by the generator |
| `generate_def.sh` | validate inputs, resolve digest, render `.def` |
| `build.sh` | sbatch script (xfer partition): build, export provenance, freeze |
| `snapshot_dates.sh` | find `SNAPSHOT_DATE`s when given CRAN `pkg@version`s were current |
| `deploy.sh` | publish a build as a `developer_tools` module via container-mod |
| `profiles/developer_tools` | container-mod profile (tracked copy) |
| `run.sh` | pipeline wrapper: `generate_def.sh`, review prompt, `sbatch build.sh`, optional wait |
| `tests/smoke/` | config + packages exercising CRAN, Bioc and GitHub refs |

## Not (yet) included

- RStudio Server images
- Rebuilding directly from an existing `renv.lock`
