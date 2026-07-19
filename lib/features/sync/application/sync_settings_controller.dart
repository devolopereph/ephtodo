import 'dart:async';
import 'dart:math';

import '../../../core/foundation/foundation.dart';
import '../../../core/security/secret_store.dart';
import '../../../core/security/tls_material.dart';
import '../domain/sync_models.dart';
import '../server/sync_server.dart';
import 'sync_auth_service.dart';
import 'sync_coordinator.dart';

final class SyncSettingsSnapshot {
  const SyncSettingsSnapshot({
    required this.persistentlyEnabled,
    required this.port,
    required this.server,
    required this.devices,
    required this.pending,
    required this.audit,
    this.pairing,
  });

  final bool persistentlyEnabled;
  final int port;
  final SyncServerStatus server;
  final List<SyncDevice> devices;
  final List<PendingPairing> pending;
  final List<SyncAuditEvent> audit;
  final PairingSession? pairing;
}

final class SyncSettingsController {
  SyncSettingsController(
    this._support,
    this._secrets,
    this._tls,
    this._auth,
    this._coordinator,
    this._server,
  );

  final AppSupportStore _support;
  final SecretStore _secrets;
  final TlsMaterialManager _tls;
  final SyncAuthService _auth;
  final SyncWriteCoordinator _coordinator;
  final SyncServer _server;
  final _snapshots = StreamController<SyncSettingsSnapshot>.broadcast();
  StreamSubscription<SyncServerStatus>? _serverSubscription;

  bool _persistentEnabled = false;
  int _port = 0;

  Stream<SyncSettingsSnapshot> get snapshots => _snapshots.stream;

  Future<void> initialize() async {
    final values = await _support.read();
    _persistentEnabled = values['sync.enabled'] == true;
    _port = (values['sync.port'] as num?)?.toInt() ?? _generatedPort();
    if (_port < 49152 || _port > 65535) _port = _generatedPort();
    _serverSubscription = _server.statuses.listen((_) => unawaited(refresh()));
    if (_persistentEnabled) {
      try {
        if (await _auth.hasPassword()) {
          await _server.start(port: _port);
        }
      } on Object {
        // Secure storage or TLS material can fail on some Windows setups
        // (PlatformException); the server stays off and settings still load.
      }
    }
    await _persist();
    await refresh();
  }

  Future<void> setPassword(String password) async {
    await _auth.setPassword(password);
    await refresh();
  }

  Future<void> setPort(int value) async {
    if (value < 49152 || value > 65535) {
      throw const SyncApiException(
        'port_invalid',
        'Choose a port between 49152 and 65535.',
      );
    }
    final running = _server.currentStatus.state == SyncServerState.running;
    if (running) await _server.stop();
    _port = value;
    await _persist();
    if (running) await _server.start(port: _port);
    await refresh();
  }

  Future<void> enable({required bool persist}) async {
    if (!await _auth.hasPassword()) {
      throw const SyncApiException(
        'password_required',
        'Set a synchronization password before enabling the server.',
        statusCode: 409,
      );
    }
    _persistentEnabled = persist;
    await _persist();
    await _server.start(port: _port);
    await refresh();
  }

  Future<void> disable() async {
    _persistentEnabled = false;
    await _persist();
    await _server.stop();
    await refresh();
  }

  Future<void> beginPairing() async {
    final fingerprint = _server.currentStatus.fingerprint;
    if (_server.currentStatus.state != SyncServerState.running ||
        fingerprint == null) {
      throw const SyncApiException(
        'server_not_running',
        'Enable the secure server before pairing a device.',
        statusCode: 409,
      );
    }
    await _auth.beginPairing(fingerprint);
    await refresh();
  }

  Future<void> approve(String requestId) async {
    await _auth.approve(requestId);
    await refresh();
  }

  Future<void> reject(String requestId) async {
    _auth.reject(requestId);
    await refresh();
  }

  Future<void> revoke(String deviceId) async {
    await _auth.revokeDevice(deviceId);
    await refresh();
  }

  Future<void> rotateCertificate() async {
    final running = _server.currentStatus.state == SyncServerState.running;
    if (running) await _server.stop();
    await _tls.rotate();
    _auth.clearSessions();
    if (running) await _server.start(port: _port);
    await refresh();
  }

  Future<void> resetCredentials() async {
    await _server.stop();
    for (final device in await _coordinator.devices()) {
      if (!device.revoked) await _coordinator.revokeDevice(device.id);
    }
    await _secrets.clearSyncSecrets();
    _auth.clearSessions();
    _persistentEnabled = false;
    await _persist();
    await refresh();
  }

  Future<void> refresh() async {
    if (_snapshots.isClosed) return;
    _snapshots.add(
      SyncSettingsSnapshot(
        persistentlyEnabled: _persistentEnabled,
        port: _port,
        server: _server.currentStatus,
        devices: await _coordinator.devices(),
        pending: _auth.pendingPairings,
        pairing: _auth.pairingSession,
        audit: _auth.auditEvents.take(20).toList(),
      ),
    );
  }

  Future<void> _persist() async {
    final current = await _support.read();
    await _support.write({
      ...current,
      'sync.enabled': _persistentEnabled,
      'sync.port': _port,
    });
  }

  static int _generatedPort() => 49152 + Random.secure().nextInt(16384);

  Future<void> dispose() async {
    await _serverSubscription?.cancel();
    await _server.dispose();
    await _coordinator.dispose();
    await _snapshots.close();
  }
}
