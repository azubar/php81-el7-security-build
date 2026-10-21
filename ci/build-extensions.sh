#!/usr/bin/env bash
# Disposable external CI only. No production access.
set -euo pipefail
test "$EXTERNAL_CI" = 1
test -f /work/EXTERNAL_CI_ONLY
cd /work
mkdir -p result pecl
test -f core/status.txt
grep -qx 'RPMBUILD_EXIT_STATUS=0' core/status.txt
python - <<'PY'
import hashlib,os
base='/work/core'
checks={}
for line in open(base+'/SHA256SUMS'):
    digest,name=line.rstrip().split(None,1)
    checks[name.lstrip('*')]=digest
for name in os.listdir(base):
    if name=='SHA256SUMS':continue
    assert name in checks,name
    assert hashlib.sha256(open(base+'/'+name,'rb').read()).hexdigest()==checks[name],name
    print('RETAINED_CORE_SHA256_OK '+name)
PY
selected=()
for f in core/*.rpm; do
  case "$f" in *.src.rpm) continue;; esac
  test "$(rpm -qp --qf '%{ARCH}' "$f")" != src || continue
  name=$(rpm -qp --qf '%{NAME}' "$f")
  release=$(rpm -qp --qf '%{RELEASE}' "$f")
  { echo "PACKAGE $name"; rpm -qpR "$f"; } >> result/core-all-requires.txt
  { echo "PACKAGE $name"; rpm -qpl "$f"; } >> result/core-all-filelists.txt
  { echo "PACKAGE $name"; rpm -qp --scripts "$f"; } >> result/core-all-scriptlets.txt
  case "$release" in *cve20261022.2) ;; *) echo 'Unexpected core release'; exit 1;; esac
  case "$name" in php|php-sodium|php-common|php-cli|php-devel|php-xml|php-mbstring|php-process|php-zts|php-pdo|php-opcache) selected+=("$f");; esac
done
test "${#selected[@]}" -ge 6
yum -y --disablerepo='*' --enablerepo='build-*' localinstall "${selected[@]}"
yum -y --disablerepo='*' --enablerepo='build-*' install php-pear curl
php -n -v | tee result/patched-cli-version.txt
php-config --vernum | tee result/patched-sdk-version.txt
rpm --import /work/keys/remi2021.asc /work/keys/remi2022.asc /work/keys/remi2023.asc
useradd --create-home builder
bash /work/synthetic-apache-smoke.sh
python - <<'PY'
import hashlib,json,subprocess,re
m=json.load(open('/work/public-pecl-sources.json'))
for x in m['sources']:
    n=x['filename']
    assert re.match(r'^php-pecl-[A-Za-z0-9_.+-]+\.src\.rpm$',n)
    p='/work/pecl/'+n
    subprocess.check_call(['curl','-q','-fsSL','--retry','2','--connect-timeout','10','--max-time','120',m['base_url']+n,'-o',p])
    assert hashlib.sha256(open(p,'rb').read()).hexdigest()==x['sha256']
    v=subprocess.check_output(['rpm','-Kv',p])
    print(v)
    assert re.search(r'Signature[^\n]*: OK',v,re.I)
PY
overall=0
for src in /work/pecl/*.src.rpm; do
  name=$(rpm -qp --qf '%{NAME}' "$src")
  top="/work/pecl/$name"
  mkdir -p "$top"/{SOURCES,SPECS,BUILD,RPMS,SRPMS,BUILDROOT}
  (cd "$top/SOURCES" && rpm2cpio "$src" | cpio -id --no-absolute-filenames --quiet)
  spec=$(find "$top/SOURCES" -maxdepth 1 -name '*.spec' -print)
  test -f "$spec"
  python - "$spec" "$top/SPECS/candidate.spec" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
s,n=re.subn(r'(?m)^(Release:\s*)([^\n]+)',lambda m:m.group(1)+m.group(2)+'.cve20261022.2',s)
assert n==1
open(sys.argv[2],'w').write(s)
PY
  if ! yum-builddep -y --disablerepo='*' --enablerepo='build-*' --define 'rhel 7' --define 'dist .el7.remi' --define '_with_tests 1' "$top/SPECS/candidate.spec"; then
    echo "$name|DEPENDENCY_FAILURE" | tee -a result/extension-status.txt
    overall=1
    continue
  fi
  # Package build and local synthetic test daemons run without root privileges.
  chown -R builder:builder "$top"
  set +e
  runuser -u builder -- env NO_INTERACTION=1 REPORT_EXIT_STATUS=1 SKIP_ONLINE_TESTS=1     rpmbuild -ba --with tests --define "_topdir $top" --define 'rhel 7'     --define 'dist .el7.remi' --define '_smp_mflags -j4'     --define 'vendor Local experimental security rebuild' "$top/SPECS/candidate.spec"     > "result/$name-build.log" 2>&1
  rc=$?
  set -e
  echo "$name|$rc" | tee -a result/extension-status.txt
  tail -n 60 "result/$name-build.log"
  if test "$rc" -eq 0; then
    find "$top/RPMS" "$top/SRPMS" -type f -name '*.rpm' ! -name '*debuginfo*' ! -name '*debugsource*' -exec cp '{}' /work/result/ \;
  else
    overall=1
  fi
done
rpm -q php-common php-cli php-devel > result/core-sdk-installed.txt
if test -x /usr/bin/zts-php; then /usr/bin/zts-php -n -v >> result/core-sdk-installed.txt; else echo 'No ZTS CLI in selected package set' >> result/core-sdk-installed.txt; fi
echo 'EXPERIMENTAL ONLY. No production approval. See per-extension strict test results.' > result/ACCEPTANCE.txt
(cd result && sha256sum * > SHA256SUMS)
exit "$overall"
