# Testing
## Automated coverage

Focused tests cover note create/read/save, content hashes, stale-save rejection,
filename collisions, missing files, interrupted autosave cleanup, archive/
Trash/restore/permanent-delete eligibility, Quick Note serialization, WAV
metadata, pause/resume/cancel, zero-byte rejection, orphan cleanup, path
safety, sticky source filtering, persisted preferences, opacity bounds,
compact state, unavailable-monitor recovery, command validation, and five-theme
rendering.

Production scripts:

1. `tooling/phase1/verify_native.ps1` — native topmost/z-order.
2. `tooling/phase2/verify_native_tasks.ps1` — two-engine task IPC, persistence,
   hide/show, geometry, and zero sticky database opens.
3. `tooling/phase34/verify_phase34.ps1` — three independent HWNDs, sticky
   topmost only, Quick Note typed autosave/restart, and zero Quick Note database
   opens.
4. `tooling/phase34/verify_audio_smoke.ps1` — real microphone WAV
   record/pause/resume/stop and WinMM playback.
5. `tooling/phase56/performance_scenario.dart` — fictional 10,000-task,
   1,000-note, audio-metadata, deep-hierarchy, and 20,000-ChangeLog profile.
6. `tooling/phase56/release_audit.ps1` — working-tree, ignored artifact,
   Git-history, identity, secret-pattern, dependency-license, and optional MSIX
   contents audit.

Automated tests cover calendar horizons (overdue, start-only, due precedence,
week configuration, month/year/leap boundaries, and Upcoming groups),
completion/reopen policies, retention off/eligibility, project and task cycle
rules, stable ordering, tag uniqueness, search composition, revision rollback,
change-log writes, hierarchy/task/subtask persistence, archive/Trash/restore/
permanent delete, the complete required English/Turkish widget matrix, the
fictional service smoke, and typed sticky snapshots/commands/rejections.

The exact required gate sequence is:

1. `dart format .`
2. `flutter pub get`
3. `dart run build_runner build`
4. `flutter gen-l10n`
5. `flutter analyze`
6. `flutter test`
7. `flutter build windows --debug`
8. `powershell -ExecutionPolicy Bypass -File tooling/phase34/verify_phase34.ps1`
9. `powershell -ExecutionPolicy Bypass -File tooling/phase34/verify_audio_smoke.ps1`

The native verifier proves distinct main/sticky HWNDs and the sticky topmost
style. The Phase 2 verifier runs two production Flutter engines, creates and
completes through typed sticky-to-main IPC, receives snapshots, restarts,
verifies persistence, exercises hide/show and geometry, and asserts the sticky
engine's instrumented `AppDatabase` open count is zero. Sanitized output is
gitignored under `.phase2`. Human-observation checks such as behavior over
third-party full-screen apps must not be reported as run unless performed.

Search uses deterministic SQLite ordering and `LIKE` matching for task,
hierarchy, and tag text. Exact-Today queries are date-bounded in SQLite before
domain classification; this reduced the fictional 10,000-task Today load from
1,030 ms to 245 ms and sticky refresh from 905 ms to 200 ms in the final JIT
tooling profile.

Automated tests cover vault creation/reopen, invalid and unsupported manifests,
write failure, traversal, onboarding resume, completion/Trash policies, all
themes and reduced motion, Drift v1 objects/indexes/repository persistence,
typed IPC round-trip/malformed rejection, geometry, log redaction, and the
injected clock.

Run the required gates from the repository root:

```powershell
dart format .
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test
flutter build windows --debug
powershell -ExecutionPolicy Bypass -File tooling/phase1/verify_native.ps1
powershell -ExecutionPolicy Bypass -File tooling/phase2/verify_native_tasks.ps1
powershell -ExecutionPolicy Bypass -File tooling/phase34/verify_phase34.ps1
powershell -ExecutionPolicy Bypass -File tooling/phase34/verify_audio_smoke.ps1
```

## Manual Windows production checklist

- Complete and resume all eight onboarding steps; cancel the folder picker.
- Create and reopen a vault on a normal drive; remove/unmount a test drive and
  confirm graceful unavailable-vault onboarding.
- Show the production sticky shell over Explorer, a browser, and a fullscreen
  capable normal app; confirm topmost and no unnecessary focus theft.
- Move/resize, hide/show, restart, and verify geometry and hide-not-close.
- Close the sticky and confirm the main process remains healthy.
- Start with a deliberately read-only test parent and verify safe failure.
- Change Windows scale/monitor layout and verify bounds stay usable.
- Confirm English and Turkish strings render and keyboard focus is visible.
- Check sticky over Chrome, Explorer, and VS Code; multi-monitor removal, DPI
  changes, fullscreen applications, focus behavior, borderless mode, and each
  of the five themes. These remain manual until explicitly recorded as run.

The script provides automated Win32 evidence. Cross-app visual readability,
audible behavior, removable-drive handling, and monitor ergonomics remain
manual and were not claimed as completed in Phase 3–4 automation.

## Phase 5–6 release gates

The release sequence adds the following after formatting, generation, analysis,
the complete Flutter suite, and Debug build:

1. `flutter build windows --release`
2. `powershell -ExecutionPolicy Bypass -File tooling/phase34/verify_phase34.ps1`
3. `powershell -ExecutionPolicy Bypass -File tooling/phase34/verify_audio_smoke.ps1`
4. `dart run tooling/phase56/performance_scenario.dart`
5. `dart run msix:create --build-windows false`
6. `powershell -ExecutionPolicy Bypass -File tooling/phase56/release_audit.ps1 -PackagePath build/msix/ephtodo-0.1.0-dev.msix`

Backup/restore tests cover complete manifests, SQLite snapshots, note/audio
inclusion, hash validation, version rejection, path traversal, collisions, and
interrupted cleanup. Sync tests cover Argon2id verification, pairing approval/
expiry/reuse, credential expiry/revocation/scopes, throttling, malformed and
oversized requests, pull pagination, idempotency, stale conflict/tombstone
behavior, server lifecycle, and WebSocket authentication/closure.

## Accessibility verification

Widget coverage exercises keyboard shortcuts, focus traversal, five theme
palettes, reduced motion, and semantics for task/sticky status. Desktop control
tokens provide visible focus, compact but usable hit targets, non-color labels,
and scalable Flutter text. Backup progress and result messages are announced
as semantic live regions; destructive sync and restore actions require
deliberate dialogs.

The automated suite cannot prove Narrator announcements, Windows forced-colors
rendering, every 200%+ text layout, switch-control input, or focus behavior
against third-party windows. Those remain explicit manual checks and must not
be reported as passed without observation.

## Performance profile

The final fictional profile ran on Windows 11 Pro build 26200 with Dart 3.12.2
in a JIT tooling process. It measured database open/first query 6.9 ms, Today
load 244.9 ms, 9,090-row project switch 264.6 ms, search 276.0 ms, sticky
refresh 199.8 ms, note metadata/body open 3.3 ms, and a 200-change sync pull
50.1 ms. Resident process memory was 362.9 MiB after seeding and all queries.

These are repeatable engineering measurements, not release-mode frame timings.
They include a synthetic in-process database and JIT overhead but exclude
Flutter first-frame, GPU, antivirus, disk variability, and native child-window
memory. Search and whole-project views still materialize large result sets;
pagination or FTS remains justified only if production traces show a need.
