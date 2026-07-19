import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/core/security/password_hasher.dart';
import 'package:ephtodo/core/security/secret_store.dart';
import 'package:ephtodo/core/security/tls_material.dart';
import 'package:ephtodo/features/sync/application/rate_limiter.dart';
import 'package:ephtodo/features/sync/application/sync_auth_service.dart';
import 'package:ephtodo/features/sync/data/drift_sync_coordinator.dart';
import 'package:ephtodo/features/sync/domain/sync_models.dart';
import 'package:ephtodo/features/sync/server/sync_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Argon2id password verifier', () {
    const hasher = Argon2idPasswordHasher(
      memoryKiB: 8192,
      iterations: 2,
      parallelism: 1,
    );

    test(
      'encodes bounded PHC parameters and verifies only the password',
      () async {
        final encoded = await hasher.hash('fictional-passphrase');

        expect(encoded, startsWith(r'$argon2id$v=19$m=8192,t=2,p=1$'));
        expect(await hasher.verify('fictional-passphrase', encoded), isTrue);
        expect(await hasher.verify('incorrect-password', encoded), isFalse);
        expect(
          await hasher.verify('fictional-passphrase', 'malformed'),
          isFalse,
        );
      },
    );

    test('constant-time comparison handles lengths and values', () {
      expect(Argon2idPasswordHasher.constantTimeEquals([1, 2], [1, 2]), isTrue);
      expect(
        Argon2idPasswordHasher.constantTimeEquals([1, 2], [1, 3]),
        isFalse,
      );
      expect(
        Argon2idPasswordHasher.constantTimeEquals([1, 2], [1, 2, 0]),
        isFalse,
      );
    });
  });

  group('pairing and access authorization', () {
    late AppDatabase database;
    late MutableClock clock;
    late MemorySecretStore secrets;
    late DriftSyncWriteCoordinator coordinator;
    late SyncAuthService auth;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      clock = MutableClock(DateTime.utc(2026, 7, 19, 12));
      secrets = MemorySecretStore();
      coordinator = DriftSyncWriteCoordinator(database, clock);
      auth = SyncAuthService(
        secrets,
        const Argon2idPasswordHasher(
          memoryKiB: 8192,
          iterations: 2,
          parallelism: 1,
        ),
        clock,
        coordinator,
        const Duration(minutes: 15),
      );
      await auth.setPassword('fictional-passphrase');
    });

    tearDown(() async {
      auth.clearSessions();
      await coordinator.dispose();
      await database.close();
    });

    test('pairing expires and one-time code cannot be reused', () async {
      final session = await auth.beginPairing('AA:BB');
      clock.value = clock.value.add(const Duration(minutes: 6));

      await expectLater(
        auth.submitPairing(
          sourceKey: 'loopback',
          code: session.code,
          deviceId: 'device-one',
          deviceName: 'Fictional phone',
          publicMaterialFingerprint: 'client-key-one',
        ),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.code,
            'code',
            'pairing_expired',
          ),
        ),
      );

      clock.value = DateTime.utc(2026, 7, 19, 13);
      final next = await auth.beginPairing('AA:BB');
      final pending = await auth.submitPairing(
        sourceKey: 'loopback',
        code: next.code,
        deviceId: 'device-one',
        deviceName: 'Fictional phone',
        publicMaterialFingerprint: 'client-key-one',
      );
      expect(auth.takeApproved(pending.requestId), isNull);
      await expectLater(
        auth.submitPairing(
          sourceKey: 'loopback',
          code: next.code,
          deviceId: 'device-two',
          deviceName: 'Second phone',
          publicMaterialFingerprint: 'client-key-two',
        ),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.code,
            'code',
            'pairing_code_invalid',
          ),
        ),
      );
    });

    test('approval issues scoped token and revocation rejects it', () async {
      final session = await auth.beginPairing('AA:BB');
      final pending = await auth.submitPairing(
        sourceKey: 'loopback',
        code: session.code,
        deviceId: 'device-one',
        deviceName: 'Fictional phone',
        publicMaterialFingerprint: 'client-key-one',
      );
      await auth.approve(pending.requestId);
      final access = auth.takeApproved(pending.requestId)!;

      final identity = await auth.authenticate(
        access.token,
        requiredScope: SyncScope.read,
      );
      expect(identity.deviceId, 'device-one');
      await expectLater(
        auth.authenticate(access.token, requiredScope: SyncScope.deviceAdmin),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.code,
            'code',
            'missing_scope',
          ),
        ),
      );

      await auth.revokeDevice('device-one');
      await expectLater(
        auth.authenticate(access.token),
        throwsA(isA<SyncApiException>()),
      );
    });

    test('token expiry and incorrect password fail closed', () async {
      await coordinator.approveDevice(
        PendingPairing(
          requestId: 'request-one',
          deviceId: 'device-one',
          deviceName: 'Fictional phone',
          publicMaterialFingerprint: 'client-key-one',
          requestedAt: clock.now(),
        ),
      );
      await expectLater(
        auth.login(
          sourceKey: 'loopback',
          deviceId: 'device-one',
          publicMaterialFingerprint: 'client-key-one',
          password: 'incorrect-password',
        ),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.code,
            'code',
            'invalid_credentials',
          ),
        ),
      );
      final access = await auth.login(
        sourceKey: 'loopback',
        deviceId: 'device-one',
        publicMaterialFingerprint: 'client-key-one',
        password: 'fictional-passphrase',
      );
      clock.value = clock.value.add(const Duration(minutes: 16));
      await expectLater(
        auth.authenticate(access.token),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.code,
            'code',
            'token_invalid',
          ),
        ),
      );
    });
  });

  test('attempt limiter applies temporary lockout', () {
    final limiter = AttemptLimiter(
      maxAttempts: 2,
      window: const Duration(minutes: 1),
      baseLockout: const Duration(seconds: 1),
    );
    limiter.failed('source');
    limiter.failed('source');
    expect(
      () => limiter.check('source'),
      throwsA(
        isA<SyncApiException>().having(
          (error) => error.code,
          'code',
          'temporarily_locked',
        ),
      ),
    );
  });

  test('structured logging redacts sync credentials and paths', () {
    final lines = <String>[];
    final logger = StructuredLogger(sink: lines.add);
    logger.log(
      LogLevel.warning,
      'sync_failure',
      fields: {
        'authorization': 'Bearer fictional',
        'path': r'C:\Users\Fictional\vault\note.md',
        'token': 'fictional-token',
      },
    );
    expect(lines.single, isNot(contains('fictional-token')));
    expect(lines.single, isNot(contains(r'C:\Users')));
    expect(lines.single, contains('<redacted>'));
  });

  test('server is disabled by default and starts no listener', () async {
    final database = AppDatabase(NativeDatabase.memory());
    const clock = SystemClock();
    final secrets = MemorySecretStore();
    final coordinator = DriftSyncWriteCoordinator(database, clock);
    final auth = SyncAuthService(
      secrets,
      const Argon2idPasswordHasher(
        memoryKiB: 8192,
        iterations: 2,
        parallelism: 1,
      ),
      clock,
      coordinator,
    );
    final server = SyncServer(
      auth,
      coordinator,
      TlsMaterialManager(secrets, clock),
      clock,
    );

    expect(server.currentStatus.state, SyncServerState.disabled);

    await server.dispose();
    await coordinator.dispose();
    await database.close();
  });
}

final class MutableClock implements Clock {
  MutableClock(this.value);
  DateTime value;

  @override
  DateTime now() => value;
}
