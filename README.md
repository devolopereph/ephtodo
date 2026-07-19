# ephtodo

ephtodo is a privacy-first, local Windows workspace for tasks, Markdown notes,
and voice notes. It uses a user-selected portable vault and keeps the main
Flutter engine as the sole SQLite and vault-file writer.

## Implemented

- Project, workspace, folder, task-list, task, and subtask hierarchies.
- Tags, priorities, dates, Today/Upcoming horizons, completion policies,
  Archive, Trash, retention, search, and filters.
- Atomically saved Markdown notes and a dedicated database-free Quick Note
  window.
- WAV recording, metadata, lifecycle controls, and WinMM playback.
- A compact independent sticky window with configurable sources, opacity,
  create/complete/reopen, monitor recovery, and typed IPC.
- Five desktop themes, keyboard-first controls, reduced motion, focus styling,
  English and Turkish localization.
- Versioned vault backups with consistent database snapshots, SHA-256
  manifests, safe restore into a new vault, and integrity validation.
- A disabled-by-default HTTPS LAN sync server with explicit pairing, scoped
  short-lived credentials, incremental ChangeLog pull/push, device revocation,
  conflict records, and authenticated WebSocket events.
- Windows Release bundles and unsigned development MSIX packaging.

## Experimental

LAN sync is a server foundation for a future mobile client; no mobile app
exists. It is intended for explicitly trusted private LANs and uses a locally
generated certificate whose SHA-256 fingerprint must be compared during
pairing. It is not an internet-facing or zero-trust service. See
`docs/local-sync.md` and `docs/sync-threat-model.md`.

## Known limitations

- Audio playback intentionally has no seek, volume, pause, or completion
  callback.
- Note bodies and audio bytes are not transferred by Phase 5 sync.
- Backups are integrity-protected but not encrypted.
- Restores detect corruption but do not repair it and do not automatically
  replace the active vault.
- Start-at-login is not implemented.
- The development MSIX is unsigned; ordinary install/uninstall validation
  requires a trusted release-signing identity.
- Some Windows high-contrast, screen-reader, DPI, multi-monitor, fullscreen,
  and third-party focus interactions require manual verification.

## Roadmap

- A separately reviewed mobile client for the documented LAN protocol.
- Safe chunked note/audio synchronization with conflict copies.
- Production package signing and store/release automation.

Key shortcuts: `Ctrl+N` task, `Ctrl+Shift+N` hierarchy node, `Ctrl+F`/`Ctrl+K`
search, `Ctrl+1/2/3` Today/Upcoming/Projects, `Ctrl+Enter` selected-task
completion, `Ctrl+E` edit, `Delete` Trash, `F2` hierarchy rename, `Alt+M`
hierarchy move, `Alt+Up/Down` reorder, and `Ctrl+Shift+S` sticky.

## Requirements

- Windows 10/11 with Visual Studio Desktop C++ tooling
- Flutter 3.44.4 stable / Dart 3.12.2

## Develop

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter run -d windows
```

Run the gates in `docs/testing.md` before contributing. Windows package
instructions are in `docs/release-windows.md`.

## Privacy and storage

Portable user data belongs only in the selected `ephtodo-vault`. Device-only
state (last vault location, window geometry, and explicit sync enablement) is
stored in Windows application support. Authentication verifiers and TLS key
material use Windows secure storage. Vaults, databases, recordings, logs,
credentials, certificates, package signing files, and build outputs are
ignored by Git. Sync is disabled and starts no listener until explicitly
enabled.

Architecture and boundaries are documented under `docs/`. The project is
licensed under the MIT License; see `LICENSE`.

## Author

[devolopereph](https://github.com/devolopereph)
