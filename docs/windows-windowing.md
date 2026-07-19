# Windows windowing
## Phase 4 production windows

Production uses one process with main, sticky, and Quick Note Flutter engines
and distinct top-level HWNDs. Main owns all writes. Both secondary engines are
prevented from terminating the process and deliberately hide on close.

Sticky is topmost; main and Quick Note are not. It supports show/hide,
move/resize persistence, monitor-aware recovery through current work areas,
opacity clamped to 0.65–1.0, compact/expanded sizing, optional hidden chrome,
source switching, metadata/completed visibility, refresh, task commands, and
launching Quick Note/main. It appears inactive when restored to reduce focus
stealing.

Quick Note has separate geometry, normal z-order, title/body editing,
debounced autosave, manual `Ctrl+S`, undo/redo, counts, monospace mode, typed
save acknowledgements, stale-generation protection, and a vault-unavailable
state.

Protocol v1 adds note create/open/update/autosave/manual-save/rename/archive/
Trash/restore/snapshot/ack, sticky source/preferences/refresh, open-main,
open-task, and open-Quick-Note families without changing existing envelopes.

Protocol v1 remains the envelope format. Phase 2 adds typed
`taskSnapshotRequest`, `taskCreate`, `taskComplete`, and `taskReopen` messages.
Snapshots contain a monotonic sequence, vault identity, and task items with
stable id, title, priority, completion state, due timestamp, and revision.
Empty snapshots contain an empty task list rather than a placeholder.

The sticky sends only title creation and id/revision completion commands. The
main command handler validates the envelope, routes the operation through
`DriftTaskWriteCoordinator`, persists and writes `ChangeLog` atomically, then
broadcasts a fresh snapshot. Acknowledgements contain request identity;
malformed, stale, missing-id, unsupported, and internal failures return typed
redacted errors. Raw method-channel name `ephtodo.v1` remains confined to the
window adapter.

Phase 4 extends the Phase 2 foundation with source selection, opacity, compact
mode, monitor-aware recovery, optional borderless presentation, and the final
desktop styling.

`tooling/phase2/verify_native_tasks.ps1` provides a production automation mode,
not a repository bypass. The real secondary engine sends the same typed
commands used by its controls through `ephtodo.v1`; the main adapter and
coordinator perform every write. Two runs prove create, complete, snapshot,
restart persistence, hide/show, and geometry. Per-engine instrumentation makes
an attempted sticky `AppDatabase` open fail and records an observed open count
of zero in gitignored sanitized evidence.

ephtodo vendors patched `multi_window_manager` 1.3.0 under `tooling/vendor`.
The runner creates one process with multiple Flutter engines and independent
top-level HWNDs. Both windows use `SetQuitOnClose(false)`; the companion is
prevented from closing and uses hide/show semantics.

Plugin imports are confined to `multi_window_adapter.dart` and the application
sticky shell. Product/domain code depends on `WindowCoordinator`,
`SecondaryWindowClient`, `WindowCommandBus`, and `WindowGeometryStore`.
Geometry is device-only app-support state.

IPC envelopes are JSON, protocol-versioned, typed, request-correlated, sourced,
timestamped, payload-validated, and return structured acknowledgements/errors.
Families cover lifecycle/health, sticky state, task snapshot placeholder,
geometry, vault state, command acknowledgement, and errors. Snapshots can later
be supplemented by incremental events.

The production Debug app passed external Win32 checks for distinct HWNDs,
same-process ownership, `WS_EX_TOPMOST`, and z-order above a foreground normal
window. A `SetWindowPos(HWND_TOPMOST)` native fallback is documented but not
activated; enable it only if a plugin regression is reproduced.
