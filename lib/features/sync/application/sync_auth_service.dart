import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/foundation/foundation.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/secret_store.dart';
import '../domain/sync_models.dart';
import 'rate_limiter.dart';
import 'sync_coordinator.dart';

final class SyncAuthService {
  SyncAuthService(
    this._secrets,
    this._hasher,
    this._clock,
    this._coordinator, [
    this._accessLifetime = const Duration(minutes: 15),
  ]);

  final SecretStore _secrets;
  final Argon2idPasswordHasher _hasher;
  final Clock _clock;
  final SyncWriteCoordinator _coordinator;
  final Duration _accessLifetime;
  final _pairingLimiter = AttemptLimiter(
    maxAttempts: 5,
    window: const Duration(minutes: 5),
    baseLockout: const Duration(seconds: 30),
  );
  final _loginLimiter = AttemptLimiter(
    maxAttempts: 5,
    window: const Duration(minutes: 5),
    baseLockout: const Duration(minutes: 1),
  );

  PairingSession? _pairing;
  bool _pairingConsumed = false;
  final Map<String, PendingPairing> _pending = {};
  final Map<String, AccessSession> _approved = {};
  final Map<String, _TokenRecord> _tokens = {};
  final List<SyncAuditEvent> _audit = [];

  PairingSession? get pairingSession {
    final current = _pairing;
    if (current != null && !_clock.now().isBefore(current.expiresAt)) {
      _pairing = null;
      _pairingConsumed = false;
      _pending.clear();
      return null;
    }
    return current;
  }

  List<PendingPairing> get pendingPairings =>
      List.unmodifiable(_pending.values);
  List<SyncAuditEvent> get auditEvents => List.unmodifiable(_audit.reversed);

  Future<bool> hasPassword() async =>
      await _secrets.read('passwordVerifier') != null;

  Future<void> setPassword(String password) async {
    final encoded = await _hasher.hash(password);
    await _secrets.write('passwordVerifier', encoded);
    clearSessions();
    _record('credentials_changed', 'ok');
  }

  Future<PairingSession> beginPairing(String serverFingerprint) async {
    if (!await hasPassword()) {
      throw const SyncApiException(
        'password_required',
        'Set a synchronization password before pairing.',
        statusCode: 409,
      );
    }
    final random = _secureRandom(6);
    final code = base64Url
        .encode(random)
        .replaceAll('=', '')
        .toUpperCase()
        .substring(0, 8);
    _pairing = PairingSession(
      code: code,
      expiresAt: _clock.now().add(const Duration(minutes: 5)),
      serverFingerprint: serverFingerprint,
    );
    _pairingConsumed = false;
    _pending.clear();
    _record('pairing_started', 'ok');
    return _pairing!;
  }

  Future<PendingPairing> submitPairing({
    required String sourceKey,
    required String code,
    required String deviceId,
    required String deviceName,
    required String publicMaterialFingerprint,
  }) async {
    _pairingLimiter.check(sourceKey);
    final session = pairingSession;
    if (session == null) {
      _pairingLimiter.failed(sourceKey);
      throw const SyncApiException(
        'pairing_expired',
        'The pairing session is no longer active.',
        statusCode: 401,
      );
    }
    if (_pairingConsumed ||
        !Argon2idPasswordHasher.constantTimeEquals(
          utf8.encode(code.toUpperCase()),
          utf8.encode(session.code),
        )) {
      _pairingLimiter.failed(sourceKey);
      throw const SyncApiException(
        'pairing_code_invalid',
        'The pairing request could not be verified.',
        statusCode: 401,
      );
    }
    _pairingConsumed = true;
    _pairingLimiter.succeeded(sourceKey);
    final request = PendingPairing(
      requestId: const Uuid().v4(),
      deviceId: deviceId,
      deviceName: deviceName,
      publicMaterialFingerprint: publicMaterialFingerprint,
      requestedAt: _clock.now(),
    );
    _pending[request.requestId] = request;
    _record('pairing_requested', 'pending', deviceId);
    return request;
  }

  Future<void> approve(String requestId) async {
    final request = _pending.remove(requestId);
    if (request == null) {
      throw const SyncApiException(
        'pairing_request_missing',
        'The pairing request is no longer available.',
        statusCode: 404,
      );
    }
    final device = await _coordinator.approveDevice(request);
    _approved[requestId] = _issue(device.id, const {
      SyncScope.read,
      SyncScope.write,
    });
    _pairing = null;
    _record('pairing_approved', 'ok', device.id);
  }

  void reject(String requestId) {
    final request = _pending.remove(requestId);
    if (request != null) {
      _record('pairing_rejected', 'ok', request.deviceId);
    }
  }

  AccessSession? takeApproved(String requestId) => _approved.remove(requestId);

  Future<AccessSession> login({
    required String sourceKey,
    required String deviceId,
    required String publicMaterialFingerprint,
    required String password,
  }) async {
    final key = '$sourceKey:$deviceId';
    _loginLimiter.check(key);
    final verifier = await _secrets.read('passwordVerifier');
    final device = await _coordinator.device(deviceId);
    final validPassword =
        verifier != null && await _hasher.verify(password, verifier);
    final validDevice =
        device != null &&
        !device.revoked &&
        Argon2idPasswordHasher.constantTimeEquals(
          utf8.encode(publicMaterialFingerprint),
          utf8.encode(device.publicMaterialFingerprint),
        );
    if (!validPassword || !validDevice) {
      _loginLimiter.failed(key);
      _record('login_failed', 'invalid_credentials', deviceId);
      throw const SyncApiException(
        'invalid_credentials',
        'The credentials could not be verified.',
        statusCode: 401,
      );
    }
    _loginLimiter.succeeded(key);
    await _coordinator.touchDevice(deviceId);
    _record('login_succeeded', 'ok', deviceId);
    return _issue(deviceId, device.scopes);
  }

  Future<AuthenticatedDevice> authenticate(
    String token, {
    SyncScope? requiredScope,
  }) async {
    final record = _tokens[_digest(token)];
    if (record == null || !_clock.now().isBefore(record.expiresAt)) {
      if (record != null) _tokens.remove(_digest(token));
      throw const SyncApiException(
        'token_invalid',
        'The access credential is invalid or expired.',
        statusCode: 401,
      );
    }
    final device = await _coordinator.device(record.deviceId);
    if (device == null || device.revoked) {
      revokeDeviceSessions(record.deviceId);
      throw const SyncApiException(
        'device_revoked',
        'The paired device is not active.',
        statusCode: 401,
      );
    }
    final authenticated = AuthenticatedDevice(
      deviceId: record.deviceId,
      expiresAt: record.expiresAt,
      scopes: record.scopes,
    );
    if (requiredScope != null) authenticated.require(requiredScope);
    return authenticated;
  }

  Future<void> revokeDevice(String deviceId) async {
    await _coordinator.revokeDevice(deviceId);
    revokeDeviceSessions(deviceId);
    _record('device_revoked', 'ok', deviceId);
  }

  void revokeDeviceSessions(String deviceId) {
    _tokens.removeWhere((_, record) => record.deviceId == deviceId);
    _approved.removeWhere((_, session) => session.deviceId == deviceId);
  }

  void clearSessions() {
    _pairing = null;
    _pairingConsumed = false;
    _pending.clear();
    _approved.clear();
    _tokens.clear();
    _pairingLimiter.clear();
    _loginLimiter.clear();
  }

  AccessSession _issue(String deviceId, Set<SyncScope> scopes) {
    final token = base64Url.encode(_secureRandom(32)).replaceAll('=', '');
    final expiresAt = _clock.now().add(_accessLifetime);
    _tokens[_digest(token)] = _TokenRecord(
      deviceId: deviceId,
      expiresAt: expiresAt,
      scopes: Set.unmodifiable(scopes),
    );
    return AccessSession(
      token: token,
      deviceId: deviceId,
      expiresAt: expiresAt,
      scopes: scopes,
    );
  }

  void _record(String type, String result, [String? deviceId]) {
    _audit.add(
      SyncAuditEvent(
        type: type,
        resultCode: result,
        at: _clock.now(),
        deviceIdSuffix: _suffix(deviceId),
      ),
    );
    if (_audit.length > 100) _audit.removeAt(0);
  }

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String? _suffix(String? value) =>
      value?.substring(max(0, value.length - 6));

  static List<int> _secureRandom(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256));
  }
}

final class _TokenRecord {
  const _TokenRecord({
    required this.deviceId,
    required this.expiresAt,
    required this.scopes,
  });

  final String deviceId;
  final DateTime expiresAt;
  final Set<SyncScope> scopes;
}
