# Architecture
## Runtime boundaries

The main engine is the only database and vault writer. `DriftNoteRepository`
owns note metadata plus atomic Markdown writes, and `AudioCoordinator` owns WAV
finalization plus metadata. Quick Note and sticky are independent Flutter
engines and HWNDs with no database, repository, recorder, or vault service;
they use backward-compatible typed protocol-v1 commands.

Note saves carry expected revision, request ID, and monotonically increasing
save generation. The main engine rejects stale saves, commits file replacement
and metadata defensively, writes `ChangeLog`, and broadcasts acknowledgements.
Note bodies are never sent to diagnostics.

`record` captures WAV PCM 44.1 kHz mono to an in-vault temporary file.
Application-owned recorder, playback, and file-service boundaries isolate
plugins and WinMM from widgets/domain code. `PlaySoundW` remains the proven
playback adapter.

The production sticky uses persisted `StickyPreferences`, typed task commands,
main-owned source filtering, snapshots after every task mutation/date rollover,
monitor-aware geometry recovery, safe opacity, compact/expanded sizing, and
optional reduced chrome. The desktop token system drives all five themes.

Immutable application-owned `ProjectNode`, `Task`, `Tag`, filter, horizon, and
typed error models live under `features/tasks/domain`. Repository interfaces
and focused Riverpod providers depend only on those models. Drift rows and
companions remain inside `features/tasks/data`.

`DriftTaskWriteCoordinator` is constructed only by the main workspace engine.
Every sync-relevant mutation validates an expected revision where applicable,
runs row and `ChangeLog` updates in an explicit transaction, emits a typed
state event, and then causes a sticky snapshot broadcast. The secondary engine
does not import or construct `AppDatabase`, a repository, or a vault service.

The optional LAN listener also runs only in the main engine. HTTP and WebSocket
adapters receive the application-owned `SyncWriteCoordinator`, not a Drift
database or writable repository. Authentication, limits, API parsing, and TLS
remain outside persistence; accepted mutations cross the coordinator and are
transactional. Sticky and Quick Note remain database-free when sync is active.

`VaultBackupService` is likewise main-engine-only. It creates a consistent
SQLite snapshot, copies allowlisted vault files to temporary staging, and
creates a versioned integrity manifest. Restore validates an archive before
opening the result through `VaultService` and can write only to a new
user-selected vault folder.

Derived horizons and rollover never modify task rows. `DateRolloverService`
compares local calendar date and timezone offset at startup/resume, schedules
the next local midnight, and invalidates task views. Retention runs at startup
and resume and is disabled by the `never` preference.

Phase 1 uses a feature-first Flutter layout with application bootstrap under
`lib/app`, reusable infrastructure under `lib/core`, localization under
`lib/l10n`, and future product features under `lib/features`.

The main engine is the sole persistence owner. Secondary engines do not open
Drift or the vault database; they communicate through the typed window
protocol. Widgets consume repository models and never receive Drift-generated
row classes directly.

Riverpod's `ProviderScope` is the dependency boundary. Clock, filesystem,
application-support storage, logging, vault, database, and window coordination
are injectable abstractions. Expected failures use typed codes; unexpected
startup failures reach a redacted logger and a safe failure screen.

Dependency direction remains presentation → application/domain interfaces →
data adapters. Widgets do not receive Drift rows, TLS keys, password
verifiers, or raw IPC/network payloads.
