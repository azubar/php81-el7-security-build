#!/usr/bin/env bash
# Synthetic smoke test only in the disposable external CI container.
set -euo pipefail
test "$EXTERNAL_CI" = 1
test -f /work/EXTERNAL_CI_ONLY
mkdir -p /work/smoke-site /work/smoke-ini /work/smoke-empty /work/smoke-sessions /work/httpd-run /work/result
chown builder:builder /work/smoke-sessions /work/httpd-run
module=$(rpm -ql php | awk '/\/libphp.so$/ {print; exit}')
test -f "$module"
opcache=$(rpm -ql php-opcache | awk '/\/opcache.so$/ {print; exit}')
test -f "$opcache"
cat > /work/smoke-ini/php.ini <<INI
date.timezone=UTC
session.save_handler=files
session.save_path=/work/smoke-sessions
zend_extension=$opcache
opcache.enable=1
display_errors=0
log_errors=1
INI
cat > /work/smoke-site/check.php <<'PHP'
<?php
session_start();
$_SESSION['n'] = ($_SESSION['n'] ?? 0) + 1;
header('Content-Type: application/json');
echo json_encode([
 'version'=>PHP_VERSION,
 'sapi'=>PHP_SAPI,
 'zts'=>PHP_ZTS,
 'session_count'=>$_SESSION['n'],
 'opcache'=>extension_loaded('Zend OPcache'),
 'upload_ok'=>isset($_FILES['sample']) && $_FILES['sample']['error']===0 &&
              file_get_contents($_FILES['sample']['tmp_name'])==="synthetic-only\n"
]);
PHP
cat > /work/smoke-httpd.conf <<CONF
ServerRoot /etc/httpd
DefaultRuntimeDir /work/httpd-run
PidFile /work/httpd-run/httpd.pid
Listen 127.0.0.1:18080
ServerName localhost
LoadModule mpm_prefork_module modules/mod_mpm_prefork.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule php_module $module
User builder
Group builder
ErrorLog /work/result/apache-smoke-error.log
LogLevel warn
DocumentRoot /work/smoke-site
PHPINIDir /work/smoke-ini
<Directory /work/smoke-site>
  Require all granted
</Directory>
<FilesMatch "\.php$">
  SetHandler application/x-httpd-php
</FilesMatch>
CONF
export PHP_INI_SCAN_DIR=/work/smoke-empty
httpd -t -f /work/smoke-httpd.conf
httpd -t -D DUMP_MODULES -f /work/smoke-httpd.conf > /work/result/apache-smoke-modules.txt 2>&1
test "$(grep -c 'php_module' /work/result/apache-smoke-modules.txt)" = 1
httpd -DFOREGROUND -f /work/smoke-httpd.conf &
smoke_pid=$!
trap 'kill "$smoke_pid" 2>/dev/null || true; wait "$smoke_pid" 2>/dev/null || true' EXIT
for n in 1 2 3 4 5; do
  if curl -q -fsS --max-time 3 --cookie-jar /work/smoke-cookies http://127.0.0.1:18080/check.php > /work/result/apache-response-1.json; then break; fi
  sleep 1
done
printf 'synthetic-only\n' > /work/smoke-upload.txt
curl -q -fsS --max-time 10 --cookie /work/smoke-cookies -F sample=@/work/smoke-upload.txt   http://127.0.0.1:18080/check.php > /work/result/apache-response-2.json
python - <<'PY'
import json
a=json.load(open('/work/result/apache-response-1.json'))
b=json.load(open('/work/result/apache-response-2.json'))
assert a['sapi']=='apache2handler' and a['zts']==0 and a['opcache'] is True
assert a['version']=='8.1.18' and a['session_count']==1
assert b['session_count']==2 and b['upload_ok'] is True
print('ISOLATED_APACHE_PREFORK_PHP_OPCACHE_SESSION_UPLOAD_SMOKE_OK')
print(a)
print(b)
PY
if grep -Ei 'already loaded|Cannot load|PHP (Warning|Fatal)' /work/result/apache-smoke-error.log; then exit 1; fi
