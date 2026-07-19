import 'dart:async';

import 'package:ephtodo/core/database/preferences_repository.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/features/tasks/domain/task_models.dart';
import 'package:ephtodo/features/tasks/domain/task_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 12, 28, 12);
  const horizons = HorizonEngine();

  group('horizon engine', () {
    test('classifies overdue, today, tomorrow and someday', () {
      expect(
        horizons.classify(_task(due: DateTime(2026, 12, 27)), now),
        TaskHorizon.overdue,
      );
      expect(
        horizons.classify(_task(due: DateTime(2026, 12, 28)), now),
        TaskHorizon.today,
      );
      expect(
        horizons.classify(_task(due: DateTime(2026, 12, 29)), now),
        TaskHorizon.tomorrow,
      );
      expect(horizons.classify(_task(), now), TaskHorizon.someday);
    });

    test('uses due date before start date when both exist', () {
      expect(
        horizons.classify(
          _task(start: DateTime(2026, 12, 28), due: DateTime(2027, 1, 1)),
          now,
        ),
        TaskHorizon.thisWeek,
      );
    });

    test('uses start date when due date is absent', () {
      expect(
        horizons.classify(_task(start: DateTime(2026, 12, 29)), now),
        TaskHorizon.tomorrow,
      );
    });

    test('handles Monday week and year boundary', () {
      expect(horizons.startOfWeek(now), DateTime(2026, 12, 28));
      expect(
        horizons.classify(_task(due: DateTime(2027, 1, 3)), now),
        TaskHorizon.thisWeek,
      );
      expect(
        horizons.classify(_task(due: DateTime(2027, 1, 4)), now),
        TaskHorizon.nextWeek,
      );
    });

    test('supports configurable Sunday week start', () {
      const sunday = HorizonEngine(firstWeekday: DateTime.sunday);
      expect(
        sunday.startOfWeek(DateTime(2026, 12, 28)),
        DateTime(2026, 12, 27),
      );
    });

    test('handles leap day and month boundaries by calendar date', () {
      final leapNow = DateTime(2028, 2, 28, 23, 55);
      expect(
        horizons.classify(_task(due: DateTime(2028, 2, 29)), leapNow),
        TaskHorizon.tomorrow,
      );
      expect(
        horizons.classify(_task(due: DateTime(2028, 3, 1)), leapNow),
        TaskHorizon.thisWeek,
      );
    });

    test('lifecycle horizons override dates', () {
      expect(
        horizons.classify(_task(completed: true), now),
        TaskHorizon.completed,
      );
      expect(
        horizons.classify(_task(archived: true), now),
        TaskHorizon.archived,
      );
      expect(horizons.classify(_task(deleted: true), now), TaskHorizon.trash);
    });

    test('upcoming groups have stable semantics', () {
      expect(
        horizons.upcomingGroup(_task(due: DateTime(2026, 12, 29)), now),
        'tomorrow',
      );
      expect(
        horizons.upcomingGroup(_task(due: DateTime(2027, 1, 4)), now),
        'nextWeek',
      );
      expect(
        horizons.upcomingGroup(_task(due: DateTime(2027, 3, 1)), now),
        'future',
      );
    });
  });

  group('completion and retention', () {
    const rules = CompletionRules();

    test('all completion policies set consistent timestamps', () {
      final original = _task();
      final at = DateTime.utc(2026, 7, 19);
      final archived = rules.complete(original, CompletionPolicy.archive, at);
      final trashed = rules.complete(original, CompletionPolicy.trash, at);
      final kept = rules.complete(original, CompletionPolicy.keepCompleted, at);
      expect(archived.completedAt, at);
      expect(archived.archivedAt, at);
      expect(trashed.deletedAt, at);
      expect(kept.archivedAt, isNull);
      expect(kept.deletedAt, isNull);
    });

    test('reopen clears completion archive and trash markers', () {
      final completed = rules.complete(
        _task(),
        CompletionPolicy.archive,
        DateTime.utc(2026, 7, 19),
      );
      final reopened = rules.reopen(completed, DateTime.utc(2026, 7, 20));
      expect(reopened.status, TaskStatus.open);
      expect(reopened.completedAt, isNull);
      expect(reopened.archivedAt, isNull);
      expect(reopened.deletedAt, isNull);
      expect(reopened.revision, completed.revision + 1);
    });

    test('retention uses deletedAt and supports never', () {
      const retention = RetentionRules();
      final task = _task(deleted: true, deletedAt: DateTime.utc(2026, 6, 19));
      expect(
        retention.eligible(
          task,
          TrashRetentionPolicy.thirtyDays,
          DateTime.utc(2026, 7, 19),
        ),
        isTrue,
      );
      expect(
        retention.eligible(
          task,
          TrashRetentionPolicy.never,
          DateTime.utc(2027),
        ),
        isFalse,
      );
    });
  });

  group('hierarchy rules and ordering', () {
    const rules = HierarchyRules();

    test('type matrix permits only documented project nesting', () {
      expect(
        ProjectNode.canContain(
          ProjectNodeType.workspace,
          ProjectNodeType.project,
        ),
        isTrue,
      );
      expect(
        ProjectNode.canContain(
          ProjectNodeType.taskList,
          ProjectNodeType.folder,
        ),
        isFalse,
      );
    });

    test('rejects project descendant cycles and root moves', () {
      final workspace = _node('w', ProjectNodeType.workspace);
      final project = _node(
        'p',
        ProjectNodeType.project,
        parentId: workspace.id,
      );
      final folder = _node('f', ProjectNodeType.folder, parentId: project.id);
      expect(
        () => rules.validateProjectMove(
          node: project,
          newParent: folder,
          allNodes: [workspace, project, folder],
        ),
        throwsA(isA<TaskMutationException>()),
      );
      expect(
        () => rules.validateProjectMove(
          node: workspace,
          newParent: project,
          allNodes: [workspace, project],
        ),
        throwsA(isA<TaskMutationException>()),
      );
    });

    test('rejects subtask self and descendant cycles', () {
      final parent = _task(id: 'parent');
      final child = _task(id: 'child', parentId: parent.id);
      expect(
        () => rules.validateTaskMove(
          task: parent,
          newParent: child,
          allTasks: [parent, child],
        ),
        throwsA(isA<TaskMutationException>()),
      );
    });

    test('stable ordering creates deterministic gaps and midpoints', () {
      const ordering = StableOrdering();
      expect(ordering.after([]), 1024);
      expect(ordering.after([1024, 2048]), 3072);
      expect(ordering.between(1024, 2048), 1536);
    });

    test('tag names trim and task dates validate', () {
      expect(Tag.normalizeName('  release  '), 'release');
      expect(
        () => Task.validateDates(
          startAt: DateTime(2026, 8, 2),
          dueAt: DateTime(2026, 8, 1),
        ),
        throwsA(isA<TaskMutationException>()),
      );
    });
  });

  test('rollover schedules local midnight and detects resume date change', () {
    final clock = _MutableClock(DateTime(2026, 7, 19, 23, 30));
    Duration? scheduled;
    var invalidations = 0;
    final service = DateRolloverService(
      clock: clock,
      onRollover: () => invalidations++,
      timerFactory: (duration, callback) {
        scheduled = duration;
        return _FakeTimer(callback);
      },
    )..start();
    expect(scheduled, const Duration(minutes: 30));
    clock.value = DateTime(2026, 7, 20, 8);
    service.resume();
    expect(invalidations, 1);
    service.dispose();
  });
}

Task _task({
  String id = 'task',
  String? parentId,
  DateTime? start,
  DateTime? due,
  bool completed = false,
  bool archived = false,
  bool deleted = false,
  DateTime? deletedAt,
}) => Task(
  id: id,
  parentTaskId: parentId,
  title: 'Fictional task',
  status: completed ? TaskStatus.completed : TaskStatus.open,
  priority: TaskPriority.none,
  startAt: start,
  dueAt: due,
  sortOrder: 1024,
  isPinned: false,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  completedAt: completed ? DateTime.utc(2026) : null,
  archivedAt: archived ? DateTime.utc(2026) : null,
  deletedAt: deletedAt ?? (deleted ? DateTime.utc(2026) : null),
  revision: 1,
  originatingDeviceId: 'fictional-device',
);

ProjectNode _node(String id, ProjectNodeType type, {String? parentId}) =>
    ProjectNode(
      id: id,
      parentId: parentId,
      type: type,
      name: 'Fictional',
      sortOrder: 1024,
      isPinned: false,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      revision: 1,
    );

final class _MutableClock implements Clock {
  _MutableClock(this.value);
  DateTime value;
  @override
  DateTime now() => value;
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.callback);
  final void Function() callback;
  var _active = true;

  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
  @override
  void cancel() => _active = false;
}
