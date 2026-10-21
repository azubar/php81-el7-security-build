# PHP 8.1 EL7 security build investigation

Experimental, source-only preparation for rebuilding PHP 8.1.18 with the upstream
CVE-2026-109618 / CVE-2026-109619 backport.

Only public upstream and packaging sources belong here. Do not add server
configuration, application code, credentials, infrastructure inventories, or data.

This repository is not a vendor-supported PHP distribution and provides no
deployment approval. No production access, deployment job, SSH secret, paid runner,
or production-derived file is used.

## Current source candidate

- Public archive: https://mirror.speedpartner.de/remi-archive/SRPMS/php-8.1.18-1.remi.src.rpm
- Observed SHA256: `28d03372c3cf8c8990a076bd63100319060e7a7eac44edf114c1a09501cc4c42`
- Upstream tarball SHA256 published by php.net:
  `f3553370f8ba42729a9ce75eed17a2111d32433a43b615694f6a571b8bad0e39`
- Upstream backport:
  https://github.com/php/php-src/commit/1d7dec178a094e6e75b229ce22754045f8c6070a

The archive filename is generic `.remi`; it is not yet proven to be the exact
original EL7 source package. A digest pins observed bytes but does not authenticate
an unsigned packaging recipe. Source provenance, the EL7 conditional recipe,
build dependencies, patch adaptation, and regression results are separate gates.

The source-probe workflow uses only a standard Ubuntu public GitHub-hosted runner.
It inspects public files and logs metadata. It does not compile PHP, execute an
SRPM recipe, deploy anything, or upload billed build artifacts.
