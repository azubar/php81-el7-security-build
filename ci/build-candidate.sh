#!/usr/bin/env bash
# Candidate build inside a disposable external EL7 CI container.
# Never run this on a production host.
set -euo pipefail
test "$EXTERNAL_CI" = 1
test -f /work/EXTERNAL_CI_ONLY
test -f /work/rpmbuild/SPECS/php81-preflight.spec
cd /work
mkdir -p /work/result

python - <<'PY'
from __future__ import print_function
s=open('/work/rpmbuild/SPECS/php81-preflight.spec').read()
assert s.count('Release: 1%{?dist}')==1
assert s.count('  #exit 1')==1
s=s.replace('Release: 1%{?dist}', 'Release: 1%{?dist}.cve20261022.1')
s=s.replace('  #exit 1', '  exit 1')
# Preserve original feature switches and the full vendor test suite.
open('/work/rpmbuild/SPECS/php81-candidate.spec','w').write(s)
PY

set +e
rpmbuild -ba --define '_topdir /work/rpmbuild' \
  --define 'rhel 7' --define 'dist .el7.remi' \
  --define '_default_patch_fuzz 0' --define '_smp_mflags -j4' \
  --define 'vendor Local experimental security rebuild' \
  --define 'packager Public EL7 backport experiment; not vendor-supported' \
  /work/rpmbuild/SPECS/php81-candidate.spec \
  > /work/result/rpmbuild.log 2>&1
build_rc=$?
set -e
tail -n 100 /work/result/rpmbuild.log
printf 'RPMBUILD_EXIT_STATUS=%s\n' "$build_rc" | tee /work/result/status.txt
cp /work/el7-buildrequires.txt /work/external-build-environment.txt /work/result/
cp /work/rpmbuild/SPECS/php81-candidate.spec /work/result/
cp /work/security-backport.patch /work/result/
find /work/rpmbuild/BUILD -type f \
  \( -name '*.diff' -o -name 'php_test_results_*.txt' \) \
  -print > /work/result/test-output-paths.txt
# Only public-code regression results from this isolated build are collected.
while IFS= read -r file; do
  printf '\nFILE %s\n' "$file" >> /work/result/test-failures.txt
  head -n 120 "$file" >> /work/result/test-failures.txt
done < /work/result/test-output-paths.txt

if test "$build_rc" -eq 0; then
  find /work/rpmbuild/RPMS /work/rpmbuild/SRPMS -type f -name '*.rpm' -print \
    | sort > /work/result/all-built-rpm-paths.txt
  while IFS= read -r file; do
    case "$file" in
      *debuginfo*|*debugsource*) continue ;;
    esac
    cp "$file" /work/result/
  done < /work/result/all-built-rpm-paths.txt
  for file in /work/result/*.rpm; do
    rpm -qp --qf '%{NAME}|%{EPOCH}|%{VERSION}|%{RELEASE}|%{ARCH}|%{SOURCERPM}\n' "$file"
    rpm -K "$file"
  done > /work/result/candidate-rpm-inventory.txt
  cat /work/result/candidate-rpm-inventory.txt
fi

cat > /work/result/ACCEPTANCE.txt <<'NOTICE'
EXPERIMENTAL BUILD OUTPUT ONLY -- NOT APPROVED FOR PRODUCTION.
The generic unsigned source candidate is not proven to be the exact original EL7 SRPM.
A passing build is not proof of application compatibility or coverage of every historical CVE.
No production data, configuration, access, or deployment was used.
RPMs, if generated, are not signed by Remi or an organizational trusted signing key.
PECL extension ABI/runtime tests, Apache startup tests, dependencies on the target,
source provenance review, independent rollback readiness, and application acceptance
remain separate gates. No production installation is authorized.
NOTICE
cd /work/result
sha256sum * > SHA256SUMS
exit "$build_rc"
