import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/foundation/foundation.dart';
import '../../../core/security/tls_material.dart';
import '../application/sync_auth_service.dart';
import '../application/sync_coordinator.dart';
import '../domain/sync_models.dart';

enum SyncServerState { disabled, starting, running, stopping, error }

final class SyncServerStatus {
  const SyncServerStatus({
    required this.state,
    this.port,
    this.addresses = const [],
    this.fingerprint,
    this.errorCode,
    this.connectedClients = 0,
  });

  final SyncServerState state;
  final int? port;
  final List<String> addresses;
  final String? fingerprint;
  final String? errorCode;
  final int connectedClients;
}

final class SyncServer {
  SyncServer(
    this._auth,
    this._coordinator,
    this._tls,
    this._clock, {
    Future<List<InternetAddress>> Function()? addressProvider,
    this.allowLoopback = false,
  }) : _addressProvider = addressProvider ?? _privateAddresses;

  static const apiVersion = 1;
  static const maxRequestBytes = 1024 * 1024;
  static const maxWebSocketMessageBytes = 64 * 1024;
  static const maxClients = 8;

  final SyncAuthService _auth;
  final SyncWriteCoordinator _coordinator;
  final TlsMaterialManager _tls;
  final Clock _clock;
  final Future<List<InternetAddress>> Function() _addressProvider;
  final bool allowLoopback;

  final _status = StreamController<SyncServerStatus>.broadcast();
  final List<HttpServer> _listeners = [];
  final Set<_SocketClient> _clients = {};
  StreamSubscription<SyncEvent>? _eventSubscription;
  SyncServerStatus _current = const SyncServerStatus(
    state: SyncServerState.disabled,
  );

  Stream<SyncServerStatus> get statuses => _status.stream;
  SyncServerStatus get currentStatus => _current;

  Future<void> start({required int port}) async {
    if (_current.state == SyncServerState.running ||
        _current.state == SyncServerState.starting) {
      return;
    }
    if (port < 49152 || port > 65535) {
      throw const SyncApiException(
        'port_invalid',
        'Choose a port between 49152 and 65535.',
      );
    }
    _setStatus(SyncServerStatus(state: SyncServerState.starting, port: port));
    try {
      if (!await _auth.hasPassword()) {
        throw const SyncApiException(
          'password_required',
          'Set a synchronization password before enabling the server.',
          statusCode: 409,
        );
      }
      final material = await _tls.loadOrCreate();
      final candidates = (await _addressProvider())
          .where(
            (address) =>
                _isPrivateIpv4(address.address) ||
                (allowLoopback && address.isLoopback),
          )
          .toSet()
          .toList();
      if (candidates.isEmpty) {
        throw const SyncApiException(
          'no_private_interface',
          'No eligible private network interface is available.',
          statusCode: 503,
        );
      }
      for (final address in candidates) {
        final listener = await HttpServer.bindSecure(
          address,
          port,
          material.createContext(),
          backlog: 16,
        );
        listener.idleTimeout = const Duration(minutes: 2);
        listener.listen(
          _handle,
          onError: (_) => _fail('listener_failed'),
          cancelOnError: false,
        );
        _listeners.add(listener);
      }
      _eventSubscription = _coordinator.events.listen(_broadcast);
      _setStatus(
        SyncServerStatus(
          state: SyncServerState.running,
          port: port,
          addresses: candidates.map((address) => address.address).toList(),
          fingerprint: material.fingerprint,
        ),
      );
    } on SyncApiException catch (error) {
      await _closeListeners();
      _fail(error.code);
      rethrow;
    } on TlsMaterialException catch (error) {
      await _closeListeners();
      _fail(error.code);
      throw const SyncApiException(
        'tls_unavailable',
        'Secure transport material is unavailable.',
        statusCode: 503,
      );
    } on Object {
      await _closeListeners();
      _fail('server_start_failed');
      throw const SyncApiException(
        'server_start_failed',
        'The local sync server could not start safely.',
        statusCode: 503,
      );
    }
  }

  Future<void> stop() async {
    if (_current.state == SyncServerState.disabled) return;
    _setStatus(
      SyncServerStatus(
        state: SyncServerState.stopping,
        port: _current.port,
        addresses: _current.addresses,
        fingerprint: _current.fingerprint,
        connectedClients: _clients.length,
      ),
    );
    _broadcast(SyncEvent(type: 'server_stopping', timestamp: _clock.now()));
    for (final client in _clients.toList()) {
      await client.close(WebSocketStatus.goingAway, 'server stopping');
    }
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _closeListeners();
    _auth.clearSessions();
    _setStatus(const SyncServerStatus(state: SyncServerState.disabled));
  }

  Future<void> rebind() async {
    final port = _current.port;
    if (_current.state != SyncServerState.running || port == null) return;
    await stop();
    await start(port: port);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await _route(request).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      await _error(
        request.response,
        const SyncApiException(
          'request_timeout',
          'The request timed out.',
          statusCode: 408,
        ),
      );
    } on SyncApiException catch (error) {
      await _error(request.response, error);
    } on FormatException {
      await _error(
        request.response,
        const SyncApiException(
          'malformed_json',
          'The request body is not valid JSON.',
        ),
      );
    } on Object {
      await _error(
        request.response,
        const SyncApiException(
          'internal_error',
          'The request could not be completed.',
          statusCode: 500,
        ),
      );
    }
  }

  Future<void> _route(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/api/v1/health') {
      return _json(request.response, 200, const {
        'status': 'ready',
        'apiVersion': apiVersion,
      });
    }
    if (request.method == 'POST' && path == '/api/v1/auth/pair') {
      final body = await _body(request);
      _version(body);
      final requestId = body['requestId'];
      if (requestId is String) {
        final approved = _auth.takeApproved(requestId);
        if (approved == null) {
          return _json(request.response, 202, const {'status': 'pending'});
        }
        return _json(request.response, 200, approved.toJson());
      }
      final pending = await _auth.submitPairing(
        sourceKey: request.connectionInfo?.remoteAddress.address ?? 'unknown',
        code: _string(body, 'pairingCode', 16),
        deviceId: _id(body, 'deviceId'),
        deviceName: _string(body, 'deviceName', 100),
        publicMaterialFingerprint: _string(
          body,
          'publicMaterialFingerprint',
          256,
        ),
      );
      return _json(request.response, 202, {
        'status': 'pending_approval',
        'requestId': pending.requestId,
      });
    }
    if (request.method == 'POST' && path == '/api/v1/auth/token') {
      final body = await _body(request);
      _version(body);
      final session = await _auth.login(
        sourceKey: request.connectionInfo?.remoteAddress.address ?? 'unknown',
        deviceId: _id(body, 'deviceId'),
        publicMaterialFingerprint: _string(
          body,
          'publicMaterialFingerprint',
          256,
        ),
        password: _string(body, 'password', 1024),
      );
      return _json(request.response, 200, session.toJson());
    }
    if (request.method == 'GET' && path == '/api/v1/devices') {
      await _authorized(request, SyncScope.deviceAdmin);
      return _json(request.response, 200, {
        'devices': (await _coordinator.devices())
            .map((device) => device.toJson())
            .toList(),
      });
    }
    if (request.method == 'DELETE' && path.startsWith('/api/v1/devices/')) {
      await _authorized(request, SyncScope.deviceAdmin);
      final id = path.substring('/api/v1/devices/'.length);
      if (!_validId(id)) {
        throw const SyncApiException(
          'device_id_invalid',
          'The device identifier is invalid.',
        );
      }
      await _auth.revokeDevice(id);
      return _json(request.response, 200, const {'status': 'revoked'});
    }
    if (request.method == 'POST' && path == '/api/v1/sync/pull') {
      final identity = await _authorized(request, SyncScope.read);
      final body = await _body(request);
      _version(body);
      final types = _entityTypes(body['entityTypes']);
      final page = await _coordinator.pull(
        deviceId: identity.deviceId,
        afterSequence: _integer(body, 'afterSequence', minimum: 0),
        pageSize: _integer(body, 'pageSize', minimum: 1, maximum: 200),
        entityTypes: types,
      );
      return _json(request.response, 200, page.toJson());
    }
    if (request.method == 'POST' && path == '/api/v1/sync/push') {
      final identity = await _authorized(request, SyncScope.write);
      final body = await _body(request);
      _version(body);
      final values = body['mutations'];
      if (values is! List || values.isEmpty || values.length > 100) {
        throw const SyncApiException(
          'invalid_batch_size',
          'Push batches must contain between 1 and 100 mutations.',
        );
      }
      final mutations = values
          .map((value) => _mutation(value, identity.deviceId))
          .toList();
      final results = await _coordinator.push(
        deviceId: identity.deviceId,
        mutations: mutations,
      );
      return _json(request.response, 200, {
        'results': results.map((result) => result.toJson()).toList(),
        'cursor': await _coordinator.latestSequence(),
      });
    }
    if (request.method == 'GET' && path == '/api/v1/sync/status') {
      await _authorized(request, SyncScope.read);
      return _json(request.response, 200, {
        'apiVersion': apiVersion,
        'cursor': await _coordinator.latestSequence(),
        'serverTime': _clock.now().toUtc().toIso8601String(),
      });
    }
    if (request.method == 'GET' && path == '/ws/v1/events') {
      return _upgrade(request);
    }
    throw const SyncApiException(
      'route_not_found',
      'The requested API route does not exist.',
      statusCode: 404,
    );
  }

  Future<Map<String, Object?>> _body(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType?.mimeType != ContentType.json.mimeType) {
      throw const SyncApiException(
        'content_type_invalid',
        'Use application/json for this request.',
        statusCode: 415,
      );
    }
    if (request.contentLength > maxRequestBytes) {
      throw const SyncApiException(
        'request_too_large',
        'The request body exceeds the allowed size.',
        statusCode: 413,
      );
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxRequestBytes) {
        throw const SyncApiException(
          'request_too_large',
          'The request body exceeds the allowed size.',
          statusCode: 413,
        );
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const SyncApiException(
        'payload_invalid',
        'The request body must be a JSON object.',
      );
    }
    return decoded.cast<String, Object?>();
  }

  Future<AuthenticatedDevice> _authorized(
    HttpRequest request,
    SyncScope scope,
  ) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      throw const SyncApiException(
        'authorization_required',
        'A bearer access credential is required.',
        statusCode: 401,
      );
    }
    return _auth.authenticate(
      authorization.substring('Bearer '.length),
      requiredScope: scope,
    );
  }

  Future<void> _upgrade(HttpRequest request) async {
    if (_clients.length >= maxClients) {
      throw const SyncApiException(
        'client_limit_reached',
        'The server has reached its connection limit.',
        statusCode: 503,
      );
    }
    final identity = await _authorized(request, SyncScope.read);
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      throw const SyncApiException(
        'websocket_upgrade_required',
        'A WebSocket upgrade is required.',
        statusCode: 426,
      );
    }
    final socket = await WebSocketTransformer.upgrade(request);
    final client = _SocketClient(socket, identity, _clock);
    _clients.add(client);
    _refreshClientCount();
    unawaited(
      client.done.whenComplete(() {
        _clients.remove(client);
        _refreshClientCount();
      }),
    );
  }

  void _broadcast(SyncEvent event) {
    for (final client in _clients.toList()) {
      if (event.type == 'device_revoked' &&
          event.entityId == client.identity.deviceId) {
        unawaited(
          client.close(WebSocketStatus.policyViolation, 'device revoked'),
        );
      } else if (!_clock.now().isBefore(client.identity.expiresAt)) {
        unawaited(
          client.close(WebSocketStatus.policyViolation, 'credential expired'),
        );
      } else {
        client.send(event);
      }
    }
  }

  void _refreshClientCount() {
    _setStatus(
      SyncServerStatus(
        state: _current.state,
        port: _current.port,
        addresses: _current.addresses,
        fingerprint: _current.fingerprint,
        errorCode: _current.errorCode,
        connectedClients: _clients.length,
      ),
    );
  }

  Future<void> _closeListeners() async {
    for (final listener in _listeners) {
      await listener.close(force: true);
    }
    _listeners.clear();
  }

  void _fail(String code) => _setStatus(
    SyncServerStatus(state: SyncServerState.error, errorCode: code),
  );

  void _setStatus(SyncServerStatus value) {
    _current = value;
    if (!_status.isClosed) _status.add(value);
  }

  Future<void> dispose() async {
    await stop();
    await _status.close();
  }

  static Future<List<InternetAddress>> _privateAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return interfaces.expand((interface) => interface.addresses).toList();
  }

  static bool _isPrivateIpv4(String value) {
    final parts = value.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  static void _version(Map<String, Object?> body) {
    if (body['protocolVersion'] != apiVersion) {
      throw const SyncApiException(
        'unsupported_api_version',
        'The requested protocol version is not supported.',
        statusCode: 409,
      );
    }
  }

  static String _string(Map<String, Object?> body, String key, int maximum) {
    final value = body[key];
    if (value is! String || value.isEmpty || value.length > maximum) {
      throw SyncApiException(
        'field_invalid',
        'The $key field is missing or invalid.',
      );
    }
    return value;
  }

  static String _id(Map<String, Object?> body, String key) {
    final value = _string(body, key, 128);
    if (!_validId(value)) {
      throw SyncApiException(
        'field_invalid',
        'The $key field is missing or invalid.',
      );
    }
    return value;
  }

  static int _integer(
    Map<String, Object?> body,
    String key, {
    required int minimum,
    int? maximum,
  }) {
    final value = body[key];
    if (value is! int ||
        value < minimum ||
        (maximum != null && value > maximum)) {
      throw SyncApiException(
        'field_invalid',
        'The $key field is missing or invalid.',
      );
    }
    return value;
  }

  static Set<SyncEntityType> _entityTypes(Object? value) {
    if (value is! List || value.length > SyncEntityType.values.length) {
      throw const SyncApiException(
        'entity_types_invalid',
        'The supported entity type list is invalid.',
      );
    }
    return value.map((item) {
      if (item is! String) {
        throw const SyncApiException(
          'unknown_entity_type',
          'An entity type is not supported.',
        );
      }
      return SyncEntityType.values.firstWhere(
        (type) => type.name == item,
        orElse: () => throw const SyncApiException(
          'unknown_entity_type',
          'An entity type is not supported.',
        ),
      );
    }).toSet();
  }

  static SyncMutation _mutation(Object? value, String deviceId) {
    if (value is! Map<String, dynamic>) {
      throw const SyncApiException(
        'mutation_invalid',
        'Every mutation must be a JSON object.',
      );
    }
    final map = value.cast<String, Object?>();
    final entityName = _string(map, 'entityType', 32);
    final operationName = _string(map, 'operation', 32);
    final fields = map['fields'];
    final timestamp = DateTime.tryParse(_string(map, 'clientTimestamp', 64));
    if (fields is! Map<String, dynamic> || timestamp == null) {
      throw const SyncApiException(
        'mutation_invalid',
        'The mutation fields or timestamp are invalid.',
      );
    }
    final entityType = SyncEntityType.values.firstWhere(
      (type) => type.name == entityName,
      orElse: () => throw const SyncApiException(
        'unknown_entity_type',
        'The entity type is not supported.',
      ),
    );
    final operation = SyncOperation.values.firstWhere(
      (item) => item.name == operationName,
      orElse: () => throw const SyncApiException(
        'operation_invalid',
        'The mutation operation is not supported.',
      ),
    );
    final origin = _id(map, 'originatingDeviceId');
    if (origin != deviceId) {
      throw const SyncApiException(
        'device_identity_mismatch',
        'The mutation device identity is invalid.',
        statusCode: 403,
      );
    }
    return SyncMutation(
      clientMutationId: _id(map, 'clientMutationId'),
      entityType: entityType,
      entityId: _id(map, 'entityId'),
      baseRevision: _integer(map, 'baseRevision', minimum: 0),
      operation: operation,
      fields: fields.cast<String, Object?>(),
      clientTimestamp: timestamp.toUtc(),
      originatingDeviceId: origin,
    );
  }

  static bool _validId(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

  static Future<void> _json(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }

  static Future<void> _error(
    HttpResponse response,
    SyncApiException error,
  ) async {
    try {
      await _json(response, error.statusCode, error.toJson());
    } on StateError {
      await response.close();
    }
  }
}

final class _SocketClient {
  _SocketClient(this.socket, this.identity, this.clock) {
    socket.listen(
      (message) {
        if (message is String && utf8.encode(message).length > 64 * 1024) {
          unawaited(close(WebSocketStatus.messageTooBig, 'message too large'));
        }
      },
      onError: (_) {},
      onDone: () {
        if (!_done.isCompleted) _done.complete();
      },
      cancelOnError: true,
    );
    _expiry = Timer(
      identity.expiresAt.difference(clock.now()),
      () => close(WebSocketStatus.policyViolation, 'credential expired'),
    );
  }

  final WebSocket socket;
  final AuthenticatedDevice identity;
  final Clock clock;
  final _done = Completer<void>();
  Timer? _expiry;
  int _queued = 0;

  Future<void> get done => _done.future;

  void send(SyncEvent event) {
    if (_queued >= 64) {
      unawaited(close(WebSocketStatus.policyViolation, 'event queue exceeded'));
      return;
    }
    _queued++;
    try {
      socket.add(jsonEncode(event.toJson()));
    } finally {
      scheduleMicrotask(() => _queued--);
    }
  }

  Future<void> close(int code, String reason) async {
    _expiry?.cancel();
    await socket.close(code, reason);
    if (!_done.isCompleted) _done.complete();
  }
}
