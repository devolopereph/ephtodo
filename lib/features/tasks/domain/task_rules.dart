import 'dart:async';

import '../../../core/database/preferences_repository.dart';
import '../../../core/foundation/foundation.dart';
import 'task_models.dart';

final class HierarchyRules {
  const HierarchyRules();

  void validateProjectMove({
    required ProjectNode node,
    required ProjectNode? newParent,
    required Iterable<ProjectNode> allNodes,
  }) {
    if (node.type == ProjectNodeType.workspace) {
      if (newParent != null) {
        throw const TaskMutationException(
          TaskMutationErrorCode.invalidHierarchy,
          'A root workspace cannot be moved below another node.',
        );
      }
      return;
    }
    if (newParent == null ||
        !ProjectNode.canContain(newParent.type, node.type)) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'This node type is not allowed at the requested location.',
      );
    }
    if (node.id == newParent.id) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'A node cannot contain itself.',
      );
    }
    final byId = {for (final candidate in allNodes) candidate.id: candidate};
    ProjectNode? cursor = newParent;
    var depth = 1;
    while (cursor != null) {
      final parentId = cursor.parentId;
      if (parentId == null) break;
      if (parentId == node.id) {
        throw const TaskMutationException(
          TaskMutationErrorCode.invalidHierarchy,
          'A node cannot move below its descendant.',
        );
      }
      cursor = byId[parentId];
      depth++;
    }
    final subtreeDepth = _projectSubtreeDepth(node.id, allNodes);
    if (depth + subtreeDepth > ProjectNode.maxDepth) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'The project hierarchy depth limit would be exceeded.',
      );
    }
  }

  void validateTaskMove({
    required Task task,
    required Task? newParent,
    required Iterable<Task> allTasks,
  }) {
    if (newParent == null) return;
    if (task.id == newParent.id) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'A task cannot be its own parent.',
      );
    }
    final byId = {for (final candidate in allTasks) candidate.id: candidate};
    Task? cursor = newParent;
    var depth = 1;
    while (cursor != null) {
      final parentId = cursor.parentTaskId;
      if (parentId == null) break;
      if (parentId == task.id) {
        throw const TaskMutationException(
          TaskMutationErrorCode.invalidHierarchy,
          'A task cannot move below its descendant.',
        );
      }
      cursor = byId[parentId];
      depth++;
    }
    final subtreeDepth = _taskSubtreeDepth(task.id, allTasks);
    if (depth + subtreeDepth > Task.maxDepth) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'The subtask depth limit would be exceeded.',
      );
    }
  }

  int _projectSubtreeDepth(String id, Iterable<ProjectNode> nodes) {
    final children = nodes.where((node) => node.parentId == id);
    if (children.isEmpty) return 1;
    return 1 +
        children
            .map((child) => _projectSubtreeDepth(child.id, nodes))
            .reduce((a, b) => a > b ? a : b);
  }

  int _taskSubtreeDepth(String id, Iterable<Task> tasks) {
    final children = tasks.where((task) => task.parentTaskId == id);
    if (children.isEmpty) return 1;
    return 1 +
        children
            .map((child) => _taskSubtreeDepth(child.id, tasks))
            .reduce((a, b) => a > b ? a : b);
  }
}

final class StableOrdering {
  const StableOrdering();

  double after(Iterable<double> orders) =>
      orders.isEmpty ? 1024 : orders.reduce((a, b) => a > b ? a : b) + 1024;

  double between(double? previous, double? next) {
    if (previous == null && next == null) return 1024;
    if (previous == null) return next! - 1024;
    if (next == null) return previous + 1024;
    return (previous + next) / 2;
  }
}

final class HorizonEngine {
  const HorizonEngine({this.firstWeekday = DateTime.monday});

  final int firstWeekday;

  TaskHorizon classify(Task task, DateTime localNow) {
    if (task.deletedAt != null) return TaskHorizon.trash;
    if (task.archivedAt != null) return TaskHorizon.archived;
    if (task.isCompleted) return TaskHorizon.completed;
    final date = task.dueAt ?? task.startAt;
    if (date == null) return TaskHorizon.someday;
    final today = _date(localNow);
    final target = _date(date.toLocal());
    if (target.isBefore(today)) return TaskHorizon.overdue;
    if (target == today) return TaskHorizon.today;
    final tomorrow = today.add(const Duration(days: 1));
    if (target == tomorrow) return TaskHorizon.tomorrow;
    final weekStart = startOfWeek(today);
    final nextWeekStart = weekStart.add(const Duration(days: 7));
    final followingWeek = nextWeekStart.add(const Duration(days: 7));
    if (target.isBefore(nextWeekStart)) return TaskHorizon.thisWeek;
    if (target.isBefore(followingWeek)) return TaskHorizon.nextWeek;
    if (target.year == today.year && target.month == today.month) {
      return TaskHorizon.thisMonth;
    }
    return TaskHorizon.scheduled;
  }

  DateTime startOfWeek(DateTime date) {
    final normalized = _date(date);
    final offset = (normalized.weekday - firstWeekday + 7) % 7;
    return normalized.subtract(Duration(days: offset));
  }

  String upcomingGroup(Task task, DateTime localNow) {
    final horizon = classify(task, localNow);
    return switch (horizon) {
      TaskHorizon.tomorrow => 'tomorrow',
      TaskHorizon.thisWeek => 'thisWeek',
      TaskHorizon.nextWeek => 'nextWeek',
      TaskHorizon.thisMonth => 'laterThisMonth',
      TaskHorizon.someday => 'someday',
      _ => 'future',
    };
  }

  DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

final class CompletionRules {
  const CompletionRules();

  Task complete(Task task, CompletionPolicy policy, DateTime now) {
    if (task.deletedAt != null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'A trashed task must be restored before completion.',
      );
    }
    return task.copyWith(
      status: TaskStatus.completed,
      completedAt: now,
      archivedAt: policy == CompletionPolicy.archive ? now : null,
      clearArchived: policy != CompletionPolicy.archive,
      deletedAt: policy == CompletionPolicy.trash ? now : null,
      clearDeleted: policy != CompletionPolicy.trash,
      updatedAt: now,
      revision: task.revision + 1,
    );
  }

  Task reopen(Task task, DateTime now) => task.copyWith(
    status: TaskStatus.open,
    clearCompleted: true,
    clearArchived: true,
    clearDeleted: true,
    updatedAt: now,
    revision: task.revision + 1,
  );
}

final class RetentionRules {
  const RetentionRules();

  bool eligible(Task task, TrashRetentionPolicy policy, DateTime now) =>
      policy == TrashRetentionPolicy.thirtyDays &&
      task.deletedAt != null &&
      !task.deletedAt!.isAfter(now.subtract(const Duration(days: 30)));
}

final class DateRolloverService {
  DateRolloverService({
    required this._clock,
    required this._onRollover,
    Timer Function(Duration, void Function())? timerFactory,
  }) : _timerFactory = timerFactory ?? Timer.new;

  final Clock _clock;
  final void Function() _onRollover;
  final Timer Function(Duration, void Function()) _timerFactory;
  Timer? _timer;
  DateTime? _observedDate;
  int? _observedOffsetMinutes;

  void start() {
    _reconcile();
    _schedule();
  }

  void resume() {
    _reconcile();
    _schedule();
  }

  void taskDatesChanged() => _onRollover();

  void _reconcile() {
    final local = _clock.now().toLocal();
    final date = DateTime(local.year, local.month, local.day);
    final offset = local.timeZoneOffset.inMinutes;
    if (_observedDate != null &&
        (_observedDate != date || _observedOffsetMinutes != offset)) {
      _onRollover();
    }
    _observedDate = date;
    _observedOffsetMinutes = offset;
  }

  void _schedule() {
    _timer?.cancel();
    final local = _clock.now().toLocal();
    final next = DateTime(local.year, local.month, local.day + 1);
    _timer = _timerFactory(next.difference(local), () {
      _reconcile();
      _onRollover();
      _schedule();
    });
  }

  void dispose() => _timer?.cancel();
}
