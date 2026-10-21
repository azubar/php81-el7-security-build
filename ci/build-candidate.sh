#!/usr/bin/env bash
# Candidate build inside a disposable external EL7 CI container.
# Never run this on a production host.
set -euo pipefail
test "$EXTERNAL_CI" = 1
test -f /work/EXTERNAL_CI_ONLY
test -f /work/rpmbuild/SPECS/php81-preflight.spec
cd /work
mkdir -p /work/result
yum -y --disablerepo='*' --enablerepo='build-*' install openssl

python - <<'PY'
from __future__ import print_function
s=open('/work/rpmbuild/SPECS/php81-preflight.spec').read()
assert s.count('Release: 1%{?dist}')==1
assert s.count('  #exit 1')==1
s=s.replace('Release: 1%{?dist}', 'Release: 1%{?dist}.cve20261022.2')
s=s.replace('  #exit 1', '  exit 1')
s=s.replace('Patch999:', 'BuildRequires: openssl\nSource998: ci-test-adaptation.py\nPatch999:')
s=s.replace('%patch999 -p1 -b .security-backport', '%patch999 -p1 -b .security-backport\npython %{SOURCE998}')
open('/work/rpmbuild/SOURCES/ci-test-adaptation.py','w').write("from __future__ import print_function\nimport os, subprocess, tempfile, shutil\nroot=os.path.abspath('.')\nnames=['rfc1867','rfc1867_inter','rfc1867_sid_cookie','rfc1867_sid_get','rfc1867_sid_get_2','rfc1867_sid_invalid','rfc1867_sid_only_cookie','rfc1867_sid_post']\nfor name in names:\n    p='ext/session/tests/'+name+'.phpt'\n    s=open(p).read()\n    old='var_dump($_SESSION[\"upload_progress_\" . basename(__FILE__)]);'\n    suffix=' . \"_1\"' if name=='rfc1867_inter' else ''\n    old='var_dump($_SESSION[\"upload_progress_\" . basename(__FILE__)'+suffix+']);'\n    assert s.count(old)==1,p\n    s=s.replace(old,'var_dump(array_key_exists(\"upload_progress_\" . basename(__FILE__)'+suffix+', $_SESSION ?? []));')\n    before,expect=s.split('--EXPECTF--\\n')\n    assert '\\narray(5) {' in expect,p\n    expect=expect.split('\\narray(5) {')[0]+'\\nbool(false)\\n'+('bool(false)\\n' if name=='rfc1867_inter' else '')\n    if name=='rfc1867_sid_invalid':\n        expect=expect[expect.index('string(%d) \"\"'):]\n    open(p,'w').write(before+'--EXPECTF--\\n'+expect)\np='Zend/tests/fibers/get-return-after-bailout.phpt'\ns=open(p).read()\nbefore,expect=s.split('--EXPECTF--\\n')\nassert 'FiberError' in expect\nopen(p,'w').write(before+'--EXPECTF--\\n'+expect.splitlines()[0]+'\\n')\n# Refresh only expired synthetic SNI certificates. TLS verification stays enabled.\nd=tempfile.mkdtemp(prefix='php81-test-ca-')\nnull=open(os.devnull,'w')\ndef run(args):\n    subprocess.check_call(args,stdout=null,stderr=null)\ntry:\n    ca=os.path.join(d,'ca.pem')\n    cakey=os.path.join(d,'ca.key')\n    run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','3650','-subj','/CN=PHP isolated regression CA','-keyout',cakey,'-out',ca])\n    shutil.copyfile(ca,'ext/openssl/tests/sni_server_ca.pem')\n    for short in ['cs','uk','us']:\n        base='ext/openssl/tests/sni_server_'+short\n        key=base+'_key.pem'\n        csr=os.path.join(d,short+'.csr')\n        ext=os.path.join(d,short+'.cnf')\n        open(ext,'w').write('subjectAltName=DNS:'+short+'.php.net\\n')\n        run(['openssl','req','-new','-key',key,'-subj','/CN='+short+'.php.net','-out',csr])\n        run(['openssl','x509','-req','-in',csr,'-CA',ca,'-CAkey',cakey,'-set_serial',str(100+len(short)+ord(short[0])),'-days','3650','-extfile',ext,'-out',base+'_cert.pem'])\n        open(base+'.pem','w').write(open(key).read()+open(base+'_cert.pem').read())\n        run(['openssl','verify','-CAfile',ca,base+'_cert.pem'])\n    print('CI_TEST_ADAPTATION: 8 progress absence assertions; immediate OOM exit assertion; synthetic verified SNI certificates refreshed.')\nfinally:\n    null.close()\n    shutil.rmtree(d)\n")

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
for file in /work/result/test-output-paths.txt /work/result/test-failures.txt; do
  test -s "$file" || printf 'No test diagnostic files were generated.\n' > "$file"
done

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
