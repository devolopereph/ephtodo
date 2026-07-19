# Phase 5 acceptance

Status: accepted on 2026-07-19 and cleared to continue directly to Phase 6.

## Architecture and package decisions

- The main Flutter engine constructs `DriftSyncWriteCoordinator`; the HTTPS and
  WebSocket adapter sees only `SyncWriteCoordinator`. Sticky and Quick Note
  remain database-free.
- Transport uses `dart:io` `HttpServer.bindSecure` with an application-generated
  self-signed RSA-2048 X.509 certificate. The SHA-256 fingerprint is displayed
  for pinning. Individual validated RFC1918 addresses are bound; no wildcard,
  public fallback, UPnP, tunnel, or cloud service exists.
- Passwords use Pointy Castle 4 Argon2id v19, 64 MiB, 3 iterations, 4 lanes,
  16-byte random salts, and 32-byte output. Tests use deliberately reduced
  memory with the same format.
- Password verifiers, TLS certificates, and TLS private keys use
  `flutter_secure_storage` 10.3.1. Windows stores encrypted values under a key
  protected by Windows secure-storage facilities.
- X.509 creation uses pure-Dart `basic_utils` 5.8.2. Access tokens are opaque
  256-bit random values; only SHA-256 verifiers remain in memory. Tokens last
  15 minutes and there is no persistent refresh credential.
- Metadata sync uses schema v3, ChangeLog cursors, 200-record pull pages,
  100-mutation pushes, per-device mutation receipts, revision checks,
  tombstones, and ConflictRecords.
- Note-body and audio-byte transfer is deliberately deferred. Metadata paths
  are not exposed as writable API fields.

## Focused acceptance evidence

- Sync/security unit tests: 8 passed in 3.87 s on the final focused rerun.
- Sync database/conflict tests: 4 passed in 3.30 s.
- Loopback HTTPS/WebSocket tests: 7 passed in 10.48 s.
- Combined Phase 5 acceptance: 19/19 passed in 10.05 s.
- Directly affected database, ChangeLog, note, and audio tests: 27/27 passed in
  4.54 s.
- `flutter analyze`: no issues in 7.07 s.
- Windows Debug build with secure-storage plugin: passed in 19.04 s.
- Drift generation after schema v3: passed in 38.27 s.

The slowest acceptance check was the Windows Debug build (19.04 s); dependency
code generation was slower (38.27 s) but is recorded as a generation step, not
a test category.

## Verified security behavior

Focused tests cover password verification and rejection, pairing expiry,
one-time pairing, approval requirement, access expiry, revocation, missing
scope, temporary lockout, malformed JSON, oversized bodies, unsupported API
versions, unauthorized HTTP/WebSocket, WebSocket expiry/revocation, ChangeLog
pagination, idempotent mutation IDs, stale conflicts, tombstones, note conflict
preservation, path-field rejection, log redaction, disabled-by-default state,
stop-server behavior, and the absence of Drift/database dependencies from the
network adapter.

## Known limitations carried into Phase 6

- A future client must correctly compare and pin the self-signed certificate
  fingerprint; public PKI and mutual TLS are not provided.
- Device public material is fingerprint-bound during login but Phase 5 does not
  implement a signed client challenge or hardware-backed client key.
- Expired sessions require re-pairing or password login; refresh tokens are not
  issued.
- File content transfer is specified but not enabled.
- Automated integration binds loopback only; no automated test exposes a
  listener to an external network.
