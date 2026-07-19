import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/features/sync/data/drift_sync_coordinator.dart';
import 'package:ephtodo/features/sync/domain/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftSyncWriteCoordinator coordinator;
  late FixedClock clock;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 7, 19, 14));
    coordinator = DriftSyncWriteCoordinator(database, clock);
  });

  tearDown(() async {
    await coordinator.dispose();
    await database.close();
  });

  test('push is idempotent and pull paginates ChangeLog', () async {
    final mutation = _taskMutation('mutation-one', 'task-one', 0);
    final first = await coordinator.push(
      deviceId: 'device-one',
      mutations: [mutation],
    );
    final replay = await coordinator.push(
      deviceId: 'device-one',
      mutations: [mutation],
    );

    expect(first.single.outcome, 'applied');
    expect(replay.single.revision, first.single.revision);
    expect(await database.select(database.tasks).get(), hasLength(1));
    expect(
      await database.select(database.syncMutationReceipts).get(),
      hasLength(1),
    );

    final page = await coordinator.pull(
      deviceId: 'device-one',
      afterSequence: 0,
      pageSize: 1,
      entityTypes: const {SyncEntityType.task},
    );
    expect(page.changes, hasLength(1));
    expect(page.changes.single.payload['title'], 'Fictional synchronized task');
    expect(page.nextCursor, greaterThan(0));
  });

  test(
    'stale update creates conflict and does not overwrite local task',
    () async {
      await coordinator.push(
        deviceId: 'device-one',
        mutations: [_taskMutation('mutation-one', 'task-one', 0)],
      );
      final applied = await coordinator.push(
        deviceId: 'device-one',
        mutations: [
          SyncMutation(
            clientMutationId: 'mutation-two',
            entityType: SyncEntityType.task,
            entityId: 'task-one',
            baseRevision: 1,
            operation: SyncOperation.update,
            fields: const {'title': 'Authoritative local title'},
            clientTimestamp: clock.now(),
            originatingDeviceId: 'device-one',
          ),
        ],
      );
      expect(applied.single.revision, 2);

      final stale = await coordinator.push(
        deviceId: 'device-two',
        mutations: [
          SyncMutation(
            clientMutationId: 'mutation-three',
            entityType: SyncEntityType.task,
            entityId: 'task-one',
            baseRevision: 1,
            operation: SyncOperation.update,
            fields: const {'title': 'Stale remote title'},
            clientTimestamp: clock.now(),
            originatingDeviceId: 'device-two',
          ),
        ],
      );

      expect(stale.single.outcome, 'conflict');
      expect(stale.single.conflictId, isNotNull);
      final task = await (database.select(
        database.tasks,
      )..where((row) => row.id.equals('task-one'))).getSingle();
      expect(task.title, 'Authoritative local title');
      expect(await coordinator.unresolvedConflicts(), hasLength(1));
    },
  );

  test(
    'deletion writes tombstone and stale client cannot resurrect it',
    () async {
      await coordinator.push(
        deviceId: 'device-one',
        mutations: [_taskMutation('mutation-one', 'task-one', 0)],
      );
      final deleted = await coordinator.push(
        deviceId: 'device-one',
        mutations: [
          SyncMutation(
            clientMutationId: 'mutation-two',
            entityType: SyncEntityType.task,
            entityId: 'task-one',
            baseRevision: 1,
            operation: SyncOperation.delete,
            fields: const {},
            clientTimestamp: clock.now(),
            originatingDeviceId: 'device-one',
          ),
        ],
      );
      expect(deleted.single.revision, 2);
      final row = await (database.select(
        database.tasks,
      )..where((item) => item.id.equals('task-one'))).getSingle();
      expect(row.deletedAt, isNotNull);

      final staleRestore = await coordinator.push(
        deviceId: 'device-two',
        mutations: [
          SyncMutation(
            clientMutationId: 'mutation-three',
            entityType: SyncEntityType.task,
            entityId: 'task-one',
            baseRevision: 1,
            operation: SyncOperation.restore,
            fields: const {},
            clientTimestamp: clock.now(),
            originatingDeviceId: 'device-two',
          ),
        ],
      );
      expect(staleRestore.single.outcome, 'conflict');
      expect(
        (await (database.select(
          database.tasks,
        )..where((item) => item.id.equals('task-one'))).getSingle()).deletedAt,
        isNotNull,
      );
    },
  );

  test(
    'note conflict preserves metadata and unsafe paths are rejected',
    () async {
      final root = await Directory.systemTemp.createTemp('ephtodo-sync-note-');
      addTearDown(() => root.delete(recursive: true));
      final notePath = '${root.path}${Platform.pathSeparator}local.md';
      await File(notePath).writeAsString('Local note body');
      await database
          .into(database.notes)
          .insert(
            NotesCompanion.insert(
              id: 'note-one',
              title: 'Local note',
              relativeFilePath: 'notes/local.md',
              contentHash: const Value('local-hash'),
              createdAt: clock.now(),
              updatedAt: clock.now(),
              revision: const Value(2),
            ),
          );

      final conflict = await coordinator.push(
        deviceId: 'device-two',
        mutations: [
          SyncMutation(
            clientMutationId: 'mutation-note',
            entityType: SyncEntityType.note,
            entityId: 'note-one',
            baseRevision: 1,
            operation: SyncOperation.update,
            fields: const {
              'title': 'Remote title',
              'body': 'Remote body must not overwrite local content',
            },
            clientTimestamp: clock.now(),
            originatingDeviceId: 'device-two',
          ),
        ],
      );
      expect(conflict.single.outcome, 'conflict');
      expect(await File(notePath).readAsString(), 'Local note body');
      final note = await (database.select(
        database.notes,
      )..where((row) => row.id.equals('note-one'))).getSingle();
      expect(note.title, 'Local note');
      expect(note.contentHash, 'local-hash');

      await expectLater(
        coordinator.push(
          deviceId: 'device-two',
          mutations: [
            SyncMutation(
              clientMutationId: 'mutation-path',
              entityType: SyncEntityType.note,
              entityId: 'note-one',
              baseRevision: 2,
              operation: SyncOperation.update,
              fields: const {'relativeFilePath': r'..\outside.md'},
              clientTimestamp: clock.now(),
              originatingDeviceId: 'device-two',
            ),
          ],
        ),
        throwsA(
          isA<SyncApiException>().having(
            (error) => error.code,
            'code',
            'field_not_writable',
          ),
        ),
      );
    },
  );
}

SyncMutation _taskMutation(
  String mutationId,
  String taskId,
  int baseRevision,
) => SyncMutation(
  clientMutationId: mutationId,
  entityType: SyncEntityType.task,
  entityId: taskId,
  baseRevision: baseRevision,
  operation: SyncOperation.create,
  fields: const {'title': 'Fictional synchronized task'},
  clientTimestamp: DateTime.utc(2026, 7, 19, 14),
  originatingDeviceId: 'device-one',
);
