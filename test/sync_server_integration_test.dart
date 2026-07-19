import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/core/security/password_hasher.dart';
import 'package:ephtodo/core/security/secret_store.dart';
import 'package:ephtodo/core/security/tls_material.dart';
import 'package:ephtodo/features/sync/application/sync_auth_service.dart';
import 'package:ephtodo/features/sync/data/drift_sync_coordinator.dart';
import 'package:ephtodo/features/sync/server/sync_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSyncWriteCoordinator coordinator;
  late MemorySecretStore secrets;
  late SyncAuthService auth;
  late SyncServer server;
  late HttpClient client;
  late int port;
  const clock = SystemClock();

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    coordinator = DriftSyncWriteCoordinator(database, clock);
    secrets = MemorySecretStore();
    auth = SyncAuthService(
      secrets,
      const Argon2idPasswordHasher(
        memoryKiB: 8192,
        iterations: 2,
        parallelism: 1,
      ),
      clock,
      coordinator,
      const Duration(seconds: 2),
    );
    await auth.setPassword('fictional-passphrase');
    port = await _availablePrivatePort();
    server = SyncServer(
      auth,
      coordinator,
      TlsMaterialManager(secrets, clock),
      clock,
      addressProvider: () async => [InternetAddress.loopbackIPv4],
      allowLoopback: true,
    );
    await server.start(port: port);
    client = HttpClient();
    client.badCertificateCallback = (_, _, _) => true;
    client.connectionTimeout = const Duration(seconds: 5);
  });

  tearDown(() async {
    client.close(force: true);
    await server.dispose();
    await coordinator.dispose();
    await database.close();
  });

  test(
    'health is minimal and protected routes require authorization',
    () async {
      final health = await _request(client, port, 'GET', '/api/v1/health');
      expect(health.status, 200);
      expect(health.json, {'status': 'ready', 'apiVersion': 1});
      expect(health.body, isNot(contains('vault')));
      expect(health.body, isNot(contains('device')));

      final status = await _request(client, port, 'GET', '/api/v1/sync/status');
      expect(status.status, 401);
      expect(
        status.json['error'],
        containsPair('code', 'authorization_required'),
      );

      final websocket = await _request(
        client,
        port,
        'GET',
        '/ws/v1/events',
        headers: {
          'connection': 'Upgrade',
          'upgrade': 'websocket',
          'sec-websocket-version': '13',
          'sec-websocket-key': 'ZmFrZS13ZWJzb2NrZXQta2V5',
        },
      );
      expect(websocket.status, 401);
    },
  );

  test('loopback pairing requires approval then permits scoped pull', () async {
    final pairing = await auth.beginPairing(server.currentStatus.fingerprint!);
    final submitted = await _request(
      client,
      port,
      'POST',
      '/api/v1/auth/pair',
      body: {
        'protocolVersion': 1,
        'pairingCode': pairing.code,
        'deviceId': 'device-one',
        'deviceName': 'Fictional phone',
        'publicMaterialFingerprint': 'client-key-one',
      },
    );
    expect(submitted.status, 202);
    final requestId = submitted.json['requestId']! as String;

    final pending = await _request(
      client,
      port,
      'POST',
      '/api/v1/auth/pair',
      body: {'protocolVersion': 1, 'requestId': requestId},
    );
    expect(pending.status, 202);
    await auth.approve(requestId);

    final approved = await _request(
      client,
      port,
      'POST',
      '/api/v1/auth/pair',
      body: {'protocolVersion': 1, 'requestId': requestId},
    );
    expect(approved.status, 200);
    final token = approved.json['accessToken']! as String;

    final pull = await _request(
      client,
      port,
      'POST',
      '/api/v1/sync/pull',
      headers: {'authorization': 'Bearer $token'},
      body: {
        'protocolVersion': 1,
        'afterSequence': 0,
        'pageSize': 20,
        'entityTypes': ['task', 'note'],
      },
    );
    expect(pull.status, 200);
    expect(pull.json['changes'], isEmpty);

    final admin = await _request(
      client,
      port,
      'GET',
      '/api/v1/devices',
      headers: {'authorization': 'Bearer $token'},
    );
    expect(admin.status, 403);
    expect(admin.json['error'], containsPair('code', 'missing_scope'));
  });

  test('malformed, oversized, and unsupported requests fail safely', () async {
    final malformed = await _rawRequest(
      client,
      port,
      '/api/v1/auth/pair',
      utf8.encode('{not-json'),
    );
    expect(malformed.status, 400);
    expect(malformed.json['error'], containsPair('code', 'malformed_json'));
    expect(malformed.body, isNot(contains('FormatException')));

    final unsupported = await _request(
      client,
      port,
      'POST',
      '/api/v1/auth/pair',
      body: {
        'protocolVersion': 99,
        'pairingCode': 'FICTIONAL',
        'deviceId': 'device-one',
        'deviceName': 'Fictional phone',
        'publicMaterialFingerprint': 'client-key-one',
      },
    );
    expect(unsupported.status, 409);
    expect(
      unsupported.json['error'],
      containsPair('code', 'unsupported_api_version'),
    );

    final oversized = await _rawRequest(
      client,
      port,
      '/api/v1/auth/pair',
      List<int>.filled(SyncServer.maxRequestBytes + 1, 65),
    );
    expect(oversized.status, 413);
    expect(oversized.json['error'], containsPair('code', 'request_too_large'));
  });

  test('stop closes listeners and clears server status', () async {
    await server.stop();
    expect(server.currentStatus.state, SyncServerState.disabled);
    await expectLater(
      _request(client, port, 'GET', '/api/v1/health'),
      throwsA(isA<SocketException>()),
    );
  });

  test('WebSocket closes when its device is revoked', () async {
    final token = await _pairToken(client, port, server, auth);
    final socket = await WebSocket.connect(
      'wss://127.0.0.1:$port/ws/v1/events',
      headers: {'authorization': 'Bearer $token'},
      customClient: client,
    );
    final closed = _closed(socket);

    await auth.revokeDevice('device-one');
    await closed.timeout(const Duration(seconds: 2));
    expect(socket.closeCode, WebSocketStatus.policyViolation);
  });

  test('WebSocket closes when its access credential expires', () async {
    final token = await _pairToken(client, port, server, auth);
    final socket = await WebSocket.connect(
      'wss://127.0.0.1:$port/ws/v1/events',
      headers: {'authorization': 'Bearer $token'},
      customClient: client,
    );
    final closed = _closed(socket);

    await closed.timeout(const Duration(seconds: 4));
    expect(socket.closeCode, WebSocketStatus.policyViolation);
  });

  test('network adapter source has no Drift or database dependency', () async {
    final source = await File(
      'lib/features/sync/server/sync_server.dart',
    ).readAsString();
    expect(source, isNot(contains('package:drift')));
    expect(source, isNot(contains('app_database.dart')));
    expect(source, isNot(contains('AppDatabase')));
  });
}

Future<int> _availablePrivatePort() async {
  final random = Random.secure();
  for (var attempt = 0; attempt < 50; attempt++) {
    final port = 49152 + random.nextInt(16384);
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return port;
    } on SocketException {
      continue;
    }
  }
  throw StateError('Could not reserve a loopback test port');
}

Future<_Response> _request(
  HttpClient client,
  int port,
  String method,
  String path, {
  Map<String, String> headers = const {},
  Map<String, Object?>? body,
}) async {
  final bytes = body == null ? null : utf8.encode(jsonEncode(body));
  return _rawRequest(
    client,
    port,
    path,
    bytes,
    method: method,
    headers: headers,
  );
}

Future<_Response> _rawRequest(
  HttpClient client,
  int port,
  String path,
  List<int>? bytes, {
  String method = 'POST',
  Map<String, String> headers = const {},
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('https://127.0.0.1:$port$path'),
  );
  headers.forEach(request.headers.set);
  if (bytes != null) {
    request.headers.contentType = ContentType.json;
    request.contentLength = bytes.length;
    request.add(bytes);
  }
  final response = await request.close();
  final body = await utf8.decodeStream(response);
  return _Response(
    response.statusCode,
    body,
    body.isEmpty
        ? const {}
        : (jsonDecode(body) as Map<String, dynamic>).cast<String, Object?>(),
  );
}

final class _Response {
  const _Response(this.status, this.body, this.json);
  final int status;
  final String body;
  final Map<String, Object?> json;
}

Future<String> _pairToken(
  HttpClient client,
  int port,
  SyncServer server,
  SyncAuthService auth,
) async {
  final pairing = await auth.beginPairing(server.currentStatus.fingerprint!);
  final submitted = await _request(
    client,
    port,
    'POST',
    '/api/v1/auth/pair',
    body: {
      'protocolVersion': 1,
      'pairingCode': pairing.code,
      'deviceId': 'device-one',
      'deviceName': 'Fictional phone',
      'publicMaterialFingerprint': 'client-key-one',
    },
  );
  final requestId = submitted.json['requestId']! as String;
  await auth.approve(requestId);
  final approved = await _request(
    client,
    port,
    'POST',
    '/api/v1/auth/pair',
    body: {'protocolVersion': 1, 'requestId': requestId},
  );
  return approved.json['accessToken']! as String;
}

Future<void> _closed(WebSocket socket) {
  final completer = Completer<void>();
  socket.listen(
    (_) {},
    onError: (_) {
      if (!completer.isCompleted) completer.complete();
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete();
    },
  );
  return completer.future;
}
