enum SyncScope {
  read('sync.read'),
  write('sync.write'),
  deviceAdmin('device.admin'),
  pairingAdmin('pairing.admin');

  const SyncScope(this.wireName);
  final String wireName;
}

enum SyncEntityType { projectNode, task, tag, taskTag, note, audio, preference }

enum SyncOperation { create, update, delete, restore, relate, unrelate }

final class SyncApiException implements Exception {
  const SyncApiException(this.code, this.message, {this.statusCode = 400});

  final String code;
  final String message;
  final int statusCode;

  Map<String, Object?> toJson() => {
    'error': {'code': code, 'message': message},
  };
}

final class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.name,
    required this.publicMaterialFingerprint,
    required this.pairedAt,
    required this.scopes,
    this.lastSeenAt,
    this.lastSynchronizedAt,
    this.revokedAt,
  });

  final String id;
  final String name;
  final String publicMaterialFingerprint;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? lastSynchronizedAt;
  final DateTime? revokedAt;
  final Set<SyncScope> scopes;

  bool get revoked => revokedAt != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'publicMaterialFingerprint': publicMaterialFingerprint,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt?.toUtc().toIso8601String(),
    'lastSynchronizedAt': lastSynchronizedAt?.toUtc().toIso8601String(),
    'state': revoked ? 'revoked' : 'active',
    'scopes': scopes.map((scope) => scope.wireName).toList()..sort(),
  };
}

final class PairingSession {
  const PairingSession({
    required this.code,
    required this.expiresAt,
    required this.serverFingerprint,
  });

  final String code;
  final DateTime expiresAt;
  final String serverFingerprint;
}

final class PendingPairing {
  const PendingPairing({
    required this.requestId,
    required this.deviceId,
    required this.deviceName,
    required this.publicMaterialFingerprint,
    required this.requestedAt,
  });

  final String requestId;
  final String deviceId;
  final String deviceName;
  final String publicMaterialFingerprint;
  final DateTime requestedAt;
}

final class AccessSession {
  const AccessSession({
    required this.token,
    required this.deviceId,
    required this.expiresAt,
    required this.scopes,
  });

  final String token;
  final String deviceId;
  final DateTime expiresAt;
  final Set<SyncScope> scopes;

  Map<String, Object?> toJson() => {
    'accessToken': token,
    'tokenType': 'Bearer',
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'scopes': scopes.map((scope) => scope.wireName).toList()..sort(),
  };
}

final class AuthenticatedDevice {
  const AuthenticatedDevice({
    required this.deviceId,
    required this.expiresAt,
    required this.scopes,
  });

  final String deviceId;
  final DateTime expiresAt;
  final Set<SyncScope> scopes;

  void require(SyncScope scope) {
    if (!scopes.contains(scope)) {
      throw const SyncApiException(
        'missing_scope',
        'The credential does not grant this operation.',
        statusCode: 403,
      );
    }
  }
}

final class SyncMutation {
  const SyncMutation({
    required this.clientMutationId,
    required this.entityType,
    required this.entityId,
    required this.baseRevision,
    required this.operation,
    required this.fields,
    required this.clientTimestamp,
    required this.originatingDeviceId,
  });

  final String clientMutationId;
  final SyncEntityType entityType;
  final String entityId;
  final int baseRevision;
  final SyncOperation operation;
  final Map<String, Object?> fields;
  final DateTime clientTimestamp;
  final String originatingDeviceId;
}

final class SyncMutationResult {
  const SyncMutationResult({
    required this.clientMutationId,
    required this.entityId,
    required this.revision,
    required this.outcome,
    this.conflictId,
  });

  final String clientMutationId;
  final String entityId;
  final int revision;
  final String outcome;
  final String? conflictId;

  Map<String, Object?> toJson() => {
    'clientMutationId': clientMutationId,
    'entityId': entityId,
    'revision': revision,
    'outcome': outcome,
    if (conflictId != null) 'conflictId': conflictId,
  };
}

final class SyncChange {
  const SyncChange({
    required this.sequence,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.revision,
    required this.changedAt,
    required this.originatingDeviceId,
    required this.payload,
  });

  final int sequence;
  final SyncEntityType entityType;
  final String entityId;
  final String operation;
  final int revision;
  final DateTime changedAt;
  final String originatingDeviceId;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'entityType': entityType.name,
    'entityId': entityId,
    'operation': operation,
    'revision': revision,
    'changedAt': changedAt.toUtc().toIso8601String(),
    'originatingDeviceId': originatingDeviceId,
    'payload': payload,
  };
}

final class SyncPullPage {
  const SyncPullPage({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<SyncChange> changes;
  final int nextCursor;
  final bool hasMore;

  Map<String, Object?> toJson() => {
    'changes': changes.map((change) => change.toJson()).toList(),
    'nextCursor': nextCursor,
    'hasMore': hasMore,
  };
}

final class SyncEvent {
  const SyncEvent({
    required this.type,
    required this.timestamp,
    this.entityType,
    this.entityId,
    this.revision,
    this.cursor,
  });

  final String type;
  final DateTime timestamp;
  final SyncEntityType? entityType;
  final String? entityId;
  final int? revision;
  final int? cursor;

  Map<String, Object?> toJson() => {
    'type': type,
    'timestamp': timestamp.toUtc().toIso8601String(),
    if (entityType != null) 'entityType': entityType!.name,
    if (entityId != null) 'entityId': entityId,
    if (revision != null) 'revision': revision,
    if (cursor != null) 'cursor': cursor,
  };
}

final class SyncAuditEvent {
  const SyncAuditEvent({
    required this.type,
    required this.resultCode,
    required this.at,
    this.deviceIdSuffix,
  });

  final String type;
  final String resultCode;
  final DateTime at;
  final String? deviceIdSuffix;
}
