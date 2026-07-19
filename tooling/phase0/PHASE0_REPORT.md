# ephtodo Phase 0 report — native capability proof on Windows

Status: **complete**. All Phase 0 questions answered on real Windows
(win32 10.0.26200, MSVC Debug build). Phase 1 not started, per plan.

## 1. Selected windowing package

**`multi_window_manager` 1.3.0, vendored with a one-line native patch**
(`tooling/vendor/multi_window_manager`, wired via `dependency_overrides`).

Upstream 1.3.0 is unusable as published on Windows: `createWindow` prepends
the new window id to the caller's window arguments with `std::merge`, which
requires both input ranges to be sorted. Arbitrary args (`["sticky",
"{...json...}", "automation"]`) trip the MSVC Debug assertion
`sequence not ordered` (xutility:1814) inside
`multi_window_manager_plugin.dll` before the secondary engine starts; Release
builds hit unchecked UB and can silently reorder args. The patch replaces the
merge with plain concatenation (prepend id, append args) — details in
`tooling/vendor/multi_window_manager/PATCH.ephtodo.md`. No fallback to
`desktop_multi_window` was needed.

Architecture: one process, two Flutter engines, two independent top-level
HWNDs. The runner (`windows/runner/main.cpp`) registers
`MultiWindowManagerPluginSetWindowCreatedCallback` and builds a second
`FlutterWindow` with the same `data` bundle; `SetQuitOnClose(false)` on both
windows so hiding/closing the sticky never kills the main engine.

## 2. Selected IPC model

`multi_window_manager`'s built-in inter-window method channel
(`invokeMethodToWindow` / `onEventFromWindow`), which routes through the
shared native plugin in-process. Commands used:

- sticky → main: `sticky.ready`, `task.create`, `task.complete`,
  `sticky.geometry`, `sticky.hide` (single-writer command pattern)
- main → sticky: `tasks.snapshot` (full task list broadcast after every write)

No sockets/pipes needed for the two-engine single-process design.

## 3. Native Win32 SetWindowPos fallback

**Not required.** `setAlwaysOnTop(true)` on the secondary window produces a
real `WS_EX_TOPMOST` extended style. Verified externally with
`tool/verify_native.ps1` (EnumWindows + GetWindowLong + z-order walk):

- sticky HWND ≠ main HWND (independent top-level windows)
- sticky `WS_EX_TOPMOST` set; main not topmost
- with a normal window foregrounded, sticky z-index 13 vs competitor 48 —
  sticky remains in the topmost band above the focused window

## 4. Database ownership and connection design

Single-writer, exactly as mandated:

- `MainDatabaseWriter` (`lib/src/database_writer.dart`) is the **only** code
  that opens SQLite, and only the main engine constructs it.
- `sqlite3` (FFI, synchronous) with `journal_mode=WAL`,
  `synchronous=NORMAL`, `busy_timeout=5000`.
- DB lives inside the vault: `<vault>/database/ephtodo-phase0.sqlite`.
- Sticky never touches the file; it sends IPC commands, main persists, then
  broadcasts the new snapshot to the sticky.

## 5. Measured update latency (Debug build)

- sticky → main command round trip (create task, persist, respond): **4.1–4.6 ms**
- main → sticky snapshot delivery (send → receive timestamp): **1.0–1.3 ms**

Both are far below perception thresholds; Release builds will be faster.

## 6. Audio package and format result

- **Recording: `record` 7.x — works.** WAV (PCM 44.1 kHz mono) with
  pause/resume/stop; automated run produced a valid RIFF/WAVE file
  (152 KB for ~2 s including a paused span) inside `<vault>/audio/`.
- **Playback: `audioplayers` rejected; replaced with `winmm.dll PlaySoundW`
  via `dart:ffi`.** audioplayers' Windows backend emits platform-channel
  events from a non-platform thread (engine logs the violation), and the
  process died ~10 s later with 0xc0000005 in `flutter_windows.dll`.
  `PlaySoundW(SND_FILENAME|SND_ASYNC)` plays the recorded WAV with no plugin
  and no threading hazard. A production app wanting seek/volume should
  evaluate `just_audio`/media_kit instead; for Phase 0 the FFI route proves
  WAV playback.

## 7. Vault picker result

`file_picker`'s `getDirectoryPath` (native IFileDialog) works, including
`lockParentWindow`. `VaultService` normalizes the selection (reuses an
existing `ephtodo-vault` folder or creates one under the chosen parent),
performs a write probe, creates the seven required subdirectories, and
validates/creates the `vault.json` manifest. Covered by unit tests
(create + reopen + nonexistent-path rejection) and by the automated run
against `.phase0/automation-vault-parent`.

## 8. Failed experiments

1. **Stock `multi_window_manager` 1.3.0** — Debug assertion
   `sequence not ordered` on every secondary-window creation (std::merge on
   unsorted args). Fixed by vendored patch; passing pre-sorted args was
   rejected as a workaround since the id prepend still breaks ordering and
   Release UB remains.
2. **`audioplayers` for WAV playback on Windows** — non-platform-thread
   channel events corrupt the engine; reproducible 0xc0000005 crash ~10 s
   after playback. Replaced with winmm PlaySoundW over FFI.
3. **`FindWindowW` by title in the verification script** — returned NULL for
   Flutter windows despite exact titles; switched to `EnumWindows` filtered
   by process id.
4. **Notepad as z-order competitor** — modern Notepad relaunches as a Store
   app under a different pid, so its HWND can't be tracked from the launcher
   process; the script now foregrounds the app's own non-topmost main window
   as the competitor.
5. **Stale CMake build tree after switching the plugin to a path override** —
   `flutter build windows` failed at the INSTALL step until
   `build/windows` was deleted once.

## 9. Residual risks

- The vendored plugin must be kept in sync if upstream releases a fix
  (upstream issue not yet filed; patch is one line and documented).
- `PlaySoundW` is fire-and-forget: no completion events, pause, or volume.
  Fine for a PoC; production needs a proper audio-playback dependency or a
  small WASAPI wrapper.
- Both engines share one process: a crash in either engine kills both
  windows. Acceptable for a sticky companion; a separate-process design
  would need real out-of-process IPC.
- Latency numbers are Debug-build, small-payload measurements; large task
  lists should switch from full snapshots to deltas.
- `record`'s device enumeration was only exercised with one input device
  present.

## 10. Files created/changed in Phase 0

- `tooling/phase0/` — Flutter app (PoC lab): `lib/main.dart`,
  `lib/src/{app_state_store,audio_poc_service,database_writer,main_screen,sticky_screen,task_item,vault_service}.dart`,
  `test/phase0_services_test.dart`, `windows/runner/*` (secondary-window
  callback + `SetQuitOnClose(false)`), `pubspec.yaml`
  (dependency_overrides, ffi; audioplayers removed)
- `tooling/vendor/multi_window_manager/` — vendored 1.3.0 with the
  `std::merge` → concatenation patch; `PATCH.ephtodo.md` documents it
- `tooling/phase0/tool/verify_native.ps1` — external Win32 verification
  (HWNDs, WS_EX_TOPMOST, z-order)
- `tooling/phase0/PHASE0_REPORT.md` — this report
- `.phase0/` (gitignored) — automation vault, run logs, JSON results

## 11. Analyze and test results

- `dart format lib test` — clean
- `flutter analyze` — No issues found
- `flutter test` — 3/3 passed (vault create/reopen, invalid path, WAL
  single-writer persistence)
- `flutter build windows --debug` — success with the patched plugin

## 12. Manual Windows verification checklist

Automated equivalents all passed (see `.phase0/` artifacts); to re-verify by
hand:

1. Run `tooling/phase0/build/windows/x64/runner/Debug/ephtodo_phase0.exe`.
2. Select/create a vault via the native directory picker; confirm
   `ephtodo-vault/` with `vault.json` + 7 subfolders appears. [automated: pass]
3. Click "Show sticky": a second window appears and stays above Notepad/
   Chrome/Explorer when they are focused. [automated via z-order check: pass]
4. Add a task in the sticky: it appears in the main list (persisted by main
   writer) and echoes back to the sticky. [automated: pass, 4.1 ms]
5. Add a task in main: sticky updates immediately. [automated: pass, 1.3 ms]
6. Hide sticky from either window: sticky vanishes, main keeps running;
   "Show sticky" restores it at its previous position/size. [automated: pass]
7. Record → pause → resume → stop → play a WAV; file lands in
   `<vault>/audio/`. [automated: pass; audible playback worth a human ear check]
8. Move/resize sticky, restart the app, show sticky: geometry is restored.
   [geometry persistence automated; restart restore is code-read verified]

## 13. Recommended final production architecture

- **Windowing:** one process, two Flutter engines via patched
  `multi_window_manager` (or upstream once fixed). Keep
  `SetQuitOnClose(false)` + hide-not-close semantics for the sticky.
  Native `SetWindowPos(HWND_TOPMOST)` fallback remains available but unneeded.
- **IPC:** in-process window method channel with a small typed command enum
  (`task.create`, `task.complete`, …) and snapshot (later delta) broadcasts.
- **Data:** single-writer SQLite (WAL) owned by the main engine, vault-
  relative path, secondary windows are pure IPC clients. LAN sync stays
  post-MVP and must route through the same single writer.
- **Audio:** `record` for WAV capture into `<vault>/audio/`; replace
  PlaySoundW with a maintained playback package (verify its Windows threading)
  or a thin WASAPI FFI layer before shipping.
- **State:** app-support JSON for non-vault state (last vault path, sticky
  geometry), everything user-owned inside the vault.
