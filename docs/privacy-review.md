# Privacy review
## Release review scope

Note bodies and audio bytes remain in the selected vault or an explicitly
selected backup destination. They are not logged, copied to app support, or
embedded in verification evidence. Phase 5 sync exchanges metadata only; note
bodies and audio bytes are deferred. Quick Note and sticky IPC remains
same-process; secondary engines cannot open `AppDatabase` or write vault files.

Phase 3–4 scanning must additionally reject committed Markdown note content,
WAV/recording files, temporary `.recording` files, vault manifests, automation
evidence, and screenshots. `.phase*` evidence and `*.wav` remain ignored.

Task and hierarchy content remains solely in the selected vault SQLite file.
Sticky snapshots stay inside the same-process window channel and are not
logged. Diagnostics for task operations contain event names and redacted IDs
only; raw task titles, descriptions, tag names, SQL, and stack traces are not
shown in the UI.

Retention and explicit permanent deletion affect owned database rows and
validated vault files. Only the backup service reads note, audio, and
attachment files for explicit export. Its archives are private user data and
are ignored. The LAN listener is disabled by default, binds validated
private/loopback addresses, and emits allowlisted audit metadata rather than
request bodies, names, addresses, or credentials.

Phase 2 fixtures use fictional names. Final scanning must include databases,
vault manifests, absolute paths, usernames, email addresses, IP addresses,
secrets/tokens/keys/certificates, logs, screenshots, and audio. Generated build
artifacts and local vault data remain ignored.

Review every release candidate with:

1. `git status --short` and staged diff inspection.
2. Search tracked content for absolute home paths, emails/user IDs, local IPs,
   credentials, private keys, certificate blocks, database/audio/log files,
   vault names, and private repository URLs.
3. Confirm `.gitignore` covers vaults, databases, recordings, logs, secrets,
   signing files, build output, and local verification artifacts.
4. Confirm fixtures are fictional and documentation does not expose machine
   paths.
5. Review generated screenshots and diagnostics manually before sharing.

Windows application support stores only device-level settings such as the last
selected vault path, window geometry, and explicit sync enablement. Windows
secure storage holds sync password verifiers and TLS key material. Portable
preferences and user content stay in the vault. Local planning prompts remain
untracked and must not be published.

The final audit must inspect both tracked working content and every commit,
classify matches as required source, fictional fixture, sanitized
documentation, or unsafe, and stop publication on any unresolved unsafe match.
Generated MSIX contents receive the same check.
