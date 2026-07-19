import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../core/database/preferences_repository.dart';
import '../../../core/foundation/foundation.dart';
import '../application/task_repositories.dart';
import '../domain/task_models.dart';
import '../domain/task_rules.dart';

final class DriftTaskWriteCoordinator implements TaskWriteCoordinator {
  DriftTaskWriteCoordinator({
    required db.AppDatabase database,
    required Clock clock,
    required String deviceId,
    required CompletionPolicy Function() completionPolicy,
    required TrashRetentionPolicy Function() retentionPolicy,
  }) : _events = StreamController<TaskStateEvent>.broadcast() {
    projects = DriftProjectRepository(database, clock, deviceId, _events);
    tasks = DriftTaskRepository(
      database,
      clock,
      deviceId,
      completionPolicy,
      retentionPolicy,
      _events,
    );
    tags = DriftTagRepository(database, clock, deviceId, _events);
  }

  final StreamController<TaskStateEvent> _events;

  @override
  late final ProjectRepository projects;
  @override
  late final TaskRepository tasks;
  @override
  late final TagRepository tags;

  @override
  Stream<TaskStateEvent> get events => _events.stream;

  Future<void> dispose() => _events.close();
}

abstract base class _DriftRepository {
  _DriftRepository(this.database, this.clock, this.deviceId, this.events);

  final db.AppDatabase database;
  final Clock clock;
  final String deviceId;
  final StreamController<TaskStateEvent> events;
  static const uuid = Uuid();

  Future<void> logChange(
    String entityType,
    String entityId,
    String operation,
    int revision,
  ) => database
      .into(database.changeLogs)
      .insert(
        db.ChangeLogsCompanion.insert(
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          revision: revision,
          changedAt: clock.now(),
          deviceId: deviceId,
        ),
      );

  void emit(
    String operation,
    String entityType,
    String entityId,
    int revision,
  ) => events.add(
    TaskStateEvent(
      operation: operation,
      entityType: entityType,
      entityId: entityId,
      revision: revision,
    ),
  );
}

final class DriftProjectRepository extends _DriftRepository
    implements ProjectRepository {
  DriftProjectRepository(
    super.database,
    super.clock,
    super.deviceId,
    super.events,
  );

  final _rules = const HierarchyRules();
  final _ordering = const StableOrdering();

  ProjectNode _model(db.ProjectNode row) => ProjectNode(
    id: row.id,
    parentId: row.parentId,
    type: ProjectNodeType.values.byName(row.nodeType),
    name: row.name,
    description: row.description,
    icon: row.icon,
    sortOrder: row.sortOrder,
    isPinned: row.isPinned,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    archivedAt: row.archivedAt,
    deletedAt: row.deletedAt,
    revision: row.revision,
  );

  @override
  Stream<List<ProjectNode>> watchActive() {
    final query = database.select(database.projectNodes)
      ..where((row) => row.archivedAt.isNull() & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.desc(row.isPinned),
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
      ]);
    return query.watch().map((rows) => rows.map(_model).toList());
  }

  @override
  Stream<List<ProjectNode>> watchAll() {
    final query = database.select(database.projectNodes)
      ..orderBy([
        (row) => OrderingTerm.desc(row.isPinned),
        (row) => OrderingTerm.asc(row.sortOrder),
        (row) => OrderingTerm.asc(row.name),
      ]);
    return query.watch().map((rows) => rows.map(_model).toList());
  }

  @override
  Future<List<ProjectNode>> all() async =>
      (await database.select(database.projectNodes).get()).map(_model).toList();

  @override
  Future<ProjectNode> create({
    required ProjectNodeType type,
    required String name,
    String? parentId,
    String? description,
  }) async {
    final trimmed = ProjectNode.validateName(name);
    final nodes = await all();
    ProjectNode? parent;
    if (parentId != null) {
      parent = nodes.where((node) => node.id == parentId).firstOrNull;
      if (parent == null) {
        throw const TaskMutationException(
          TaskMutationErrorCode.missingNode,
          'The requested parent no longer exists.',
        );
      }
    }
    final now = clock.now();
    final candidate = ProjectNode(
      id: _DriftRepository.uuid.v4(),
      parentId: parentId,
      type: type,
      name: trimmed,
      description: description?.trim(),
      sortOrder: _ordering.after(
        nodes
            .where((node) => node.parentId == parentId)
            .map((node) => node.sortOrder),
      ),
      isPinned: false,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    );
    _rules.validateProjectMove(
      node: candidate,
      newParent: parent,
      allNodes: [...nodes, candidate],
    );
    await database.transaction(() async {
      await database
          .into(database.projectNodes)
          .insert(
            db.ProjectNodesCompanion.insert(
              id: candidate.id,
              parentId: Value(parentId),
              nodeType: candidate.type.name,
              name: candidate.name,
              description: Value(candidate.description),
              sortOrder: Value(candidate.sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await logChange('projectNode', candidate.id, 'create', 1);
    });
    emit('create', 'projectNode', candidate.id, 1);
    return candidate;
  }

  Future<ProjectNode> _get(String id) async {
    final row = await (database.select(
      database.projectNodes,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The hierarchy node no longer exists.',
      );
    }
    return _model(row);
  }

  Future<ProjectNode> _mutate(
    String id,
    int revision,
    String operation,
    ProjectNode Function(ProjectNode current, DateTime now) change,
  ) async {
    final current = await _get(id);
    if (current.revision != revision) {
      throw const TaskMutationException(
        TaskMutationErrorCode.staleRevision,
        'The hierarchy node changed in another view.',
      );
    }
    final next = change(current, clock.now());
    await database.transaction(() async {
      final count =
          await (database.update(database.projectNodes)..where(
                (row) => row.id.equals(id) & row.revision.equals(revision),
              ))
              .write(
                db.ProjectNodesCompanion(
                  parentId: Value(next.parentId),
                  name: Value(next.name),
                  description: Value(next.description),
                  sortOrder: Value(next.sortOrder),
                  isPinned: Value(next.isPinned),
                  updatedAt: Value(next.updatedAt),
                  archivedAt: Value(next.archivedAt),
                  deletedAt: Value(next.deletedAt),
                  revision: Value(next.revision),
                ),
              );
      if (count != 1) {
        throw const TaskMutationException(
          TaskMutationErrorCode.staleRevision,
          'The hierarchy node changed in another view.',
        );
      }
      await logChange('projectNode', id, operation, next.revision);
    });
    emit(operation, 'projectNode', id, next.revision);
    return next;
  }

  @override
  Future<ProjectNode> rename(String id, String name, {required int revision}) =>
      _mutate(
        id,
        revision,
        'rename',
        (node, now) => node.copyWith(
          name: ProjectNode.validateName(name),
          updatedAt: now,
          revision: node.revision + 1,
        ),
      );

  @override
  Future<ProjectNode> updateDescription(
    String id,
    String? description, {
    required int revision,
  }) => _mutate(
    id,
    revision,
    'update',
    (node, now) => node.copyWith(
      description: description?.trim(),
      updatedAt: now,
      revision: node.revision + 1,
    ),
  );

  @override
  Future<ProjectNode> move(
    String id,
    String? parentId, {
    required double sortOrder,
    required int revision,
  }) async {
    final nodes = await all();
    final current = nodes.where((node) => node.id == id).firstOrNull;
    final parent = parentId == null
        ? null
        : nodes.where((node) => node.id == parentId).firstOrNull;
    if (current == null || (parentId != null && parent == null)) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The requested hierarchy location no longer exists.',
      );
    }
    _rules.validateProjectMove(
      node: current,
      newParent: parent,
      allNodes: nodes,
    );
    return _mutate(
      id,
      revision,
      'move',
      (node, now) => node.copyWith(
        parentId: parentId,
        clearParent: parentId == null,
        sortOrder: sortOrder,
        updatedAt: now,
        revision: node.revision + 1,
      ),
    );
  }

  @override
  Future<ProjectNode> pin(String id, bool pinned, {required int revision}) =>
      _mutate(
        id,
        revision,
        'pin',
        (node, now) => node.copyWith(
          isPinned: pinned,
          updatedAt: now,
          revision: node.revision + 1,
        ),
      );

  Future<ProjectNode> _cascadeLifecycle(
    String id,
    int revision,
    String operation, {
    required bool archive,
    required bool trash,
    required bool restoreArchive,
    required bool restoreTrash,
  }) async {
    final nodes = await all();
    final root = nodes.where((node) => node.id == id).firstOrNull;
    if (root == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The hierarchy node no longer exists.',
      );
    }
    if (root.revision != revision) {
      throw const TaskMutationException(
        TaskMutationErrorCode.staleRevision,
        'The hierarchy node changed in another view.',
      );
    }
    final affected = <ProjectNode>[root];
    for (var index = 0; index < affected.length; index++) {
      affected.addAll(
        nodes.where((node) => node.parentId == affected[index].id),
      );
    }
    final now = clock.now();
    await database.transaction(() async {
      for (final node in affected) {
        final nextRevision = node.revision + 1;
        await (database.update(
          database.projectNodes,
        )..where((row) => row.id.equals(node.id))).write(
          db.ProjectNodesCompanion(
            archivedAt: Value(
              restoreArchive ? null : (archive ? now : node.archivedAt),
            ),
            deletedAt: Value(
              restoreTrash ? null : (trash ? now : node.deletedAt),
            ),
            updatedAt: Value(now),
            revision: Value(nextRevision),
          ),
        );
        await logChange('projectNode', node.id, operation, nextRevision);
      }
    });
    for (final node in affected) {
      emit(operation, 'projectNode', node.id, node.revision + 1);
    }
    return _get(id);
  }

  @override
  Future<ProjectNode> archive(String id, {required int revision}) =>
      _cascadeLifecycle(
        id,
        revision,
        'archive',
        archive: true,
        trash: false,
        restoreArchive: false,
        restoreTrash: false,
      );

  @override
  Future<ProjectNode> restore(String id, {required int revision}) =>
      _cascadeLifecycle(
        id,
        revision,
        'restore',
        archive: false,
        trash: false,
        restoreArchive: true,
        restoreTrash: false,
      );

  @override
  Future<ProjectNode> trash(String id, {required int revision}) =>
      _cascadeLifecycle(
        id,
        revision,
        'trash',
        archive: false,
        trash: true,
        restoreArchive: false,
        restoreTrash: false,
      );

  @override
  Future<ProjectNode> restoreFromTrash(String id, {required int revision}) =>
      _cascadeLifecycle(
        id,
        revision,
        'restoreTrash',
        archive: false,
        trash: false,
        restoreArchive: false,
        restoreTrash: true,
      );
}

final class DriftTaskRepository extends _DriftRepository
    implements TaskRepository {
  DriftTaskRepository(
    super.database,
    super.clock,
    super.deviceId,
    this._completionPolicy,
    this._retentionPolicy,
    super.events,
  );

  final CompletionPolicy Function() _completionPolicy;
  final TrashRetentionPolicy Function() _retentionPolicy;
  final _rules = const HierarchyRules();
  final _completion = const CompletionRules();
  final _retention = const RetentionRules();
  final _ordering = const StableOrdering();

  Task _model(db.Task row, [Set<String> tags = const {}]) => Task(
    id: row.id,
    parentTaskId: row.parentTaskId,
    projectNodeId: row.projectNodeId,
    title: row.title,
    description: row.description,
    status: TaskStatus.values.byName(row.status),
    priority: TaskPriority.values[row.priority],
    startAt: row.startAt,
    dueAt: row.dueAt,
    reminderAt: row.reminderAt,
    recurrenceRule: row.recurrenceRule,
    sortOrder: row.sortOrder,
    isPinned: row.isPinned,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    completedAt: row.completedAt,
    archivedAt: row.archivedAt,
    deletedAt: row.deletedAt,
    revision: row.revision,
    originatingDeviceId: row.originatingDeviceId,
    tagIds: tags,
  );

  Future<Map<String, Set<String>>> _tagsFor(Iterable<String> taskIds) async {
    final ids = taskIds.toList();
    if (ids.isEmpty) return {};
    final rows = await (database.select(
      database.taskTags,
    )..where((row) => row.taskId.isIn(ids))).get();
    final result = <String, Set<String>>{};
    for (final row in rows) {
      result.putIfAbsent(row.taskId, () => <String>{}).add(row.tagId);
    }
    return result;
  }

  @override
  Stream<List<Task>> watch(TaskSearchFilter filter) {
    final query = database.select(database.tasks);
    final search = filter.query.trim();
    if (!filter.includeTrash) {
      query.where((row) => row.deletedAt.isNull());
    }
    if (!filter.includeArchived) {
      query.where((row) => row.archivedAt.isNull());
    }
    if (!filter.includeCompleted) {
      query.where(
        (row) =>
            row.status.equals(TaskStatus.open.name) |
            row.status.equals(TaskStatus.inProgress.name),
      );
    }
    if (filter.projectNodeId != null) {
      query.where((row) => row.projectNodeId.equals(filter.projectNodeId!));
    }
    if (filter.statuses.isNotEmpty) {
      query.where((row) => row.status.isIn(filter.statuses.map((v) => v.name)));
    }
    if (filter.priorities.isNotEmpty) {
      query.where(
        (row) => row.priority.isIn(filter.priorities.map((v) => v.index)),
      );
    }
    if (filter.horizons.length == 1 &&
        filter.horizons.contains(TaskHorizon.today)) {
      final current = clock.now();
      final start = DateTime(current.year, current.month, current.day);
      final end = start.add(const Duration(days: 1));
      query.where(
        (row) =>
            (row.dueAt.isBiggerOrEqualValue(start) &
                row.dueAt.isSmallerThanValue(end)) |
            (row.dueAt.isNull() &
                row.startAt.isBiggerOrEqualValue(start) &
                row.startAt.isSmallerThanValue(end)),
      );
    }
    if (filter.pinnedOnly) query.where((row) => row.isPinned.equals(true));
    query.orderBy([
      (row) => OrderingTerm.desc(row.isPinned),
      (row) => OrderingTerm.asc(row.sortOrder),
      (row) => OrderingTerm.asc(row.createdAt),
    ]);
    return query.watch().asyncMap((rows) async {
      final tags = await _tagsFor(rows.map((row) => row.id));
      var models = rows.map((row) => _model(row, tags[row.id] ?? {})).toList();
      if (filter.tagId != null) {
        models = models
            .where((task) => task.tagIds.contains(filter.tagId))
            .toList();
      }
      if (filter.horizons.isNotEmpty) {
        final engine = const HorizonEngine();
        models = models
            .where(
              (task) =>
                  filter.horizons.contains(engine.classify(task, clock.now())),
            )
            .toList();
      }
      if (search.isNotEmpty) {
        final lower = search.toLowerCase();
        final projectIds =
            (await (database.select(
                  database.projectNodes,
                )..where((row) => row.name.like('%$search%'))).get())
                .map((row) => row.id)
                .toSet();
        final tagIds =
            (await (database.select(
              database.tags,
            )..where((row) => row.name.like('%$search%'))).get()).map(
              (row) => row.id,
            );
        models = models
            .where(
              (task) =>
                  task.title.toLowerCase().contains(lower) ||
                  (task.description?.toLowerCase().contains(lower) ?? false) ||
                  (task.projectNodeId != null &&
                      projectIds.contains(task.projectNodeId)) ||
                  task.tagIds.any(tagIds.contains),
            )
            .toList();
      }
      return models;
    });
  }

  @override
  Future<List<Task>> all() async {
    final rows = await database.select(database.tasks).get();
    final tags = await _tagsFor(rows.map((row) => row.id));
    return rows.map((row) => _model(row, tags[row.id] ?? {})).toList();
  }

  @override
  Future<Task?> byId(String id) async {
    final row = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final tags = await _tagsFor([id]);
    return _model(row, tags[id] ?? {});
  }

  @override
  Future<Task> create({
    required String title,
    String? description,
    String? projectNodeId,
    String? parentTaskId,
    DateTime? startAt,
    DateTime? dueAt,
    DateTime? reminderAt,
    String? recurrenceRule,
    TaskPriority priority = TaskPriority.none,
    bool isPinned = false,
  }) async {
    final trimmed = Task.validateTitle(title);
    Task.validateDates(startAt: startAt, dueAt: dueAt, reminderAt: reminderAt);
    final tasks = await all();
    final parent = parentTaskId == null
        ? null
        : tasks.where((task) => task.id == parentTaskId).firstOrNull;
    if (parentTaskId != null && parent == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The parent task no longer exists.',
      );
    }
    final now = clock.now();
    final task = Task(
      id: _DriftRepository.uuid.v4(),
      parentTaskId: parentTaskId,
      projectNodeId: projectNodeId ?? parent?.projectNodeId,
      title: trimmed,
      description: description?.trim(),
      status: TaskStatus.open,
      priority: priority,
      startAt: startAt,
      dueAt: dueAt,
      reminderAt: reminderAt,
      recurrenceRule: recurrenceRule?.trim(),
      sortOrder: _ordering.after(
        tasks
            .where(
              (candidate) =>
                  candidate.parentTaskId == parentTaskId &&
                  candidate.projectNodeId ==
                      (projectNodeId ?? parent?.projectNodeId),
            )
            .map((candidate) => candidate.sortOrder),
      ),
      isPinned: isPinned,
      createdAt: now,
      updatedAt: now,
      revision: 1,
      originatingDeviceId: deviceId,
    );
    _rules.validateTaskMove(
      task: task,
      newParent: parent,
      allTasks: [...tasks, task],
    );
    await database.transaction(() async {
      await database
          .into(database.tasks)
          .insert(
            db.TasksCompanion.insert(
              id: task.id,
              parentTaskId: Value(task.parentTaskId),
              projectNodeId: Value(task.projectNodeId),
              title: task.title,
              description: Value(task.description),
              status: Value(task.status.name),
              priority: Value(task.priority.index),
              startAt: Value(startAt),
              dueAt: Value(dueAt),
              reminderAt: Value(reminderAt),
              recurrenceRule: Value(recurrenceRule?.trim()),
              sortOrder: Value(task.sortOrder),
              isPinned: Value(isPinned),
              createdAt: now,
              updatedAt: now,
              originatingDeviceId: deviceId,
            ),
          );
      await logChange('task', task.id, 'create', 1);
    });
    emit('create', 'task', task.id, 1);
    return task;
  }

  @override
  Future<Task> update(Task task, {required int expectedRevision}) async {
    Task.validateTitle(task.title);
    Task.validateDates(
      startAt: task.startAt,
      dueAt: task.dueAt,
      reminderAt: task.reminderAt,
    );
    final current = await byId(task.id);
    if (current == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The task no longer exists.',
      );
    }
    if (current.revision != expectedRevision) {
      throw const TaskMutationException(
        TaskMutationErrorCode.staleRevision,
        'The task changed in another view.',
      );
    }
    final next = task.copyWith(
      title: Task.validateTitle(task.title),
      updatedAt: clock.now(),
      revision: expectedRevision + 1,
    );
    await database.transaction(() async {
      final count =
          await (database.update(database.tasks)..where(
                (row) =>
                    row.id.equals(task.id) &
                    row.revision.equals(expectedRevision),
              ))
              .write(
                db.TasksCompanion(
                  parentTaskId: Value(next.parentTaskId),
                  projectNodeId: Value(next.projectNodeId),
                  title: Value(next.title),
                  description: Value(next.description),
                  status: Value(next.status.name),
                  priority: Value(next.priority.index),
                  startAt: Value(next.startAt),
                  dueAt: Value(next.dueAt),
                  reminderAt: Value(next.reminderAt),
                  recurrenceRule: Value(next.recurrenceRule),
                  sortOrder: Value(next.sortOrder),
                  isPinned: Value(next.isPinned),
                  updatedAt: Value(next.updatedAt),
                  completedAt: Value(next.completedAt),
                  archivedAt: Value(next.archivedAt),
                  deletedAt: Value(next.deletedAt),
                  revision: Value(next.revision),
                ),
              );
      if (count != 1) {
        throw const TaskMutationException(
          TaskMutationErrorCode.staleRevision,
          'The task changed in another view.',
        );
      }
      await logChange('task', task.id, 'update', next.revision);
    });
    emit('update', 'task', task.id, next.revision);
    return next;
  }

  @override
  Future<Task> move(
    String id, {
    String? projectNodeId,
    String? parentTaskId,
    required double sortOrder,
    required int revision,
  }) async {
    final tasks = await all();
    final current = tasks.where((task) => task.id == id).firstOrNull;
    final parent = parentTaskId == null
        ? null
        : tasks.where((task) => task.id == parentTaskId).firstOrNull;
    if (current == null || (parentTaskId != null && parent == null)) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The requested task location no longer exists.',
      );
    }
    _rules.validateTaskMove(task: current, newParent: parent, allTasks: tasks);
    return update(
      current.copyWith(
        parentTaskId: parentTaskId,
        clearParent: parentTaskId == null,
        projectNodeId: projectNodeId ?? parent?.projectNodeId,
        clearProject: projectNodeId == null && parent == null,
        sortOrder: sortOrder,
      ),
      expectedRevision: revision,
    );
  }

  Future<Task> _lifecycle(
    String id,
    int revision,
    String operation,
    Task Function(Task task, DateTime now) change,
  ) async {
    final current = await byId(id);
    if (current == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The task no longer exists.',
      );
    }
    if (current.revision != revision) {
      throw const TaskMutationException(
        TaskMutationErrorCode.staleRevision,
        'The task changed in another view.',
      );
    }
    final next = change(current, clock.now());
    await database.transaction(() async {
      await (database.update(
        database.tasks,
      )..where((row) => row.id.equals(id))).write(
        db.TasksCompanion(
          status: Value(next.status.name),
          completedAt: Value(next.completedAt),
          archivedAt: Value(next.archivedAt),
          deletedAt: Value(next.deletedAt),
          updatedAt: Value(next.updatedAt),
          revision: Value(next.revision),
        ),
      );
      await logChange('task', id, operation, next.revision);
    });
    emit(operation, 'task', id, next.revision);
    return next;
  }

  @override
  Future<Task> complete(String id, {required int revision}) => _lifecycle(
    id,
    revision,
    'complete',
    (task, now) => _completion.complete(task, _completionPolicy(), now),
  );

  @override
  Future<Task> reopen(String id, {required int revision}) => _lifecycle(
    id,
    revision,
    'reopen',
    (task, now) => _completion.reopen(task, now),
  );

  @override
  Future<Task> archive(String id, {required int revision}) => _lifecycle(
    id,
    revision,
    'archive',
    (task, now) => task.copyWith(
      archivedAt: now,
      updatedAt: now,
      revision: task.revision + 1,
    ),
  );

  @override
  Future<Task> restore(String id, {required int revision}) => _lifecycle(
    id,
    revision,
    'restore',
    (task, now) => task.copyWith(
      clearArchived: true,
      updatedAt: now,
      revision: task.revision + 1,
    ),
  );

  @override
  Future<Task> trash(String id, {required int revision}) => _lifecycle(
    id,
    revision,
    'trash',
    (task, now) => task.copyWith(
      deletedAt: now,
      updatedAt: now,
      revision: task.revision + 1,
    ),
  );

  @override
  Future<Task> restoreFromTrash(String id, {required int revision}) =>
      _lifecycle(
        id,
        revision,
        'restoreTrash',
        (task, now) => task.copyWith(
          clearDeleted: true,
          updatedAt: now,
          revision: task.revision + 1,
        ),
      );

  @override
  Future<void> permanentlyDelete(String id) async {
    final task = await byId(id);
    if (task == null) return;
    if (task.deletedAt == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.retention,
        'Only items already in Trash can be permanently deleted.',
      );
    }
    final descendants = <Task>[task];
    final tasks = await all();
    for (var index = 0; index < descendants.length; index++) {
      descendants.addAll(
        tasks.where(
          (candidate) => candidate.parentTaskId == descendants[index].id,
        ),
      );
    }
    await database.transaction(() async {
      for (final child in descendants.reversed) {
        await (database.delete(
          database.tasks,
        )..where((row) => row.id.equals(child.id))).go();
        await logChange(
          'task',
          child.id,
          'permanentDelete',
          child.revision + 1,
        );
      }
    });
    for (final child in descendants) {
      emit('permanentDelete', 'task', child.id, child.revision + 1);
    }
  }

  @override
  Future<int> purgeEligibleTrash() async {
    if (_retentionPolicy() == TrashRetentionPolicy.never) return 0;
    final eligible = (await all())
        .where(
          (task) => _retention.eligible(task, _retentionPolicy(), clock.now()),
        )
        .toList();
    for (final task in eligible.where((task) => task.parentTaskId == null)) {
      await permanentlyDelete(task.id);
    }
    return eligible.length;
  }

  @override
  Future<Task> assignTag(String taskId, String tagId) async {
    final task = await byId(taskId);
    if (task == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The task no longer exists.',
      );
    }
    await database.transaction(() async {
      await database
          .into(database.taskTags)
          .insert(
            db.TaskTagsCompanion.insert(taskId: taskId, tagId: tagId),
            mode: InsertMode.insertOrIgnore,
          );
      await (database.update(
        database.tasks,
      )..where((row) => row.id.equals(taskId))).write(
        db.TasksCompanion(
          updatedAt: Value(clock.now()),
          revision: Value(task.revision + 1),
        ),
      );
      await logChange('task', taskId, 'assignTag', task.revision + 1);
    });
    emit('assignTag', 'task', taskId, task.revision + 1);
    return (await byId(taskId))!;
  }

  @override
  Future<Task> unassignTag(String taskId, String tagId) async {
    final task = await byId(taskId);
    if (task == null) {
      throw const TaskMutationException(
        TaskMutationErrorCode.missingNode,
        'The task no longer exists.',
      );
    }
    await database.transaction(() async {
      await (database.delete(database.taskTags)..where(
            (row) => row.taskId.equals(taskId) & row.tagId.equals(tagId),
          ))
          .go();
      await (database.update(
        database.tasks,
      )..where((row) => row.id.equals(taskId))).write(
        db.TasksCompanion(
          updatedAt: Value(clock.now()),
          revision: Value(task.revision + 1),
        ),
      );
      await logChange('task', taskId, 'unassignTag', task.revision + 1);
    });
    emit('unassignTag', 'task', taskId, task.revision + 1);
    return (await byId(taskId))!;
  }
}

final class DriftTagRepository extends _DriftRepository
    implements TagRepository {
  DriftTagRepository(super.database, super.clock, super.deviceId, super.events);

  Tag _model(db.Tag row) => Tag(
    id: row.id,
    name: row.name,
    colorToken: row.colorToken,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  Future<void> _ensureUnique(String name, {String? excludingId}) async {
    final rows = await database.select(database.tags).get();
    final duplicate = rows.any(
      (row) =>
          row.id != excludingId && row.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw const TaskMutationException(
        TaskMutationErrorCode.duplicateTag,
        'Tag names are unique regardless of letter case.',
      );
    }
  }

  @override
  Stream<List<Tag>> watchAll() =>
      (database.select(database.tags)
            ..orderBy([(row) => OrderingTerm.asc(row.name)]))
          .watch()
          .map((rows) => rows.map(_model).toList());

  @override
  Future<List<Tag>> all() async =>
      (await (database.select(
            database.tags,
          )..orderBy([(row) => OrderingTerm.asc(row.name)])).get())
          .map(_model)
          .toList();

  @override
  Future<Tag> create(String name, {String? colorToken}) async {
    final normalized = Tag.normalizeName(name);
    await _ensureUnique(normalized);
    final now = clock.now();
    final tag = Tag(
      id: _DriftRepository.uuid.v4(),
      name: normalized,
      colorToken: colorToken,
      createdAt: now,
      updatedAt: now,
    );
    await database.transaction(() async {
      await database
          .into(database.tags)
          .insert(
            db.TagsCompanion.insert(
              id: tag.id,
              name: tag.name,
              colorToken: Value(colorToken),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await logChange('tag', tag.id, 'create', 1);
    });
    emit('create', 'tag', tag.id, 1);
    return tag;
  }

  @override
  Future<Tag> rename(String id, String name) async {
    final normalized = Tag.normalizeName(name);
    await _ensureUnique(normalized, excludingId: id);
    final now = clock.now();
    await database.transaction(() async {
      final count =
          await (database.update(
            database.tags,
          )..where((row) => row.id.equals(id))).write(
            db.TagsCompanion(name: Value(normalized), updatedAt: Value(now)),
          );
      if (count != 1) {
        throw const TaskMutationException(
          TaskMutationErrorCode.missingNode,
          'The tag no longer exists.',
        );
      }
      await logChange('tag', id, 'rename', 1);
    });
    emit('rename', 'tag', id, 1);
    return _model(
      await (database.select(
        database.tags,
      )..where((row) => row.id.equals(id))).getSingle(),
    );
  }

  @override
  Future<void> delete(String id) async {
    await database.transaction(() async {
      await (database.delete(
        database.taskTags,
      )..where((row) => row.tagId.equals(id))).go();
      await (database.delete(
        database.tags,
      )..where((row) => row.id.equals(id))).go();
      await logChange('tag', id, 'delete', 1);
    });
    emit('delete', 'tag', id, 1);
  }
}
