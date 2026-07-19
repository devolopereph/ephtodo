import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/foundation/foundation.dart';
import '../application/sync_coordinator.dart';
import '../domain/sync_models.dart';

final class DriftSyncWriteCoordinator implements SyncWriteCoordinator {
  DriftSyncWriteCoordinator(this._database, this._clock);

  final AppDatabase _database;
  final Clock _clock;
  final _events = StreamController<SyncEvent>.broadcast();

  static const _syncablePreferences = {
    'theme.id',
    'completion.policy',
    'trash.retention',
  };

  @override
  Stream<SyncEvent> get events => _events.stream;

  @override
  Future<List<SyncDevice>> devices() async {
    final rows = await _database.select(_database.devices).get();
    return rows.map(_deviceModel).toList();
  }

  @override
  Future<SyncDevice?> device(String id) async {
    final row = await (_database.select(
      _database.devices,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _deviceModel(row);
  }

  SyncDevice _deviceModel(Device row) => SyncDevice(
    id: row.id,
    name: row.name,
    publicMaterialFingerprint: row.fingerprint ?? '',
    pairedAt: row.pairedAt ?? _clock.now(),
    lastSeenAt: row.lastSeenAt,
    lastSynchronizedAt: row.lastSynchronizedAt,
    revokedAt: row.revokedAt,
    scopes: row.scopes
        .split(',')
        .map(
          (value) => SyncScope.values.firstWhere(
            (scope) => scope.wireName == value,
            orElse: () => SyncScope.read,
          ),
        )
        .toSet(),
  );

  @override
  Future<SyncDevice> approveDevice(PendingPairing request) async {
    final now = _clock.now();
    await _database.transaction(() async {
      await _database
          .into(_database.devices)
          .insertOnConflictUpdate(
            DevicesCompanion.insert(
              id: request.deviceId,
              name: request.deviceName,
              fingerprint: Value(request.publicMaterialFingerprint),
              scopes: const Value('sync.read,sync.write'),
              pairedAt: Value(now),
              lastSeenAt: Value(now),
              revokedAt: const Value(null),
            ),
          );
    });
    return (await device(request.deviceId))!;
  }

  @override
  Future<void> revokeDevice(String id) async {
    final changed =
        await (_database.update(_database.devices)
              ..where((table) => table.id.equals(id)))
            .write(DevicesCompanion(revokedAt: Value(_clock.now())));
    if (changed != 1) {
      throw const SyncApiException(
        'device_not_found',
        'The paired device was not found.',
        statusCode: 404,
      );
    }
    _events.add(
      SyncEvent(type: 'device_revoked', entityId: id, timestamp: _clock.now()),
    );
  }

  @override
  Future<void> touchDevice(String id, {bool synchronized = false}) async {
    final now = _clock.now();
    await (_database.update(
      _database.devices,
    )..where((table) => table.id.equals(id))).write(
      synchronized
          ? DevicesCompanion(
              lastSeenAt: Value(now),
              lastSynchronizedAt: Value(now),
            )
          : DevicesCompanion(lastSeenAt: Value(now)),
    );
  }

  @override
  Future<SyncPullPage> pull({
    required String deviceId,
    required int afterSequence,
    required int pageSize,
    required Set<SyncEntityType> entityTypes,
  }) async {
    if (afterSequence < 0 || pageSize < 1 || pageSize > 200) {
      throw const SyncApiException(
        'invalid_cursor',
        'The pull cursor or page size is invalid.',
      );
    }
    final types = entityTypes.isEmpty
        ? SyncEntityType.values.toSet()
        : entityTypes;
    final wireTypes = types.map((type) => type.name).toList();
    final placeholders = List.filled(wireTypes.length, '?').join(',');
    final rows = await _database
        .customSelect(
          'SELECT sequence, entity_type, entity_id, operation, revision, '
          'changed_at, device_id FROM change_logs '
          'WHERE sequence > ? AND entity_type IN ($placeholders) '
          'ORDER BY sequence ASC LIMIT ?',
          variables: [
            Variable<int>(afterSequence),
            ...wireTypes.map(Variable<String>.new),
            Variable<int>(pageSize + 1),
          ],
        )
        .get();
    final hasMore = rows.length > pageSize;
    final selected = rows.take(pageSize);
    final changes = <SyncChange>[];
    for (final row in selected) {
      final type = _parseEntityType(row.read<String>('entity_type'));
      if (type == null) continue;
      changes.add(
        SyncChange(
          sequence: row.read<int>('sequence'),
          entityType: type,
          entityId: row.read<String>('entity_id'),
          operation: row.read<String>('operation'),
          revision: row.read<int>('revision'),
          changedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('changed_at'),
          ),
          originatingDeviceId: row.read<String>('device_id'),
          payload: await _payload(type, row.read<String>('entity_id')),
        ),
      );
    }
    final next = changes.isEmpty ? afterSequence : changes.last.sequence;
    await touchDevice(deviceId, synchronized: true);
    return SyncPullPage(changes: changes, nextCursor: next, hasMore: hasMore);
  }

  @override
  Future<List<SyncMutationResult>> push({
    required String deviceId,
    required List<SyncMutation> mutations,
  }) async {
    if (mutations.isEmpty || mutations.length > 100) {
      throw const SyncApiException(
        'invalid_batch_size',
        'Push batches must contain between 1 and 100 mutations.',
      );
    }
    if (mutations.any((mutation) => mutation.originatingDeviceId != deviceId)) {
      throw const SyncApiException(
        'device_identity_mismatch',
        'A mutation has an invalid originating device.',
        statusCode: 403,
      );
    }
    final results = <SyncMutationResult>[];
    for (final mutation in mutations) {
      results.add(await _applyIdempotent(deviceId, mutation));
    }
    await touchDevice(deviceId, synchronized: true);
    return results;
  }

  Future<SyncMutationResult> _applyIdempotent(
    String deviceId,
    SyncMutation mutation,
  ) async {
    final existing =
        await (_database.select(_database.syncMutationReceipts)..where(
              (row) =>
                  row.deviceId.equals(deviceId) &
                  row.mutationId.equals(mutation.clientMutationId),
            ))
            .getSingleOrNull();
    if (existing != null) {
      return _resultFromJson(
        jsonDecode(existing.resultJson) as Map<String, dynamic>,
      );
    }
    late SyncMutationResult result;
    await _database.transaction(() async {
      result = await _apply(deviceId, mutation);
      await _database
          .into(_database.syncMutationReceipts)
          .insert(
            SyncMutationReceiptsCompanion.insert(
              deviceId: deviceId,
              mutationId: mutation.clientMutationId,
              resultJson: jsonEncode(result.toJson()),
              createdAt: _clock.now(),
            ),
          );
    });
    if (result.outcome == 'applied') {
      final cursor = await latestSequence();
      _events.add(
        SyncEvent(
          type: mutation.operation == SyncOperation.delete
              ? 'entity_deleted'
              : 'entity_changed',
          entityType: mutation.entityType,
          entityId: mutation.entityId,
          revision: result.revision,
          cursor: cursor,
          timestamp: _clock.now(),
        ),
      );
    }
    return result;
  }

  Future<SyncMutationResult> _apply(
    String deviceId,
    SyncMutation mutation,
  ) async {
    _validateMutation(mutation);
    final current = await _currentRevision(
      mutation.entityType,
      mutation.entityId,
    );
    if (mutation.operation == SyncOperation.create) {
      if (mutation.baseRevision != 0 || current != null) {
        return _conflict(mutation, current ?? 0, 'create_collision');
      }
      await _create(deviceId, mutation);
      await _log(mutation, deviceId, 1);
      return SyncMutationResult(
        clientMutationId: mutation.clientMutationId,
        entityId: mutation.entityId,
        revision: 1,
        outcome: 'applied',
      );
    }
    if (current == null) {
      return _conflict(mutation, 0, 'missing_entity');
    }
    if (current != mutation.baseRevision) {
      return _conflict(mutation, current, 'stale_revision');
    }
    final nextRevision = current + 1;
    await _update(deviceId, mutation, nextRevision);
    await _log(mutation, deviceId, nextRevision);
    return SyncMutationResult(
      clientMutationId: mutation.clientMutationId,
      entityId: mutation.entityId,
      revision: nextRevision,
      outcome: 'applied',
    );
  }

  Future<SyncMutationResult> _conflict(
    SyncMutation mutation,
    int localRevision,
    String conflictType,
  ) async {
    final id = const Uuid().v4();
    await _database
        .into(_database.conflictRecords)
        .insert(
          ConflictRecordsCompanion.insert(
            id: id,
            entityType: mutation.entityType.name,
            entityId: mutation.entityId,
            localRevision: localRevision,
            remoteRevision: mutation.baseRevision,
            conflictType: conflictType,
            createdAt: _clock.now(),
          ),
        );
    return SyncMutationResult(
      clientMutationId: mutation.clientMutationId,
      entityId: mutation.entityId,
      revision: localRevision,
      outcome: 'conflict',
      conflictId: id,
    );
  }

  Future<void> _create(String deviceId, SyncMutation mutation) async {
    final now = _clock.now().millisecondsSinceEpoch;
    final fields = mutation.fields;
    switch (mutation.entityType) {
      case SyncEntityType.task:
        await _database.customInsert(
          'INSERT INTO tasks '
          '(id,title,description,status,priority,sort_order,is_pinned,'
          'created_at,updated_at,revision,originating_device_id) '
          'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
          variables: [
            Variable<String>(mutation.entityId),
            Variable<String>(_requiredString(fields, 'title', 500)),
            Variable<String>(fields['description'] as String?),
            Variable<String>((fields['status'] as String?) ?? 'open'),
            Variable<int>((fields['priority'] as int?) ?? 0),
            Variable<double>((fields['sortOrder'] as num?)?.toDouble() ?? 0),
            Variable<bool>((fields['isPinned'] as bool?) ?? false),
            Variable<int>(now),
            Variable<int>(now),
            const Variable<int>(1),
            Variable<String>(deviceId),
          ],
        );
      case SyncEntityType.projectNode:
        await _database.customInsert(
          'INSERT INTO project_nodes '
          '(id,node_type,name,description,sort_order,is_pinned,created_at,'
          'updated_at,revision,originating_device_id) VALUES (?,?,?,?,?,?,?,?,?,?)',
          variables: [
            Variable<String>(mutation.entityId),
            Variable<String>(_requiredString(fields, 'nodeType', 32)),
            Variable<String>(_requiredString(fields, 'name', 200)),
            Variable<String>(fields['description'] as String?),
            Variable<double>((fields['sortOrder'] as num?)?.toDouble() ?? 0),
            Variable<bool>((fields['isPinned'] as bool?) ?? false),
            Variable<int>(now),
            Variable<int>(now),
            const Variable<int>(1),
            Variable<String>(deviceId),
          ],
        );
      case SyncEntityType.tag:
        await _database.customInsert(
          'INSERT INTO tags '
          '(id,name,color_token,created_at,updated_at,revision,'
          'originating_device_id) VALUES (?,?,?,?,?,?,?)',
          variables: [
            Variable<String>(mutation.entityId),
            Variable<String>(_requiredString(fields, 'name', 100)),
            Variable<String>(fields['colorToken'] as String?),
            Variable<int>(now),
            Variable<int>(now),
            const Variable<int>(1),
            Variable<String>(deviceId),
          ],
        );
      case SyncEntityType.taskTag:
        await _createTaskTag(deviceId, mutation, now);
      case SyncEntityType.preference:
        final key = _requiredString(fields, 'key', 100);
        if (!_syncablePreferences.contains(key)) {
          throw const SyncApiException(
            'preference_not_syncable',
            'The preference is not syncable.',
          );
        }
        await _database.customInsert(
          'INSERT INTO app_preferences '
          '(key,value,scope,updated_at,revision,originating_device_id) '
          "VALUES (?,?,'vault',?,1,?)",
          variables: [
            Variable<String>(key),
            Variable<String>(_requiredString(fields, 'value', 200)),
            Variable<int>(now),
            Variable<String>(deviceId),
          ],
        );
      case SyncEntityType.note:
      case SyncEntityType.audio:
        throw const SyncApiException(
          'content_create_deferred',
          'Creating file-backed entities through sync is not enabled yet.',
          statusCode: 409,
        );
    }
  }

  Future<void> _createTaskTag(
    String deviceId,
    SyncMutation mutation,
    int now,
  ) async {
    final taskId = _requiredString(mutation.fields, 'taskId', 64);
    final tagId = _requiredString(mutation.fields, 'tagId', 64);
    if (mutation.entityId != '$taskId:$tagId') {
      throw const SyncApiException(
        'entity_id_invalid',
        'The relation identifier is invalid.',
      );
    }
    await _database.customInsert(
      'INSERT INTO task_tags '
      '(task_id,tag_id,updated_at,revision,originating_device_id) '
      'VALUES (?,?,?,1,?)',
      variables: [
        Variable<String>(taskId),
        Variable<String>(tagId),
        Variable<int>(now),
        Variable<String>(deviceId),
      ],
    );
  }

  Future<void> _update(
    String deviceId,
    SyncMutation mutation,
    int revision,
  ) async {
    final now = _clock.now().millisecondsSinceEpoch;
    final delete = mutation.operation == SyncOperation.delete;
    final restore = mutation.operation == SyncOperation.restore;
    final definition = _definition(mutation.entityType);
    final assignments = <String>[];
    final variables = <Variable<Object>>[];
    if (delete || restore) {
      assignments.add('deleted_at = ?');
      variables.add(Variable<int>(delete ? now : null));
    } else {
      for (final entry in mutation.fields.entries) {
        final column = definition.mutableFields[entry.key];
        if (column == null) {
          throw const SyncApiException(
            'field_not_writable',
            'The mutation contains a server-owned or unknown field.',
          );
        }
        _validateField(entry.key, entry.value);
        assignments.add('$column = ?');
        variables.add(Variable<Object>(entry.value));
      }
    }
    assignments.addAll([
      'updated_at = ?',
      'revision = ?',
      'originating_device_id = ?',
    ]);
    variables.addAll([
      Variable<int>(now),
      Variable<int>(revision),
      Variable<String>(deviceId),
      Variable<String>(mutation.entityId),
    ]);
    final changed = await _database.customUpdate(
      'UPDATE ${definition.table} SET ${assignments.join(', ')} '
      'WHERE ${definition.idColumn} = ?',
      variables: variables,
      updates: definition.tableInfo == null ? {} : {definition.tableInfo!},
    );
    if (changed != 1) {
      throw const SyncApiException(
        'mutation_rejected',
        'The entity could not be updated.',
        statusCode: 409,
      );
    }
  }

  Future<int?> _currentRevision(SyncEntityType type, String entityId) async {
    final definition = _definition(type);
    if (type == SyncEntityType.taskTag) {
      final parts = entityId.split(':');
      if (parts.length != 2) return null;
      final row = await _database
          .customSelect(
            'SELECT revision FROM task_tags WHERE task_id = ? AND tag_id = ?',
            variables: [Variable<String>(parts[0]), Variable<String>(parts[1])],
          )
          .getSingleOrNull();
      return row?.read<int>('revision');
    }
    final row = await _database
        .customSelect(
          'SELECT revision FROM ${definition.table} '
          'WHERE ${definition.idColumn} = ?',
          variables: [Variable<String>(entityId)],
        )
        .getSingleOrNull();
    return row?.read<int>('revision');
  }

  Future<void> _log(SyncMutation mutation, String deviceId, int revision) {
    return _database
        .into(_database.changeLogs)
        .insert(
          ChangeLogsCompanion.insert(
            entityType: mutation.entityType.name,
            entityId: mutation.entityId,
            operation: mutation.operation.name,
            revision: revision,
            changedAt: _clock.now(),
            deviceId: deviceId,
          ),
        );
  }

  Future<Map<String, Object?>> _payload(
    SyncEntityType type,
    String entityId,
  ) async {
    final definition = _definition(type);
    QueryRow? row;
    if (type == SyncEntityType.taskTag) {
      final parts = entityId.split(':');
      if (parts.length != 2) return const {};
      row = await _database
          .customSelect(
            'SELECT * FROM task_tags WHERE task_id = ? AND tag_id = ?',
            variables: [Variable<String>(parts[0]), Variable<String>(parts[1])],
          )
          .getSingleOrNull();
    } else {
      row = await _database
          .customSelect(
            'SELECT * FROM ${definition.table} '
            'WHERE ${definition.idColumn} = ?',
            variables: [Variable<String>(entityId)],
          )
          .getSingleOrNull();
    }
    if (row == null) return const {'tombstone': true};
    final data = row.data;
    return {
      for (final entry in definition.publicFields.entries)
        if (data.containsKey(entry.value))
          entry.key: _wireValue(data[entry.value]),
    };
  }

  Object? _wireValue(Object? value) {
    if (value is int && value > 100000000000) {
      return DateTime.fromMillisecondsSinceEpoch(
        value,
      ).toUtc().toIso8601String();
    }
    return value;
  }

  void _validateMutation(SyncMutation mutation) {
    if (!_validId(mutation.entityId) ||
        !_validId(mutation.clientMutationId) ||
        mutation.baseRevision < 0 ||
        mutation.fields.length > 32) {
      throw const SyncApiException(
        'mutation_invalid',
        'The mutation identifier, revision, or field count is invalid.',
      );
    }
    if (mutation.clientTimestamp.isAfter(
      _clock.now().add(const Duration(hours: 24)),
    )) {
      throw const SyncApiException(
        'timestamp_invalid',
        'The client timestamp is outside the accepted range.',
      );
    }
  }

  void _validateField(String key, Object? value) {
    if (value is String && value.length > 20000) {
      throw SyncApiException('field_too_long', 'The $key field is too long.');
    }
    if (value is List || value is Map) {
      throw const SyncApiException(
        'field_type_invalid',
        'Nested mutation fields are not accepted.',
      );
    }
  }

  String _requiredString(Map<String, Object?> fields, String key, int max) {
    final value = fields[key];
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw SyncApiException(
        'field_invalid',
        'The $key field is missing or invalid.',
      );
    }
    return value.trim();
  }

  bool _validId(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

  _EntityDefinition _definition(SyncEntityType type) => switch (type) {
    SyncEntityType.projectNode => _EntityDefinition(
      'project_nodes',
      'id',
      _database.projectNodes,
      const {
        'parentId': 'parent_id',
        'name': 'name',
        'description': 'description',
        'icon': 'icon',
        'sortOrder': 'sort_order',
        'isPinned': 'is_pinned',
        'archivedAt': 'archived_at',
      },
      const {
        'id': 'id',
        'parentId': 'parent_id',
        'nodeType': 'node_type',
        'name': 'name',
        'description': 'description',
        'icon': 'icon',
        'sortOrder': 'sort_order',
        'isPinned': 'is_pinned',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'archivedAt': 'archived_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
    SyncEntityType.task => _EntityDefinition(
      'tasks',
      'id',
      _database.tasks,
      const {
        'parentTaskId': 'parent_task_id',
        'projectNodeId': 'project_node_id',
        'title': 'title',
        'description': 'description',
        'status': 'status',
        'priority': 'priority',
        'startAt': 'start_at',
        'dueAt': 'due_at',
        'reminderAt': 'reminder_at',
        'recurrenceRule': 'recurrence_rule',
        'sortOrder': 'sort_order',
        'isPinned': 'is_pinned',
        'completedAt': 'completed_at',
        'archivedAt': 'archived_at',
      },
      const {
        'id': 'id',
        'parentTaskId': 'parent_task_id',
        'projectNodeId': 'project_node_id',
        'title': 'title',
        'description': 'description',
        'status': 'status',
        'priority': 'priority',
        'startAt': 'start_at',
        'dueAt': 'due_at',
        'reminderAt': 'reminder_at',
        'recurrenceRule': 'recurrence_rule',
        'sortOrder': 'sort_order',
        'isPinned': 'is_pinned',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'completedAt': 'completed_at',
        'archivedAt': 'archived_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
    SyncEntityType.tag => _EntityDefinition(
      'tags',
      'id',
      _database.tags,
      const {'name': 'name', 'colorToken': 'color_token'},
      const {
        'id': 'id',
        'name': 'name',
        'colorToken': 'color_token',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
    SyncEntityType.taskTag => _EntityDefinition(
      'task_tags',
      'task_id',
      _database.taskTags,
      const {},
      const {
        'taskId': 'task_id',
        'tagId': 'tag_id',
        'updatedAt': 'updated_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
    SyncEntityType.note => _EntityDefinition(
      'notes',
      'id',
      _database.notes,
      const {
        'projectNodeId': 'project_node_id',
        'linkedTaskId': 'linked_task_id',
        'title': 'title',
        'archivedAt': 'archived_at',
      },
      const {
        'id': 'id',
        'projectNodeId': 'project_node_id',
        'linkedTaskId': 'linked_task_id',
        'title': 'title',
        'contentHash': 'content_hash',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'archivedAt': 'archived_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
    SyncEntityType.audio => _EntityDefinition(
      'audio_notes',
      'id',
      _database.audioNotes,
      const {
        'projectNodeId': 'project_node_id',
        'linkedTaskId': 'linked_task_id',
        'linkedNoteId': 'linked_note_id',
        'title': 'title',
      },
      const {
        'id': 'id',
        'projectNodeId': 'project_node_id',
        'linkedTaskId': 'linked_task_id',
        'linkedNoteId': 'linked_note_id',
        'title': 'title',
        'durationMs': 'duration_ms',
        'mimeType': 'mime_type',
        'fileSize': 'file_size',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
    SyncEntityType.preference => _EntityDefinition(
      'app_preferences',
      'key',
      _database.appPreferences,
      const {'value': 'value'},
      const {
        'key': 'key',
        'value': 'value',
        'scope': 'scope',
        'updatedAt': 'updated_at',
        'deletedAt': 'deleted_at',
        'revision': 'revision',
      },
    ),
  };

  SyncEntityType? _parseEntityType(String value) {
    for (final type in SyncEntityType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  SyncMutationResult _resultFromJson(Map<String, dynamic> value) =>
      SyncMutationResult(
        clientMutationId: value['clientMutationId']! as String,
        entityId: value['entityId']! as String,
        revision: value['revision']! as int,
        outcome: value['outcome']! as String,
        conflictId: value['conflictId'] as String?,
      );

  @override
  Future<int> latestSequence() async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(MAX(sequence), 0) AS latest FROM change_logs',
        )
        .getSingle();
    return row.read<int>('latest');
  }

  @override
  Future<List<Map<String, Object?>>> unresolvedConflicts() async {
    final rows = await (_database.select(
      _database.conflictRecords,
    )..where((row) => row.resolvedAt.isNull())).get();
    return rows
        .map(
          (row) => <String, Object?>{
            'id': row.id,
            'entityType': row.entityType,
            'entityId': row.entityId,
            'localRevision': row.localRevision,
            'remoteRevision': row.remoteRevision,
            'conflictType': row.conflictType,
            'createdAt': row.createdAt.toUtc().toIso8601String(),
          },
        )
        .toList();
  }

  @override
  Future<void> dispose() => _events.close();
}

final class _EntityDefinition {
  const _EntityDefinition(
    this.table,
    this.idColumn,
    this.tableInfo,
    this.mutableFields,
    this.publicFields,
  );

  final String table;
  final String idColumn;
  final TableInfo<Table, Object>? tableInfo;
  final Map<String, String> mutableFields;
  final Map<String, String> publicFields;
}
