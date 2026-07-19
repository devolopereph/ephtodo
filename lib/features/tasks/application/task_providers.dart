import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task_models.dart';
import 'task_repositories.dart';

enum WorkspaceDestination {
  today,
  upcoming,
  projects,
  notes,
  audio,
  completed,
  archive,
  trash,
  settings,
}

/// Overridden inside the workspace's nested [ProviderScope] once the vault's
/// coordinator exists. Every derived provider must declare it in
/// `dependencies` so Riverpod instantiates them inside that scope instead of
/// the root container (where this throws).
final taskCoordinatorProvider = Provider<TaskWriteCoordinator>(
  (ref) => throw StateError('Task coordinator was not provided'),
  dependencies: const [],
);

final navigationProvider =
    NotifierProvider<NavigationController, WorkspaceDestination>(
      NavigationController.new,
    );

final class NavigationController extends Notifier<WorkspaceDestination> {
  @override
  WorkspaceDestination build() => WorkspaceDestination.today;

  void select(WorkspaceDestination value) => state = value;
}

final selectedProjectProvider =
    NotifierProvider<SelectedProjectController, String?>(
      SelectedProjectController.new,
    );

final selectedTaskProvider = NotifierProvider<SelectedTaskController, String?>(
  SelectedTaskController.new,
);

final class SelectedTaskController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final class SelectedProjectController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final searchFilterProvider =
    NotifierProvider<SearchFilterController, TaskSearchFilter>(
      SearchFilterController.new,
    );

final class SearchFilterController extends Notifier<TaskSearchFilter> {
  @override
  TaskSearchFilter build() => const TaskSearchFilter();

  void setQuery(String query) => state = TaskSearchFilter(
    query: query,
    statuses: state.statuses,
    priorities: state.priorities,
    projectNodeId: state.projectNodeId,
    tagId: state.tagId,
    horizons: state.horizons,
    includeCompleted: state.includeCompleted,
    includeArchived: state.includeArchived,
    includeTrash: state.includeTrash,
    pinnedOnly: state.pinnedOnly,
  );

  void replace(TaskSearchFilter filter) => state = filter;
  void clear() => state = const TaskSearchFilter();
}

final projectListProvider = StreamProvider.autoDispose<List<ProjectNode>>(
  (ref) => ref.watch(taskCoordinatorProvider).projects.watchActive(),
  dependencies: [taskCoordinatorProvider],
);

/// Maps every project node id (including archived/trashed ones) to its name
/// so task tiles can show which project a task belongs to.
final projectNamesProvider = StreamProvider.autoDispose<Map<String, String>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .projects
      .watchAll()
      .map((nodes) => {for (final node in nodes) node.id: node.name}),
  dependencies: [taskCoordinatorProvider],
);

final todayTasksProvider = StreamProvider.autoDispose<List<Task>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .tasks
      .watch(
        const TaskSearchFilter(
          horizons: {TaskHorizon.overdue, TaskHorizon.today},
          includeCompleted: true,
        ),
      ),
  dependencies: [taskCoordinatorProvider],
);

final upcomingTasksProvider = StreamProvider.autoDispose<List<Task>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .tasks
      .watch(
        const TaskSearchFilter(
          horizons: {
            TaskHorizon.tomorrow,
            TaskHorizon.thisWeek,
            TaskHorizon.nextWeek,
            TaskHorizon.thisMonth,
            TaskHorizon.scheduled,
            // Tasks without any date would otherwise be invisible in every
            // default view; surface them under a "Someday" group.
            TaskHorizon.someday,
          },
        ),
      ),
  dependencies: [taskCoordinatorProvider],
);

final searchResultsProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  final filter = ref.watch(searchFilterProvider);
  return ref.watch(taskCoordinatorProvider).tasks.watch(filter);
}, dependencies: [taskCoordinatorProvider]);

final projectTasksProvider = StreamProvider.autoDispose
    .family<List<Task>, String>(
      (ref, projectId) => ref
          .watch(taskCoordinatorProvider)
          .tasks
          .watch(TaskSearchFilter(projectNodeId: projectId)),
      dependencies: [taskCoordinatorProvider],
    );

final completedTasksProvider = StreamProvider.autoDispose<List<Task>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .tasks
      .watch(
        const TaskSearchFilter(
          includeCompleted: true,
          statuses: {TaskStatus.completed, TaskStatus.cancelled},
        ),
      ),
  dependencies: [taskCoordinatorProvider],
);

final archivedTasksProvider = StreamProvider.autoDispose<List<Task>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .tasks
      .watch(
        const TaskSearchFilter(includeCompleted: true, includeArchived: true),
      )
      .map((tasks) => tasks.where((task) => task.archivedAt != null).toList()),
  dependencies: [taskCoordinatorProvider],
);

final trashedProjectsProvider = StreamProvider.autoDispose<List<ProjectNode>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .projects
      .watchAll()
      .map((nodes) => nodes.where((node) => node.deletedAt != null).toList()),
  dependencies: [taskCoordinatorProvider],
);

final trashedTasksProvider = StreamProvider.autoDispose<List<Task>>(
  (ref) => ref
      .watch(taskCoordinatorProvider)
      .tasks
      .watch(
        const TaskSearchFilter(
          includeCompleted: true,
          includeArchived: true,
          includeTrash: true,
        ),
      )
      .map((tasks) => tasks.where((task) => task.deletedAt != null).toList()),
  dependencies: [taskCoordinatorProvider],
);

final class TaskEditorState {
  const TaskEditorState({this.task, this.open = false, this.errorCode});

  final Task? task;
  final bool open;
  final TaskMutationErrorCode? errorCode;
}

final taskEditorProvider =
    NotifierProvider<TaskEditorController, TaskEditorState>(
      TaskEditorController.new,
    );

final class TaskEditorController extends Notifier<TaskEditorState> {
  @override
  TaskEditorState build() => const TaskEditorState();

  void edit(Task task) => state = TaskEditorState(task: task, open: true);
  void create() => state = const TaskEditorState(open: true);
  void close() => state = const TaskEditorState();
  void fail(TaskMutationErrorCode code) =>
      state = TaskEditorState(task: state.task, open: true, errorCode: code);
}

final class ProjectEditorState {
  const ProjectEditorState({this.node, this.open = false});
  final ProjectNode? node;
  final bool open;
}

final projectEditorProvider =
    NotifierProvider<ProjectEditorController, ProjectEditorState>(
      ProjectEditorController.new,
    );

final class ProjectEditorController extends Notifier<ProjectEditorState> {
  @override
  ProjectEditorState build() => const ProjectEditorState();

  void edit(ProjectNode node) =>
      state = ProjectEditorState(node: node, open: true);
  void create() => state = const ProjectEditorState(open: true);
  void close() => state = const ProjectEditorState();
}
