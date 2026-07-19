import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:ephtodo/core/backup/vault_backup_service.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/core/vault/vault_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory root;
  late VaultService vaultService;
  late VaultHandle vault;
  late AppDatabase database;
  late VaultBackupService backups;
  final clock = FixedClock(DateTime.utc(2026, 7, 19, 16));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ephtodo-backup-test-');
    vaultService = VaultService(const LocalFileSystem(), clock);
    vault = await vaultService.createInParent(root.path);
    database = AppDatabase.open(
      p.join(vault.root, 'database', 'ephtodo.sqlite'),
    );
    backups = VaultBackupService(database, vault, vaultService, clock);
    await database
        .into(database.tasks)
        .insert(
          TasksCompanion.insert(
            id: 'fictional-task',
            title: 'Fictional backup task',
            createdAt: clock.now(),
            updatedAt: clock.now(),
            originatingDeviceId: 'desktop-test',
          ),
        );
    await File(
      p.join(vault.root, 'notes', 'fictional-note.md'),
    ).writeAsString('# Fictional note');
    await File(
      p.join(vault.root, 'audio', 'fictional-audio.wav'),
    ).writeAsBytes(List<int>.generate(64, (index) => index));
  });

  tearDown(() async {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'backup includes manifest, database, note, audio, and integrity hashes',
    () async {
      final destination = await Directory(
        p.join(root.path, 'selected-export'),
      ).create();
      final result = await backups.createBackup(destination.path);

      expect(await File(result.path).exists(), isTrue);
      expect(result.fileCount, greaterThanOrEqualTo(4));
      final archive = ZipDecoder().decodeBytes(
        await File(result.path).readAsBytes(),
        verify: true,
      );
      final names = archive.map((entry) => entry.name).toSet();
      expect(names, contains('backup.json'));
      expect(names, contains('vault.json'));
      expect(names, contains('database/ephtodo.sqlite'));
      expect(names, contains('notes/fictional-note.md'));
      expect(names, contains('audio/fictional-audio.wav'));
      final manifest =
          jsonDecode(
                utf8.decode(
                  archive
                      .firstWhere((entry) => entry.name == 'backup.json')
                      .readBytes()!,
                ),
              )
              as Map<String, dynamic>;
      expect(manifest['format'], 'ephtodo-backup');
      expect(manifest['backupVersion'], backupFormatVersion);
      expect(manifest['databaseSchemaVersion'], database.schemaVersion);
      expect(manifest['files'], hasLength(result.fileCount));
    },
  );

  test('restore validates integrity and uses a new vault path', () async {
    final destination = await Directory(
      p.join(root.path, 'selected-export'),
    ).create();
    final backup = await backups.createBackup(destination.path);
    final restoreParent = await Directory(
      p.join(root.path, 'restore-parent'),
    ).create();

    final restored = await backups.restoreIntoNewVault(
      backup.path,
      restoreParent.path,
    );

    expect(restored.databaseIntegrity, 'ok');
    expect(p.equals(restored.vault.root, vault.root), isFalse);
    expect(
      await File(
        p.join(restored.vault.root, 'notes', 'fictional-note.md'),
      ).readAsString(),
      '# Fictional note',
    );
    final restoredDatabase = sqlite3.open(
      p.join(restored.vault.root, 'database', 'ephtodo.sqlite'),
      mode: OpenMode.readOnly,
    );
    addTearDown(restoredDatabase.close);
    final task = restoredDatabase.select(
      "SELECT title FROM tasks WHERE id = 'fictional-task'",
    );
    expect(task.single['title'], 'Fictional backup task');
  });

  test('restore collision creates a new path instead of overwriting', () async {
    final destination = await Directory(
      p.join(root.path, 'selected-export'),
    ).create();
    final backup = await backups.createBackup(destination.path);
    final restoreParent = await Directory(
      p.join(root.path, 'restore-parent'),
    ).create();
    await Directory(
      p.join(restoreParent.path, 'ephtodo-vault-restored'),
    ).create();

    final restored = await backups.restoreIntoNewVault(
      backup.path,
      restoreParent.path,
    );

    expect(p.basename(restored.vault.root), 'ephtodo-vault-restored-1');
  });

  test(
    'restore rejects traversal before writing outside destination',
    () async {
      final archive = Archive()
        ..add(ArchiveFile.string('../outside.txt', 'unsafe'))
        ..add(
          ArchiveFile.string(
            'backup.json',
            jsonEncode({
              'format': 'ephtodo-backup',
              'backupVersion': backupFormatVersion,
              'vaultSchemaVersion': vaultManifestVersion,
              'databaseSchemaVersion': database.schemaVersion,
              'files': const [],
            }),
          ),
        );
      final encoded = ZipEncoder().encode(archive);
      final file = File(p.join(root.path, 'unsafe.zip'));
      await file.writeAsBytes(encoded);

      await expectLater(
        backups.restoreIntoNewVault(file.path, root.path),
        throwsA(
          isA<BackupException>().having(
            (error) => error.code,
            'code',
            BackupFailureCode.traversal,
          ),
        ),
      );
      expect(
        await File(p.join(root.parent.path, 'outside.txt')).exists(),
        isFalse,
      );
    },
  );

  test('restore rejects unsupported backup versions', () async {
    final destination = await Directory(
      p.join(root.path, 'selected-export'),
    ).create();
    final backup = await backups.createBackup(destination.path);
    final incompatible = await _rewriteManifest(
      File(backup.path),
      (manifest) => {...manifest, 'backupVersion': 999},
    );

    await expectLater(
      backups.restoreIntoNewVault(incompatible.path, root.path),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupFailureCode.versionUnsupported,
        ),
      ),
    );
  });

  test('restore rejects a payload that fails its manifest hash', () async {
    final destination = await Directory(
      p.join(root.path, 'selected-export'),
    ).create();
    final backup = await backups.createBackup(destination.path);
    final decoded = ZipDecoder().decodeBytes(
      await File(backup.path).readAsBytes(),
      verify: true,
    );
    final altered = Archive();
    for (final entry in decoded) {
      final bytes = entry.readBytes();
      if (!entry.isFile || bytes == null) continue;
      altered.add(
        ArchiveFile.bytes(
          entry.name,
          entry.name == 'notes/fictional-note.md'
              ? utf8.encode('# Altered note')
              : bytes,
        ),
      );
    }
    final file = File(p.join(root.path, 'altered.zip'));
    await file.writeAsBytes(ZipEncoder().encode(altered));

    await expectLater(
      backups.restoreIntoNewVault(file.path, root.path),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          anyOf(
            BackupFailureCode.integrityFailed,
            BackupFailureCode.manifestInvalid,
          ),
        ),
      ),
    );
  });

  test('interrupted backup artifacts are cleaned on the next backup', () async {
    final destination = await Directory(
      p.join(root.path, 'selected-export'),
    ).create();
    final staleDirectory = await Directory(
      p.join(destination.path, '.ephtodo-backup-stale.partial'),
    ).create();
    final staleFile = await File(
      p.join(destination.path, '.ephtodo-backup-stale.partial.zip'),
    ).writeAsString('partial');

    await backups.createBackup(destination.path);

    expect(await staleDirectory.exists(), isFalse);
    expect(await staleFile.exists(), isFalse);
  });
}

Future<File> _rewriteManifest(
  File source,
  Map<String, dynamic> Function(Map<String, dynamic>) update,
) async {
  final decoded = ZipDecoder().decodeBytes(
    await source.readAsBytes(),
    verify: true,
  );
  final rewritten = Archive();
  for (final entry in decoded) {
    final bytes = entry.readBytes();
    if (!entry.isFile || bytes == null) continue;
    if (entry.name == 'backup.json') {
      final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      rewritten.add(
        ArchiveFile.string(
          entry.name,
          const JsonEncoder.withIndent(' ').convert(update(manifest)),
        ),
      );
    } else {
      rewritten.add(ArchiveFile.bytes(entry.name, bytes));
    }
  }
  final output = File(p.join(source.parent.path, 'rewritten.zip'));
  await output.writeAsBytes(ZipEncoder().encode(rewritten));
  return output;
}
