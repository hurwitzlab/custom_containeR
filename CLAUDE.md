# CLAUDE.md

Guidance for Claude Code when working in this directory.

## Purpose

BRC admins use this to build reproducible R Apptainer images on the NC State
Hazel cluster from a plain package list. See README.md for usage. Sibling of
`../custom_container_module` (generic GitHub tools, LLM-generated `.def`s).
This project deliberately has **no LLM step**: every R image comes from the
one `template.def`, filled in by `generate_def.sh`.

## Pipeline

```
new_image.sh <NAME> -> recipes/<NAME>/{config.sh,packages.txt}  (gitignored copies of *.example*)
site.sh + recipes/<NAME>/config.sh + packages.txt
  -> generate_def.sh   validate, resolve rocker digest, render template.def
                       -> builds/<NAME>/<VERSION_TAG>/<NAME>_<VERSION_TAG>.def + inputs/
  -> sbatch build.sh builds/<NAME>/<VERSION_TAG>   (xfer partition)
                       apptainer build (+%test) -> .sif, export /opt/provenance, chmod a-w
```

`snapshot_dates.sh pkg@ver ...` is a standalone helper: crandb timeline ->
window when each version was current -> overlap, latest date verified against
the PPM snapshot's PACKAGES. It nudges users to pin by date rather than by
`@version`.

Settings are split: `site.sh` (tracked, shared paths/maintainer) is sourced
first, then the image's config (which may override it). `build.sh` sources
only `site.sh`. `config.example.sh`/`packages.example.txt` are templates and
must not be edited for a build; `generate_def.sh` refuses the template and a
blank `NAME`. The repo is one shared checkout, which is why per-image recipes
(inputs; `builds/` holds outputs) live in `recipes/<NAME>/` rather than in a tracked `config.sh`.

`run.sh` chains both steps: it captures the build dir from `generate_def.sh`'s
stdout (the summary goes to stderr; keep it that way), prompts unless
`--yes`, and with `--wait` polls `squeue` and treats the existence of the
`.sif` as success.

`deploy.sh builds/<NAME>/<TAG>` publishes to `DEPLOY_ROOT`
(`/usr/local/usrapps/brc/developer_tools`) with `container-mod pipe -t
--profile developer_tools <copied .sif>`, name/version on stdin
(`<name lowercased>`, `<TAG>`). Facts it relies on, verified on Hazel
2026-10-09 (Environment Modules 5.3, Tcl, not Lmod):
- container-mod leaves a local image in place and its wrappers point at that
  exact path, so the `.sif` is copied to `DEPLOY_ROOT/images/` first.
- container-mod reads `repos/<app>` (Description/Home Page/Programs) and
  prompts on stdin if it is missing, so `deploy.sh` writes it first. `repos/`
  is shared with the `brc` profile; entries this repo owns have
  `Home Page: $REPO_URL`, and others are never overwritten.
- For local images container-mod renders a bogus `DockerHub:
  https://hub.docker.com/r//<path>` help line; `deploy.sh` deletes it.
- `family "R"` makes a second R image fail to load with a clear hint.
- Shared Tcl in `/usr/local/usrapps/brc/env/` (`modules.config`,
  `module_log.tcl`) is `source`d by modulefiles. `$ModulesCurrentModulefile`
  gives the modulefile path, so the log's tree field is derived, not baked
  in. `module show` processes `source` lines but not load-mode blocks, so
  it checks modulefiles without writing log lines.
- `module_loads.log` is parsed by the BRC Infrastructure Homepage
  (`/rs1/shares/brc/admin/infrastructure/brc_infra_site`,
  `scripts/parse_modules.py` `parse_usage_log()`), which counts only lines
  whose 6th field is `brc_modules`. Any change to the log format or path in
  `module_log.tcl` must be made there too, and that repo's config.sh points
  at the brc_modules paths (modules, images, log).
- Setgid dirs (2755) make container-mod print "expected 755" permission
  warnings; harmless.
- container-mod's repo is TuftsRT's (no fork), so `profiles/developer_tools`
  is tracked here; `deploy.sh` installs it and refuses if the copies differ.

## Design rules (don't regress these)

- **The reproducibility contract.** Base image pinned by **digest**. CRAN
  *and* Bioconductor both come from Posit Package Manager snapshots of the
  same `SNAPSHOT_DATE`. GitHub refs are SHA-only (the generator rejects
  branches and tags). pak/renv come from the same snapshot. apt sysreqs are
  logged, not pinned. Any new install path must keep this; e.g. a `url::`
  source would need a checksum before it could be allowed.
- **Never overwrite a build.** `generate_def.sh` and `build.sh` both refuse
  if the `.sif` exists; builds go to `.sif.partial` and are renamed only on
  success; finished build dirs are `chmod -R a-w`.
- **Provenance lives in two places:** `/opt/provenance` inside the image
  (travels with the `.sif`) and `builds/.../provenance/` (greppable without
  apptainer). `install.R` is written into the image so the exact install
  logic is recorded.
- **pak, not `install.packages`/BiocManager**, for user packages: one call
  handles CRAN/Bioc/GitHub and installs apt sysreqs (`PKG_SYSREQS=true`).
  Bioc version comes from `R_BIOC_VERSION`, mirror from `options(BioC_mirror)`.
- **PPM binary URLs are per Ubuntu codename.** `%post` reads it from
  `/etc/os-release` rather than hardcoding (rocker 4.6.x is noble/24.04).
- `%post` is unindented on purpose: heredoc terminators must be at column 0.
- Blank `R_VERSION`/`BIOC_VERSION` are a generate-time convenience only:
  `generate_def.sh` resolves them (Bioc = newest release by `SNAPSHOT_DATE`
  from `release_dates` in bioconductor.org/config.yaml; R = newest rocker
  patch tag for that Bioc's R minor) and the `.def` gets exact values plus
  `inputs/resolved.txt`. Never let a blank or "latest" reach the `.def`.
- Template placeholders are `@UPPER_CASE@`; the generator fails if any are
  left unfilled.

## Lessons from empirical builds (2026-10-08)

1. **Never touch `/tmp` in `%post`.** During `apptainer build` on Hazel,
   `/tmp` is the **build node's real `/tmp`**, bind-mounted in. An early
   template ended with `rm -rf /tmp/*`. On servxfer it tried to delete other
   users' files (blocked by sticky-bit permissions, which also failed the
   build). It would have succeeded on any files owned by the building user.
   Only clean paths that are definitely inside the image (`/var/lib/apt/lists`,
   `/root/.cache/R`, `$TMPDIR`).
   Related: pak's worker processes are killed rather than exiting, so their R
   `tempdir()`s survived each build (~157 MB each in servxfer's `/tmp`). Fixed
   twice over: (a) `build.sh` binds a per-job dir under `BUILD_TMP_ROOT`
   (scratch) over `/tmp` and `/var/tmp` with `apptainer build --bind`, which
   applies to both `%post` and `%test`, and removes it on exit. Apptainer warns
   "destination is already in the mount point list", but marker files proved
   the scratch bind is mounted on top and wins. (b) `%post` sets
   `TMPDIR=/opt/build-tmp` (inside the rootfs), so a hand-run
   `apptainer build` without the bind doesn't litter the host either. The
   only remaining files in the node's `/tmp` are Slurm's own
   `slurmsum-<jobid>.prolog.lock`, created by the job prolog for every job.
   Interactive `srun` on xfer is refused ("QOS 'xfer' is batch-only"), so
   inspect xfer's `/tmp` with a tiny `sbatch` job, never ssh.
2. **`unset` in `%environment` does not remove host-passed variables, but
   `export` overrides them.** With `R_LIBS_SITE` set on the host (e.g. a
   loaded R module), an image using `unset R_LIBS_SITE` still saw the host
   value. `.libPaths()` lost `/usr/local/lib/R/site-library`, and every
   installed package became "not found". Fixed by exporting the container's
   own values for `R_HOME`, `R_LIBS`, `R_LIBS_SITE`, `R_LIBS_USER`. Test
   isolation with real host variables
   (`R_LIBS_SITE=/x apptainer exec img.sif Rscript -e '.libPaths()'`), not
   only from inside `%test`.
3. **PPM serves date-pinned Bioconductor snapshots and Linux binaries**:
   `https://p3m.dev/bioconductor/__linux__/<codename>/<date>/packages/<bioc>/bioc`.
   Verified with DESeq2 for Bioc 3.18: 1.42.0 at 2024-01-05 vs 1.42.1 at
   `latest`. limma installed as a binary in ~1s.
4. **renv warns "curl does not appear to be installed"** in rocker images.
   Harmless: `snapshot()` downloads nothing. Setting
   `RENV_DOWNLOAD_METHOD=libcurl` before `snapshot()` did **not** silence it
   (renv checks when it loads), so it was removed. Expect the warning in
   build logs.
5. Docker Hub digest lookup: request the manifest with OCI index + Docker
   manifest-list Accept headers and read `docker-content-digest`. Apptainer
   pulls `rocker/r-ver@sha256:<index digest>` fine.
6. The smoke test (tidyverse + data.table + bioc::limma + a SHA-pinned GitHub
   package; 99 packages) builds in about 7 min on xfer to a ~550 MB `.sif`.

## Hazel rules

- Builds run via `sbatch build.sh` on `--partition=xfer --qos=xfer`
  (internet, not a login node). `generate_def.sh` only does small HTTP
  lookups and is fine on a login node.
- `APPTAINER_CACHEDIR`/`APPTAINER_TMPDIR`/`BUILD_TMP_ROOT` must be on
  `/share/brc/$USER`, never `$HOME` (1 GB quota) or node-local `/tmp`.
  `APPTAINER_BINDPATH=""` is required for builds.
- Under sbatch, `$0` is a spool copy; `build.sh` uses `$SLURM_SUBMIT_DIR`, so
  submit from this directory.
- Never ssh to compute/xfer nodes; check jobs with `squeue`/`sacct`.

## Testing changes

```bash
./generate_def.sh tests/smoke/config.sh      # writes to /share/brc/$USER/custom_containeR_tests
sbatch build.sh /share/brc/$USER/custom_containeR_tests/builds/smoke_test/<TAG>
```

Then check `provenance/renv.lock` (limma `RemoteRepos` = PPM snapshot,
rematch2 `RemoteSha` = the pinned SHA) and the host-env isolation check from
lesson 2. To rebuild the same tag: `chmod -R u+w <dir> && rm -r <dir>` first.
