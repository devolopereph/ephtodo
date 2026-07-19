# ephtodo_phase0

Phase 0 proof-of-concept lab for ephtodo on Windows: always-on-top secondary
(sticky) window, inter-window IPC with main-owned single-writer SQLite, vault
directory picker/validation, and WAV record/playback.

Findings and verification results: see [PHASE0_REPORT.md](PHASE0_REPORT.md).

Notes:

- `multi_window_manager` is consumed from a vendored, patched copy at
  `../vendor/multi_window_manager` (see its `PATCH.ephtodo.md`).
- `tool/verify_native.ps1` performs external Win32 verification
  (independent HWNDs, `WS_EX_TOPMOST`, z-order) against a running app.
- Run automated end-to-end verification with:
  `ephtodo_phase0.exe --phase0-auto=<writable-parent-dir>` — it creates a
  vault, spawns the sticky, exercises IPC/audio, and writes
  `phase0-automation-report.json` next to the vault.
