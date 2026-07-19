# Local synchronization

## Status

Local sync is an experimental, disabled-by-default Phase 5 foundation for a
future mobile client. It is intended only for private LANs. ephtodo does not
provide a cloud service, internet relay, UPnP, port forwarding, public tunnel,
or mobile application.

## Architecture

The server runs only in the main Flutter engine. HTTP and WebSocket adapters
depend on `SyncWriteCoordinator`, an application-owned interface. They never
receive `AppDatabase`, Drift tables, writable task/note/audio repositories, or
vault filesystem services. The coordinator serializes accepted mutations
through the same main-engine write boundary used by the desktop UI.

Sticky and Quick Note remain database-free and do not host listeners.

## Lifecycle and binding

- The persisted setting starts as disabled.
- Enabling requires an explicit desktop action, a configured password, valid
  secure-storage material, and at least one eligible interface.
- The generated default port is in the dynamic/private range. Users may choose
  ports 49152 through 65535.
- The implementation enumerates and binds individual loopback or RFC1918 IPv4
  addresses. It never binds `0.0.0.0`, `::`, a public address, or a public
  fallback.
- Disabling closes listeners and WebSockets immediately and clears access
  sessions and pairing codes.
- Persisted enablement is honored only after the user explicitly opts into it.
  Invalid credentials or TLS material fail closed.
- Interface changes cause a controlled stop and rebind to the currently
  eligible addresses.

The Settings page reports status, redacted actionable failures, API version,
port, local bound addresses, TLS fingerprint, pending pairing expiry, paired
devices, and limited audit event types.

## TLS

At first enable, ephtodo generates a 2048-bit RSA key and a self-signed X.509
certificate valid for 397 days using `basic_utils`/Pointy Castle. The private
key is stored through `flutter_secure_storage`; the certificate is public
material but is stored beside the protected value to make rotation atomic.
`dart:io` `SecurityContext` loads both from memory and `HttpServer.bindSecure`
provides TLS.

The Settings and pairing views show a colon-separated SHA-256 certificate
fingerprint. Clients must compare and pin it. Rotation creates a new key and
certificate, clears active sessions and pairing state, and requires
fingerprint verification again.

## Password and pairing

The sync password uses Argon2id from Pointy Castle with:

- version 0x13;
- a unique 16-byte salt;
- 64 MiB memory;
- 3 iterations;
- parallelism 4;
- a 32-byte output.

The encoded verifier includes algorithm, version, parameters, salt, and output.
Verification parses and bounds every parameter before deriving and compares in
constant time. Tests include a fixed compatibility vector and incorrect-input
cases. No weaker fallback is used.

Pairing:

1. The desktop opens a five-minute session with a cryptographically random,
   eight-character code.
2. The client checks the displayed TLS fingerprint and submits the code,
   protocol version, device ID, display name, and public-material fingerprint.
3. The desktop lists the request as pending; no token is issued.
4. The desktop user explicitly approves or rejects it.
5. Approval persists non-secret device metadata and issues one 256-bit opaque
   access token with `sync.read` and `sync.write`.
6. The code is consumed and cannot be reused.

The access token expires after 15 minutes and is retained only as a SHA-256
verifier in memory. Phase 5 intentionally has no refresh token: expiry or
server restart requires explicit re-pairing. This avoids persistent bearer
credentials.

## Versioned API

All errors have this form:

```json
{"error":{"code":"stable_code","message":"Safe explanation"}}
```

Routes:

- `GET /api/v1/health` — unauthenticated; returns only readiness and API
  version.
- `POST /api/v1/auth/pair` — submits a pairing request.
- `POST /api/v1/auth/token` — verifies the configured password for an already
  approved, non-revoked device and issues a short access session.
- `GET /api/v1/devices` — requires `device.admin`.
- `DELETE /api/v1/devices/{deviceId}` — requires `device.admin`.
- `POST /api/v1/sync/pull` — requires `sync.read`.
- `POST /api/v1/sync/push` — requires `sync.write`.
- `GET /api/v1/sync/status` — requires `sync.read`.
- `/ws/v1/events` — authenticated WebSocket upgrade.

Normal paired mobile devices receive only read/write scopes. Device and pairing
administration remain desktop-local in Phase 5.

## Incremental pull and push

Pull accepts `protocolVersion`, `afterSequence`, `pageSize`, and supported
entity types. It returns application-owned change envelopes and a next cursor;
page size is capped at 200.

Push accepts at most 100 mutations. Each includes a client mutation ID, entity
type and ID, base revision, operation, changed fields, client timestamp, and
originating device ID. Metadata paths and server-owned fields are rejected.
Mutation IDs are idempotent per device.

Supported metadata entities are project nodes, tasks, tags, task-tag
relations, notes, audio, and an allowlist of syncable preferences. Accepted
operations validate, execute transactionally through the main coordinator,
append ChangeLog, return the authoritative revision, and emit a minimal event.

## Conflicts and deletion

Stale updates never overwrite local content. Safe independent scalar fields may
merge; documented display preferences use last-write-wins. Other stale writes
preserve local data and create a ConflictRecord containing revisions and
redacted conflict metadata. Deletion is represented by tombstones, and stale
clients cannot silently resurrect deleted entities.

Phase 5 does not transfer note bodies or audio bytes. The reserved protocol
uses hashes, server-generated paths, bounded chunks, and preserve-both
conflicts; it must be implemented before those content types are enabled.

## Events and limits

WebSocket events contain only event type, entity type/ID, revision, cursor, and
timestamp. Bodies, binaries, credentials, names, and unrelated content are
never broadcast. Each client has a bounded queue; expiry, revocation, overflow,
idle timeout, server stop, or vault loss closes it.

Default limits are 1 MiB HTTP bodies, 100 push mutations, 200 pull records,
64 KiB WebSocket messages, 8 concurrent clients, 30-second request timeouts,
two-minute idle timeout, and bounded authentication/pairing attempts.

See `sync-threat-model.md` for guarantees and limitations.
