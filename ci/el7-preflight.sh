#!/usr/bin/env bash
# External disposable EL7 container only. This is not a production installer.
set -euo pipefail
test "$EXTERNAL_CI" = 1
test -f /work/EXTERNAL_CI_ONLY
test -f /work/source.src.rpm
grep -q '^ID="centos"' /etc/os-release
test "$(rpm -q --qf '%{VERSION}' glibc)" = 2.17
cd /work
echo 'EXPERIMENTAL SOURCE PREPARATION ONLY: no deployment approval.'

cat >/etc/yum.repos.d/public-build.repo <<'REPOS'
[build-base]
name=Public CentOS 7.9 base for disposable build
baseurl=https://vault.centos.org/7.9.2009/os/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///work/keys/centos.asc
[build-updates]
name=Public CentOS 7.9 updates for disposable build
baseurl=https://vault.centos.org/7.9.2009/updates/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///work/keys/centos.asc
[build-extras]
name=Public CentOS 7.9 extras for disposable build
baseurl=https://vault.centos.org/7.9.2009/extras/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///work/keys/centos.asc
[build-epel]
name=Public EPEL 7 archive for disposable build
baseurl=https://archives.fedoraproject.org/pub/archive/epel/7/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///work/keys/epel.asc
[build-remi-safe]
name=Public Remi EL7 safe mirror for disposable build
baseurl=https://mirror.speedpartner.de/remi/enterprise/7/safe/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///work/keys/remi.asc
[build-remi]
name=Public Remi EL7 development dependencies for disposable build
baseurl=https://mirror.speedpartner.de/remi/enterprise/7/remi/$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///work/keys/remi.asc
REPOS

rpm --import /work/keys/centos.asc /work/keys/epel.asc /work/keys/remi.asc
yum -y --disablerepo='*' --enablerepo='build-*' \
  --setopt=timeout=20 --setopt=retries=2 install \
  rpm-build redhat-rpm-config yum-utils patch cpio xz make gcc gcc-c++ \
  autoconf automake libtool git gnupg2
mkdir -p /work/rpmbuild/SOURCES /work/rpmbuild/SPECS /work/rpmbuild/BUILD
cd /work/rpmbuild/SOURCES
rpm2cpio /work/source.src.rpm | cpio -id --no-absolute-filenames --quiet
echo 'f3553370f8ba42729a9ce75eed17a2111d32433a43b615694f6a571b8bad0e39  php-8.1.18.tar.xz' | sha256sum -c -
cp php81.spec /work/rpmbuild/SPECS/php81-original.spec
cp /work/security-backport.patch php81-security-backport.patch

python - <<'PY'
from __future__ import print_function
p='/work/rpmbuild/SOURCES/php81.spec'
s=open(p).read()
assert s.count('Patch300: php-7.4.0-datetests.patch') == 1
assert s.count('# security patches\n') == 1
s=s.replace('Patch300: php-7.4.0-datetests.patch',
            'Patch300: php-7.4.0-datetests.patch\nPatch999: php81-security-backport.patch')
s=s.replace('# security patches\n', '# security patches\n%patch999 -p1 -b .security-backport\n')
open('/work/rpmbuild/SPECS/php81-preflight.spec','w').write(s)
PY

rpmspec --define 'rhel 7' --define 'dist .el7.remi' \
  -q --buildrequires /work/rpmbuild/SPECS/php81-preflight.spec \
  | sort -u | tee /work/el7-buildrequires.txt

yum-builddep -y --disablerepo='*' --enablerepo='build-*' \
  --setopt=timeout=20 --setopt=retries=2 \
  --define 'rhel 7' --define 'dist .el7.remi' \
  /work/rpmbuild/SPECS/php81-preflight.spec

rpm -qa --qf '%{NAME}|%{EPOCH}|%{VERSION}|%{RELEASE}|%{ARCH}\n' \
  | sort > /work/external-build-environment.txt
cat /work/external-build-environment.txt

rpmbuild -bp --define '_topdir /work/rpmbuild' --define 'rhel 7' \
  --define 'dist .el7.remi' --define '_default_patch_fuzz 0' \
  /work/rpmbuild/SPECS/php81-preflight.spec
echo 'EL7_PREP_AND_BACKPORT_PATCH_OK'
echo 'No compilation, production installation, or application tests were performed.'
echo 'Unsigned generic source provenance and exact original-source equivalence remain unresolved.'
