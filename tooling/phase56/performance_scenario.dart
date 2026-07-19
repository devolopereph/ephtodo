import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/database/preferences_repository.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/features/sync/data/drift_sync_coordinator.dart';
import 'package:ephtodo/features/sync/domain/sync_models.dart';
import 'package:ephtodo/features/tasks/data/drift_task_repositories.dart';
import 'package:ephtodo/features/tasks/domain/task_models.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  DatabaseOpenAudit.configure('main');
  final root = await Directory.systemTemp.createTemp(
    'ephtodo-fictional-performance-',
  );
  final databasePath = p.join(root.path, 'ephtodo.sqlite');
  final noteDirectory = await Directory(p.join(root.path, 'notes')).create();
  final now = DateTime.utc(2026, 7, 19, 12);
  final clock = FixedClock(now);
  var database = AppDatabase.open(databasePath);
  try {
    await _seed(database, noteDirectory, now);
    await database.close();

    final startup = Stopwatch()..start();
    database = AppDatabase.open(databasePath);
    await database.customSelect('SELECT 1').getSingle();
    startup.stop();

    final coordinator = DriftTaskWriteCoordinator(
      database: database,
      clock: clock,
      deviceId: 'fictional-desktop',
      completionPolicy: () => CompletionPolicy.keepCompleted,
      retentionPolicy: () => TrashRetentionPolicy.never,
    );
    final sync = DriftSyncWriteCoordinator(database, clock);

    final today = await _measure(() async {
      final rows = await coordinator.tasks
          .watch(const TaskSearchFilter(horizons: {TaskHorizon.today}))
          .first;
      if (rows.isEmpty) throw StateError('Today scenario returned no rows.');
    });
    final projectSwitch = await _measure(() async {
      final rows = await coordinator.tasks
          .watch(const TaskSearchFilter(projectNodeId: 'project-7'))
          .first;
      if (rows.length != 9090) {
        throw StateError('Project scenario returned ${rows.length} rows.');
      }
    });
    final search = await _measure(() async {
      final rows = await coordinator.tasks
          .watch(const TaskSearchFilter(query: 'needle-9998'))
          .first;
      if (rows.length != 1) {
        throw StateError('Search scenario returned ${rows.length} rows.');
      }
    });
    final stickyRefresh = await _measure(() async {
      final rows = await coordinator.tasks
          .watch(const TaskSearchFilter(horizons: {TaskHorizon.today}))
          .first;
      rows.take(50).toList(growable: false);
    });
    final noteOpen = await _measure(() async {
      final metadata = await (database.select(
        database.notes,
      )..where((row) => row.id.equals('note-999'))).getSingle();
      final body = await File(
        p.join(root.path, metadata.relativeFilePath),
      ).readAsString();
      if (!body.contains('Fictional note 999')) {
        throw StateError('Note body validation failed.');
      }
    });
    final syncPull = await _measure(() async {
      final page = await sync.pull(
        deviceId: 'fictional-mobile',
        afterSequence: 0,
        pageSize: 200,
        entityTypes: const {SyncEntityType.task},
      );
      if (page.changes.length != 200 || !page.hasMore) {
        throw StateError('Sync page validation failed.');
      }
    });

    final result = {
      'scenario': 'fictional-release-profile',
      'taskCount': 10000,
      'projectDepth': 8,
      'noteCount': 1000,
      'audioMetadataCount': 500,
      'changeLogCount': 20000,
      'startupMs': startup.elapsedMicroseconds / 1000,
      'todayLoadMs': today,
      'projectSwitchMs': projectSwitch,
      'searchMs': search,
      'stickyRefreshMs': stickyRefresh,
      'noteOpenMs': noteOpen,
      'syncPull200Ms': syncPull,
      'residentMemoryMiB': ProcessInfo.currentRss / (1024 * 1024),
      'environment': {
        'os': Platform.operatingSystemVersion,
        'dart': Platform.version.split(' ').first,
        'mode': 'Dart VM debug/JIT tooling scenario',
      },
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
    await coordinator.dispose();
    await sync.dispose();
  } finally {
    await database.close();
    if (await root.exists()) await root.delete(recursive: true);
  }
}

Future<double> _measure(Future<void> Function() action) async {
  final stopwatch = Stopwatch()..start();
  await action();
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds / 1000;
}

Future<void> _seed(
  AppDatabase database,
  Directory noteDirectory,
  DateTime now,
) async {
  await database.batch((batch) {
    batch.insertAll(database.projectNodes, [
      for (var index = 0; index < 8; index++)
        ProjectNodesCompanion.insert(
          id: 'project-$index',
          parentId: Value(index == 0 ? null : 'project-${index - 1}'),
          nodeType: index == 0
              ? 'workspace'
              : index == 1
              ? 'project'
              : index == 7
              ? 'taskList'
              : 'folder',
          name: 'Fictional level $index',
          sortOrder: Value(index.toDouble()),
          createdAt: now,
          updatedAt: now,
          originatingDeviceId: const Value('fictional-desktop'),
        ),
    ]);
  });

  for (var start = 0; start < 10000; start += 1000) {
    await database.batch((batch) {
      batch.insertAll(database.tasks, [
        for (var index = start; index < start + 1000; index++)
          TasksCompanion.insert(
            id: 'task-$index',
            projectNodeId: const Value('project-7'),
            title: index == 9998
                ? 'Fictional needle-9998'
                : 'Fictional task $index',
            description: Value('Synthetic release profile item $index'),
            status: Value(index % 11 == 0 ? 'completed' : 'open'),
            priority: Value(index % 5),
            dueAt: Value(
              index % 3 == 0 ? now : now.add(Duration(days: index % 45)),
            ),
            sortOrder: Value(index.toDouble()),
            isPinned: Value(index < 50),
            createdAt: now.subtract(Duration(days: index % 365)),
            updatedAt: now,
            completedAt: Value(index % 11 == 0 ? now : null),
            originatingDeviceId: 'fictional-desktop',
          ),
      ]);
    });
  }

  for (var start = 0; start < 1000; start += 100) {
    final notes = <NotesCompanion>[];
    for (var index = start; index < start + 100; index++) {
      final relative = 'notes/fictional-$index.md';
      await File(
        p.join(noteDirectory.parent.path, relative),
      ).writeAsString('# Fictional note $index\nSynthetic profile content.');
      notes.add(
        NotesCompanion.insert(
          id: 'note-$index',
          projectNodeId: const Value('project-7'),
          title: 'Fictional note $index',
          relativeFilePath: relative,
          createdAt: now,
          updatedAt: now,
          originatingDeviceId: const Value('fictional-desktop'),
        ),
      );
    }
    await database.batch((batch) => batch.insertAll(database.notes, notes));
  }

  await database.batch((batch) {
    batch.insertAll(database.audioNotes, [
      for (var index = 0; index < 500; index++)
        AudioNotesCompanion.insert(
          id: 'audio-$index',
          projectNodeId: const Value('project-7'),
          title: 'Fictional audio $index',
          relativeFilePath: 'audio/fictional-$index.wav',
          durationMs: Value(1000 + index),
          fileSize: Value(4096 + index),
          createdAt: now,
          updatedAt: now,
          originatingDeviceId: const Value('fictional-desktop'),
        ),
    ]);
  });

  for (var start = 0; start < 20000; start += 1000) {
    await database.batch((batch) {
      batch.insertAll(database.changeLogs, [
        for (var index = start; index < start + 1000; index++)
          ChangeLogsCompanion.insert(
            entityType: 'task',
            entityId: 'task-${index % 10000}',
            operation: index < 10000 ? 'create' : 'update',
            revision: index < 10000 ? 1 : 2,
            changedAt: now.add(Duration(milliseconds: index)),
            deviceId: 'fictional-desktop',
          ),
      ]);
    });
  }
}
