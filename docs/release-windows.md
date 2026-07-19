# Windows release and packaging

## Supported release target

ephtodo targets 64-bit Windows 10 version 1809 or newer and Windows 11. A
normal app launch does not require administrator rights. User content remains
in the user-selected vault, outside the application installation directory, so
package removal does not delete a vault.

## Build

From a clean repository:

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test
flutter build windows --release
dart run msix:create --build-windows false
```

The MSIX configuration declares the product as `ephtodo`, x64 architecture,
English and Turkish resources, microphone access for recording, and private
network client/server access for explicitly enabled LAN sync. It does not add
a startup task, public-internet server capability, protocol activation, or file
association. Start-at-login is not implemented.

The package creates the normal Windows application entry. The current MSIX
tool does not expose an opt-in desktop-shortcut setting, so no desktop shortcut
is created by this release.

## Signing

The checked-in configuration creates an **unsigned development MSIX**. It
contains a non-secret development publisher subject solely to form a valid
manifest. No certificate, private key, password, or production publisher
identity is committed.

For public distribution, supply a code-signing certificate outside the
repository and override the signing settings. Never place a certificate path
containing personal information, its password, or private key in `pubspec.yaml`,
shell history intended for publication, CI logs, or Git. Production signing
has not been claimed unless separately verified.

Unsigned MSIX packages cannot pass a normal end-user install/uninstall smoke
without an explicit developer policy or trusted signing certificate. Package
contents and manifest can still be inspected offline. The unpackaged Release
bundle remains runnable for verification.

## Package inspection

Before distribution:

1. extract or list the MSIX;
2. confirm `ephtodo.exe`, Flutter runtime, required plug-in DLLs, generated
   assets, and `AppxManifest.xml` are present;
3. confirm no vault, SQLite/WAL/SHM, note, WAV, log, dump, test fixture,
   `.phase*` evidence, certificate, key, or source-control metadata is present;
4. confirm display name, version, architecture, languages, and capabilities;
5. install only a properly signed candidate, launch it, create a disposable
   fictional vault, uninstall, and verify the external vault remains.

Production installation and clean-uninstall validation remain blocked until a
trusted signing identity is available. Do not weaken Windows package policy to
make that check pass.
