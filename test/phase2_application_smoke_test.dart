import 'dart:async';

import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/database/preferences_repository.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/features/tasks/data/drift_task_repositories.dart';
import 'package:ephtodo/features/tasks/domain/task_models.dart';
import 'package:ephtodo/features/tasks/domain/task_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('complete fictional Phase 2 application smoke', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final clock = _MutableClock(DateTime.utc(2026, 7, 20, 12));
    var completion = CompletionPolicy.keepCompleted;
    var retention = TrashRetentionPolicy.thirtyDays;
    final coordinator = DriftTaskWriteCoordinator(
      database: database,
      clock: clock,
      deviceId: 'fictional-smoke-device',
      completionPolicy: () => completion,
      retentionPolicy: () => retention,
    );

    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Fictional Workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Orchid',
      parentId: workspace.id,
    );
    final folder = await coordinator.projects.create(
      type: ProjectNodeType.folder,
      name: 'Release',
      parentId: project.id,
    );
    final list = await coordinator.projects.create(
      type: ProjectNodeType.taskList,
      name: 'Tasks',
      parentId: folder.id,
    );

    final today = await coordinator.tasks.create(
      title: 'Fictional Today',
      projectNodeId: list.id,
      dueAt: DateTime.utc(2026, 7, 20),
    );
    final tomorrow = await coordinator.tasks.create(
      title: 'Fictional Tomorrow',
      projectNodeId: list.id,
      dueAt: DateTime.utc(2026, 7, 21),
    );
    final thisWeek = await coordinator.tasks.create(
      title: 'Fictional Week',
      dueAt: DateTime.utc(2026, 7, 22),
    );
    final thisMonth = await coordinator.tasks.create(
      title: 'Fictional Month',
      dueAt: DateTime.utc(2026, 7, 30),
    );
    const horizon = HorizonEngine();
    expect(horizon.classify(today, clock.now()), TaskHorizon.today);
    expect(horizon.classify(tomorrow, clock.now()), TaskHorizon.tomorrow);
    expect(horizon.classify(thisWeek, clock.now()), TaskHorizon.thisWeek);
    expect(horizon.classify(thisMonth, clock.now()), TaskHorizon.nextWeek);
    expect(
      horizon.classify(
        thisMonth.copyWith(dueAt: DateTime.utc(2026, 7, 20)),
        DateTime.utc(2026, 7, 1),
      ),
      TaskHorizon.thisMonth,
    );

    completion = CompletionPolicy.keepCompleted;
    final kept = await coordinator.tasks.complete(
      today.id,
      revision: today.revision,
    );
    expect(kept.archivedAt, isNull);
    expect(kept.deletedAt, isNull);
    final reopened = await coordinator.tasks.reopen(
      kept.id,
      revision: kept.revision,
    );

    completion = CompletionPolicy.archive;
    final archivedByPolicy = await coordinator.tasks.complete(
      reopened.id,
      revision: reopened.revision,
    );
    expect(archivedByPolicy.archivedAt, isNotNull);
    final reopenedAgain = await coordinator.tasks.reopen(
      archivedByPolicy.id,
      revision: archivedByPolicy.revision,
    );

    completion = CompletionPolicy.trash;
    final trashedByPolicy = await coordinator.tasks.complete(
      reopenedAgain.id,
      revision: reopenedAgain.revision,
    );
    expect(trashedByPolicy.deletedAt, isNotNull);
    await coordinator.tasks.restoreFromTrash(
      trashedByPolicy.id,
      revision: trashedByPolicy.revision,
    );

    final archived = await coordinator.tasks.archive(
      tomorrow.id,
      revision: tomorrow.revision,
    );
    await coordinator.tasks.restore(archived.id, revision: archived.revision);
    final trashed = await coordinator.tasks.trash(
      thisWeek.id,
      revision: thisWeek.revision,
    );
    await coordinator.tasks.restoreFromTrash(
      trashed.id,
      revision: trashed.revision,
    );

    final tag = await coordinator.tags.create('Fictional');
    await coordinator.tasks.assignTag(thisMonth.id, tag.id);
    expect(
      await coordinator.tasks
          .watch(
            TaskSearchFilter(
              query: 'Month',
              tagId: tag.id,
              priorities: const {TaskPriority.none},
            ),
          )
          .first,
      hasLength(1),
    );

    var rolloverCount = 0;
    final rollover = DateRolloverService(
      clock: clock,
      onRollover: () => rolloverCount++,
      timerFactory: (_, callback) => _FakeTimer(callback),
    )..start();
    clock.value = DateTime.utc(2026, 7, 21, 8);
    rollover.resume();
    expect(rolloverCount, 1);
    rollover.dispose();

    final old = await coordinator.tasks.create(title: 'Old trash');
    final oldTrash = await coordinator.tasks.trash(
      old.id,
      revision: old.revision,
    );
    clock.value = DateTime.utc(2026, 8, 21, 12);
    retention = TrashRetentionPolicy.thirtyDays;
    expect(
      await coordinator.tasks.purgeEligibleTrash(),
      greaterThanOrEqualTo(1),
    );
    expect(await coordinator.tasks.byId(oldTrash.id), isNull);

    await coordinator.dispose();
    await database.close();
  });
}

final class _MutableClock implements Clock {
  _MutableClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function() callback;
  var active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
  @override
  void cancel() => active = false;
}
