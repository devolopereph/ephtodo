enum ProjectNodeType { workspace, project, folder, taskList }

enum TaskStatus { open, inProgress, completed, cancelled }

enum TaskPriority { none, low, medium, high, urgent }

enum TaskHorizon {
  overdue,
  today,
  tomorrow,
  thisWeek,
  nextWeek,
  thisMonth,
  scheduled,
  someday,
  completed,
  archived,
  trash,
}

enum TaskMutationErrorCode {
  invalidHierarchy,
  invalidDates,
  missingNode,
  staleRevision,
  database,
  vault,
  malformedIpc,
  unsupported,
  retention,
  duplicateTag,
}

final class TaskMutationException implements Exception {
  const TaskMutationException(this.code, this.message);

  final TaskMutationErrorCode code;
  final String message;

  @override
  String toString() => 'TaskMutationException(${code.name})';
}

final class ProjectNode {
  const ProjectNode({
    required this.id,
    required this.type,
    required this.name,
    required this.sortOrder,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.parentId,
    this.description,
    this.icon,
    this.archivedAt,
    this.deletedAt,
  });

  static const maxDepth = 8;

  final String id;
  final String? parentId;
  final ProjectNodeType type;
  final String name;
  final String? description;
  final String? icon;
  final double sortOrder;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;
  final int revision;

  bool get isArchived => archivedAt != null;
  bool get isDeleted => deletedAt != null;

  static bool canContain(ProjectNodeType parent, ProjectNodeType child) =>
      switch (parent) {
        ProjectNodeType.workspace => child == ProjectNodeType.project,
        ProjectNodeType.project =>
          child == ProjectNodeType.folder || child == ProjectNodeType.taskList,
        ProjectNodeType.folder =>
          child == ProjectNodeType.folder || child == ProjectNodeType.taskList,
        ProjectNodeType.taskList => false,
      };

  static String validateName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 160) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidHierarchy,
        'A hierarchy name must contain 1–160 characters.',
      );
    }
    return trimmed;
  }

  ProjectNode copyWith({
    String? parentId,
    bool clearParent = false,
    ProjectNodeType? type,
    String? name,
    String? description,
    String? icon,
    double? sortOrder,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? archivedAt,
    bool clearArchived = false,
    DateTime? deletedAt,
    bool clearDeleted = false,
    int? revision,
  }) => ProjectNode(
    id: id,
    parentId: clearParent ? null : parentId ?? this.parentId,
    type: type ?? this.type,
    name: name ?? this.name,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    sortOrder: sortOrder ?? this.sortOrder,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: clearArchived ? null : archivedAt ?? this.archivedAt,
    deletedAt: clearDeleted ? null : deletedAt ?? this.deletedAt,
    revision: revision ?? this.revision,
  );
}

final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.sortOrder,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required this.originatingDeviceId,
    this.parentTaskId,
    this.projectNodeId,
    this.description,
    this.startAt,
    this.dueAt,
    this.reminderAt,
    this.recurrenceRule,
    this.completedAt,
    this.archivedAt,
    this.deletedAt,
    this.tagIds = const {},
  });

  static const maxDepth = 6;

  final String id;
  final String? parentTaskId;
  final String? projectNodeId;
  final String title;
  final String? description;
  final TaskStatus status;
  final TaskPriority priority;
  final DateTime? startAt;
  final DateTime? dueAt;
  final DateTime? reminderAt;
  final String? recurrenceRule;
  final double sortOrder;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;
  final int revision;
  final String originatingDeviceId;
  final Set<String> tagIds;

  bool get isArchived => archivedAt != null;
  bool get isDeleted => deletedAt != null;
  bool get isCompleted =>
      status == TaskStatus.completed || status == TaskStatus.cancelled;

  static String validateTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 500) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidDates,
        'A task title must contain 1–500 characters.',
      );
    }
    return trimmed;
  }

  static void validateDates({
    DateTime? startAt,
    DateTime? dueAt,
    DateTime? reminderAt,
  }) {
    if (startAt != null && dueAt != null && startAt.isAfter(dueAt)) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidDates,
        'Start date cannot be after due date.',
      );
    }
    if (reminderAt != null && dueAt != null && reminderAt.isAfter(dueAt)) {
      throw const TaskMutationException(
        TaskMutationErrorCode.invalidDates,
        'Reminder cannot be after due date.',
      );
    }
  }

  Task copyWith({
    String? parentTaskId,
    bool clearParent = false,
    String? projectNodeId,
    bool clearProject = false,
    String? title,
    String? description,
    TaskStatus? status,
    TaskPriority? priority,
    DateTime? startAt,
    bool clearStart = false,
    DateTime? dueAt,
    bool clearDue = false,
    DateTime? reminderAt,
    bool clearReminder = false,
    String? recurrenceRule,
    double? sortOrder,
    bool? isPinned,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompleted = false,
    DateTime? archivedAt,
    bool clearArchived = false,
    DateTime? deletedAt,
    bool clearDeleted = false,
    int? revision,
    Set<String>? tagIds,
  }) => Task(
    id: id,
    parentTaskId: clearParent ? null : parentTaskId ?? this.parentTaskId,
    projectNodeId: clearProject ? null : projectNodeId ?? this.projectNodeId,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    startAt: clearStart ? null : startAt ?? this.startAt,
    dueAt: clearDue ? null : dueAt ?? this.dueAt,
    reminderAt: clearReminder ? null : reminderAt ?? this.reminderAt,
    recurrenceRule: recurrenceRule ?? this.recurrenceRule,
    sortOrder: sortOrder ?? this.sortOrder,
    isPinned: isPinned ?? this.isPinned,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    completedAt: clearCompleted ? null : completedAt ?? this.completedAt,
    archivedAt: clearArchived ? null : archivedAt ?? this.archivedAt,
    deletedAt: clearDeleted ? null : deletedAt ?? this.deletedAt,
    revision: revision ?? this.revision,
    originatingDeviceId: originatingDeviceId,
    tagIds: tagIds ?? this.tagIds,
  );
}

final class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.colorToken,
  });

  final String id;
  final String name;
  final String? colorToken;
  final DateTime createdAt;
  final DateTime updatedAt;

  static String normalizeName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw const TaskMutationException(
        TaskMutationErrorCode.duplicateTag,
        'A tag name must contain 1–80 characters.',
      );
    }
    return trimmed;
  }
}

final class TaskSearchFilter {
  const TaskSearchFilter({
    this.query = '',
    this.statuses = const {},
    this.priorities = const {},
    this.projectNodeId,
    this.tagId,
    this.horizons = const {},
    this.includeCompleted = false,
    this.includeArchived = false,
    this.includeTrash = false,
    this.pinnedOnly = false,
  });

  final String query;
  final Set<TaskStatus> statuses;
  final Set<TaskPriority> priorities;
  final String? projectNodeId;
  final String? tagId;
  final Set<TaskHorizon> horizons;
  final bool includeCompleted;
  final bool includeArchived;
  final bool includeTrash;
  final bool pinnedOnly;
}
