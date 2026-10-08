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

# 1. Edit the per-image settings at the top of config.sh
#    (NAME, R_VERSION, BIOC_VERSION, SNAPSHOT_DATE)
# 2. List packages in packages.txt
# 3. Generate the .def (login node is fine: only small HTTP lookups)
./generate_def.sh

# 4. Review the printed .def, then build on the xfer partition
sbatch build.sh builds/<NAME>/<VERSION_TAG>
```

A tidyverse + a few Bioconductor packages builds in about 5–10 minutes
because Posit Package Manager serves pre-compiled binaries.

Builds write nothing to the xfer node's local `/tmp`. Apptainer's cache,
its working rootfs, and a per-job directory bound over `/tmp` and `/var/tmp`
all live on scratch (`/share/brc/$USER/.apptainer/`; see the bottom of
`config.sh`). The per-job directory is deleted when the build ends.

## packages.txt syntax

One reference per line ([pak](https://pak.r-lib.org/) syntax), `#` for comments:

| Line | Source |
|---|---|
| `dplyr` | CRAN, version as of `SNAPSHOT_DATE` |
| `bioc::DESeq2` | Bioconductor `BIOC_VERSION`, as of `SNAPSHOT_DATE` |
| `github::owner/repo@<commit-sha>` | GitHub at an exact commit |
| `pkgname=github::owner/repo@<sha>` | same, when the R package name differs from the repo name |

GitHub refs **must** be commit SHAs; branches and tags are rejected because
they can move. To get the SHA for a branch's current head:

```bash
curl -s https://api.github.com/repos/<owner>/<repo>/commits/HEAD | jq -r .sha
```

`DEFAULT_PACKAGES` in `config.sh` (default: `tidyverse`) is added to every image.

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
├── inputs/                       config.sh + packages.txt used
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

`VERSION_TAG` defaults to today's date. Set it explicitly in `config.sh` to
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

## Recreating the library outside the container

```r
renv::restore(lockfile = "builds/<NAME>/<TAG>/provenance/renv.lock")
```

## Validation done by generate_def.sh

- `NAME`/`VERSION_TAG` charset, `R_VERSION` is X.Y.Z (no floating `4.6`)
- `BIOC_VERSION` matches the R version (from `bioconductor.org/config.yaml`)
- `SNAPSHOT_DATE` is valid, in the past, and exists on PPM for CRAN and Bioc
- the rocker tag exists (digest lookup)
- every package line is a supported form; GitHub refs are SHA-pinned
- refuses if the target `.sif` already exists

## Files

| File | Purpose |
|---|---|
| `config.sh` | per-image settings (top) + site settings (bottom) |
| `packages.txt` | package list |
| `template.def` | the single R template; `@PLACEHOLDER@`s filled by the generator |
| `generate_def.sh` | validate inputs, resolve digest, render `.def` |
| `build.sh` | sbatch script (xfer partition): build, export provenance, freeze |
| `tests/smoke/` | config + packages exercising CRAN, Bioc and GitHub refs |

## Not (yet) included

- Deploying as a BRC module via `container-mod` (see `../custom_container_module`)
- RStudio Server images
- Rebuilding directly from an existing `renv.lock`
