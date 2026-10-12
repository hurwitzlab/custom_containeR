prov <- "/opt/provenance"
refs <- readLines(file.path(prov, "requested_packages.txt"))
refs <- refs[nzchar(trimws(refs))]

res <- pak::pkg_install(refs, ask = FALSE, upgrade = FALSE)

# R package names of the directly requested refs (they can differ from
# GitHub repo names); %test loads each of these.
direct <- sort(unique(res$package[res$direct]))
writeLines(direct, file.path(prov, "direct_packages.txt"))

# Lockfile covering every non-base package in the image.
lockproj <- file.path(tempdir(), "lockproj")
dir.create(lockproj)
options(renv.bioconductor.version = Sys.getenv("R_BIOC_VERSION"))
renv::snapshot(project = lockproj, library = .libPaths(),
               lockfile = file.path(prov, "renv.lock"),
               type = "all", prompt = FALSE, force = TRUE)

# Flat table of everything installed, including where it came from.
fields <- c("Repository", "RemoteType", "RemoteUsername", "RemoteRepo",
            "RemoteRef", "RemoteSha", "Built")
ip <- installed.packages(fields = fields)
cols <- c("Package", "Version", "Priority", "LibPath", fields)
write.table(ip[order(ip[, "Package"]), cols],
            file.path(prov, "installed_packages.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE, na = "")

# What `microbial_ecology --help` shows: each package once (the copy that loads first
# on .libPaths()), where it came from, and whether it was requested.
ip <- installed.packages(fields = c(fields, "git_url"))
ip <- ip[!duplicated(ip[, "Package"]), , drop = FALSE]
src <- ifelse(ip[, "RemoteType"] %in% "github",
              paste0("GitHub ", ip[, "RemoteUsername"], "/", ip[, "RemoteRepo"], "@", ip[, "RemoteSha"]),
       ifelse(grepl("bioconductor", ip[, "git_url"]), "Bioconductor",
       ifelse(ip[, "Priority"] %in% "base", "R (base)",
       ifelse(ip[, "Priority"] %in% "recommended" & ip[, "LibPath"] == .Library,
              "R (recommended)", "CRAN"))))
pv <- data.frame(Package = ip[, "Package"], Version = ip[, "Version"], Source = src,
                 Requested = ifelse(ip[, "Package"] %in% direct, "yes", ""))
write.table(pv[order(tolower(pv$Package)), ], file.path(prov, "package_versions.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)

# sessionInfo with every requested package attached.
for (p in direct) suppressPackageStartupMessages(library(p, character.only = TRUE))
writeLines(c(capture.output(sessionInfo()), "",
             "repos:", paste0("  ", names(getOption("repos")), " = ", getOption("repos")),
             paste0("BioC_mirror = ", getOption("BioC_mirror")),
             paste0("R_BIOC_VERSION = ", Sys.getenv("R_BIOC_VERSION"))),
           file.path(prov, "sessionInfo.txt"))
