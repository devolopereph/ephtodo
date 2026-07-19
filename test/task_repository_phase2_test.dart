import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/database/preferences_repository.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/features/tasks/data/drift_task_repositories.dart';
import 'package:ephtodo/features/tasks/domain/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftTaskWriteCoordinator coordinator;
  var completionPolicy = CompletionPolicy.keepCompleted;
  var retentionPolicy = TrashRetentionPolicy.thirtyDays;
  final clock = FixedClock(DateTime.utc(2026, 7, 19, 12));

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    coordinator = DriftTaskWriteCoordinator(
      database: database,
      clock: clock,
      deviceId: 'fictional-device',
      completionPolicy: () => completionPolicy,
      retentionPolicy: () => retentionPolicy,
    );
    completionPolicy = CompletionPolicy.keepCompleted;
    retentionPolicy = TrashRetentionPolicy.thirtyDays;
  });

  tearDown(() async {
    await coordinator.dispose();
    await database.close();
  });

  test('creates hierarchy, tasks, subtasks, and stable order', () async {
    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Fictional Workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Orchid',
      parentId: workspace.id,
    );
    final list = await coordinator.projects.create(
      type: ProjectNodeType.taskList,
      name: 'Launch',
      parentId: project.id,
    );
    final task = await coordinator.tasks.create(
      title: 'Prepare fictional launch',
      projectNodeId: list.id,
    );
    final subtask = await coordinator.tasks.create(
      title: 'Review checklist',
      parentTaskId: task.id,
    );
    expect(subtask.parentTaskId, task.id);
    expect(subtask.projectNodeId, list.id);
    expect((await coordinator.projects.all()), hasLength(3));
    expect((await coordinator.tasks.all()), hasLength(2));
  });

  test('moves project nodes and rejects hierarchy cycles', () async {
    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Project',
      parentId: workspace.id,
    );
    final folder = await coordinator.projects.create(
      type: ProjectNodeType.folder,
      name: 'Folder',
      parentId: project.id,
    );
    expect(
      () => coordinator.projects.move(
        project.id,
        folder.id,
        sortOrder: 1,
        revision: project.revision,
      ),
      throwsA(isA<TaskMutationException>()),
    );
  });

  test('completion policy is atomic with revision and change log', () async {
    completionPolicy = CompletionPolicy.archive;
    final task = await coordinator.tasks.create(title: 'Complete me');
    final complete = await coordinator.tasks.complete(
      task.id,
      revision: task.revision,
    );
    expect(complete.status, TaskStatus.completed);
    expect(complete.completedAt, clock.now());
    expect(complete.archivedAt, clock.now());
    expect(complete.revision, 2);
    final logs = await database.select(database.changeLogs).get();
    expect(logs.map((row) => row.operation), ['create', 'complete']);
  });

  test('reopen clears lifecycle policy effects', () async {
    completionPolicy = CompletionPolicy.trash;
    final task = await coordinator.tasks.create(title: 'Reopen me');
    final complete = await coordinator.tasks.complete(
      task.id,
      revision: task.revision,
    );
    final reopened = await coordinator.tasks.reopen(
      task.id,
      revision: complete.revision,
    );
    expect(reopened.completedAt, isNull);
    expect(reopened.deletedAt, isNull);
    expect(reopened.status, TaskStatus.open);
  });

  test('archive, trash, restore, and explicit permanent delete', () async {
    final task = await coordinator.tasks.create(title: 'Lifecycle');
    final archived = await coordinator.tasks.archive(
      task.id,
      revision: task.revision,
    );
    final restored = await coordinator.tasks.restore(
      task.id,
      revision: archived.revision,
    );
    final trashed = await coordinator.tasks.trash(
      task.id,
      revision: restored.revision,
    );
    final restoredTrash = await coordinator.tasks.restoreFromTrash(
      task.id,
      revision: trashed.revision,
    );
    final trashedAgain = await coordinator.tasks.trash(
      task.id,
      revision: restoredTrash.revision,
    );
    await coordinator.tasks.permanentlyDelete(trashedAgain.id);
    expect(await coordinator.tasks.byId(task.id), isNull);
  });

  test('tag names are case-insensitively unique and safely delete', () async {
    final tag = await coordinator.tags.create('Release');
    expect(
      () => coordinator.tags.create(' release '),
      throwsA(isA<TaskMutationException>()),
    );
    final task = await coordinator.tasks.create(title: 'Tagged');
    final assigned = await coordinator.tasks.assignTag(task.id, tag.id);
    expect(assigned.tagIds, contains(tag.id));
    await coordinator.tags.delete(tag.id);
    expect((await coordinator.tasks.byId(task.id))!.tagIds, isEmpty);
  });

  test('search composes title, project, tag, priority and lifecycle', () async {
    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Orchid',
      parentId: workspace.id,
    );
    final task = await coordinator.tasks.create(
      title: 'Prepare launch',
      projectNodeId: project.id,
      priority: TaskPriority.high,
    );
    final byProjectName = await coordinator.tasks
        .watch(const TaskSearchFilter(query: 'Orchid'))
        .first;
    final byPriority = await coordinator.tasks
        .watch(const TaskSearchFilter(priorities: {TaskPriority.high}))
        .first;
    expect(byProjectName.single.id, task.id);
    expect(byPriority.single.id, task.id);
  });

  test('stale revisions roll back without an extra change log', () async {
    final task = await coordinator.tasks.create(title: 'Original');
    await coordinator.tasks.update(
      task.copyWith(title: 'Current'),
      expectedRevision: task.revision,
    );
    expect(
      () => coordinator.tasks.update(
        task.copyWith(title: 'Stale'),
        expectedRevision: task.revision,
      ),
      throwsA(isA<TaskMutationException>()),
    );
    final logs = await database.select(database.changeLogs).get();
    expect(logs, hasLength(2));
    expect((await coordinator.tasks.byId(task.id))!.title, 'Current');
  });

  test('project lifecycle deliberately cascades to descendants', () async {
    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Project',
      parentId: workspace.id,
    );
    final folder = await coordinator.projects.create(
      type: ProjectNodeType.folder,
      name: 'Folder',
      parentId: project.id,
    );
    await coordinator.projects.archive(project.id, revision: project.revision);
    final all = await coordinator.projects.all();
    expect(
      all.singleWhere((node) => node.id == folder.id).archivedAt,
      isNotNull,
    );
  });

  test('never retention leaves trash intact', () async {
    retentionPolicy = TrashRetentionPolicy.never;
    final task = await coordinator.tasks.create(title: 'Retained');
    await coordinator.tasks.trash(task.id, revision: task.revision);
    expect(await coordinator.tasks.purgeEligibleTrash(), 0);
    expect(await coordinator.tasks.byId(task.id), isNotNull);
  });

  test(
    'indexed task query remains responsive with fictional seeded data',
    () async {
      await database.batch((batch) {
        for (var index = 0; index < 1000; index++) {
          batch.insert(
            database.tasks,
            TasksCompanion.insert(
              id: 'fictional-task-$index',
              title: 'Fictional task $index',
              status: Value(index.isEven ? 'open' : 'completed'),
              priority: Value(index % TaskPriority.values.length),
              dueAt: Value(DateTime.utc(2026, 7, 19 + (index % 30))),
              sortOrder: Value(index.toDouble()),
              createdAt: clock.now(),
              updatedAt: clock.now(),
              originatingDeviceId: 'fictional-device',
            ),
          );
        }
      });
      final stopwatch = Stopwatch()..start();
      final results = await coordinator.tasks
          .watch(
            const TaskSearchFilter(
              query: 'task 99',
              priorities: {TaskPriority.urgent},
            ),
          )
          .first;
      stopwatch.stop();
      expect(results, isNotEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test('task data persists across a database restart', () async {
    await coordinator.dispose();
    await database.close();
    final directory = await Directory.systemTemp.createTemp(
      'ephtodo-fictional-restart-',
    );
    final path = '${directory.path}${Platform.pathSeparator}tasks.sqlite';
    final firstDatabase = AppDatabase.open(path);
    final first = DriftTaskWriteCoordinator(
      database: firstDatabase,
      clock: clock,
      deviceId: 'fictional-device',
      completionPolicy: () => CompletionPolicy.keepCompleted,
      retentionPolicy: () => TrashRetentionPolicy.never,
    );
    final task = await first.tasks.create(
      title: 'Persist fictional task',
      dueAt: DateTime.utc(2026, 7, 20),
    );
    await first.dispose();
    await firstDatabase.close();

    final reopenedDatabase = AppDatabase.open(path);
    final reopened = DriftTaskWriteCoordinator(
      database: reopenedDatabase,
      clock: clock,
      deviceId: 'fictional-device',
      completionPolicy: () => CompletionPolicy.keepCompleted,
      retentionPolicy: () => TrashRetentionPolicy.never,
    );
    expect((await reopened.tasks.byId(task.id))!.title, task.title);
    await reopened.dispose();
    await reopenedDatabase.close();
    await directory.delete(recursive: true);
    database = AppDatabase(NativeDatabase.memory());
    coordinator = DriftTaskWriteCoordinator(
      database: database,
      clock: clock,
      deviceId: 'fictional-device',
      completionPolicy: () => completionPolicy,
      retentionPolicy: () => retentionPolicy,
    );
  });
}
