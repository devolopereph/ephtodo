# Contributing

Keep changes phase-scoped, feature-first, and privacy-safe. Do not commit user
vaults, machine paths, recordings, databases, secrets, certificates, or local
diagnostics. Domain and feature code must not import the windowing plugin or
Drift-generated row types.

Before a local commit, run the gates in `docs/testing.md`, inspect the diff,
and update tests and documentation. Use fictional fixtures only. Sync changes
must preserve private-interface validation, fail-closed TLS and secure storage,
scoped authorization, request bounds, redacted logging, and the main-engine
write coordinator boundary.

Do not add cloud services, analytics, UPnP, public tunnels, automatic router
configuration, plaintext secrets, or a database dependency to secondary
Flutter engines. Backup extraction must remain allowlisted, traversal-safe,
integrity-checked, and unable to overwrite the active vault.

Release candidates require the privacy, secret, history, package-content, and
dependency/license checks documented in `docs/privacy-review.md` and
`docs/release-windows.md`. Never commit signing keys or passwords.
