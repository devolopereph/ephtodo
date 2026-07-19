# ephtodo Phase 2 report

Status: **implemented through the Phase 2 boundary**. No Notes, audio feature,
LAN server, packaging, remote, push, publication, or Phase 4 sticky controls
were added.

## 1. Architecture

Phase 2 adds application-owned immutable task, hierarchy, tag, filter, horizon,
event, and typed-error models. Widgets depend on repository interfaces and
focused Riverpod providers. Drift rows/companions are confined to the data
implementation. `DriftTaskWriteCoordinator` is constructed only in the main
workspace engine; the sticky engine sends typed protocol-v1 commands and never
constructs `AppDatabase`, a repository, or a vault mutation service.

## 2. Domain rules

Project types are workspace/project/folder/taskList with the documented
containment matrix, UUID identity, stable fractional sibling order, maximum
depth 8, root workspace restrictions, and rejection of self/cycle/descendant
moves. Task depth is bounded at 6. Titles/names trim and validate; start cannot
follow due; reminder cannot follow due. Statuses are open/inProgress/completed/
cancelled and priorities none/low/medium/high/urgent. Archive and Trash remain
separate. Tag names are case-insensitively unique.

## 3. Database and repositories

Drift schema v2 changes the task default from the Phase 1 placeholder `inbox`
to `open` and adds start, lifecycle, and text indexes. Project, task, tag,
ordering, hierarchy, archive, Trash, search, and retention repositories return
application models. Sync-relevant writes increment revisions, update
`updatedAt`, add `ChangeLog` rows in explicit transactions, and emit typed
events. Expected-revision checks reject stale edits. Permanent deletion is
accepted only for tasks already in Trash and deliberately includes descendants.

## 4. Horizon engine

The pure engine uses an injected local reference date and configurable first
weekday (Monday default). Due date takes precedence when both start and due are
present; start-only tasks use start. Calendar dates, not elapsed durations,
derive overdue/today/tomorrow/thisWeek/nextWeek/thisMonth/scheduled/someday,
with completed/archive/Trash lifecycle precedence. Upcoming maps to Tomorrow,
This Week, Next Week, Later This Month, and Future without duplicate rows.

## 5. Date rollover

`DateRolloverService` reconciles startup/resume date and timezone offset,
schedules the next local midnight, and invalidates derived views without
mutating tasks. Main lifecycle resume also runs retention. Fake-clock coverage
checks midnight scheduling and a slept-across date change.

## 6. Completion

The authoritative Phase 1 policy is read at command time. Complete atomically
sets `completedAt` and either `archivedAt`, `deletedAt`, or neither. Reopen
returns to open and clears completion plus policy-created lifecycle markers.
Subtasks are never auto-completed.

## 7. Archive, Trash, and retention

Task and project restore paths are explicit. Project archive/Trash deliberately
cascades lifecycle markers to descendants in one transaction; project
permanent deletion is not exposed. Thirty-day cleanup uses `deletedAt` and runs
at startup/resume; never mode performs no cleanup. Cleanup touches database
task/tag rows only, never note/audio/attachment files. Empty Trash requires UI
confirmation.

## 8. Search and filter

Search covers task title/description, hierarchy names, and assigned tags.
Filters cover status, priority, project, tag, horizon, completion, archive,
Trash, and pin state. Default queries exclude completed, archived, and deleted
items. Presentation debounce is 250 ms; SQLite uses deterministic order and
indexed lifecycle/date/location columns. Text matching uses SQLite `LIKE`;
FTS and pagination remain optional future performance improvements.

## 9. Main UI

The placeholder is replaced by localized Today, Upcoming, Projects, Completed,
Archive, Trash, and Settings navigation. Today includes overdue, due, pinned,
and collapsible completed sections plus quick add. Upcoming uses the five
derived groups. Projects presents a tree/content split, context archive/Trash,
and hierarchy creation. Every hierarchy type has localized rename, move,
move-up, move-down, archive, Trash, and restore controls. The same actions are
available from context menus and F2/Alt+M/Alt+Up/Alt+Down shortcuts. Typed
hierarchy failures are localized. The compact task editor covers title,
description, priority, status, start, due, project/list, parent task, tags,
subtasks, pin, reminder date, and editable recurrence rule. Lifecycle views
provide restore/permanent-delete actions.
Notes/audio are described as later work and sync remains visibly disabled.

## 10. Keyboard

Central shortcuts provide task creation (`Ctrl+N`), hierarchy creation
(`Ctrl+Shift+N`), search/command navigation (`Ctrl+F`/`Ctrl+K`), Today/
Upcoming/Projects (`Ctrl+1/2/3`), sticky (`Ctrl+Shift+S`), selected-task
complete/reopen (`Ctrl+Enter`), edit (`Ctrl+E`), Trash (`Delete`), and Escape
editor dismissal. Hierarchy shortcuts are F2 rename, Alt+M move, and
Alt+Up/Alt+Down reorder. Global actions avoid firing while an editable text
control has focus. Visible localized hints appear in the workspace footer.

## 11. Sticky IPC

Protocol v1 remains backward compatible and adds taskSnapshotRequest,
taskCreate, taskComplete, and taskReopen. Today snapshots contain sequence,
vault identity, and stable id/title/priority/completed/due/revision fields;
empty state is a real empty payload. Main validates commands, routes them
through the write coordinator, persists, adds ChangeLog, and rebroadcasts.
Acknowledgements include request identity; malformed, stale, missing-id,
unsupported, and internal paths use typed errors. Raw `ephtodo.v1` remains in
the platform adapter. Phase 4 source/opacity/monitor/compact/final styling is
absent.

## 12. Automated tests

Final `flutter test`: **53 passed**. Coverage includes horizons, local midnight,
week configuration, month/year/leap boundaries, start/due precedence,
completion/reopen policies, retention eligibility/off, hierarchy/task cycles,
stable order, tag duplicates, search composition, revision rollback,
ChangeLog, hierarchy/task/subtask/tag persistence, moves, archive/Trash/
restore/permanent delete, deliberate cascades, restart persistence, 1,000-row
seeded search, typed snapshots and every allowed sticky command shape,
malformed protocol rejection, the complete fictional application smoke, Today
sections/quick add/completion, all Upcoming groups, hierarchy tree/navigation
and context/keyboard actions, required editor fields and date validation,
completion-policy UI effects, Archive restore, Trash restore, Empty Trash
confirmation, search/filter, selected-task keyboard actions, and English and
Turkish key screens.

## 13. Native verification

`flutter build windows --debug` passed. The production Win32 verifier passed at
2026-07-19T14:42:08Z: distinct main/sticky HWNDs, same process, sticky
`WS_EX_TOPMOST=true`, main topmost=false, sticky visible, sticky z-index 12,
foreground main z-index 44, and sticky above the foreground normal window.
This is automated native evidence. The Phase 2 two-engine production smoke also
passed at 2026-07-19T15:07:08Z. A real sticky engine created and completed a
fictional Today task through typed platform IPC and the main write coordinator,
received snapshots, restarted the process, and observed persisted completion
at revision 2. AppDatabase instrumentation reported sticky open count 0 in both
runs. Hide/show was acknowledged and 380x540 geometry persisted. Sanitized
evidence is in gitignored `.phase2/stage1.json`, `.phase2/stage2.json`, and
`.phase2/summary.json`. No manual click or visual claim is substituted for this
automation; third-party-app visual appearance remains a manual visual check.

## 14. Seeded performance

An automated database test seeds 1,000 fictional tasks and requires composed
text/priority search to complete below two seconds in the test environment. It
passed. The suite did not record a stable microbenchmark number, so none is
claimed. Large-vault FTS/pagination remains future optimization.

## 15. Privacy

Scans found no database, vault, audio, certificate, key, credential, or log
artifacts. Tests use fictional fixtures and temporary restart data is deleted.
Sticky payloads are same-process IPC and are not logged. No network service,
remote, or push was created. `master_prompt_ephtodo.md` remains intentionally
untracked.

## 16. Known limits

- Drag-and-drop is optional and was not added because complete context,
  dedicated-control, and keyboard alternatives are present.
- Search uses `LIKE` and materializes candidate models for cross-entity
  matching; the seeded 1,000-task gate passed.
- Retention runs at startup/resume rather than through a continuously running
  daily timer, which still satisfies the Phase 2 retention boundary.
- Recurrence is preserved/editable but not evaluated or scheduled in Phase 2.
- Third-party-app visual appearance is a genuinely manual visual check and was
  not claimed. Phase 4 sticky controls and styling remain deliberately absent.

## 17. Commits

- `210616a` — transactional task hierarchy engine, rules, repositories, tests.
- `e253480` — localized keyboard-first workspace and typed sticky interaction.
- `7614a45` — architecture, testing, privacy documentation and this report.
- `fd0e128` — complete localized workspace controls and widget matrix.
- `538a55f` — two-engine sticky persistence and database-ownership proof.
- `19337c2` — final Phase 2 acceptance evidence and documentation.

## 18. Recommended Phase 3

Phase 2 acceptance gaps are closed. Phase 3 may begin with file-backed Notes
and WAV audio strictly through application services, preserving the main-owned
database writer and redacted diagnostics.
