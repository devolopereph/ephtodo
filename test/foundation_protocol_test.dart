import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/core/theme/app_theme.dart';
import 'package:ephtodo/core/windowing/multi_window_adapter.dart';
import 'package:ephtodo/core/windowing/window_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('injected clock is deterministic', () {
    final value = DateTime.utc(2026, 7, 19, 12, 30);
    expect(FixedClock(value).now(), same(value));
  });

  test('structured logging redacts paths and secrets', () {
    final lines = <String>[];
    StructuredLogger(sink: lines.add).log(
      LogLevel.info,
      r'opened C:\Users\fictional\private\vault',
      fields: const {'detail': 'token=fictional-secret'},
    );
    expect(lines.single, isNot(contains('fictional-secret')));
    expect(lines.single, isNot(contains(r'C:\Users')));
    expect(lines.single, contains('<redacted>'));
  });

  test('all themes provide complete tokens and reduced motion', () {
    expect(appThemeTokens.keys.toSet(), AppThemeId.values.toSet());
    for (final id in AppThemeId.values) {
      final theme = buildAppTheme(id, reducedMotion: true);
      expect(theme.extension<AppTokens>()!.animationDuration, Duration.zero);
    }
  });

  test('IPC round-trips typed versioned envelopes', () {
    final original = WindowEnvelope(
      type: WindowMessageType.lifecycleReady,
      requestId: 'fictional-request',
      sourceWindowId: 'sticky-1',
      payload: const {'health': 'ready'},
      timestamp: DateTime.utc(2026, 7, 19),
    );
    final decoded = WindowEnvelope.decode(original.encode());
    expect(decoded.protocolVersion, windowProtocolVersion);
    expect(decoded.type, WindowMessageType.lifecycleReady);
    expect(decoded.requestId, original.requestId);
  });

  test('IPC rejects malformed, unknown, and invalid geometry messages', () {
    expect(
      () => WindowEnvelope.decode('{bad'),
      throwsA(
        isA<WindowProtocolException>().having(
          (error) => error.code,
          'code',
          WindowErrorCode.malformed,
        ),
      ),
    );
    expect(
      () => WindowEnvelope.fromJson({
        'protocolVersion': 1,
        'type': 'notACommand',
        'requestId': 'request',
        'sourceWindowId': 'source',
        'payload': <String, Object?>{},
        'timestamp': '2026-07-19T00:00:00Z',
      }),
      throwsA(isA<WindowProtocolException>()),
    );
    expect(
      () => WindowEnvelope.fromJson({
        'protocolVersion': 1,
        'type': 'geometryChanged',
        'requestId': 'request',
        'sourceWindowId': 'source',
        'payload': {'x': 1},
        'timestamp': '2026-07-19T00:00:00Z',
      }),
      throwsA(isA<WindowProtocolException>()),
    );
  });

  test('IPC validates task snapshots and all sticky commands', () {
    final snapshot = StickyTaskSnapshot(
      sequence: 7,
      vaultId: 'fictional-vault',
      tasks: const [
        StickyTaskSnapshotItem(
          id: 'task-1',
          title: 'Fictional task',
          priority: 'high',
          completed: false,
          revision: 3,
        ),
      ],
    );
    final decoded = WindowEnvelope.decode(
      WindowEnvelope(
        type: WindowMessageType.taskSnapshot,
        requestId: 'snapshot-request',
        sourceWindowId: 'main',
        payload: snapshot.toPayload(),
        timestamp: DateTime.utc(2026, 7, 19),
      ).encode(),
    );
    expect(StickyTaskSnapshot.fromPayload(decoded.payload).sequence, 7);

    for (final message in [
      WindowEnvelope(
        type: WindowMessageType.taskCreate,
        requestId: 'create',
        sourceWindowId: 'sticky',
        payload: const {'title': 'Fictional task'},
        timestamp: DateTime.utc(2026, 7, 19),
      ),
      WindowEnvelope(
        type: WindowMessageType.taskComplete,
        requestId: 'complete',
        sourceWindowId: 'sticky',
        payload: const {'id': 'task-1', 'revision': 3},
        timestamp: DateTime.utc(2026, 7, 19),
      ),
      WindowEnvelope(
        type: WindowMessageType.taskReopen,
        requestId: 'reopen',
        sourceWindowId: 'sticky',
        payload: const {'id': 'task-1', 'revision': 4},
        timestamp: DateTime.utc(2026, 7, 19),
      ),
    ]) {
      expect(WindowEnvelope.decode(message.encode()).type, message.type);
    }
  });

  test('IPC rejects malformed task commands and snapshots', () {
    expect(
      () => WindowEnvelope.fromJson({
        'protocolVersion': 1,
        'type': 'taskCreate',
        'requestId': 'request',
        'sourceWindowId': 'sticky',
        'payload': {'title': '  '},
        'timestamp': '2026-07-19T00:00:00Z',
      }),
      throwsA(
        isA<WindowProtocolException>().having(
          (error) => error.code,
          'code',
          WindowErrorCode.invalidPayload,
        ),
      ),
    );
    expect(
      () => WindowEnvelope.fromJson({
        'protocolVersion': 1,
        'type': 'taskComplete',
        'requestId': 'request',
        'sourceWindowId': 'sticky',
        'payload': {'id': 'task'},
        'timestamp': '2026-07-19T00:00:00Z',
      }),
      throwsA(isA<WindowProtocolException>()),
    );
  });

  test('IPC validates projectCreate names', () {
    final valid = WindowEnvelope(
      type: WindowMessageType.projectCreate,
      requestId: 'project-create',
      sourceWindowId: 'sticky',
      payload: const {'name': 'Fictional project'},
      timestamp: DateTime.utc(2026, 7, 19),
    );
    expect(
      WindowEnvelope.decode(valid.encode()).type,
      WindowMessageType.projectCreate,
    );
    expect(
      () => WindowEnvelope.fromJson({
        'protocolVersion': 1,
        'type': 'projectCreate',
        'requestId': 'request',
        'sourceWindowId': 'sticky',
        'payload': {'name': '  '},
        'timestamp': '2026-07-19T00:00:00Z',
      }),
      throwsA(
        isA<WindowProtocolException>().having(
          (error) => error.code,
          'code',
          WindowErrorCode.invalidPayload,
        ),
      ),
    );
  });

  test(
    'app support store salvages torn writes and keeps files valid',
    () async {
      final fs = _MemoryFileSystem();
      const path = 'support/state.json';
      final store = JsonAppSupportStore(path, fs);
      await store.write({'lastVaultPath': 'fictional-vault', 'count': 1});
      expect(
        await store.read(),
        containsPair('lastVaultPath', 'fictional-vault'),
      );

      // Simulate the interleaved-writer corruption seen in the field: valid
      // JSON followed by trailing garbage from an older, longer write.
      fs.files[path] = '${fs.files[path]!}ss":false}}';
      final salvaged = await store.read();
      expect(salvaged, containsPair('lastVaultPath', 'fictional-vault'));

      fs.files[path] = 'not json at all';
      expect(await store.read(), isEmpty);

      // Concurrent writes stay serialized and the final file decodes.
      await Future.wait([
        for (var i = 0; i < 20; i++) store.write({'value': i}),
      ]);
      expect(await store.read(), containsPair('value', 19));
    },
  );

  test(
    'geometry validates and persists through app-support boundary',
    () async {
      final support = _MemoryAppSupportStore();
      final store = AppSupportWindowGeometryStore(support);
      const expected = WindowGeometry(x: 100, y: 120, width: 380, height: 540);
      await store.save(expected);
      final loaded = await store.load();
      expect(loaded.toJson(), expected.toJson());
      expect(
        const WindowGeometry(x: 0, y: 0, width: 20, height: 20).isValid,
        isFalse,
      );
    },
  );
}

final class _MemoryAppSupportStore implements AppSupportStore {
  Map<String, Object?> values = {};
  @override
  Future<Map<String, Object?>> read() async => {...values};
  @override
  Future<void> write(Map<String, Object?> values) async {
    this.values = {...values};
  }
}

final class _MemoryFileSystem implements FileSystem {
  final files = <String, String>{};
  final directories = <String>{};

  @override
  Future<void> createDirectory(String path) async => directories.add(path);
  @override
  Future<bool> directoryExists(String path) async => directories.contains(path);
  @override
  Future<bool> fileExists(String path) async => files.containsKey(path);
  @override
  Future<String> readText(String path) async => files[path]!;
  @override
  Future<void> writeText(
    String path,
    String value, {
    bool overwrite = true,
  }) async {
    files[path] = value;
  }

  @override
  Future<void> deleteFile(String path) async => files.remove(path);
}
