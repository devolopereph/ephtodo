import 'dart:io';

import 'package:ephtodo_phase0/src/database_writer.dart';
import 'package:ephtodo_phase0/src/vault_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaultService', () {
    test('creates a portable vault and reopens it', () async {
      final parent = await Directory.systemTemp.createTemp('ephtodo-p0-');
      addTearDown(() => parent.delete(recursive: true));
      final service = VaultService();

      final created = await service.createOrOpen(parent.path);
      expect(created.isValid, isTrue);
      expect(created.isExistingVault, isFalse);
      expect(File('${created.path}/vault.json').existsSync(), isTrue);
      for (final directory in VaultService.requiredDirectories) {
        expect(Directory('${created.path}/$directory').existsSync(), isTrue);
      }

      final reopened = await service.createOrOpen(created.path);
      expect(reopened.isValid, isTrue);
      expect(reopened.isExistingVault, isTrue);
    });

    test('rejects a path that does not exist', () async {
      final service = VaultService();
      final result = await service.createOrOpen(
        '${Directory.systemTemp.path}/ephtodo-definitely-missing/path',
      );
      expect(result.isValid, isFalse);
    });
  });

  group('MainDatabaseWriter', () {
    test('persists main-owned task changes in WAL database', () async {
      final vault = await Directory.systemTemp.createTemp('ephtodo-db-p0-');
      addTearDown(() => vault.delete(recursive: true));
      final writer = MainDatabaseWriter.open(vault.path);
      addTearDown(writer.close);

      final task = writer.createTask('Prove single writer');
      expect(writer.loadTasks().single.title, 'Prove single writer');

      writer.setCompleted(task.id, true);
      expect(writer.loadTasks().single.completed, isTrue);
    });
  });
}
