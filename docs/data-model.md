# Data model
## Portable entities

`Note` metadata references a normalized vault-relative Markdown path, optional
project/task, SHA-256 content hash, lifecycle timestamps, and revision. Create,
save, rename, archive, Trash, restore, and permanent delete write a matching
`ChangeLog` row in an explicit transaction. Permanent deletion requires
`deletedAt`.

`AudioNote` metadata references a normalized `audio/` WAV path, optional
project/task/note, duration, MIME type, byte size, lifecycle timestamps, and
revision. Files are finalized from `.recording` temporary files only after a
non-empty WAV is produced. Permanent file deletion requires a trashed owner and
revalidated in-vault path.

Sticky source, opacity, compact state, metadata visibility, completed collapse,
borderless choice, and geometry are device-only app-support preferences; they
are not portable content.

Schema version 2 changed the task status default to `open` and added indexes for
start dates, lifecycle state, and case-insensitive task/project name lookup.
Application statuses are `open`, `inProgress`, `completed`, and `cancelled`;
priorities are `none`, `low`, `medium`, `high`, and `urgent`.

Project nodes use UUIDs, stable fractional sibling order, revision counters,
and a maximum depth of 8. A workspace contains projects; projects contain
folders or task lists; folders contain folders or task lists; task lists are
leaves. Root workspaces cannot be moved beneath another node, and self,
descendant, and cycle moves are rejected. Archive and Trash operations on a
project node deliberately update descendants in one transaction; permanent
project deletion is not exposed.

Tasks use UUIDs, stable sibling order, revision counters, and a maximum subtask
depth of 6. Completing a parent never completes subtasks. Archive and
`deletedAt` are independent. Permanent task deletion is accepted only from
Trash and deliberately includes descendants. Tag names are trimmed and
case-insensitively unique; deleting a tag removes assignments without deleting
tasks.

Horizon rows are not stored. Due date takes precedence when both start and due
exist; otherwise start date is used. Calendar-day comparisons classify
overdue, today, tomorrow, this/next week, this month, scheduled, and someday,
with lifecycle state taking precedence.

Drift schema version 1 defines Vault, ProjectNode, Task, Tag, TaskTag, Note,
AudioNote, Attachment, AppPreference, Device, ChangeLog, and ConflictRecord.
Stable text IDs, revisions, tombstone timestamps, originating device fields,
and the change log prepare future local synchronization without enabling it.

Indexes cover task due/status lookup, project task order, hierarchy order, and
change-log entity sequences. Foreign keys are enabled. Production connections
use WAL, `synchronous=NORMAL`, and a 5000 ms busy timeout.

Schema version 3 adds originating-device, revision, tombstone, and update
metadata required by synchronization; scoped paired devices; and
`SyncMutationReceipt` rows for client-mutation idempotency. ChangeLog sequence
is the incremental pull cursor. `ConflictRecord` preserves unsafe remote
payload metadata alongside the authoritative local revision until explicit
resolution. Stale deletion cannot silently resurrect a tombstoned entity.

Only the main Flutter engine opens the writable database. Task, note, audio,
sync, and backup operations define explicit write/snapshot boundaries. Backup
manifests are external versioned documents and never become application rows.
