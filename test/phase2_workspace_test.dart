import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart' hide ProjectNode, Task;
import 'package:ephtodo/core/database/preferences_repository.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/features/tasks/application/task_providers.dart';
import 'package:ephtodo/features/tasks/data/drift_task_repositories.dart';
import 'package:ephtodo/features/tasks/domain/task_models.dart';
import 'package:ephtodo/features/tasks/presentation/workspace.dart';
import 'package:ephtodo/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftTaskWriteCoordinator coordinator;
  var completionPolicy = CompletionPolicy.keepCompleted;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    coordinator = DriftTaskWriteCoordinator(
      database: database,
      clock: FixedClock(DateTime.utc(2026, 7, 19, 12)),
      deviceId: 'fictional-device',
      completionPolicy: () => completionPolicy,
      retentionPolicy: () => TrashRetentionPolicy.thirtyDays,
    );
    completionPolicy = CompletionPolicy.keepCompleted;
  });

  tearDown(() async {
    await coordinator.dispose();
    await database.close();
  });

  testWidgets('English workspace exposes navigation and quick add', (
    tester,
  ) async {
    await tester.pumpWidget(_app(coordinator, const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Projects'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
    expect(find.text('Nothing scheduled for today.'), findsOneWidget);

    await tester.tap(find.text('Quick add'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Task title'), findsWidgets);
    await tester.enterText(find.byType(TextField).at(1), 'Fictional task');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await coordinator.tasks.all()).single.title, 'Fictional task');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('Turkish key workspace screen is localized', (tester) async {
    await tester.pumpWidget(_app(coordinator, const Locale('tr')));
    await tester.pumpAndSettle();
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.text('Yaklaşan'), findsOneWidget);
    expect(find.text('Projeler'), findsOneWidget);
    expect(find.text('Hızlı ekle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('Today sections render and checkbox completes without archive', (
    tester,
  ) async {
    completionPolicy = CompletionPolicy.keepCompleted;
    final overdue = await coordinator.tasks.create(
      title: 'Overdue item',
      dueAt: DateTime(2026, 7, 18),
    );
    final today = await coordinator.tasks.create(
      title: 'Today item',
      dueAt: DateTime(2026, 7, 19),
      isPinned: true,
    );
    await tester.pumpWidget(
      _app(coordinator, const Locale('en'), todayTasks: [overdue, today]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Completed today'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    final completed = (await coordinator.tasks.byId(today.id))!;
    expect(completed.isCompleted, isTrue);
    expect(completed.archivedAt, isNull);
    expect(completed.deletedAt, isNull);
    await _dispose(tester);
  });

  testWidgets('Upcoming renders every deterministic group', (tester) async {
    final tasks = [
      _task('Tomorrow task', DateTime(2026, 7, 2)),
      _task('Week task', DateTime(2026, 7, 3)),
      _task('Next task', DateTime(2026, 7, 6)),
      _task('Month task', DateTime(2026, 7, 20)),
      _task('Future task', DateTime(2026, 9, 1)),
    ];
    await tester.pumpWidget(
      _app(
        coordinator,
        const Locale('en'),
        upcomingTasks: tasks,
        now: DateTime(2026, 7),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    for (final label in [
      'Tomorrow',
      'This Week',
      'Next Week',
      'Later This Month',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Future'), findsWidgets);
    await _dispose(tester);
  });

  testWidgets('project tree navigates and exposes hierarchy actions', (
    tester,
  ) async {
    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Fictional workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Fictional project',
      parentId: workspace.id,
    );
    await tester.pumpWidget(
      _app(coordinator, const Locale('en'), projects: [workspace, project]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Fictional project'), findsOneWidget);
    await tester.tap(find.text('Fictional project'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Fictional project'),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Move'), findsOneWidget);
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);
    expect(find.text('Add note'), findsOneWidget);
    expect(find.text('Add task'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _dispose(tester);
  });

  testWidgets('editor exposes required fields and validates dates', (
    tester,
  ) async {
    await tester.pumpWidget(_app(coordinator, const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick add'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    for (final label in [
      'Task title',
      'Description',
      'Status',
      'Project or task list',
      'Parent task',
      'Start date (YYYY-MM-DD)',
      'Due date (YYYY-MM-DD)',
      'Reminder date (YYYY-MM-DD)',
      'Recurrence rule',
      'Pin task',
      'Tags',
    ]) {
      expect(find.text(label), findsWidgets);
    }
    await tester.enterText(find.byType(TextField).at(1), 'Invalid dates');
    await tester.enterText(find.byType(TextField).at(3), '2026-07-21');
    await tester.enterText(find.byType(TextField).at(4), '2026-07-20');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Check the start, due, and reminder dates.'),
      findsOneWidget,
    );
    await _dispose(tester);
  });

  testWidgets('editor opens when the assigned project is archived', (
    tester,
  ) async {
    final workspace = await coordinator.projects.create(
      type: ProjectNodeType.workspace,
      name: 'Fictional workspace',
    );
    final project = await coordinator.projects.create(
      type: ProjectNodeType.project,
      name: 'Archived project',
      parentId: workspace.id,
    );
    final task = await coordinator.tasks.create(
      title: 'Orphaned assignment',
      projectNodeId: project.id,
      dueAt: DateTime(2026, 7, 19),
    );
    await coordinator.projects.archive(project.id, revision: project.revision);

    await tester.pumpWidget(
      _app(coordinator, const Locale('en'), todayTasks: [task]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    // The name appears both in the tile subtitle and in the editor's
    // project dropdown ("Archived project (unavailable)").
    expect(find.text('Archived project (unavailable)'), findsOneWidget);
    expect(find.text('Orphaned assignment'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _dispose(tester);
  });

  testWidgets('Archive and Trash restore and Empty Trash confirms', (
    tester,
  ) async {
    final original = await coordinator.tasks.create(title: 'Lifecycle item');
    final archived = await coordinator.tasks.archive(
      original.id,
      revision: original.revision,
    );
    await tester.pumpWidget(
      _app(coordinator, const Locale('en'), archivedTasks: [archived]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.archive_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();
    final restored = (await coordinator.tasks.byId(original.id))!;
    final trashed = await coordinator.tasks.trash(
      restored.id,
      revision: restored.revision,
    );
    await _dispose(tester);

    await tester.pumpWidget(
      _app(coordinator, const Locale('en'), trashedTasks: [trashed]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();
    final restoredTrash = (await coordinator.tasks.byId(original.id))!;
    final trashedAgain = await coordinator.tasks.trash(
      restoredTrash.id,
      revision: restoredTrash.revision,
    );
    await _dispose(tester);

    await tester.pumpWidget(
      _app(coordinator, const Locale('en'), trashedTasks: [trashedAgain]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty Trash'));
    await tester.pumpAndSettle();
    expect(
      find.text('Permanently delete everything in Trash?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete permanently').last);
    await tester.pumpAndSettle();
    expect(await coordinator.tasks.byId(original.id), isNull);
    await _dispose(tester);
  });

  testWidgets('search and selected-task keyboard actions work', (
    tester,
  ) async {
    final task = await coordinator.tasks.create(
      title: 'Searchable item',
      dueAt: DateTime(2026, 7, 19),
    );
    await tester.pumpWidget(
      _app(
        coordinator,
        const Locale('en'),
        todayTasks: [task],
        searchTasks: [task],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Searchable');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Searchable item'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Searchable item'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Recurrence rule'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect((await coordinator.tasks.byId(task.id))!.isCompleted, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect((await coordinator.tasks.byId(task.id))!.deletedAt, isNotNull);
    await _dispose(tester);
  });
}

Widget _app(
  DriftTaskWriteCoordinator coordinator,
  Locale locale, {
  List<Task> todayTasks = const [],
  List<Task> upcomingTasks = const [],
  List<ProjectNode> projects = const [],
  List<Task> archivedTasks = const [],
  List<Task> trashedTasks = const [],
  List<Task> searchTasks = const [],
  DateTime? now,
}) => ProviderScope(
  overrides: [
    taskCoordinatorProvider.overrideWithValue(coordinator),
    todayTasksProvider.overrideWith((ref) => Stream.value(todayTasks)),
    upcomingTasksProvider.overrideWith((ref) => Stream.value(upcomingTasks)),
    projectListProvider.overrideWith((ref) => Stream.value(projects)),
    projectTasksProvider.overrideWith((ref, id) => Stream.value(const [])),
    archivedTasksProvider.overrideWith((ref) => Stream.value(archivedTasks)),
    trashedTasksProvider.overrideWith((ref) => Stream.value(trashedTasks)),
    searchResultsProvider.overrideWith((ref) => Stream.value(searchTasks)),
    trashedProjectsProvider.overrideWith(
      (ref) => Stream.value(const <ProjectNode>[]),
    ),
    projectNamesProvider.overrideWith(
      (ref) => Stream.value({
        for (final node in projects) node.id: node.name,
      }),
    ),
  ],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Phase2Workspace(
      coordinator: coordinator,
      clock: () => now ?? DateTime(2026, 7, 19, 12),
      settings: const OnboardingSettings(completed: true),
      onShowSticky: () async {},
      onSettingsChanged: (_) async {},
    ),
  ),
);

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump();
}

Task _task(String title, DateTime due) => Task(
  id: title,
  title: title,
  status: TaskStatus.open,
  priority: TaskPriority.none,
  dueAt: due,
  sortOrder: 1,
  isPinned: false,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  revision: 1,
  originatingDeviceId: 'fictional',
);
