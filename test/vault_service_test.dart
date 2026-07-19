import 'dart:convert';
import 'dart:io';

import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/core/vault/vault_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  final clock = FixedClock(DateTime.utc(2026, 7, 19, 12));

  setUp(() async => temp = await Directory.systemTemp.createTemp('ephtodo-'));
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('creates and reopens a valid portable vault', () async {
    final service = VaultService(const LocalFileSystem(), clock);
    final created = await service.createInParent(temp.path);
    final reopened = await service.open(created.root);

    expect(reopened.manifest.id, created.manifest.id);
    for (final directory in vaultDirectories) {
      expect(Directory(p.join(created.root, directory)).existsSync(), isTrue);
    }
  });

  test('rejects malformed and unsupported manifests', () async {
    final service = VaultService(const LocalFileSystem(), clock);
    final root = Directory(p.join(temp.path, 'ephtodo-vault'))
      ..createSync(recursive: true);
    final manifest = File(p.join(root.path, 'vault.json'));
    manifest.writeAsStringSync('{bad');
    await expectLater(
      service.open(root.path),
      throwsA(
        isA<VaultException>().having(
          (error) => error.code,
          'code',
          VaultFailureCode.manifestInvalid,
        ),
      ),
    );
    manifest.writeAsStringSync(
      jsonEncode({
        'format': 'ephtodo-vault',
        'id': 'fictional-id',
        'schemaVersion': 999,
        'createdAt': clock.now().toIso8601String(),
      }),
    );
    await expectLater(
      service.open(root.path),
      throwsA(
        isA<VaultException>().having(
          (error) => error.code,
          'code',
          VaultFailureCode.schemaUnsupported,
        ),
      ),
    );
  });

  test('rejects traversal and absolute paths', () async {
    final service = VaultService(const LocalFileSystem(), clock);
    final vault = await service.createInParent(temp.path);
    expect(
      () => service.resolveInside(vault, '..${p.separator}outside.txt'),
      throwsA(isA<VaultException>()),
    );
    expect(
      () => service.resolveInside(vault, p.absolute('outside.txt')),
      throwsA(isA<VaultException>()),
    );
  });

  test('reports write probe failure without overwriting data', () async {
    final root = Directory(p.join(temp.path, 'ephtodo-vault'))
      ..createSync(recursive: true);
    final service = VaultService(_WriteFailingFileSystem(), clock);
    await expectLater(
      service.createInParent(root.path),
      throwsA(
        isA<VaultException>().having(
          (error) => error.code,
          'code',
          VaultFailureCode.notWritable,
        ),
      ),
    );
    expect(File(p.join(root.path, 'vault.json')).existsSync(), isFalse);
  });
}

final class _WriteFailingFileSystem implements FileSystem {
  final _delegate = const LocalFileSystem();
  @override
  Future<void> createDirectory(String path) => _delegate.createDirectory(path);
  @override
  Future<void> deleteFile(String path) => _delegate.deleteFile(path);
  @override
  Future<bool> directoryExists(String path) => _delegate.directoryExists(path);
  @override
  Future<bool> fileExists(String path) => _delegate.fileExists(path);
  @override
  Future<String> readText(String path) => _delegate.readText(path);
  @override
  Future<void> writeText(String path, String value, {bool overwrite = true}) =>
      throw const FileSystemException('fictional access denied');
}
