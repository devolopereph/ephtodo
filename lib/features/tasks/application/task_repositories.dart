import '../domain/task_models.dart';

abstract interface class ProjectRepository {
  Stream<List<ProjectNode>> watchActive();
  Stream<List<ProjectNode>> watchAll();
  Future<List<ProjectNode>> all();
  Future<ProjectNode> create({
    required ProjectNodeType type,
    required String name,
    String? parentId,
    String? description,
  });
  Future<ProjectNode> rename(String id, String name, {required int revision});
  Future<ProjectNode> updateDescription(
    String id,
    String? description, {
    required int revision,
  });
  Future<ProjectNode> move(
    String id,
    String? parentId, {
    required double sortOrder,
    required int revision,
  });
  Future<ProjectNode> pin(String id, bool pinned, {required int revision});
  Future<ProjectNode> archive(String id, {required int revision});
  Future<ProjectNode> restore(String id, {required int revision});
  Future<ProjectNode> trash(String id, {required int revision});
  Future<ProjectNode> restoreFromTrash(String id, {required int revision});
}

abstract interface class TaskRepository {
  Stream<List<Task>> watch(TaskSearchFilter filter);
  Future<List<Task>> all();
  Future<Task?> byId(String id);
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
  });
  Future<Task> update(Task task, {required int expectedRevision});
  Future<Task> move(
    String id, {
    String? projectNodeId,
    String? parentTaskId,
    required double sortOrder,
    required int revision,
  });
  Future<Task> complete(String id, {required int revision});
  Future<Task> reopen(String id, {required int revision});
  Future<Task> archive(String id, {required int revision});
  Future<Task> restore(String id, {required int revision});
  Future<Task> trash(String id, {required int revision});
  Future<Task> restoreFromTrash(String id, {required int revision});
  Future<void> permanentlyDelete(String id);
  Future<int> purgeEligibleTrash();
  Future<Task> assignTag(String taskId, String tagId);
  Future<Task> unassignTag(String taskId, String tagId);
}

abstract interface class TagRepository {
  Stream<List<Tag>> watchAll();
  Future<List<Tag>> all();
  Future<Tag> create(String name, {String? colorToken});
  Future<Tag> rename(String id, String name);
  Future<void> delete(String id);
}

final class TaskStateEvent {
  const TaskStateEvent({
    required this.operation,
    required this.entityType,
    required this.entityId,
    required this.revision,
  });

  final String operation;
  final String entityType;
  final String entityId;
  final int revision;
}

abstract interface class TaskWriteCoordinator {
  Stream<TaskStateEvent> get events;
  ProjectRepository get projects;
  TaskRepository get tasks;
  TagRepository get tags;
}
