import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../foundation/foundation.dart';
import '../vault/vault_service.dart';

const backupFormatVersion = 1;

enum BackupFailureCode {
  destinationInvalid,
  activeVaultCollision,
  archiveInvalid,
  manifestInvalid,
  versionUnsupported,
  traversal,
  integrityFailed,
  databaseCorrupt,
  interrupted,
}

final class BackupException implements Exception {
  const BackupException(this.code, this.message);
  final BackupFailureCode code;
  final String message;
}

final class BackupResult {
  const BackupResult({
    required this.path,
    required this.fileCount,
    required this.totalBytes,
    required this.createdAt,
  });

  final String path;
  final int fileCount;
  final int totalBytes;
  final DateTime createdAt;
}

final class RestoreResult {
  const RestoreResult({
    required this.vault,
    required this.fileCount,
    required this.totalBytes,
    required this.databaseIntegrity,
  });

  final VaultHandle vault;
  final int fileCount;
  final int totalBytes;
  final String databaseIntegrity;
}

final class VaultBackupService {
  VaultBackupService(
    this._database,
    this._vault,
    this._vaultService,
    this._clock, {
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  static const maxArchiveFiles = 100000;
  static const maxArchiveBytes = 20 * 1024 * 1024 * 1024;

  final AppDatabase _database;
  final VaultHandle _vault;
  final VaultService _vaultService;
  final Clock _clock;
  final Uuid _uuid;

  Future<BackupResult> createBackup(String destinationDirectory) async {
    final destination = Directory(
      p.normalize(p.absolute(destinationDirectory)),
    );
    if (!await destination.exists()) {
      throw const BackupException(
        BackupFailureCode.destinationInvalid,
        'The selected backup destination is unavailable.',
      );
    }
    await _cleanupInterrupted(destination);
    final createdAt = _clock.now();
    final operationId = _uuid.v4();
    final staging = Directory(
      p.join(destination.path, '.ephtodo-backup-$operationId.partial'),
    );
    final partialArchive = File(
      p.join(destination.path, '.ephtodo-backup-$operationId.partial.zip'),
    );
    try {
      await staging.create();
      final records = <Map<String, Object?>>[];
      var totalBytes = 0;
      final databaseTarget = File(
        p.join(staging.path, 'database', 'ephtodo.sqlite'),
      );
      await databaseTarget.parent.create(recursive: true);
      final escaped = databaseTarget.path.replaceAll("'", "''");
      await _database.customStatement("VACUUM INTO '$escaped'");
      final databaseRecord = await _record(
        databaseTarget,
        'database/ephtodo.sqlite',
      );
      records.add(databaseRecord);
      totalBytes += databaseRecord['size']! as int;

      for (final relative in ['vault.json', 'notes', 'audio', 'attachments']) {
        final entity = FileSystemEntity.typeSync(
          p.join(_vault.root, relative),
          followLinks: false,
        );
        if (entity == FileSystemEntityType.file) {
          final record = await _copyAndRecord(
            File(p.join(_vault.root, relative)),
            staging,
            relative,
          );
          records.add(record);
          totalBytes += record['size']! as int;
        } else if (entity == FileSystemEntityType.directory) {
          await for (final child in Directory(
            p.join(_vault.root, relative),
          ).list(recursive: true, followLinks: false)) {
            if (child is! File || p.basename(child.path).startsWith('.')) {
              continue;
            }
            final childRelative = _safeArchivePath(
              p.relative(child.path, from: _vault.root),
            );
            final record = await _copyAndRecord(child, staging, childRelative);
            records.add(record);
            totalBytes += record['size']! as int;
          }
        }
      }
      records.sort(
        (left, right) =>
            (left['path']! as String).compareTo(right['path']! as String),
      );
      final manifest = {
        'format': 'ephtodo-backup',
        'backupVersion': backupFormatVersion,
        'vaultSchemaVersion': _vault.manifest.schemaVersion,
        'databaseSchemaVersion': _database.schemaVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'fileCount': records.length,
        'totalBytes': totalBytes,
        'files': records,
      };
      await File(
        p.join(staging.path, 'backup.json'),
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));

      final encoder = ZipFileEncoder();
      await encoder.zipDirectory(
        staging,
        filename: partialArchive.path,
        followLinks: false,
      );
      final finalPath = await _uniqueBackupPath(destination, createdAt);
      await partialArchive.rename(finalPath);
      return BackupResult(
        path: finalPath,
        fileCount: records.length,
        totalBytes: totalBytes,
        createdAt: createdAt,
      );
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException(
        BackupFailureCode.interrupted,
        'The backup could not be completed. Partial output was removed.',
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await partialArchive.exists()) await partialArchive.delete();
    }
  }

  Future<RestoreResult> restoreIntoNewVault(
    String archivePath,
    String destinationParent,
  ) async {
    final archiveFile = File(p.normalize(p.absolute(archivePath)));
    final parent = Directory(p.normalize(p.absolute(destinationParent)));
    if (!await archiveFile.exists() || !await parent.exists()) {
      throw const BackupException(
        BackupFailureCode.destinationInvalid,
        'The backup or selected destination is unavailable.',
      );
    }
    final input = InputFileStream(archiveFile.path);
    late Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
    } on Object {
      input.closeSync();
      throw const BackupException(
        BackupFailureCode.archiveInvalid,
        'The selected file is not a valid backup archive.',
      );
    }
    if (archive.length > maxArchiveFiles) {
      input.closeSync();
      throw const BackupException(
        BackupFailureCode.archiveInvalid,
        'The backup contains too many entries.',
      );
    }
    final entries = <String, ArchiveFile>{};
    var declaredBytes = 0;
    for (final entry in archive) {
      late String safe;
      try {
        safe = _safeArchivePath(entry.name);
      } on BackupException {
        input.closeSync();
        rethrow;
      }
      if (entry.isSymbolicLink) {
        input.closeSync();
        throw const BackupException(
          BackupFailureCode.traversal,
          'Symbolic links are not accepted in backups.',
        );
      }
      if (entry.isFile) {
        declaredBytes += entry.size;
        if (declaredBytes > maxArchiveBytes || entries.containsKey(safe)) {
          input.closeSync();
          throw const BackupException(
            BackupFailureCode.archiveInvalid,
            'The backup size or entry names are invalid.',
          );
        }
        entries[safe] = entry;
      }
    }
    final manifestEntry = entries['backup.json'];
    if (manifestEntry == null || manifestEntry.size > 5 * 1024 * 1024) {
      input.closeSync();
      throw const BackupException(
        BackupFailureCode.manifestInvalid,
        'The backup manifest is missing or invalid.',
      );
    }
    late _BackupManifest manifest;
    try {
      final bytes = manifestEntry.readBytes();
      if (bytes == null) {
        throw const BackupException(
          BackupFailureCode.manifestInvalid,
          'The backup manifest cannot be read.',
        );
      }
      manifest = _parseManifest(jsonDecode(utf8.decode(bytes)));
    } on BackupException {
      input.closeSync();
      rethrow;
    } on Object {
      input.closeSync();
      throw const BackupException(
        BackupFailureCode.manifestInvalid,
        'The backup manifest is malformed.',
      );
    }
    final expectedEntries = {
      'backup.json',
      ...manifest.files.map((record) => record.path),
    };
    if (!entries.keys.toSet().containsAll(expectedEntries) ||
        !expectedEntries.containsAll(entries.keys)) {
      input.closeSync();
      throw const BackupException(
        BackupFailureCode.manifestInvalid,
        'The archive and manifest file lists do not match.',
      );
    }
    late Directory root;
    try {
      root = await _uniqueRestoreRoot(parent);
    } on BackupException {
      input.closeSync();
      rethrow;
    }
    if (p.equals(p.normalize(root.path), p.normalize(_vault.root))) {
      input.closeSync();
      throw const BackupException(
        BackupFailureCode.activeVaultCollision,
        'Restore cannot overwrite the active vault.',
      );
    }
    final partial = Directory('${root.path}.partial-${_uuid.v4()}');
    try {
      await partial.create();
      var restoredBytes = 0;
      var restoredFiles = 0;
      for (final record in manifest.files) {
        final entry = entries[record.path];
        if (entry == null || entry.size != record.size) {
          throw const BackupException(
            BackupFailureCode.integrityFailed,
            'A manifest file is missing or has the wrong size.',
          );
        }
        final target = File(p.join(partial.path, p.fromUri(record.path)));
        final normalized = p.normalize(p.absolute(target.path));
        if (!p.isWithin(p.normalize(p.absolute(partial.path)), normalized)) {
          throw const BackupException(
            BackupFailureCode.traversal,
            'A backup entry escapes the restore destination.',
          );
        }
        await target.parent.create(recursive: true);
        final output = OutputFileStream(target.path);
        entry.writeContent(output);
        output.closeSync();
        final digest = await _sha256(target);
        if (digest != record.sha256) {
          throw const BackupException(
            BackupFailureCode.integrityFailed,
            'A restored file failed its integrity check.',
          );
        }
        restoredBytes += record.size;
        restoredFiles++;
      }
      final databasePath = p.join(partial.path, 'database', 'ephtodo.sqlite');
      final integrity = await _databaseIntegrity(databasePath);
      if (integrity != 'ok') {
        throw const BackupException(
          BackupFailureCode.databaseCorrupt,
          'The restored database failed SQLite integrity validation.',
        );
      }
      await partial.rename(root.path);
      final handle = await _vaultService.open(root.path);
      return RestoreResult(
        vault: handle,
        fileCount: restoredFiles,
        totalBytes: restoredBytes,
        databaseIntegrity: integrity,
      );
    } finally {
      input.closeSync();
      if (await partial.exists()) await partial.delete(recursive: true);
    }
  }

  Future<Map<String, Object?>> _copyAndRecord(
    File source,
    Directory staging,
    String relative,
  ) async {
    final safe = _safeArchivePath(relative);
    final target = File(p.join(staging.path, p.fromUri(safe)));
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return _record(target, safe);
  }

  Future<Map<String, Object?>> _record(File file, String relative) async {
    final size = await file.length();
    return {
      'path': _safeArchivePath(relative),
      'size': size,
      'sha256': await _sha256(file),
    };
  }

  Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<String> _databaseIntegrity(String path) async {
    final restored = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return restored
          .select('PRAGMA integrity_check')
          .first
          .values
          .single
          .toString();
    } finally {
      restored.close();
    }
  }

  _BackupManifest _parseManifest(Object? decoded) {
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'ephtodo-backup') {
      throw const BackupException(
        BackupFailureCode.manifestInvalid,
        'The backup manifest format is invalid.',
      );
    }
    if (decoded['backupVersion'] != backupFormatVersion ||
        decoded['vaultSchemaVersion'] != vaultManifestVersion ||
        decoded['databaseSchemaVersion'] != _database.schemaVersion) {
      throw const BackupException(
        BackupFailureCode.versionUnsupported,
        'The backup version is not supported by this application.',
      );
    }
    final rawFiles = decoded['files'];
    if (rawFiles is! List || rawFiles.length > maxArchiveFiles) {
      throw const BackupException(
        BackupFailureCode.manifestInvalid,
        'The backup file list is invalid.',
      );
    }
    final files = rawFiles.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const BackupException(
          BackupFailureCode.manifestInvalid,
          'A backup file record is invalid.',
        );
      }
      final path = value['path'];
      final size = value['size'];
      final hash = value['sha256'];
      if (path is! String ||
          size is! int ||
          size < 0 ||
          hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const BackupException(
          BackupFailureCode.manifestInvalid,
          'A backup file record is invalid.',
        );
      }
      return _BackupFile(_safeArchivePath(path), size, hash);
    }).toList();
    final paths = files.map((file) => file.path).toSet();
    final expectedCount = decoded['fileCount'];
    final expectedBytes = decoded['totalBytes'];
    if (paths.length != files.length ||
        expectedCount is! int ||
        expectedCount != files.length ||
        expectedBytes is! int ||
        expectedBytes !=
            files.fold<int>(0, (total, file) => total + file.size)) {
      throw const BackupException(
        BackupFailureCode.manifestInvalid,
        'The backup manifest totals are invalid.',
      );
    }
    return _BackupManifest(files);
  }

  String _safeArchivePath(String value) {
    final portable = value.replaceAll(r'\', '/');
    final normalized = p.posix.normalize(portable);
    final first = normalized.split('/').first;
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.startsWith('/') ||
        normalized.contains(':') ||
        !{
          'vault.json',
          'database',
          'notes',
          'audio',
          'attachments',
          'backup.json',
        }.contains(first)) {
      throw const BackupException(
        BackupFailureCode.traversal,
        'The backup contains an unsafe path.',
      );
    }
    return normalized;
  }

  Future<String> _uniqueBackupPath(
    Directory destination,
    DateTime createdAt,
  ) async {
    final stamp = createdAt
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll('T', '-')
        .split('.')
        .first;
    for (var suffix = 0; suffix < 1000; suffix++) {
      final name = 'ephtodo-backup-$stamp${suffix == 0 ? '' : '-$suffix'}.zip';
      final candidate = File(p.join(destination.path, name));
      if (!await candidate.exists()) return candidate.path;
    }
    throw const BackupException(
      BackupFailureCode.destinationInvalid,
      'A unique backup filename could not be created.',
    );
  }

  Future<Directory> _uniqueRestoreRoot(Directory parent) async {
    for (var suffix = 0; suffix < 1000; suffix++) {
      final name = 'ephtodo-vault-restored${suffix == 0 ? '' : '-$suffix'}';
      final candidate = Directory(p.join(parent.path, name));
      if (!await candidate.exists()) return candidate;
    }
    throw const BackupException(
      BackupFailureCode.destinationInvalid,
      'A unique restore destination could not be created.',
    );
  }

  Future<void> _cleanupInterrupted(Directory destination) async {
    await for (final entity in destination.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.ephtodo-backup-') &&
          (name.endsWith('.partial') || name.endsWith('.partial.zip'))) {
        if (entity is Directory) {
          await entity.delete(recursive: true);
        } else if (entity is File) {
          await entity.delete();
        }
      }
    }
  }
}

final class _BackupManifest {
  const _BackupManifest(this.files);
  final List<_BackupFile> files;
}

final class _BackupFile {
  const _BackupFile(this.path, this.size, this.sha256);
  final String path;
  final int size;
  final String sha256;
}
