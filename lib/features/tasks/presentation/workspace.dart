import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_recovery_page.dart';
import '../../../core/backup/vault_backup_service.dart';
import '../../../core/database/preferences_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../audio/application/audio_coordinator.dart';
import '../../audio/presentation/audio_page.dart';
import '../../notes/application/note_repository.dart';
import '../../notes/presentation/notes_page.dart';
import '../../sync/application/sync_settings_controller.dart';
import '../../sync/presentation/sync_settings_page.dart';
import '../application/task_providers.dart';
import '../application/task_repositories.dart';
import '../domain/task_models.dart';
import '../domain/task_rules.dart';

String completionPolicyLabel(BuildContext context, CompletionPolicy value) =>
    switch (value) {
      CompletionPolicy.archive => AppLocalizations.of(context).policyArchive,
      CompletionPolicy.trash => AppLocalizations.of(context).policyTrash,
      CompletionPolicy.keepCompleted => AppLocalizations.of(
        context,
      ).policyKeepCompleted,
    };

String taskStatusLabel(BuildContext context, TaskStatus value) =>
    switch (value) {
      TaskStatus.open => AppLocalizations.of(context).taskStatusOpen,
      TaskStatus.inProgress => AppLocalizations.of(context).taskStatusInProgress,
      TaskStatus.completed => AppLocalizations.of(context).taskStatusCompleted,
      TaskStatus.cancelled => AppLocalizations.of(context).taskStatusCancelled,
    };

String themeLabel(BuildContext context, AppThemeId value) => switch (value) {
  AppThemeId.obsidianBlack => AppLocalizations.of(context).themeObsidianBlack,
  AppThemeId.graphite => AppLocalizations.of(context).themeGraphite,
  AppThemeId.midnightIndigo =>
    AppLocalizations.of(context).themeMidnightIndigo,
  AppThemeId.nordicLight => AppLocalizations.of(context).themeNordicLight,
  AppThemeId.warmPaper => AppLocalizations.of(context).themeWarmPaper,
};

String trashRetentionLabel(BuildContext context, TrashRetentionPolicy value) =>
    switch (value) {
      TrashRetentionPolicy.thirtyDays => AppLocalizations.of(
        context,
      ).retentionThirtyDays,
      TrashRetentionPolicy.never => AppLocalizations.of(context).retentionNever,
    };

final class Phase2Workspace extends ConsumerStatefulWidget {
  const Phase2Workspace({
    super.key,
    required this.coordinator,
    required this.clock,
    required this.settings,
    required this.onShowSticky,
    required this.onSettingsChanged,
    this.noteRepository,
    this.audioCoordinator,
    this.syncSettings,
    this.backupService,
    this.onOpenQuickNote,
    this.externalTaskId,
    this.externalTaskRequestId,
  });

  final TaskWriteCoordinator coordinator;
  final DateTime Function() clock;
  final OnboardingSettings settings;
  final Future<void> Function() onShowSticky;
  final Future<void> Function(OnboardingSettings settings) onSettingsChanged;
  final NoteRepository? noteRepository;
  final AudioCoordinator? audioCoordinator;
  final SyncSettingsController? syncSettings;
  final VaultBackupService? backupService;
  final Future<void> Function()? onOpenQuickNote;
  final String? externalTaskId;
  final String? externalTaskRequestId;

  @override
  ConsumerState<Phase2Workspace> createState() => _Phase2WorkspaceState();
}

final class _Phase2WorkspaceState extends ConsumerState<Phase2Workspace> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  @override
  void didUpdateWidget(covariant Phase2Workspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalTaskId != null &&
        widget.externalTaskRequestId != oldWidget.externalTaskRequestId) {
      unawaited(_openExternalTask(widget.externalTaskId!));
    }
  }

  Future<void> _openExternalTask(String id) async {
    final tasks = await widget.coordinator.tasks.all();
    final task = tasks.where((candidate) => candidate.id == id).firstOrNull;
    if (task == null || !mounted) return;
    ref.read(selectedTaskProvider.notifier).select(task.id);
    ref.read(taskEditorProvider.notifier).edit(task);
  }

  @override
  Widget build(BuildContext context) {
    final destination = ref.watch(navigationProvider);
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _CreateTaskIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
            _CreateProjectIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _SearchIntent(),
        SingleActivator(LogicalKeyboardKey.digit1, control: true):
            _NavigateIntent(WorkspaceDestination.today),
        SingleActivator(LogicalKeyboardKey.digit2, control: true):
            _NavigateIntent(WorkspaceDestination.upcoming),
        SingleActivator(LogicalKeyboardKey.digit3, control: true):
            _NavigateIntent(WorkspaceDestination.projects),
        SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true):
            _StickyIntent(),
        SingleActivator(LogicalKeyboardKey.enter, control: true):
            _CompleteSelectedIntent(),
        SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _EditSelectedIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _TrashSelectedIntent(),
        SingleActivator(LogicalKeyboardKey.f2): _HierarchyActionIntent(
          'rename',
        ),
        SingleActivator(LogicalKeyboardKey.keyM, alt: true):
            _HierarchyActionIntent('move'),
        SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
            _HierarchyActionIntent('up'),
        SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
            _HierarchyActionIntent('down'),
        SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
      },
      child: Actions(
        actions: {
          _CreateTaskIntent: CallbackAction<_CreateTaskIntent>(
            onInvoke: (_) {
              if (!_editingText) unawaited(_showTaskEditor());
              return null;
            },
          ),
          _CreateProjectIntent: CallbackAction<_CreateProjectIntent>(
            onInvoke: (_) {
              if (!_editingText) unawaited(_showProjectCreator());
              return null;
            },
          ),
          _SearchIntent: CallbackAction<_SearchIntent>(
            onInvoke: (_) {
              _searchFocus.requestFocus();
              return null;
            },
          ),
          _NavigateIntent: CallbackAction<_NavigateIntent>(
            onInvoke: (intent) {
              if (!_editingText) {
                ref
                    .read(navigationProvider.notifier)
                    .select(intent.destination);
              }
              return null;
            },
          ),
          _StickyIntent: CallbackAction<_StickyIntent>(
            onInvoke: (_) {
              if (!_editingText) unawaited(widget.onShowSticky());
              return null;
            },
          ),
          _CompleteSelectedIntent: CallbackAction<_CompleteSelectedIntent>(
            onInvoke: (_) {
              if (!_editingText) {
                unawaited(
                  _withSelectedTask(
                    (task) => task.isCompleted
                        ? widget.coordinator.tasks.reopen(
                            task.id,
                            revision: task.revision,
                          )
                        : widget.coordinator.tasks.complete(
                            task.id,
                            revision: task.revision,
                          ),
                  ),
                );
              }
              return null;
            },
          ),
          _EditSelectedIntent: CallbackAction<_EditSelectedIntent>(
            onInvoke: (_) {
              if (!_editingText) {
                unawaited(_withSelectedTask(_showTaskEditor));
              }
              return null;
            },
          ),
          _TrashSelectedIntent: CallbackAction<_TrashSelectedIntent>(
            onInvoke: (_) {
              if (!_editingText) {
                unawaited(
                  _withSelectedTask(
                    (task) => widget.coordinator.tasks.trash(
                      task.id,
                      revision: task.revision,
                    ),
                  ),
                );
              }
              return null;
            },
          ),
          _HierarchyActionIntent: CallbackAction<_HierarchyActionIntent>(
            onInvoke: (intent) {
              if (!_editingText &&
                  destination == WorkspaceDestination.projects) {
                unawaited(_runHierarchyShortcut(intent.action));
              }
              return null;
            },
          ),
          _EscapeIntent: CallbackAction<_EscapeIntent>(
            onInvoke: (_) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                FocusManager.instance.primaryFocus?.unfocus();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  extended: MediaQuery.sizeOf(context).width >= 700,
                  selectedIndex: destination.index,
                  onDestinationSelected: (index) => ref
                      .read(navigationProvider.notifier)
                      .select(WorkspaceDestination.values[index]),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: IconButton(
                      tooltip: AppLocalizations.of(context).showSticky,
                      onPressed: widget.onShowSticky,
                      icon: const Icon(Icons.picture_in_picture_alt),
                    ),
                  ),
                  destinations: _destinations(context),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      _SearchBar(
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 250),
                            () => ref
                                .read(searchFilterProvider.notifier)
                                .setQuery(value),
                          );
                          setState(() {});
                        },
                      ),
                      Expanded(
                        child: _search.text.trim().isNotEmpty
                            ? _SearchResults(
                                onEdit: _showTaskEditor,
                                onClear: () {
                                  _search.clear();
                                  ref
                                      .read(searchFilterProvider.notifier)
                                      .clear();
                                  setState(() {});
                                },
                              )
                            : _page(destination),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton:
                destination == WorkspaceDestination.settings ||
                    destination == WorkspaceDestination.trash
                ? null
                : SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: _showTaskEditor,
                      icon: const Icon(Icons.add),
                      label: Text(AppLocalizations.of(context).quickAdd),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  List<NavigationRailDestination> _destinations(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      NavigationRailDestination(
        icon: const Icon(Icons.today_outlined),
        selectedIcon: const Icon(Icons.today),
        label: Text(l10n.today),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.calendar_month_outlined),
        selectedIcon: const Icon(Icons.calendar_month),
        label: Text(l10n.upcoming),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.account_tree_outlined),
        selectedIcon: const Icon(Icons.account_tree),
        label: Text(l10n.projects),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.note_outlined),
        selectedIcon: const Icon(Icons.note),
        label: Text(l10n.notes),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.graphic_eq),
        selectedIcon: const Icon(Icons.graphic_eq),
        label: Text(l10n.audio),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.task_alt_outlined),
        selectedIcon: const Icon(Icons.task_alt),
        label: Text(l10n.completed),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.archive_outlined),
        selectedIcon: const Icon(Icons.archive),
        label: Text(l10n.archive),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.delete_outline),
        selectedIcon: const Icon(Icons.delete),
        label: Text(l10n.trash),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(l10n.settings),
      ),
    ];
  }

  Widget _page(WorkspaceDestination destination) => switch (destination) {
    WorkspaceDestination.today => _TodayPage(
      now: widget.clock(),
      onEdit: _showTaskEditor,
    ),
    WorkspaceDestination.upcoming => _UpcomingPage(
      now: widget.clock(),
      onEdit: _showTaskEditor,
    ),
    WorkspaceDestination.projects => _ProjectsPage(
      onCreate: _showProjectCreator,
      onEditTask: _showTaskEditor,
      onAddNote: widget.noteRepository == null
          ? null
          : (projectId) async {
              await widget.noteRepository!.create(
                title: AppLocalizations.of(context).newNote,
                projectNodeId: projectId,
              );
              ref
                  .read(navigationProvider.notifier)
                  .select(WorkspaceDestination.notes);
            },
    ),
    WorkspaceDestination.notes =>
      widget.noteRepository == null
          ? Center(child: Text(AppLocalizations.of(context).vaultUnavailable))
          : NotesPage(
              repository: widget.noteRepository!,
              onOpenQuickNote: widget.onOpenQuickNote ?? () async {},
              projects: widget.coordinator.projects.watchActive(),
            ),
    WorkspaceDestination.audio =>
      widget.audioCoordinator == null
          ? Center(child: Text(AppLocalizations.of(context).vaultUnavailable))
          : AudioPage(
              coordinator: widget.audioCoordinator!,
              projects: widget.coordinator.projects.watchActive(),
            ),
    WorkspaceDestination.completed => _LifecyclePage(
      title: AppLocalizations.of(context).completed,
      archived: false,
      onEdit: _showTaskEditor,
    ),
    WorkspaceDestination.archive => _LifecyclePage(
      title: AppLocalizations.of(context).archive,
      archived: true,
      onEdit: _showTaskEditor,
    ),
    WorkspaceDestination.trash => _TrashPage(onEdit: _showTaskEditor),
    WorkspaceDestination.settings => _SettingsPage(
      settings: widget.settings,
      onChanged: widget.onSettingsChanged,
      syncSettings: widget.syncSettings,
      backupService: widget.backupService,
    ),
  };

  Future<void> _withSelectedTask(
    Future<Object?> Function(Task task) action,
  ) async {
    final id = ref.read(selectedTaskProvider);
    if (id == null) return;
    final task = await widget.coordinator.tasks.byId(id);
    if (task == null) return;
    try {
      await action(task);
    } on TaskMutationException catch (error) {
      if (mounted) _showTypedError(error);
    }
  }

  Future<void> _runHierarchyShortcut(String action) async {
    final id = ref.read(selectedProjectProvider);
    if (id == null) return;
    final nodes = await widget.coordinator.projects.all();
    final node = nodes.where((candidate) => candidate.id == id).firstOrNull;
    if (node == null || !mounted) return;
    await _ProjectsPage._nodeAction(context, ref, node, nodes, action);
  }

  void _showTypedError(TaskMutationException error) =>
      _showErrorSnack(context, error);

  Future<void> _showTaskEditor([Task? task]) async {
    final allNodes = await widget.coordinator.projects.all();
    final activeNodes = allNodes
        .where(
          (node) =>
              node.deletedAt == null &&
              node.archivedAt == null &&
              node.type != ProjectNodeType.workspace,
        )
        .toList();
    final allTasks = (await widget.coordinator.tasks.all())
        .where((candidate) => candidate.id != task?.id)
        .toList();
    final activeParents = allTasks
        .where(
          (candidate) =>
              candidate.deletedAt == null && candidate.archivedAt == null,
        )
        .toList();
    final tags = await widget.coordinator.tags.all();
    if (!mounted) return;
    final title = TextEditingController(text: task?.title);
    final description = TextEditingController(text: task?.description);
    final start = TextEditingController(
      text: task?.startAt?.toIso8601String().split('T').first,
    );
    final due = TextEditingController(
      text: task?.dueAt?.toIso8601String().split('T').first,
    );
    final reminder = TextEditingController(
      text: task?.reminderAt?.toIso8601String().split('T').first,
    );
    final recurrence = TextEditingController(text: task?.recurrenceRule);
    // Priority is intentionally not exposed in the UI; existing values are
    // carried through unchanged.
    final priority = task?.priority ?? TaskPriority.none;
    var status = task?.status ?? TaskStatus.open;
    var projectNodeId = task?.projectNodeId;
    var parentTaskId = task?.parentTaskId;
    final currentProject = projectNodeId == null
        ? null
        : allNodes.where((node) => node.id == projectNodeId).firstOrNull;
    final projectChoices = [
      ...activeNodes,
      if (currentProject != null &&
          !activeNodes.any((node) => node.id == currentProject.id))
        currentProject,
    ];
    if (projectNodeId != null &&
        !projectChoices.any((node) => node.id == projectNodeId)) {
      projectNodeId = null;
    }
    final currentParent = parentTaskId == null
        ? null
        : allTasks
              .where((candidate) => candidate.id == parentTaskId)
              .firstOrNull;
    final parentChoices = [
      ...activeParents,
      if (currentParent != null &&
          !activeParents.any((candidate) => candidate.id == currentParent.id))
        currentParent,
    ];
    if (parentTaskId != null &&
        !parentChoices.any((candidate) => candidate.id == parentTaskId)) {
      parentTaskId = null;
    }
    var pinned = task?.isPinned ?? false;
    final selectedTags = <String>{...?task?.tagIds};
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(AppLocalizations.of(context).taskTitle),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: title,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).taskTitle,
                      ),
                    ),
                    TextField(
                      controller: description,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).description,
                      ),
                    ),
                    DropdownButtonFormField<TaskStatus>(
                      initialValue: status,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).status,
                      ),
                      items: TaskStatus.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(taskStatusLabel(context, value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => status = value!),
                    ),
                    DropdownButtonFormField<String?>(
                      initialValue: projectNodeId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).projectList,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(AppLocalizations.of(context).noProject),
                        ),
                        for (final node in projectChoices)
                          DropdownMenuItem<String?>(
                            value: node.id,
                            child: Text(
                              node.archivedAt != null || node.deletedAt != null
                                  ? '${node.name} (unavailable)'
                                  : node.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => projectNodeId = value),
                    ),
                    DropdownButtonFormField<String?>(
                      initialValue: parentTaskId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).parentTask,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(AppLocalizations.of(context).noParent),
                        ),
                        for (final candidate in parentChoices)
                          DropdownMenuItem<String?>(
                            value: candidate.id,
                            child: Text(
                              candidate.archivedAt != null ||
                                      candidate.deletedAt != null
                                  ? '${candidate.title} (unavailable)'
                                  : candidate.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => parentTaskId = value),
                    ),
                    TextField(
                      controller: start,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).startDate,
                      ),
                    ),
                    TextField(
                      controller: due,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).dueDate,
                      ),
                    ),
                    TextField(
                      controller: reminder,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).reminderDate,
                      ),
                    ),
                    TextField(
                      controller: recurrence,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).recurrence,
                      ),
                    ),
                    SwitchListTile(
                      value: pinned,
                      onChanged: (value) =>
                          setDialogState(() => pinned = value),
                      title: Text(AppLocalizations.of(context).pinTask),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(AppLocalizations.of(context).tags),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final tag in tags)
                          FilterChip(
                            label: Text(tag.name),
                            selected: selectedTags.contains(tag.id),
                            onSelected: (selected) => setDialogState(() {
                              if (selected) {
                                selectedTags.add(tag.id);
                              } else {
                                selectedTags.remove(tag.id);
                              }
                            }),
                          ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final accepted = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(AppLocalizations.of(context).createTag),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: InputDecoration(
                                labelText: AppLocalizations.of(context).name,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(
                                  AppLocalizations.of(context).cancel,
                                ),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(AppLocalizations.of(context).save),
                              ),
                            ],
                          ),
                        );
                        if (accepted == true) {
                          try {
                            final created = await widget.coordinator.tags
                                .create(controller.text);
                            setDialogState(() {
                              tags.add(created);
                              selectedTags.add(created.id);
                            });
                          } on TaskMutationException catch (error) {
                            if (context.mounted) {
                              _showErrorSnack(context, error);
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.new_label_outlined),
                      label: Text(AppLocalizations.of(context).createTag),
                    ),
                    if (task != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(AppLocalizations.of(context).subtasks),
                          ),
                          IconButton(
                            tooltip: AppLocalizations.of(context).add,
                            onPressed: () => _showSubtaskCreator(task),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      for (final child in allTasks.where(
                        (candidate) => candidate.parentTaskId == task.id,
                      ))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.subdirectory_arrow_right),
                          title: Text(child.title),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppLocalizations.of(context).save),
              ),
            ],
          ),
        ),
      );
      if (result != true || !mounted) return;
      final startAt = start.text.trim().isEmpty
          ? null
          : DateTime.parse(start.text.trim());
      final dueAt = due.text.trim().isEmpty
          ? null
          : DateTime.parse(due.text.trim());
      final reminderAt = reminder.text.trim().isEmpty
          ? null
          : DateTime.parse(reminder.text.trim());
      Task.validateDates(
        startAt: startAt,
        dueAt: dueAt,
        reminderAt: reminderAt,
      );
      if (task == null) {
        var created = await widget.coordinator.tasks.create(
          title: title.text,
          description: description.text,
          projectNodeId: projectNodeId ?? ref.read(selectedProjectProvider),
          parentTaskId: parentTaskId,
          startAt: startAt,
          dueAt: dueAt,
          reminderAt: reminderAt,
          recurrenceRule: recurrence.text,
          priority: priority,
          isPinned: pinned,
        );
        if (status == TaskStatus.completed) {
          created = await widget.coordinator.tasks.complete(
            created.id,
            revision: created.revision,
          );
        } else if (status != TaskStatus.open) {
          created = await widget.coordinator.tasks.update(
            created.copyWith(
              status: status,
              completedAt: status == TaskStatus.cancelled
                  ? widget.clock()
                  : null,
            ),
            expectedRevision: created.revision,
          );
        }
        for (final tagId in selectedTags) {
          created = await widget.coordinator.tasks.assignTag(created.id, tagId);
        }
      } else {
        var updated = await widget.coordinator.tasks.update(
          task.copyWith(
            title: title.text,
            description: description.text,
            parentTaskId: parentTaskId,
            clearParent: parentTaskId == null,
            projectNodeId: projectNodeId,
            clearProject: projectNodeId == null,
            startAt: startAt,
            clearStart: startAt == null,
            dueAt: dueAt,
            clearDue: dueAt == null,
            reminderAt: reminderAt,
            clearReminder: reminderAt == null,
            recurrenceRule: recurrence.text.trim(),
            priority: priority,
            status: status == TaskStatus.completed ? task.status : status,
            completedAt: status == TaskStatus.cancelled
                ? task.completedAt ?? widget.clock()
                : task.completedAt,
            isPinned: pinned,
          ),
          expectedRevision: task.revision,
        );
        if (status == TaskStatus.completed && !updated.isCompleted) {
          updated = await widget.coordinator.tasks.complete(
            updated.id,
            revision: updated.revision,
          );
        }
        for (final tagId in selectedTags.difference(updated.tagIds)) {
          updated = await widget.coordinator.tasks.assignTag(updated.id, tagId);
        }
        for (final tagId in updated.tagIds.difference(selectedTags)) {
          updated = await widget.coordinator.tasks.unassignTag(
            updated.id,
            tagId,
          );
        }
      }
    } on TaskMutationException catch (error) {
      if (mounted) _showTypedError(error);
    } on FormatException {
      if (mounted) {
        _showTypedError(
          const TaskMutationException(
            TaskMutationErrorCode.invalidDates,
            'Invalid date',
          ),
        );
      }
    } finally {
      // Wait for dialog route teardown before disposing controllers.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      title.dispose();
      description.dispose();
      start.dispose();
      due.dispose();
      reminder.dispose();
      recurrence.dispose();
    }
  }

  Future<void> _showSubtaskCreator(Task parent) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).subtasks),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).taskTitle,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context).add),
          ),
        ],
      ),
    );
    if (accepted == true) {
      try {
        await widget.coordinator.tasks.create(
          title: controller.text,
          parentTaskId: parent.id,
          projectNodeId: parent.projectNodeId,
        );
      } on TaskMutationException catch (error) {
        if (mounted) _showTypedError(error);
      }
    }
  }

  Future<void> _showProjectCreator() async {
    final controller = TextEditingController();
    var type = ProjectNodeType.project;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(AppLocalizations.of(context).newProject),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context).name,
                ),
              ),
              DropdownButton<ProjectNodeType>(
                value: type,
                isExpanded: true,
                items: ProjectNodeType.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => type = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).save),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        final nodes = await widget.coordinator.projects.all();
        String? parentId = ref.read(selectedProjectProvider);
        if (type == ProjectNodeType.workspace) parentId = null;
        if (type == ProjectNodeType.project && parentId == null) {
          parentId = nodes
              .where((node) => node.type == ProjectNodeType.workspace)
              .firstOrNull
              ?.id;
          if (parentId == null) {
            final root = await widget.coordinator.projects.create(
              type: ProjectNodeType.workspace,
              name: 'ephtodo',
            );
            parentId = root.id;
          }
        }
        await widget.coordinator.projects.create(
          type: type,
          name: controller.text,
          parentId: parentId,
        );
      } on TaskMutationException catch (error) {
        if (mounted) _showTypedError(error);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }
}

final class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: AppLocalizations.of(context).search,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.clear),
              ),
      ),
    ),
  );
}

final class _TodayPage extends ConsumerWidget {
  const _TodayPage({required this.now, required this.onEdit});
  final DateTime now;
  final Future<void> Function([Task? task]) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todayTasksProvider);
    return tasks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          Center(child: Text(AppLocalizations.of(context).invalidEntry)),
      data: (items) {
        if (items.isEmpty) {
          return Center(child: Text(AppLocalizations.of(context).nothingToday));
        }
        final engine = const HorizonEngine();
        final overdue = items
            .where((task) => engine.classify(task, now) == TaskHorizon.overdue)
            .toList();
        final today = items
            .where(
              (task) =>
                  engine.classify(task, now) == TaskHorizon.today &&
                  !task.isCompleted &&
                  !task.isPinned,
            )
            .toList();
        final pinned = items
            .where((task) => task.isPinned && !task.isCompleted)
            .toList();
        final completed = items.where((task) => task.isCompleted).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
          children: [
            _TaskSection(
              title: AppLocalizations.of(context).overdue,
              tasks: overdue,
              onEdit: onEdit,
            ),
            _TaskSection(
              title: AppLocalizations.of(context).dueToday,
              tasks: today,
              onEdit: onEdit,
            ),
            _TaskSection(
              title: AppLocalizations.of(context).pinned,
              tasks: pinned,
              onEdit: onEdit,
            ),
            ExpansionTile(
              title: Text(AppLocalizations.of(context).completedToday),
              children: [
                for (final task in completed)
                  _TaskTile(task: task, onEdit: onEdit),
              ],
            ),
          ],
        );
      },
    );
  }
}

final class _UpcomingPage extends ConsumerWidget {
  const _UpcomingPage({required this.now, required this.onEdit});
  final DateTime now;
  final Future<void> Function([Task? task]) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(upcomingTasksProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(AppLocalizations.of(context).invalidEntry)),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Text(AppLocalizations.of(context).nothingUpcoming),
            );
          }
          final engine = const HorizonEngine();
          final labels = {
            'tomorrow': AppLocalizations.of(context).tomorrow,
            'thisWeek': AppLocalizations.of(context).thisWeek,
            'nextWeek': AppLocalizations.of(context).nextWeek,
            'laterThisMonth': AppLocalizations.of(context).laterThisMonth,
            'future': AppLocalizations.of(context).future,
            'someday': AppLocalizations.of(context).someday,
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
            children: [
              for (final group in labels.entries)
                _TaskSection(
                  title: group.value,
                  tasks: tasks
                      .where(
                        (task) => engine.upcomingGroup(task, now) == group.key,
                      )
                      .toList(),
                  onEdit: onEdit,
                ),
            ],
          );
        },
      );
}

final class _ProjectsPage extends ConsumerWidget {
  const _ProjectsPage({
    required this.onCreate,
    required this.onEditTask,
    this.onAddNote,
  });
  final Future<void> Function() onCreate;
  final Future<void> Function([Task? task]) onEditTask;
  final Future<void> Function(String projectId)? onAddNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodes = ref.watch(projectListProvider);
    final selected = ref.watch(selectedProjectProvider);
    return Row(
      children: [
        SizedBox(
          width: 300,
          child: Column(
            children: [
              ListTile(
                title: Text(AppLocalizations.of(context).projects),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: AppLocalizations.of(context).restoreHierarchy,
                      onPressed: () => _showLifecycleNodes(context, ref),
                      icon: const Icon(Icons.restore),
                    ),
                    IconButton(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: nodes.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: Text(AppLocalizations.of(context).invalidEntry),
                  ),
                  data: (items) => ListView(
                    children: [
                      for (final node in _flatten(items))
                        Padding(
                          padding: EdgeInsets.only(left: node.$2 * 16.0),
                          child: Builder(
                            builder: (tileContext) => GestureDetector(
                              onSecondaryTapDown: (details) async {
                                final action = await showMenu<String>(
                                  context: tileContext,
                                  position: RelativeRect.fromLTRB(
                                    details.globalPosition.dx,
                                    details.globalPosition.dy,
                                    details.globalPosition.dx,
                                    details.globalPosition.dy,
                                  ),
                                  items: [
                                    PopupMenuItem(
                                      value: 'addTask',
                                      child: Text(
                                        AppLocalizations.of(context).addTask,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'addNote',
                                      child: Text(
                                        AppLocalizations.of(context).addNote,
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    PopupMenuItem(
                                      value: 'rename',
                                      child: Text(
                                        AppLocalizations.of(context).rename,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'move',
                                      child: Text(
                                        AppLocalizations.of(context).move,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'up',
                                      child: Text(
                                        AppLocalizations.of(context).moveUp,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'down',
                                      child: Text(
                                        AppLocalizations.of(context).moveDown,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'archive',
                                      child: Text(
                                        AppLocalizations.of(context).archive,
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'trash',
                                      child: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).sendToTrash,
                                      ),
                                    ),
                                  ],
                                );
                                if (action == null || !context.mounted) return;
                                if (action == 'addTask') {
                                  ref
                                      .read(selectedProjectProvider.notifier)
                                      .select(node.$1.id);
                                  await onEditTask();
                                  return;
                                }
                                if (action == 'addNote') {
                                  ref
                                      .read(selectedProjectProvider.notifier)
                                      .select(node.$1.id);
                                  if (onAddNote != null) {
                                    await onAddNote!(node.$1.id);
                                  } else {
                                    ref
                                        .read(navigationProvider.notifier)
                                        .select(WorkspaceDestination.notes);
                                  }
                                  return;
                                }
                                await _nodeAction(
                                  context,
                                  ref,
                                  node.$1,
                                  items,
                                  action,
                                );
                              },
                              child: ListTile(
                                selected: selected == node.$1.id,
                                leading: Icon(_nodeIcon(node.$1.type)),
                                title: Text(node.$1.name),
                                onTap: () => ref
                                    .read(selectedProjectProvider.notifier)
                                    .select(node.$1.id),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? Center(child: Text(AppLocalizations.of(context).nothingHere))
              : _ProjectTasks(projectId: selected, onEdit: onEditTask),
        ),
      ],
    );
  }

  static List<(ProjectNode, int)> _flatten(List<ProjectNode> nodes) {
    final result = <(ProjectNode, int)>[];
    void append(String? parentId, int depth) {
      for (final node
          in nodes.where((node) => node.parentId == parentId).toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder))) {
        result.add((node, depth));
        append(node.id, depth + 1);
      }
    }

    append(null, 0);
    return result;
  }

  static IconData _nodeIcon(ProjectNodeType type) => switch (type) {
    ProjectNodeType.workspace => Icons.workspaces_outline,
    ProjectNodeType.project => Icons.folder_special_outlined,
    ProjectNodeType.folder => Icons.folder_outlined,
    ProjectNodeType.taskList => Icons.list_alt,
  };

  static Future<void> _nodeAction(
    BuildContext context,
    WidgetRef ref,
    ProjectNode node,
    List<ProjectNode> nodes,
    String action,
  ) async {
    final repository = ref.read(taskCoordinatorProvider).projects;
    try {
      if (action == 'rename') {
        final controller = TextEditingController(text: node.name);
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(AppLocalizations.of(context).rename),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context).name,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(AppLocalizations.of(context).cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(AppLocalizations.of(context).save),
              ),
            ],
          ),
        );
        if (accepted == true) {
          await repository.rename(
            node.id,
            controller.text,
            revision: node.revision,
          );
        }
      } else if (action == 'move') {
        String? target = node.parentId;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text(AppLocalizations.of(context).moveTo),
              content: DropdownButton<String?>(
                value: target,
                isExpanded: true,
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(AppLocalizations.of(context).noParent),
                  ),
                  for (final candidate in nodes.where(
                    (candidate) => candidate.id != node.id,
                  ))
                    DropdownMenuItem<String?>(
                      value: candidate.id,
                      child: Text(candidate.name),
                    ),
                ],
                onChanged: (value) => setState(() => target = value),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(AppLocalizations.of(context).cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(AppLocalizations.of(context).move),
                ),
              ],
            ),
          ),
        );
        if (accepted == true) {
          await repository.move(
            node.id,
            target,
            sortOrder: node.sortOrder,
            revision: node.revision,
          );
        }
      } else if (action == 'up' || action == 'down') {
        final siblings =
            nodes
                .where((candidate) => candidate.parentId == node.parentId)
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        final index = siblings.indexWhere(
          (candidate) => candidate.id == node.id,
        );
        final otherIndex = action == 'up' ? index - 1 : index + 1;
        if (index >= 0 && otherIndex >= 0 && otherIndex < siblings.length) {
          final other = siblings[otherIndex];
          await repository.move(
            node.id,
            node.parentId,
            sortOrder: action == 'up'
                ? other.sortOrder - 0.5
                : other.sortOrder + 0.5,
            revision: node.revision,
          );
        }
      } else if (action == 'archive') {
        await repository.archive(node.id, revision: node.revision);
      } else if (action == 'trash') {
        await repository.trash(node.id, revision: node.revision);
      }
    } on TaskMutationException catch (error) {
      if (context.mounted) _showErrorSnack(context, error);
    }
  }

  static Future<void> _showLifecycleNodes(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final repository = ref.read(taskCoordinatorProvider).projects;
    final nodes = await repository.all();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).restoreHierarchy),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final node in nodes.where(
                (node) => node.archivedAt != null || node.deletedAt != null,
              ))
                ListTile(
                  title: Text(node.name),
                  subtitle: Text(
                    node.deletedAt != null
                        ? AppLocalizations.of(context).trashedProjects
                        : AppLocalizations.of(context).archivedProjects,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      if (node.deletedAt != null) {
                        await repository.restoreFromTrash(
                          node.id,
                          revision: node.revision,
                        );
                      } else {
                        await repository.restore(
                          node.id,
                          revision: node.revision,
                        );
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    },
                    child: Text(AppLocalizations.of(context).restore),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ProjectTasks extends ConsumerWidget {
  const _ProjectTasks({required this.projectId, required this.onEdit});
  final String projectId;
  final Future<void> Function([Task? task]) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(projectTasksProvider(projectId))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const SizedBox.shrink(),
          data: (tasks) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (final task in tasks) _TaskTile(task: task, onEdit: onEdit),
            ],
          ),
        );
  }
}

final class _LifecyclePage extends ConsumerWidget {
  const _LifecyclePage({
    required this.title,
    required this.archived,
    required this.onEdit,
  });
  final String title;
  final bool archived;
  final Future<void> Function([Task? task]) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(archived ? archivedTasksProvider : completedTasksProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(AppLocalizations.of(context).invalidEntry)),
        data: (tasks) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            if (tasks.isEmpty) Text(AppLocalizations.of(context).nothingHere),
            for (final task in tasks) _TaskTile(task: task, onEdit: onEdit),
          ],
        ),
      );
}

final class _TrashPage extends ConsumerWidget {
  const _TrashPage({required this.onEdit});
  final Future<void> Function([Task? task]) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trashedProjects =
        ref.watch(trashedProjectsProvider).value ?? const <ProjectNode>[];
    return ref
        .watch(trashedTasksProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const SizedBox.shrink(),
          data: (tasks) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
            Row(
              children: [
                Text(
                  AppLocalizations.of(context).trash,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: tasks.isEmpty
                      ? null
                      : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              content: Text(
                                AppLocalizations.of(context).confirmEmptyTrash,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(
                                    AppLocalizations.of(context).cancel,
                                  ),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).deletePermanently,
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            for (final task in tasks) {
                              await ref
                                  .read(taskCoordinatorProvider)
                                  .tasks
                                  .permanentlyDelete(task.id);
                            }
                          }
                        },
                  child: Text(AppLocalizations.of(context).emptyTrash),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (tasks.isEmpty && trashedProjects.isEmpty)
              Text(AppLocalizations.of(context).nothingHere),
            for (final task in tasks) _TaskTile(task: task, onEdit: onEdit),
            if (trashedProjects.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context).trashedProjects,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final node in trashedProjects)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder_delete_outlined),
                    title: Text(node.name),
                    trailing: TextButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(taskCoordinatorProvider)
                              .projects
                              .restoreFromTrash(
                                node.id,
                                revision: node.revision,
                              );
                        } on TaskMutationException catch (error) {
                          if (context.mounted) {
                            _showErrorSnack(context, error);
                          }
                        }
                      },
                      child: Text(AppLocalizations.of(context).restore),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
  }
}

final class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.onEdit, required this.onClear});
  final Future<void> Function([Task? task]) onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchFilterProvider).query.trim().toLowerCase();
    final projects =
        (ref.watch(projectListProvider).value ?? const <ProjectNode>[])
            .where((node) => node.name.toLowerCase().contains(query))
            .toList();
    return ref
        .watch(searchResultsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const SizedBox.shrink(),
          data: (tasks) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (projects.isNotEmpty) ...[
                Text(
                  AppLocalizations.of(context).searchProjectsSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final project in projects)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(project.name),
                    onTap: () {
                      ref
                          .read(selectedProjectProvider.notifier)
                          .select(project.id);
                      ref
                          .read(navigationProvider.notifier)
                          .select(WorkspaceDestination.projects);
                      onClear();
                    },
                  ),
                const SizedBox(height: 16),
              ],
              if (tasks.isNotEmpty)
                Text(
                  AppLocalizations.of(context).searchTasksSection,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              for (final task in tasks) _TaskTile(task: task, onEdit: onEdit),
              if (projects.isEmpty && tasks.isEmpty)
                Text(AppLocalizations.of(context).nothingHere),
            ],
          ),
        );
  }
}

final class _TaskSection extends StatelessWidget {
  const _TaskSection({
    required this.title,
    required this.tasks,
    required this.onEdit,
  });
  final String title;
  final List<Task> tasks;
  final Future<void> Function([Task? task]) onEdit;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 6),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final task in tasks) _TaskTile(task: task, onEdit: onEdit),
      ],
    );
  }
}

final class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task, required this.onEdit});
  final Task task;
  final Future<void> Function([Task? task]) onEdit;

  Future<bool> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final permanent = task.deletedAt != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.areYouSure),
        content: Text(
          permanent ? l10n.confirmDeleteForever : l10n.confirmTrashTask,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(permanent ? l10n.deletePermanently : l10n.sendToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final repository = ref.read(taskCoordinatorProvider).tasks;
    try {
      if (permanent) {
        await repository.permanentlyDelete(task.id);
      } else {
        await repository.trash(task.id, revision: task.revision);
      }
      return true;
    } on TaskMutationException catch (error) {
      if (context.mounted) _showErrorSnack(context, error);
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueLabel = task.dueAt?.toLocal().toIso8601String().split('T').first;
    final projectName = task.projectNodeId == null
        ? null
        : ref.watch(projectNamesProvider).value?[task.projectNodeId];
    final subtitle = [?dueLabel, ?projectName].join(' · ');
    final card = Card(
      child: ListTile(
        selected: ref.watch(selectedTaskProvider) == task.id,
        leading: Checkbox(
          value: task.isCompleted,
          semanticLabel: 'Complete ${task.title}',
          onChanged: (_) async {
            final repository = ref.read(taskCoordinatorProvider).tasks;
            if (task.isCompleted) {
              await repository.reopen(task.id, revision: task.revision);
            } else {
              await repository.complete(task.id, revision: task.revision);
            }
          },
        ),
        title: Text(task.title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: PopupMenuButton<String>(
          tooltip: AppLocalizations.of(context).edit,
          onSelected: (action) async {
            final repository = ref.read(taskCoordinatorProvider).tasks;
            if (action == 'edit') {
              await onEdit(task);
            } else if (action == 'archive') {
              await repository.archive(task.id, revision: task.revision);
            } else if (action == 'restore') {
              if (task.deletedAt != null) {
                await repository.restoreFromTrash(
                  task.id,
                  revision: task.revision,
                );
              } else {
                await repository.restore(task.id, revision: task.revision);
              }
            } else if (action == 'trash') {
              await repository.trash(task.id, revision: task.revision);
            } else if (action == 'delete') {
              await repository.permanentlyDelete(task.id);
            }
          },
          itemBuilder: (context) => [
            if (task.archivedAt == null && task.deletedAt == null)
              PopupMenuItem(
                value: 'edit',
                child: Text(AppLocalizations.of(context).edit),
              ),
            if (task.archivedAt == null && task.deletedAt == null)
              PopupMenuItem(
                value: 'archive',
                child: Text(AppLocalizations.of(context).archive),
              ),
            if (task.archivedAt != null || task.deletedAt != null)
              PopupMenuItem(
                value: 'restore',
                child: Text(AppLocalizations.of(context).restore),
              ),
            if (task.deletedAt == null)
              PopupMenuItem(
                value: 'trash',
                child: Text(AppLocalizations.of(context).sendToTrash),
              ),
            if (task.deletedAt != null)
              PopupMenuItem(
                value: 'delete',
                child: Text(AppLocalizations.of(context).deletePermanently),
              ),
          ],
        ),
        onTap: () => ref.read(selectedTaskProvider.notifier).select(task.id),
      ),
    );
    return Dismissible(
      key: ValueKey('task-dismiss-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.error,
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      confirmDismiss: (_) => _confirmAndDelete(context, ref),
      child: card,
    );
  }
}

final class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.settings,
    required this.onChanged,
    required this.syncSettings,
    required this.backupService,
  });
  final OnboardingSettings settings;
  final Future<void> Function(OnboardingSettings settings) onChanged;
  final SyncSettingsController? syncSettings;
  final VaultBackupService? backupService;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

final class _SettingsPageState extends State<_SettingsPage> {
  late OnboardingSettings settings = widget.settings;
  _SettingsSection section = _SettingsSection.general;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 248,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              AppLocalizations.of(context).settings,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            _SettingsDestination(
              icon: Icons.tune_rounded,
              label: AppLocalizations.of(context).generalSection,
              selected: section == _SettingsSection.general,
              onTap: () => setState(() => section = _SettingsSection.general),
            ),
            const SizedBox(height: 4),
            _SettingsDestination(
              icon: Icons.archive_outlined,
              label: AppLocalizations.of(context).backupSection,
              selected: section == _SettingsSection.backup,
              onTap: () => setState(() => section = _SettingsSection.backup),
            ),
            const SizedBox(height: 4),
            _SettingsDestination(
              icon: Icons.sync_lock_rounded,
              label: AppLocalizations.of(context).syncSection,
              selected: section == _SettingsSection.sync,
              onTap: () => setState(() => section = _SettingsSection.sync),
            ),
          ],
        ),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: switch (section) {
          _SettingsSection.general => _GeneralSettings(
            settings: settings,
            onChanged: (value) async {
              settings = value;
              setState(() {});
              await widget.onChanged(value);
            },
          ),
          _SettingsSection.backup =>
            widget.backupService == null
                ? Center(
                    child: Text(
                      AppLocalizations.of(context).openVaultForBackups,
                    ),
                  )
                : BackupRecoveryPage(service: widget.backupService!),
          _SettingsSection.sync =>
            widget.syncSettings == null
                ? Center(child: Text(AppLocalizations.of(context).syncDisabled))
                : SyncSettingsPage(controller: widget.syncSettings!),
        },
      ),
    ],
  );
}

enum _SettingsSection { general, backup, sync }

final class _SettingsDestination extends StatelessWidget {
  const _SettingsDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? Theme.of(context).colorScheme.primary : null,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

final class _GeneralSettings extends StatelessWidget {
  const _GeneralSettings({required this.settings, required this.onChanged});

  final OnboardingSettings settings;
  final Future<void> Function(OnboardingSettings) onChanged;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(32, 28, 40, 40),
    children: [
      Text(
        AppLocalizations.of(context).generalSection,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 4),
      Text(AppLocalizations.of(context).generalSectionHint),
      const SizedBox(height: 28),
      Text(
        AppLocalizations.of(context).language,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        AppLocalizations.of(context).languageHint,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'system',
              label: Text(AppLocalizations.of(context).languageSystem),
            ),
            ButtonSegment(
              value: 'en',
              label: Text(AppLocalizations.of(context).languageEnglish),
            ),
            ButtonSegment(
              value: 'tr',
              label: Text(AppLocalizations.of(context).languageTurkish),
            ),
          ],
          selected: {
            OnboardingSettings.supportedLocaleCodes.contains(
                  settings.localeCode,
                )
                ? settings.localeCode
                : 'system',
          },
          onSelectionChanged: (values) =>
              onChanged(settings.copyWith(localeCode: values.single)),
        ),
      ),
      const SizedBox(height: 24),
      Text(
        AppLocalizations.of(context).themeSection,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        AppLocalizations.of(context).themeSectionHint,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: AppThemeId.values
            .map(
              (value) => ChoiceChip(
                label: Text(themeLabel(context, value)),
                selected: settings.themeId == value.name,
                onSelected: (_) =>
                    onChanged(settings.copyWith(themeId: value.name)),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 24),
      Text(
        AppLocalizations.of(context).trashRetentionSection,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<TrashRetentionPolicy>(
          segments: TrashRetentionPolicy.values
              .map(
                (value) => ButtonSegment(
                  value: value,
                  label: Text(trashRetentionLabel(context, value)),
                ),
              )
              .toList(),
          selected: {settings.trashRetention},
          onSelectionChanged: (values) =>
              onChanged(settings.copyWith(trashRetention: values.single)),
        ),
      ),
      const SizedBox(height: 28),
      const Divider(),
      const SizedBox(height: 18),
      Text(AppLocalizations.of(context).weekStartsMonday),
      const SizedBox(height: 8),
      Text(AppLocalizations.of(context).audioPlaybackLimits),
    ],
  );
}

final class _CreateTaskIntent extends Intent {
  const _CreateTaskIntent();
}

final class _CreateProjectIntent extends Intent {
  const _CreateProjectIntent();
}

final class _SearchIntent extends Intent {
  const _SearchIntent();
}

final class _NavigateIntent extends Intent {
  const _NavigateIntent(this.destination);
  final WorkspaceDestination destination;
}

final class _StickyIntent extends Intent {
  const _StickyIntent();
}

final class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

final class _CompleteSelectedIntent extends Intent {
  const _CompleteSelectedIntent();
}

final class _EditSelectedIntent extends Intent {
  const _EditSelectedIntent();
}

final class _TrashSelectedIntent extends Intent {
  const _TrashSelectedIntent();
}

final class _HierarchyActionIntent extends Intent {
  const _HierarchyActionIntent(this.action);
  final String action;
}

void _showErrorSnack(BuildContext context, TaskMutationException error) {
  final l10n = AppLocalizations.of(context);
  final message = switch (error.code) {
    TaskMutationErrorCode.invalidHierarchy => l10n.invalidHierarchyError,
    TaskMutationErrorCode.invalidDates => l10n.invalidDatesError,
    TaskMutationErrorCode.missingNode => l10n.missingNodeError,
    TaskMutationErrorCode.staleRevision => l10n.staleRevisionError,
    TaskMutationErrorCode.duplicateTag => l10n.duplicateTagError,
    TaskMutationErrorCode.retention => l10n.retentionError,
    _ => l10n.databaseError,
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
