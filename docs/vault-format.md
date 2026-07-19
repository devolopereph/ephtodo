# Vault format

```text
ephtodo-vault/
  vault.json
  database/ephtodo.sqlite
  notes/
  audio/
  attachments/
  backups/
  exports/
  logs/
```

`vault.json` contains the format marker, UUID, schema version, and UTC creation
time. Version 1 is accepted. Creation never overwrites an existing manifest;
reopening validates the marker and schema, performs a temporary write probe,
and ensures required directories exist.

All app-owned relative paths are normalized and must remain beneath the vault
root. Absolute and traversal paths are rejected. An unavailable, malformed,
unsupported, or read-only vault produces a typed failure. No user task/note/
audio content belongs in Windows application support.

Phase 3 stores UTF-8 Markdown notes under `notes/` and WAV PCM recordings under
`audio/`. Note updates use a unique temporary file, flush, replacement, then a
transactional metadata/change-log update; a failed metadata update restores the
previous body. Recording uses hidden `.recording.wav` files and finalizes only
non-empty output. Startup recovery removes interrupted temporary files and
reports missing metadata/file counterparts without guessing or overwriting.

The application does not place generated backups inside `backups/`
automatically. The user chooses an export destination, which may be outside the
vault. A backup ZIP carries its own `backup.json` manifest and allowlisted
copies of `vault.json`, the database snapshot, notes, audio, and attachments.
See `backup-and-recovery.md`.

Restore never extracts over this layout in place. It validates names, links,
versions, lengths, hashes, and SQLite integrity in a temporary sibling and then
renames that sibling to a collision-safe `ephtodo-vault-restored[-N]` folder.
