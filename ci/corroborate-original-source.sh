#!/usr/bin/env bash
# Read/compare public source only, inside the disposable CI EL7 container.
set -euo pipefail
test "$EXTERNAL_CI" = 1
test -f /work/EXTERNAL_CI_ONLY
test -f /work/original-debuginfo.rpm
cd /work
rpm -Kv original-debuginfo.rpm | tee debug-signature-check.txt
grep -E 'Signature.*key ID 00f97f56: OK' debug-signature-check.txt
test "$(rpm -qp --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}|%{SOURCERPM}' original-debuginfo.rpm)" \
  = 'php-debuginfo|8.1.18|1.el7.remi|x86_64|php-8.1.18-1.el7.remi.src.rpm'
rpm2cpio original-debuginfo.rpm | cpio -it --quiet > debug-members.txt
python - <<'PY'
import re
names=open('/work/debug-members.txt').read().splitlines()
chosen=[]
for name in names:
    n=name.lstrip('./')
    if n.startswith('usr/src/debug/') and re.match(r'^[A-Za-z0-9_./+-]+$',n) and n.endswith(('.c','.h')):
        assert '..' not in n.split('/')
        chosen.append(name)
assert chosen,'No authenticated debug source members found'
open('/work/debug-source-members.txt','w').write('\n'.join(chosen)+'\n')
print('Authenticated debug source member count: '+str(len(chosen)))
PY
mkdir /work/authenticated-debug-source
cd /work/authenticated-debug-source
rpm2cpio /work/original-debuginfo.rpm \
  | cpio -id --no-absolute-filenames --no-preserve-owner --quiet -E /work/debug-source-members.txt

# Reverse the fix only in an ephemeral source tree to compare the baseline.
# This never touches a runtime, package database, or production file.
cd /work/rpmbuild/BUILD/php-8.1.18
patch -R -p1 --fuzz=0 < /work/security-backport.patch
python - <<'PY'
from __future__ import print_function
import os,hashlib,json
baseline='/work/rpmbuild/BUILD/php-8.1.18'
debug='/work/authenticated-debug-source'
targets=[
'Zend/zend_API.h','Zend/zend_alloc.c','Zend/zend_alloc.h',
'Zend/zend_execute_API.c','Zend/zend_hash.c','Zend/zend_hash.h',
'Zend/zend_multiply.h','Zend/zend_strtod.c','Zend/zend_types.h',
'Zend/zend_vm_def.h','Zend/zend_vm_execute.h',
'ext/opcache/ZendAccelerator.c','ext/opcache/ZendAccelerator.h',
'ext/opcache/zend_file_cache.c','ext/opcache/zend_persist.c',
'ext/session/session.c','main/SAPI.c','main/main.c',
'main/php_variables.c','main/rfc1867.c']
files=[]
for root,dirs,names in os.walk(debug):
    files.extend(os.path.join(root,n) for n in names)
out=[]
for target in targets:
    candidates=[p for p in files if p.endswith('/'+target)]
    want=hashlib.sha256(open(os.path.join(baseline,target),'rb').read()).hexdigest()
    hashes=[{'path':os.path.relpath(p,debug),'sha256':hashlib.sha256(open(p,'rb').read()).hexdigest()} for p in candidates]
    matches=[p for p in hashes if p['sha256']==want]
    out.append({'target':target,'candidate_sha256':want,'authenticated_source_candidates':hashes,'any_exact_match':bool(matches)})
print(json.dumps(out,indent=2))
print('EXACT_CRITICAL_FILES_MATCHED='+str(sum(x['any_exact_match'] for x in out))+'/'+str(len(out)))
print('This establishes only the compared source bytes, not complete original SRPM identity or application compatibility.')

# Broaden the comparison to authenticated source files present in the baseline.
matched=[];different=[];not_in_baseline=[]
for original in files:
    marker='/php-8.1.18/'
    if marker not in original:
        continue
    relative=original.split(marker,1)[1]
    candidate=os.path.join(baseline,relative)
    if not os.path.isfile(candidate):
        not_in_baseline.append(relative)
        continue
    oldhash=hashlib.sha256(open(original,'rb').read()).hexdigest()
    newhash=hashlib.sha256(open(candidate,'rb').read()).hexdigest()
    if oldhash==newhash:
        matched.append(relative)
    else:
        different.append({'path':relative,'authenticated_sha256':oldhash,'candidate_sha256':newhash})
print('FULL_AUTHENTICATED_SOURCE_COMPARISON')
print(json.dumps({'exact_match_count':len(matched),'different_files':different,'not_in_prepared_baseline':not_in_baseline},indent=2))

PY
