# Regression test policy for the 8.1.18 experiment

The initial unmodified test suite is deliberately strict (the vendor spec's commented exit is enabled).
Run 39678029179 compiled the candidate and stopped with 11 failures:
eight session upload-progress tests, one Fiber shutdown-after-OOM test, and two SNI TLS tests.
Other .diff files include pre-existing XFAIL tests and must not be confused with unexpected failures.

The official minimal EOL backport unconditionally returns from php_session_rfc1867_callback
and uses _exit on allocation failure. The test adaptation explicitly asserts the resulting
absence of progress state while retaining session ID and uploaded-file assertions. The
interleaved test retains both absence assertions. The Fiber test still asserts the OOM
diagnostic and that the shutdown callback is not executed. No security code is reverted.

The two SNI tests use old synthetic certificates. The external build regenerates only their
test CA and three leaf certificates with current validity, using the existing PUBLIC fixture
keys. TLS peer verification and hostname checking remain enabled. The generated temporary CA
private key exists only inside the disposable CI container and is removed immediately.
A control build without the CVE patch is run with the original fixtures to establish baseline failures.

No test is skipped or changed to XFAIL by this adaptation. Any remaining unexpected failure
stops packaging. Passing these adapted tests does not establish Bitrix compatibility, complete
historical vulnerability coverage, or production readiness.

Source: https://github.com/php/php-src/commit/1d7dec178a094e6e75b229ce22754045f8c6070a
