# ephtodo Phase 1 report

Status: **complete for Phase 1 only**. Phase 2 was not started. No remote was
added, no push occurred, and no public repository was created.

## 1. Final structure

- `lib/app/` — typed bootstrap, global error handling, app/onboarding/workspace
  and sticky foundation shells.
- `lib/core/database/` — Drift v1 schema, migration, preferences/onboarding
  repositories.
- `lib/core/foundation/` — injected clock, filesystem, app-support storage,
  and structured redacted logging.
- `lib/core/theme/` — five tokenized themes and reduced-motion support.
- `lib/core/vault/` — portable vault create/open/validation/path safety.
- `lib/core/windowing/` — plugin adapters, typed IPC, geometry persistence.
- `lib/features/audio/domain/` — recorder/playback boundaries only; no Phase 1
  audio feature implementation.
- `lib/l10n/` — English and Turkish ARB plus generated localization.
- `test/` — vault, database/repository, policy, IPC, geometry, theme, logging,
  and clock coverage.
- `windows/` — production runner with multi-engine callback and
  `SetQuitOnClose(false)`.
- `docs/` and `tooling/phase1/` — architecture, privacy/testing guidance, and
  production native verifier.
- Existing `tooling/phase0/` and `tooling/vendor/` remain intact.

## 2. Toolchain and dependency policy

Validated with Flutter 3.44.4 stable and Dart 3.12.2. Direct package versions
are centralized in `pubspec.yaml` and resolved transitive versions are locked
in `pubspec.lock`.

- `flutter_riverpod` 3.3.2
- `drift` 2.34.2 / `drift_dev` 2.34.0
- `sqlite3` 3.5.0 (native assets; obsolete `sqlite3_flutter_libs` removed)
- `multi_window_manager` 1.3.0, vendored patched path
- `file_picker` 11.0.2
- `path` 1.9.1 / `path_provider` 2.1.6
- `uuid` 4.6.0
- `intl` 0.20.2 from the Flutter SDK constraint
- `build_runner` 2.15.1 / `flutter_lints` 6.0.0

No `audioplayers` dependency exists.

## 3. Architecture and bootstrap

The production entry point establishes Flutter and platform error handlers,
redacted structured logging, multi-window initialization, and `ProviderScope`.
Clock, filesystem, application-support storage, vault, geometry, database, and
window coordination are injectable boundaries. Startup vault failures are
handled without opening an unsafe database and unexpected bootstrap failures
render a minimal failure screen.

Windows application support stores only nonportable state: last vault path,
pre-vault onboarding resume step, and sticky geometry. The temporary onboarding
step is removed once a vault is selected. Portable preferences and future user
content stay in the vault.

## 4. Drift v1

Schema version 1 contains Vault, ProjectNode, Task, Tag, TaskTag, Note,
AudioNote, Attachment, AppPreference, Device, ChangeLog, and ConflictRecord.
Indexes cover due/status, project task order, hierarchy order, and change-log
entity sequences. Foreign keys, WAL, `synchronous=NORMAL`, and 5000 ms busy
timeout are configured at open. Migration creation and repository writes use
explicit boundaries.

Only the main engine constructs `AppDatabase`. Secondary engines have no
database dependency and submit typed commands to main. Generated Drift classes
are confined to the persistence/repository layer and are not exposed to
widgets.

## 5. Vault

The user selects a parent folder or an existing `ephtodo-vault`. Creation
normalizes paths, performs a unique write probe, creates the seven required
directories, and writes a versioned UUID manifest without overwrite. Reopen
validates format/schema and writability. Missing, malformed, unsupported,
unavailable, and unwritable vaults produce typed failures. Vault-relative path
resolution rejects absolute paths and normalized traversal.

## 6. Onboarding and policies

The app contains the required eight-step shell: welcome, vault,
completion behavior, Trash retention, theme, disabled sync introduction,
shortcuts/sticky introduction, and finish. Progress resumes before and after
vault creation. Completion (`archive`, `trash`, `keepCompleted`), Trash
retention (`thirtyDays`, `never`), theme, completion state, and current step
persist through repositories and remain represented as typed settings.
Monday is the documented/default product week boundary; horizon behavior is
reserved for Phase 2.

## 7. Windowing and IPC

Production uses the patched vendored plugin: one process, multiple Flutter
engines, independent HWNDs, runner callbacks, `SetQuitOnClose(false)`, and
hide-not-close sticky behavior. Plugin-specific Dart APIs are confined to the
application-owned window adapter. Main owns all persistence.

Protocol v1 envelopes include type, request ID, source window ID, payload, and
UTC timestamp. Validation rejects malformed JSON, unsupported versions,
unknown types, missing fields, and invalid payloads. Implemented families cover
lifecycle/ready/health, sticky state, task snapshot placeholder, geometry,
vault state, command acknowledgement, and structured errors. Full snapshots
can later coexist with incremental events.

The final sticky task interface is intentionally absent. Phase 1 provides a
real AOT shell, show/hide, ready acknowledgement, placeholder snapshot
broadcast, and geometry persistence.

## 8. Themes and localization

Obsidian Black is the default. Graphite, Midnight Indigo, Nordic Light, and
Warm Paper are selectable. Every theme defines background, surface, elevated
surface, primary/secondary text, accent, success, warning, danger, border,
focus ring, shadow, radius, spacing, and animation duration. Reduced motion
sets animation duration to zero. Tests instantiate and inspect all themes.
English and Turkish localization generation succeeds.

## 9. Tests and gates

Final gate run:

- `dart format .` — pass. It mechanically reformats one unchanged vendored
  upstream file; that unrelated formatting was restored afterward.
- `flutter pub get` — pass.
- `dart run build_runner build --delete-conflicting-outputs` — pass. Current
  build_runner reports that this legacy flag is removed/ignored, then
  successfully generates outputs.
- `flutter gen-l10n` — pass.
- `flutter analyze` — pass, no issues.
- `flutter test` — pass, 13 tests.
- `flutter build windows --debug` — pass.
- production native topmost verifier — pass.

Native automated evidence from the production Debug app: distinct main/sticky
HWNDs, same process, sticky `WS_EX_TOPMOST=true`, main topmost=false, sticky
visible, and sticky z-order above the foreground normal main window. The
external verifier waits for settled native style state. This is automated
Win32 evidence, not a claim that every manual production scenario was run.

The manual checklist in `docs/testing.md` covers Explorer/browser/fullscreen
competition, focus behavior, close/hide/restart, removable/unavailable drives,
read-only media, monitor/DPI changes, localization, and visual accessibility.
Those human-observation items were not executed in this automated session.

## 10. Privacy review

Final Git status and staged state were inspected; no staged files remained.
Searches covered absolute home/project paths, local/private IP patterns,
email/user identifiers, credentials/tokens/private keys, certificates, vault
artifacts, databases, WAV/audio, and logs.

Findings were benign: fictional test path/token strings, documentation terms,
and upstream vendor author/example metadata. No database, audio, certificate,
credential, log, or local verification artifact was present. `.gitignore`
covers runtime/build/privacy-sensitive files. `master_prompt_ephtodo.md`
remains intentionally untracked and was not committed.

## 11. Limitations and deferred work

- No task/project CRUD, horizons, hierarchy UI, search, cleanup scheduler, or
  final sticky task interaction: Phase 2 or later.
- No note or audio implementation. WAV recording and the app-owned audio
  interfaces remain the locked direction. PlaySoundW may only be used behind
  playback abstraction; its lack of seek/volume/pause/completion is documented.
- No sync server or network listener. The onboarding sync step is visibly
  disabled.
- The native `SetWindowPos(HWND_TOPMOST)` fallback is documented but inactive;
  activate only for a reproduced plugin regression.
- One process means a fatal engine crash affects all windows.
- Snapshot payload is currently a placeholder; later large datasets should use
  incremental events.

## 12. Phase 1 commits and notable files

- `4da8dd0` — application foundation, schema, onboarding, tests, runner.
- `96b7fbf` — architecture/privacy/testing documentation and native verifier.
- `cc60a44` — strict plugin adapter boundaries and audio service boundaries.
- `f27ea2e` — pre-vault onboarding resume.

Notable files include `lib/core/database/app_database.dart`,
`lib/core/vault/vault_service.dart`, `lib/core/windowing/window_protocol.dart`,
`lib/core/windowing/multi_window_adapter.dart`, `lib/app/ephtodo_app.dart`, and
`tooling/phase1/verify_native.ps1`.

## 13. Recommended Phase 2 plan

1. Add repository/domain models for project hierarchy, tasks, tags, stable
   ordering, transactions, and change-log writes.
2. Implement deterministic clock-based horizon/week/month calculations with
   Monday default and date-rollover reconciliation.
3. Build keyboard-first task CRUD, hierarchy navigation, completion/archive/
   soft-delete/restore, retention cleanup, and settings editors.
4. Broadcast typed task snapshots first, then introduce versioned incremental
   task events without allowing secondary database writes.
5. Add unit/database/widget coverage for hierarchy, horizons, rollover,
   completion policies, retention, soft deletion, and search/filter.
6. Repeat all gates, native regression verification, privacy review, focused
   local commits, and stop before Phase 3.
