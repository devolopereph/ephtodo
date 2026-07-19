import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../foundation/foundation.dart';

const vaultManifestVersion = 1;
const vaultDirectories = [
  'database',
  'notes',
  'audio',
  'attachments',
  'backups',
  'exports',
  'logs',
];

enum VaultFailureCode {
  parentUnavailable,
  manifestInvalid,
  schemaUnsupported,
  notWritable,
  pathTraversal,
}

final class VaultException implements Exception {
  const VaultException(this.code, this.message);
  final VaultFailureCode code;
  final String message;
  @override
  String toString() => 'VaultException(${code.name}, $message)';
}

final class VaultManifest {
  const VaultManifest({
    required this.id,
    required this.schemaVersion,
    required this.createdAt,
  });

  factory VaultManifest.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final version = json['schemaVersion'];
    final createdAt = json['createdAt'];
    if (id is! String || version is! int || createdAt is! String) {
      throw const VaultException(
        VaultFailureCode.manifestInvalid,
        'Manifest fields are invalid',
      );
    }
    if (version != vaultManifestVersion) {
      throw const VaultException(
        VaultFailureCode.schemaUnsupported,
        'Unsupported vault schema',
      );
    }
    return VaultManifest(
      id: id,
      schemaVersion: version,
      createdAt: DateTime.parse(createdAt),
    );
  }

  final String id;
  final int schemaVersion;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'format': 'ephtodo-vault',
    'id': id,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

final class VaultHandle {
  const VaultHandle(this.root, this.manifest);
  final String root;
  final VaultManifest manifest;
}

final class VaultService {
  VaultService(this.fs, this.clock, {Uuid? uuid}) : uuid = uuid ?? const Uuid();
  final FileSystem fs;
  final Clock clock;
  final Uuid uuid;

  Future<VaultHandle> createInParent(String parent) async {
    final normalizedParent = p.normalize(p.absolute(parent));
    if (!await fs.directoryExists(normalizedParent)) {
      throw const VaultException(
        VaultFailureCode.parentUnavailable,
        'Selected parent is unavailable',
      );
    }
    final root = p.basename(normalizedParent).toLowerCase() == 'ephtodo-vault'
        ? normalizedParent
        : p.join(normalizedParent, 'ephtodo-vault');
    final manifestPath = p.join(root, 'vault.json');
    if (await fs.fileExists(manifestPath)) return open(root);

    await fs.createDirectory(root);
    await _writeProbe(root);
    for (final directory in vaultDirectories) {
      await fs.createDirectory(p.join(root, directory));
    }
    final manifest = VaultManifest(
      id: uuid.v4(),
      schemaVersion: vaultManifestVersion,
      createdAt: clock.now(),
    );
    await fs.writeText(
      manifestPath,
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
      overwrite: false,
    );
    return VaultHandle(root, manifest);
  }

  Future<VaultHandle> open(String root) async {
    final normalized = p.normalize(p.absolute(root));
    if (!await fs.directoryExists(normalized)) {
      throw const VaultException(
        VaultFailureCode.parentUnavailable,
        'Vault is unavailable',
      );
    }
    final path = p.join(normalized, 'vault.json');
    if (!await fs.fileExists(path)) {
      throw const VaultException(
        VaultFailureCode.manifestInvalid,
        'vault.json is missing',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(await fs.readText(path));
    } on FormatException {
      throw const VaultException(
        VaultFailureCode.manifestInvalid,
        'vault.json is malformed',
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'ephtodo-vault') {
      throw const VaultException(
        VaultFailureCode.manifestInvalid,
        'Not an ephtodo vault',
      );
    }
    final manifest = VaultManifest.fromJson(decoded);
    await _writeProbe(normalized);
    for (final directory in vaultDirectories) {
      await fs.createDirectory(p.join(normalized, directory));
    }
    return VaultHandle(normalized, manifest);
  }

  String resolveInside(VaultHandle vault, String relativePath) {
    if (p.isAbsolute(relativePath)) {
      throw const VaultException(
        VaultFailureCode.pathTraversal,
        'Absolute paths are rejected',
      );
    }
    final root = p.normalize(p.absolute(vault.root));
    final candidate = p.normalize(p.join(root, relativePath));
    if (!p.isWithin(root, candidate)) {
      throw const VaultException(
        VaultFailureCode.pathTraversal,
        'Path escapes vault',
      );
    }
    return candidate;
  }

  Future<void> _writeProbe(String root) async {
    final probe = p.join(root, '.ephtodo-write-probe-${uuid.v4()}');
    try {
      await fs.writeText(probe, 'probe', overwrite: false);
      await fs.deleteFile(probe);
    } catch (_) {
      throw const VaultException(
        VaultFailureCode.notWritable,
        'Vault is not writable',
      );
    }
  }
}
