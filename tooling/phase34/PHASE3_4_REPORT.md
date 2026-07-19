# ephtodo Phase 3–4 completion report

Status: **complete through Phase 4**. Phase 5, LAN sync, packaging,
publication, remotes, and push were not started.

## 1. Notes architecture

`DriftNoteRepository` is constructed only by the main engine. It owns Note
metadata, Markdown files, revision checks, SHA-256 hashes, lifecycle timestamps,
associations, and ChangeLog writes. Domain models and repository interfaces
remain outside widgets and generated Drift models remain in the data layer.

## 2. Quick Note architecture

Quick Note is a real secondary Flutter engine and independent HWND. It has no
database, repository, or vault-file service. Typed protocol-v1 requests route
create/open/update/autosave/manual-save/rename/archive/Trash/restore through the
main coordinator. It provides deliberate hide-on-close, geometry persistence,
keyboard save, undo/redo, counts, monospace mode, associations, unavailable
state, and save-generation stale-response protection.

## 3. Note storage and autosave behavior

Notes are UTF-8 Markdown under vault-relative `notes/` paths. Every operation
revalidates path ownership. Writes use a unique temporary file, flush, backup,
replace, then transactional metadata/ChangeLog update with rollback. Main and
Quick Note editors debounce saves (700 ms and 600 ms). Search includes title
and file body without logging body content. Recovery removes interrupted
temporary files and reports orphan files or missing owned files without
guessing or overwriting.

## 4. Audio recording and playback behavior

`record` captures WAV PCM, 44.1 kHz, mono into hidden in-vault
`.recording.wav` files. `AudioCoordinator` exposes start/pause/resume/stop/
cancel, elapsed duration, metadata, rename, Trash/restore/delete, associations,
and ChangeLog. `WinmmAudioPlaybackService` isolates `PlaySoundW`; widgets never
call plugin or WinMM APIs directly.

## 5. Audio and note lifecycle safety

Zero-byte/header-only recordings are rejected, failed metadata commits remove
the finalized file, interrupted recordings are cleaned at startup, and
shutdown cancels active capture. Audio and notes quarantine files before
permanent deletion and restore them if the database transaction fails.
Permanent deletion requires a trashed owner and a validated in-vault path.
Stale revisions and stale save generations are rejected.

## 6. Sticky production architecture

Sticky is a real independent top-level HWND in the same process, using the
patched `multi_window_manager` architecture. It is topmost while main and Quick
Note are not, restores inactive to reduce focus stealing, hides instead of
terminating main, and supports move/resize persistence, monitor recovery,
opacity 0.65–1.0, compact/expanded sizing, and optional borderless chrome.

## 7. Sticky source and interaction behavior

Persisted sources include Today, Tomorrow, This Week, project, folder/list, and
pinned tasks. Main-owned filtering refreshes after task events, date rollover,
vault/window readiness, source changes, and manual refresh. Typed commands
complete/reopen/create tasks, open the selected task editor in main, switch
source, collapse completed, toggle metadata, open Quick Note/main, and refresh.

## 8. Desktop UI and theme improvements

Main navigation now includes Notes and Audio. Notes, Quick Note, audio controls,
sticky rows, menus, dialogs, surfaces, focus indicators, and density use the
desktop token system. Obsidian Black remains the default; Graphite, Midnight
Indigo, Nordic Light, and Warm Paper render in smoke coverage. Reduced motion
uses zero-duration theme tokens and sticky rows include semantics.

## 9. IPC additions

Protocol v1 remains backward compatible. Added typed note create/open/update/
autosave/manual-save/rename/archive/Trash/restore/snapshot/ack families and
sticky source/preferences/refresh/open-main/open-task/open-Quick-Note families.
Payload validation rejects malformed source, preference, task, note, geometry,
snapshot, and acknowledgement data. Raw `ephtodo.v1` method names remain
confined to the window adapter.

## 10. Single-writer and vault-ownership verification

Only main constructs `AppDatabase`, `DriftNoteRepository`, and
`AudioCoordinator`. Production evidence recorded sticky database opens **0**
and Quick Note database opens **0**. Both secondary engines mutated persistent
state through typed IPC; main performed all SQLite and vault-file writes.

## 11. Test categories and runtimes

- Phase 3 focused acceptance: 12 passed, approximately 7.7 s.
- Phase 4 focused acceptance: 5 passed, approximately 7.2 s.
- Final static analysis: 8.35 s, no issues.
- Complete Flutter suite: 70 passed in 10.04 s.
- Windows Debug build: 11.97 s in the timed gate; final rebuild 9.7 s.
- Production three-window native verifier: 16.99 s timed run.
- Two-engine sticky smoke: 12.30 s.
- WAV record/playback smoke: 4.90 s.
- Dependency resolution plus generation: approximately 16.0 s.

The slowest category was native three-window verification. In the Flutter
suite, `phase2_workspace_test.dart` was the slowest file group (about 4 s);
the complete fictional application smoke took about 2 s.

## 12. Exact passed-test count

The one complete `flutter test` acceptance run passed **70/70** tests. Focused
post-fix reruns also passed 12 Phase 3 tests, 5 Phase 4 tests, and 13 affected
workspace/Phase 4 tests.

## 13. Native HWND verification

Final production Debug evidence passed: three distinct HWNDs, one process,
sticky `WS_EX_TOPMOST=true`, main and Quick Note not topmost, all visible,
sticky z-index 10 above foreground main z-index 46, hide/show acknowledged,
geometry restored, main survived, and both secondary database-open counts were
zero. Evidence is gitignored in `.phase34/summary.json`.

## 14. Three-window coexistence result

Main, sticky, and Quick Note coexisted as visible independent windows. Sticky
created/completed a task through typed IPC and retained it after restart. Quick
Note created/autosaved through typed IPC and restored the note at revision 2
after restart. The separate two-engine smoke also passed create, complete,
snapshot, restart, hide/show, geometry, and zero sticky DB-open assertions.

## 15. Privacy scan results

No committed database, vault, audio, recording, key, certificate, credential,
log, dump, or local evidence artifacts were found. Path/key scans found only a
fictional Windows path and fictional secret in redaction tests. No personal
email, private key, access token, or personal note/audio content was found.
`.phase34/`, `.phase34-audio/`, vault data, databases, and audio formats are
ignored. No remote exists and no push occurred.

## 16. Known limitations

`PlaySoundW` intentionally has no seek, volume, playback pause, or completion
callback. Cross-application visual checks for Chrome, Explorer, VS Code,
multi-monitor removal, DPI scaling, fullscreen applications, focus behavior,
borderless ergonomics, and all five themes were **not manually performed**;
they remain an honest human checklist in `docs/testing.md`. Custom saved
filters are not exposed because the current filter architecture does not yet
provide a safely persisted named-filter model.

## 17. Commits created

- `bda789b` — Phase 3 notes/audio and Phase 4 multi-window implementation.
- `de3d2e0` — focused safety tests and production native/WAV verifiers.
- `7279acd` — sticky open-task routing into the main task editor.
- `9a98fff` — Phase 3–4 architecture, privacy, testing, and user documentation.

## 18. Recommended Phase 5 plan

Begin only under a new Phase 5 instruction: define the threat model and
versioned local API, add disabled-by-default binding, secure pairing and
credential storage, rate limiting, device revocation, incremental ChangeLog
pull/push, conflict preservation, and focused authorization/malformed-payload
tests. Route every sync mutation through the existing main write coordinator;
never let network handlers or secondary engines write SQLite or vault files.
