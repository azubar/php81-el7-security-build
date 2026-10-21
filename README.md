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

## External build and corroboration status

The EL7 preparation succeeds with all backport hunks applied at fuzz zero.
An original signed EL7 debuginfo RPM corroborates 1371 available baseline C/H files,
with no differences among comparable files; generated build-directory files and
complete original SRPM identity remain outside that comparison.
[Comparison run](https://github.com/azubar/php81-el7-security-build/actions/runs/39679791093).

The first candidate compiled to the strict regression gate and stopped on eleven
unexpected failures. It produced no accepted RPM set. Nine failures relate to
intentional upstream EOL mitigation behavior, and two involve old TLS fixtures.
See [the test policy](ci/TEST-POLICY.md) for explicit replacement assertions.
A separate unpatched control build uses the same environment.

The upstream minimal mitigation disables PHP session upload progress and exits
the process immediately on allocation failure. These are observable behavior changes.
No application compatibility is claimed.

Build outputs and diagnostics, when available, are retained only as draft release
assets; no release is published, no Actions artifact storage is used, and no
production deployment is configured. Standard runners for this public repository
are used. Extension builds require a successful strict core build, use its SDK,
and run non-root synthetic tests in disposable EL7 containers.

This experiment targets the two stated CVEs. It does not claim to fix all other
vulnerabilities accumulated since PHP 8.1.18, maintain EL7, or provide ongoing
vendor security support. A successful build is not production acceptance.
