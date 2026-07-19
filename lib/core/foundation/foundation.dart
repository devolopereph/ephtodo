import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

abstract interface class Clock {
  DateTime now();
}

final class DatabaseOpenAudit {
  DatabaseOpenAudit._();

  static String engineRole = 'unconfigured';
  static int openCount = 0;

  static void configure(String role) {
    engineRole = role;
    openCount = 0;
  }

  static void recordOpen() {
    if (engineRole != 'main' && engineRole != 'unconfigured') {
      throw StateError('Secondary engine attempted to open AppDatabase');
    }
    openCount++;
  }
}

final class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now().toUtc();
}

final class FixedClock implements Clock {
  const FixedClock(this.value);
  final DateTime value;
  @override
  DateTime now() => value;
}

abstract interface class FileSystem {
  Future<bool> directoryExists(String path);
  Future<bool> fileExists(String path);
  Future<void> createDirectory(String path);
  Future<String> readText(String path);
  Future<void> writeText(String path, String value, {bool overwrite = true});
  Future<void> deleteFile(String path);
}

final class LocalFileSystem implements FileSystem {
  const LocalFileSystem();
  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: true);
  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();
  @override
  Future<bool> fileExists(String path) => File(path).exists();
  @override
  Future<String> readText(String path) => File(path).readAsString();
  @override
  Future<void> writeText(
    String path,
    String value, {
    bool overwrite = true,
  }) async {
    final file = File(path);
    if (!overwrite && await file.exists()) {
      throw FileSystemException('Refusing to overwrite file');
    }
    // Write-then-rename keeps the destination valid even if two writers
    // race or the process dies mid-write (a torn state.json previously
    // made the whole app fail to start).
    final temp = File(
      '$path.tmp-${DateTime.now().microsecondsSinceEpoch}-$pid',
    );
    await temp.writeAsString(value, flush: true);
    try {
      await temp.rename(path);
    } on FileSystemException {
      await temp.delete();
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String path) => File(path).delete();
}

abstract interface class AppSupportStore {
  Future<Map<String, Object?>> read();
  Future<void> write(Map<String, Object?> values);
}

final class JsonAppSupportStore implements AppSupportStore {
  JsonAppSupportStore(this.path, this.fs);
  final String path;
  final FileSystem fs;
  Future<void> _writes = Future<void>.value();

  @override
  Future<Map<String, Object?>> read() async {
    if (!await fs.fileExists(path)) return <String, Object?>{};
    final raw = await fs.readText(path);
    Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException {
      value = _salvage(raw);
      if (value == null) {
        return <String, Object?>{};
      }
    }
    if (value is! Map<String, dynamic>) return <String, Object?>{};
    return value;
  }

  @override
  Future<void> write(Map<String, Object?> values) {
    // Serialize writers so concurrent saves (geometry, preferences, sync
    // settings) cannot interleave on the same file.
    return _writes = _writes.then((_) async {
      await fs.createDirectory(p.dirname(path));
      await fs.writeText(path, jsonEncode(values));
    });
  }

  /// Recovers the longest valid JSON object prefix from a file that was
  /// corrupted by a torn write (valid JSON followed by trailing garbage).
  static Map<String, dynamic>? _salvage(String raw) {
    for (var end = raw.length - 1; end > 1; end--) {
      if (raw[end] != '}') continue;
      try {
        final value = jsonDecode(raw.substring(0, end + 1));
        if (value is Map<String, dynamic>) return value;
      } on FormatException {
        continue;
      }
    }
    return null;
  }
}

enum LogLevel { debug, info, warning, error }

final class StructuredLogger {
  StructuredLogger({this.sink = print});
  final void Function(String line) sink;

  static final _path = RegExp(r'(?:[A-Za-z]:[\\/]|/Users/|/home/)[^\s"]+');
  static final _secret = RegExp(
    r'(password|token|secret|authorization|noteBody|taskBody)=([^\s,]+)',
    caseSensitive: false,
  );
  static final _secretKey = RegExp(
    r'(password|token|secret|authorization|note.?body|task.?body|payload|audio)',
    caseSensitive: false,
  );

  String redact(String value) => value
      .replaceAll(_path, '<redacted-path>')
      .replaceAllMapped(_secret, (match) => '${match.group(1)}=<redacted>');

  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
  }) {
    sink(
      jsonEncode({
        'level': level.name,
        'event': redact(event),
        'fields': fields.map(
          (key, value) => MapEntry(
            key,
            _secretKey.hasMatch(key)
                ? '<redacted>'
                : redact(value?.toString() ?? 'null'),
          ),
        ),
      }),
    );
  }
}
