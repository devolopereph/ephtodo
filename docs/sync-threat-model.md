# Local sync threat model

## Scope and trust boundary

Phase 5 makes the Windows desktop application an explicitly enabled HTTPS and
WebSocket server for devices on the same private LAN. The desktop user selects
when pairing is possible and approves each device. The main Flutter engine is
the only SQLite and vault-file writer; network code can call only the typed sync
coordinator.

This is a local-network security design, not an internet-facing zero-trust
service. There is no cloud relay, discovery broadcast, UPnP, router
configuration, tunnel, or public-interface fallback.

## Protected assets

- task, project, tag, note metadata, audio metadata, and syncable preferences;
- note and audio vault files (their transfer is deferred in Phase 5);
- the sync password verifier, TLS private key, access tokens, pairing codes,
  device state, and audit metadata;
- entity revisions, tombstones, ChangeLog order, and conflict copies.

Passwords, access tokens, pairing codes, and TLS private keys are never written
to SQLite, JSON settings, logs, audit events, or source. The password verifier
and TLS key are held by the platform secure-storage implementation. Pairing
codes and access-token verifiers are memory-only.

## Threats and controls

### Another person on the same Wi-Fi or a malicious LAN device

The server is disabled by default, binds only to enumerated RFC1918 or loopback
addresses, and exposes only a content-free health response before
authentication. TLS protects transport. Pairing requires a short-lived,
single-use code plus explicit desktop approval. Every protected request needs a
non-expired, scoped token for a non-revoked device.

### Replay and stolen tokens

Access tokens are high-entropy opaque values, stored server-side only as
SHA-256 verifiers, expire after 15 minutes, and are invalidated by server stop,
credential reset, or device revocation. Push mutation IDs are idempotent per
device. TLS prevents passive token capture when the client pins the displayed
certificate fingerprint. This phase deliberately uses re-pairing instead of
refresh tokens, so no long-lived bearer credential is issued.

### Brute force and denial of service

Pairing and password attempts have per-source and per-device sliding limits,
exponential temporary lockout, and generic failures. Request bodies, field
lengths, collections, pull pages, push batches, clients, WebSocket frames,
queues, and idle/request duration are bounded. Slow or over-limit clients are
closed. Limits reduce abuse but cannot stop a device that can saturate the host
or LAN before application processing.

### Malformed, oversized, or hostile payloads

The HTTP boundary checks media type, declared and actual body size, JSON shape,
field types, enum values, UUID-like identifiers, timestamps, revisions, API
version, and collection counts. Errors use stable codes and never include SQL,
paths, raw exceptions, stack traces, or request payloads.

### Path traversal and file attacks

Phase 5 does not accept note bodies, audio bytes, archives, or client-provided
filesystem paths. Metadata paths are never writable API fields. Future file
transfer must use server-generated vault-relative paths, hashes, bounded
chunks, no symlinks or executable launch, and preserve both files on conflict.

### Unauthorized modification, stale revisions, and data loss

Endpoint scopes are checked separately from authentication. Pushes route to the
main write coordinator, verify device identity and base revision, run explicit
transactions, append ChangeLog, return authoritative revisions, and emit
minimal events. Stale or unsafe mutations create a ConflictRecord and preserve
the local value. Tombstones prevent implicit resurrection. Note-body and binary
conflict transfer remains deferred rather than silently overwriting content.

### Hostile proxies and certificate impersonation

The desktop generates a self-signed TLS certificate and displays its SHA-256
fingerprint during pairing. A client must compare and pin that fingerprint.
TLS alone does not protect a user who ignores a fingerprint mismatch, approves
an unknown device, or installs a hostile trust root. Certificate rotation
invalidates sessions and requires clients to verify the new fingerprint.

### Compromised or stolen paired devices

The desktop can revoke a device immediately; requests and WebSockets re-check
revocation. Revocation cannot erase data already synchronized to that device or
protect a currently unlocked, compromised desktop account.

### Sensitive logging

Audit records contain event kind, result code, redacted source class, device ID
suffix, and timestamp only. Request bodies, entity content, names, credentials,
tokens, local addresses, vault identity, paths, and exception text are not
logged.

### Accidental public binding and network changes

No wildcard address is used. Every bound address is independently validated as
private or loopback immediately before bind. Interface changes trigger a
controlled rebind; if no acceptable interface remains, the server fails closed
and reports a redacted actionable status.

## Explicit limitations

- LAN clients do not yet exist; interoperability is verified with loopback test
  clients.
- No internet exposure, NAT traversal, public PKI, hardware-backed client keys,
  mutual TLS, remote attestation, or protection from a compromised Windows
  account is claimed.
- Self-signed TLS depends on correct out-of-band fingerprint comparison.
- Metadata sync is implemented; note-body and binary audio transfer are
  specified but deferred.
- Application limits mitigate, but cannot eliminate, local resource exhaustion
  or network-level flooding.
