import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class VaultValidation {
  const VaultValidation({
    required this.isValid,
    required this.path,
    required this.message,
    required this.isExistingVault,
  });

  final bool isValid;
  final String path;
  final String message;
  final bool isExistingVault;
}

class VaultService {
  static const _uuid = Uuid();
  static const requiredDirectories = [
    'database',
    'notes',
    'audio',
    'attachments',
    'backups',
    'exports',
    'logs',
  ];

  Future<String?> pickParentDirectory() {
    return FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a location for the ephtodo Phase 0 vault',
      lockParentWindow: true,
    );
  }

  Future<VaultValidation> createOrOpen(String selectedPath) async {
    if (selectedPath.trim().isEmpty) {
      return const VaultValidation(
        isValid: false,
        path: '',
        message: 'No directory was selected.',
        isExistingVault: false,
      );
    }

    final selected = Directory(p.normalize(p.absolute(selectedPath)));
    if (!await selected.exists()) {
      return VaultValidation(
        isValid: false,
        path: selected.path,
        message: 'Selected directory does not exist.',
        isExistingVault: false,
      );
    }

    final isVaultFolder =
        p.basename(selected.path).toLowerCase() == 'ephtodo-vault';
    final vault = isVaultFolder
        ? selected
        : Directory(p.join(selected.path, 'ephtodo-vault'));
    final manifest = File(p.join(vault.path, 'vault.json'));
    final existed = await manifest.exists();

    try {
      await vault.create(recursive: true);
      final probe = File(
        p.join(vault.path, '.ephtodo-write-probe-${_uuid.v4()}'),
      );
      await probe.writeAsString('write-probe', flush: true);
      await probe.delete();

      for (final name in requiredDirectories) {
        await Directory(p.join(vault.path, name)).create(recursive: true);
      }

      if (!existed) {
        await manifest.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'format': 'ephtodo-vault',
            'schemaVersion': 0,
            'phase': 'proof-of-concept',
            'id': _uuid.v4(),
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
          flush: true,
        );
      } else {
        final decoded =
            jsonDecode(await manifest.readAsString()) as Map<String, Object?>;
        if (decoded['format'] != 'ephtodo-vault') {
          return VaultValidation(
            isValid: false,
            path: vault.path,
            message: 'vault.json does not identify an ephtodo vault.',
            isExistingVault: true,
          );
        }
      }

      return VaultValidation(
        isValid: true,
        path: vault.path,
        message: existed
            ? 'Existing vault opened and write access verified.'
            : 'Vault created and write access verified.',
        isExistingVault: existed,
      );
    } on FileSystemException catch (error) {
      return VaultValidation(
        isValid: false,
        path: vault.path,
        message: 'Vault validation failed: ${error.message}',
        isExistingVault: existed,
      );
    } on FormatException {
      return VaultValidation(
        isValid: false,
        path: vault.path,
        message: 'Existing vault.json is not valid JSON.',
        isExistingVault: true,
      );
    }
  }
}
