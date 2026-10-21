# Backport provenance and review status

Both diffs contain all 23 files from the official upstream commit:
https://github.com/php/php-src/commit/1d7dec178a094e6e75b229ce22754045f8c6070a

The diff is reconstructed from the per-file patches returned by the official
GitHub commit API. It is not an independently signed patch or a new PHP release.
Upstream describes the change as a minimal mitigation for EOL PHP.

`upstream-1d7dec1.patch` preserves all upstream hunks.
`php-8.1.18-context-adaptation.patch` changes only two *unchanged context lines*
inside the `zend_hash_packed_grow` hunk to match the older 8.1.18 source.
It does not change any added or removed fix line.

No generated-VM source regeneration, build, complete patch dry-run, runtime test,
or production acceptance is claimed by committing these files.
An exact-context dry-run on the prepared packaging source and a reviewed
comparison of all resulting changed lines are required before a build.

The patch changes OOM behavior, including immediate process termination in the
allocator, and shutdown / OPcache state handling. API equality does not establish
application compatibility. This is not a complete fix for every historical PHP CVE.

PHP source licensing and authorship remain with their upstream holders.
See the upstream source LICENSE and Zend/LICENSE and the linked commit attribution.
