# Third-party notices

ephtodo is MIT-licensed. The following direct dependencies are redistributed
or used to produce the application. Their full license texts remain available
in the corresponding package distributions and Flutter SDK.

## BSD-3-Clause

- Flutter SDK and Flutter-maintained packages
- `path`, `path_provider`
- `ffi`, `crypto`
- `pointycastle`
- `flutter_secure_storage`

The BSD copyright and disclaimer notices supplied by those packages must be
retained in source and binary distributions.

## MIT

- `drift`, `drift_dev`
- `flutter_riverpod`
- `file_picker`
- `uuid`
- `record`
- `screen_retriever`
- `basic_utils`
- `archive`
- `msix`
- `multi_window_manager`

The MIT copyright and permission notices supplied by those packages must be
included in substantial distributions.

## Other permissive components

- Dart `intl` is distributed under a BSD-style license.
- SQLite is public domain. The Dart `sqlite3` package is permissively licensed;
  its package license and bundled SQLite notices apply.

## Patched dependency

`tooling/vendor/multi_window_manager` is a source-vendored MIT dependency. The
ephtodo patch adds same-process multi-engine window registration, typed IPC
support, native HWND verification hooks, and lifecycle behavior. Its upstream
`LICENSE`, `README.md`, `CHANGELOG.md`, and `PATCH.ephtodo.md` are retained.

No reviewed direct dependency imposes copyleft, source-disclosure, advertising,
or non-commercial terms incompatible with this project's MIT distribution.
This notice is an engineering inventory, not legal advice. Release automation
must re-read actual resolved package licenses after dependency updates.
