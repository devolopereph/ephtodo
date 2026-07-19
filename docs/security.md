# Security

## Trust boundaries

The main engine is the only writable database and vault-file owner. Secondary
windows submit validated typed commands and never open the vault database.
Phase 5 adds an optional LAN listener in the main engine, but network adapters
receive only the application-owned `SyncWriteCoordinator`; they never receive
Drift or writable repositories. See `sync-threat-model.md` and `local-sync.md`.

Vault file resolution rejects absolute paths and traversal after
normalization. Existing manifests are validated rather than overwritten.
Note and audio operations additionally require the `notes/` or `audio/`
namespace before every read, write, rename, move, playback, or deletion.
Permanent file deletion requires a trashed metadata owner; files are first
quarantined so a database failure can restore them.
Structured logs redact path-like values and credential-like key/value pairs.
Audit events are allowlisted metadata rather than serialized requests. Task
bodies, note bodies, credentials, tokens, pairing codes, hashes, raw sync
payloads, device names, private addresses, and audio content must never be
logged.

Secrets, certificates, signing material, environment files, databases, audio,
vaults, local logs, and exports are ignored.

## Sync credentials

Sync remains disabled by default. Passwords use Argon2id with unique random
salts and bounded encoded parameters. Access credentials are random,
short-lived, scoped, revocable, and retained only as memory-only SHA-256
verifiers. Pairing codes are short-lived and single-use. Password verifiers and
TLS private keys use the Windows secure-storage implementation; no authentication
secret is written to SQLite or JSON settings.

The server uses a generated self-signed certificate through Dart TLS. Users
must compare the displayed SHA-256 fingerprint while pairing. Rotation clears
sessions. No plain HTTP mutation listener, wildcard/public bind, public tunnel,
UPnP, router configuration, or cloud service exists.

## Cryptographic dependencies

- Pointy Castle 4 provides Argon2id and key primitives (BSD-3-Clause).
- basic_utils 5 provides pure-Dart X.509 generation (MIT).
- flutter_secure_storage 10 uses the Windows secure-storage implementation,
  which protects an AES-GCM storage key with Windows facilities (BSD-3-Clause).
- `dart:io` `SecurityContext` and `HttpServer.bindSecure` provide TLS.

There is no weak password-hash fallback. If secure storage, certificate parsing,
or TLS setup fails, sync fails closed with a redacted error.
