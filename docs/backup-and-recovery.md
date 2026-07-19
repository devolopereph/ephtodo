# Backup and recovery

## Backup format

Backups are user-initiated ZIP archives written to a selected export folder.
The main engine creates a transactionally consistent SQLite snapshot with
`VACUUM INTO`; it never copies a live WAL file. The archive contains:

- `backup.json`, format version, schema versions, creation time, counts, and a
  SHA-256 hash and byte length for every payload file;
- `vault.json`;
- `database/ephtodo.sqlite`;
- regular, non-hidden files below `notes/`, `audio/`, and `attachments/`.

Archive creation uses a unique staging directory and `.partial.zip` output in
the destination. Both are removed after success or failure. A later backup in
the same destination removes abandoned ephtodo partial outputs. Existing
backups are never overwritten; a numeric suffix resolves filename collisions.

Backups are **not encrypted**. They contain the same private content as the
vault and must be stored accordingly.

## Restore validation

Restore always targets a newly generated `ephtodo-vault-restored[-N]` folder
under a user-selected parent. It never replaces or merges into the active
vault.

Before the new folder is made available, restore:

1. verifies the ZIP structure and CRC;
2. limits the archive to 100,000 entries and 20 GiB of declared content;
3. rejects duplicate names, absolute paths, drive-qualified paths, `..`
   traversal, symbolic links, and unknown top-level folders;
4. validates backup, vault, and database schema versions;
5. extracts only files listed in `backup.json`;
6. verifies every byte length and SHA-256 digest;
7. opens the restored SQLite snapshot read-only and requires
   `PRAGMA integrity_check` to return `ok`;
8. validates the restored vault manifest through `VaultService`.

Extraction occurs in a unique partial folder. Failure removes that folder and
leaves the active vault unchanged. Restore detects corruption but does not
claim to repair it.

## Recovery behavior and limitations

- Missing or unavailable sources and destinations return a bounded,
  user-actionable error.
- Malformed manifests, unsupported versions, corruption, and unsafe paths fail
  closed.
- Startup vault recovery already detects interrupted note/audio temporary
  files, missing owned files, and orphan files without guessing ownership.
- A recovered vault is not selected automatically. The user can inspect it and
  select it during a later startup.
- Files changed concurrently during backup are copied atomically at the file
  level, but only SQLite receives a cross-file consistent snapshot. Stop
  editing large note/audio files during a critical archival backup.
