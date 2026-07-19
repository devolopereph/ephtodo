import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/backup/vault_backup_service.dart';
import '../core/database/preferences_repository.dart';
import '../core/foundation/foundation.dart';
import '../core/security/password_hasher.dart';
import '../core/security/secret_store.dart';
import '../core/security/tls_material.dart';
import '../core/theme/app_theme.dart';
import '../core/windowing/multi_window_adapter.dart';
import '../core/windowing/window_protocol.dart';
import '../features/tasks/application/task_providers.dart';
import '../features/tasks/application/task_repositories.dart';
import '../features/tasks/data/drift_task_repositories.dart';
import '../features/tasks/domain/task_models.dart';
import '../features/tasks/domain/task_rules.dart';
import '../features/tasks/presentation/workspace.dart';
import '../features/audio/application/audio_coordinator.dart';
import '../features/audio/data/windows_audio_services.dart';
import '../features/notes/data/drift_note_repository.dart';
import '../features/notes/domain/note_models.dart';
import '../features/sticky_window/domain/sticky_source.dart';
import '../features/sync/application/sync_auth_service.dart';
import '../features/sync/application/sync_settings_controller.dart';
import '../features/sync/data/drift_sync_coordinator.dart';
import '../features/sync/server/sync_server.dart';
import '../l10n/app_localizations.dart';
import 'bootstrap.dart';

/// Maps the persisted language preference to an explicit [Locale], or null
/// to follow the operating system locale.
Locale? localeForCode(String code) =>
    code == 'system' ? null : Locale(code);

final class EphtodoApp extends StatefulWidget {
  const EphtodoApp({super.key, required this.bootstrap});
  final AppBootstrapState bootstrap;

  @override
  State<EphtodoApp> createState() => _EphtodoAppState();
}

final class _EphtodoAppState extends State<EphtodoApp> {
  late AppBootstrapState _bootstrap = widget.bootstrap;
  OnboardingSettings _settings = const OnboardingSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final database = _bootstrap.database;
    if (database != null) {
      _settings = await OnboardingRepository(
        DriftPreferencesRepository(database, _bootstrap.clock),
      ).load();
    } else {
      final support = await _bootstrap.appSupport.read();
      _settings = _settings.copyWith(
        step: (support['pendingOnboardingStep'] as num?)?.toInt() ?? 0,
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(OnboardingSettings value) async {
    _settings = value;
    final database = _bootstrap.database;
    if (database != null) {
      await OnboardingRepository(
        DriftPreferencesRepository(database, _bootstrap.clock),
      ).save(value);
    } else {
      final support = await _bootstrap.appSupport.read();
      await _bootstrap.appSupport.write({
        ...support,
        'pendingOnboardingStep': value.step,
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _selectVault() async {
    final parent = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose the parent for ephtodo-vault',
      lockParentWindow: true,
    );
    if (parent == null) return;
    final handle = await _bootstrap.vaultService.createInParent(parent);
    _bootstrap = _bootstrap.withVault(handle);
    final support = await _bootstrap.appSupport.read();
    support.remove('pendingOnboardingStep');
    await _bootstrap.appSupport.write({
      ...support,
      'lastVaultPath': handle.root,
    });
    await _save(_settings.copyWith(step: 2));
  }

  AppThemeId get _theme => AppThemeId.values.firstWhere(
    (value) => value.name == _settings.themeId,
    orElse: () => AppThemeId.obsidianBlack,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: localeForCode(_settings.localeCode),
      theme: buildAppTheme(_theme),
      builder: (context, child) {
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        return Theme(
          data: buildAppTheme(_theme, reducedMotion: reduceMotion),
          child: child ?? const SizedBox.shrink(),
        );
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: _loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _settings.completed
          ? WorkspaceShell(
              bootstrap: _bootstrap,
              settings: _settings,
              onSettingsChanged: _save,
            )
          : OnboardingShell(
              settings: _settings,
              vaultReady: _bootstrap.vault != null,
              onChanged: _save,
              onSelectVault: _selectVault,
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_bootstrap.database?.close());
    super.dispose();
  }
}

final class OnboardingShell extends StatelessWidget {
  const OnboardingShell({
    super.key,
    required this.settings,
    required this.vaultReady,
    required this.onChanged,
    required this.onSelectVault,
  });

  final OnboardingSettings settings;
  final bool vaultReady;
  final Future<void> Function(OnboardingSettings) onChanged;
  final Future<void> Function() onSelectVault;

  static const _titles = [
    'A calm place for what matters',
    'Choose your portable vault',
    'Trash retention',
    'Choose your workspace theme',
    'Local-network sync',
    'Shortcuts and sticky window',
    'Foundation ready',
  ];

  @override
  Widget build(BuildContext context) {
    final step = settings.step.clamp(0, 6);
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 720,
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Step ${step + 1} of 7'),
                  const SizedBox(height: 12),
                  Text(
                    _titles[step],
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  Flexible(
                    child: SingleChildScrollView(child: _body(context, step)),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (step > 0)
                        TextButton(
                          onPressed: () =>
                              onChanged(settings.copyWith(step: step - 1)),
                          child: const Text('Back'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: step == 1 && !vaultReady
                            ? onSelectVault
                            : () => onChanged(
                                settings.copyWith(
                                  step: step == 6 ? 6 : step + 1,
                                  completed: step == 6,
                                  // Completed tasks always stay in Completed.
                                  completionPolicy:
                                      CompletionPolicy.keepCompleted,
                                ),
                              ),
                        child: Text(
                          step == 1 && !vaultReady
                              ? 'Choose folder'
                              : step == 6
                              ? 'Open workspace'
                              : 'Continue',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, int step) => switch (step) {
    0 => const Text(
      'ephtodo keeps your work local and separates portable vault data '
      'from device-only window state.',
    ),
    1 => Text(
      vaultReady
          ? 'Vault selected and validated.'
          : 'Choose a parent folder. ephtodo creates ephtodo-vault safely.',
    ),
    2 => SegmentedButton<TrashRetentionPolicy>(
      segments: TrashRetentionPolicy.values
          .map(
            (value) => ButtonSegment(
              value: value,
              label: Text(trashRetentionLabel(context, value)),
            ),
          )
          .toList(),
      selected: {settings.trashRetention},
      onSelectionChanged: (choices) =>
          onChanged(settings.copyWith(trashRetention: choices.single)),
    ),
    3 => Wrap(
      spacing: 12,
      runSpacing: 12,
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
    4 => const ListTile(
      leading: Icon(Icons.security_outlined),
      title: Text('Local-network sync starts disabled'),
      subtitle: Text(
        'After onboarding, Settings lets you configure a password, verify '
        'the TLS fingerprint, and explicitly enable private-LAN access.',
      ),
    ),
    5 => const Text(
      'Use Ctrl+K for the future command palette. The companion sticky '
      'window can be shown from the workspace and hides instead of closing.',
    ),
    _ => const Text(
      'Your vault, preferences, theme, and Windows foundation are ready.',
    ),
  };
}

final class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.bootstrap,
    required this.settings,
    required this.onSettingsChanged,
  });
  final AppBootstrapState bootstrap;
  final OnboardingSettings settings;
  final Future<void> Function(OnboardingSettings) onSettingsChanged;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

final class _WorkspaceShellState extends State<WorkspaceShell>
    with WidgetsBindingObserver {
  MultiWindowCommandBus? _bus;
  StreamSubscription<TaskStateEvent>? _eventSubscription;
  late OnboardingSettings _settings = widget.settings;
  DriftTaskWriteCoordinator? _coordinator;
  DriftNoteRepository? _notes;
  AudioCoordinator? _audio;
  SyncSettingsController? _sync;
  VaultBackupService? _backups;
  DateRolloverService? _rollover;
  StickyPreferences _stickyPreferences = const StickyPreferences();
  var _snapshotSequence = 0;
  String? _externalTaskId;
  String? _externalTaskRequestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final database = widget.bootstrap.database;
    final vault = widget.bootstrap.vault;
    if (database != null && vault != null) {
      _coordinator = DriftTaskWriteCoordinator(
        database: database,
        clock: widget.bootstrap.clock,
        deviceId: vault.manifest.id,
        // Completed tasks always stay in Completed — never auto-archive/trash.
        completionPolicy: () => CompletionPolicy.keepCompleted,
        retentionPolicy: () => _settings.trashRetention,
      );
      _notes = DriftNoteRepository(
        database: database,
        vault: vault,
        vaultService: widget.bootstrap.vaultService,
        clock: widget.bootstrap.clock,
        deviceId: vault.manifest.id,
      );
      _audio = AudioCoordinator(
        database: database,
        vault: vault,
        vaultService: widget.bootstrap.vaultService,
        clock: widget.bootstrap.clock,
        deviceId: vault.manifest.id,
        recorder: RecordAudioRecorderService(),
        playback: WinmmAudioPlaybackService(),
        files: const LocalAudioFileService(),
      );
      _backups = VaultBackupService(
        database,
        vault,
        widget.bootstrap.vaultService,
        widget.bootstrap.clock,
      );
      const secrets = WindowsSecretStore();
      final syncCoordinator = DriftSyncWriteCoordinator(
        database,
        widget.bootstrap.clock,
      );
      final tls = TlsMaterialManager(secrets, widget.bootstrap.clock);
      final auth = SyncAuthService(
        secrets,
        const Argon2idPasswordHasher(),
        widget.bootstrap.clock,
        syncCoordinator,
      );
      final server = SyncServer(
        auth,
        syncCoordinator,
        tls,
        widget.bootstrap.clock,
      );
      _sync = SyncSettingsController(
        widget.bootstrap.appSupport,
        secrets,
        tls,
        auth,
        syncCoordinator,
        server,
      );
      unawaited(_sync!.initialize());
      unawaited(_notes!.recover());
      unawaited(_audio!.recover());
      if (Platform.environment['EPHTODO_AUDIO_SMOKE_ROOT'] != null) {
        unawaited(_runAudioSmoke());
      }
      unawaited(
        widget.bootstrap.stickyPreferencesStore.load().then((value) {
          _stickyPreferences = value;
        }),
      );
      _rollover = DateRolloverService(
        clock: widget.bootstrap.clock,
        onRollover: () {
          if (mounted) setState(() {});
          unawaited(_broadcastSnapshot());
        },
      )..start();
      _eventSubscription = _coordinator!.events.listen((_) {
        _rollover?.taskDatesChanged();
        unawaited(_broadcastSnapshot());
      });
      unawaited(_coordinator!.tasks.purgeEligibleTrash());
    }
    _bus = MultiWindowCommandBus(handler: _handleCommand);
  }

  Future<Map<String, Object?>> _handleCommand(WindowEnvelope message) async {
    try {
      final extra = await _handleMessage(message);
      return {
        ...?extra,
        'ok': true,
        'requestId': message.requestId,
        'protocolVersion': windowProtocolVersion,
      };
    } on TaskMutationException catch (error) {
      return {
        'ok': false,
        'requestId': message.requestId,
        'protocolVersion': windowProtocolVersion,
        'error': {'code': error.code.name, 'message': error.message},
      };
    } on NoteException catch (error) {
      return {
        'ok': false,
        'requestId': message.requestId,
        'protocolVersion': windowProtocolVersion,
        'error': {'code': error.code.name, 'message': error.message},
      };
    } on Object {
      return {
        'ok': false,
        'requestId': message.requestId,
        'protocolVersion': windowProtocolVersion,
        'error': {
          'code': WindowErrorCode.internal.name,
          'message': 'The command could not be completed.',
        },
      };
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _rollover?.resume();
      unawaited(_coordinator?.tasks.purgeEligibleTrash());
    }
  }

  Future<Map<String, Object?>?> _handleMessage(WindowEnvelope message) async {
    if (message.type == WindowMessageType.lifecycleHealth &&
        message.payload['action'] == 'hideShow' &&
        (Platform.environment['EPHTODO_PHASE2_SMOKE_ROOT'] != null ||
            Platform.environment['EPHTODO_PHASE34_SMOKE_ROOT'] != null)) {
      await widget.bootstrap.windowCoordinator.hideSticky();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await widget.bootstrap.windowCoordinator.showSticky(
        await widget.bootstrap.geometryStore.load(),
      );
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.lifecycleReady &&
        message.payload['role'] == 'quickNote') {
      await widget.bootstrap.windowCoordinator.broadcast(
        WindowEnvelope(
          type: WindowMessageType.vaultState,
          requestId: message.requestId,
          sourceWindowId: 'main',
          payload: {'available': widget.bootstrap.vault != null},
          timestamp: widget.bootstrap.clock.now(),
        ),
      );
      await _broadcastLocale();
      await _broadcastTheme();
      // The quick note needs the project list (delivered with the task
      // snapshot) for its project picker.
      await _broadcastSnapshot();
      if (Platform.environment['EPHTODO_PHASE34_SMOKE_STAGE'] == '2') {
        final existing = await _notes?.all() ?? const <Note>[];
        if (existing.isNotEmpty) {
          final latest = existing.reduce(
            (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
          );
          await _broadcastNote(
            await _notes!.open(latest.id),
            message.requestId,
            0,
          );
        }
      }
    } else if (message.type == WindowMessageType.lifecycleReady ||
        message.type == WindowMessageType.lifecycleHealth ||
        message.type == WindowMessageType.taskSnapshotRequest) {
      await widget.bootstrap.windowCoordinator.broadcast(
        WindowEnvelope(
          type: WindowMessageType.stickyState,
          requestId: message.requestId,
          sourceWindowId: 'main',
          payload: _stickyPreferences.toJson(),
          timestamp: widget.bootstrap.clock.now(),
        ),
      );
      await _broadcastLocale();
      await _broadcastTheme();
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.taskCreate) {
      await _coordinator?.tasks.create(
        title: message.payload['title']! as String,
        projectNodeId:
            _stickyPreferences.source == StickySourceType.project ||
                _stickyPreferences.source == StickySourceType.folderOrList
            ? _stickyPreferences.sourceId
            : null,
        isPinned: _stickyPreferences.source == StickySourceType.pinned,
        dueAt: _stickyPreferences.source == StickySourceType.tomorrow
            ? DateTime(
                widget.bootstrap.clock.now().toLocal().year,
                widget.bootstrap.clock.now().toLocal().month,
                widget.bootstrap.clock.now().toLocal().day + 1,
              )
            : DateTime(
                widget.bootstrap.clock.now().toLocal().year,
                widget.bootstrap.clock.now().toLocal().month,
                widget.bootstrap.clock.now().toLocal().day,
              ),
      );
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.projectCreate) {
      final coordinator = _coordinator;
      if (coordinator == null) {
        throw const TaskMutationException(
          TaskMutationErrorCode.vault,
          'The vault is unavailable.',
        );
      }
      final nodes = await coordinator.projects.all();
      var rootId = nodes
          .where(
            (node) =>
                node.type == ProjectNodeType.workspace &&
                node.deletedAt == null &&
                node.archivedAt == null,
          )
          .firstOrNull
          ?.id;
      rootId ??= (await coordinator.projects.create(
        type: ProjectNodeType.workspace,
        name: 'ephtodo',
      )).id;
      final project = await coordinator.projects.create(
        type: ProjectNodeType.project,
        name: message.payload['name']! as String,
        parentId: rootId,
      );
      await _broadcastSnapshot();
      return {'projectId': project.id};
    } else if (message.type == WindowMessageType.taskComplete) {
      final id = message.payload['id']! as String;
      final current = await _coordinator?.tasks.byId(id);
      if (current != null) {
        await _coordinator!.tasks.complete(id, revision: current.revision);
      }
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.taskReopen) {
      final id = message.payload['id']! as String;
      final current = await _coordinator?.tasks.byId(id);
      if (current != null) {
        await _coordinator!.tasks.reopen(id, revision: current.revision);
      }
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.taskTrash) {
      // Sticky snapshots can lag behind the main revision after checkbox
      // toggles; always trash against the live row so "Move to Trash" works.
      final id = message.payload['id']! as String;
      final current = await _coordinator?.tasks.byId(id);
      if (current != null && current.deletedAt == null) {
        await _coordinator!.tasks.trash(id, revision: current.revision);
      }
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.taskOpen) {
      _externalTaskId = message.payload['id']! as String;
      _externalTaskRequestId = message.requestId;
      if (mounted) setState(() {});
      await widget.bootstrap.windowCoordinator.showMain();
    } else if (message.type == WindowMessageType.openMain) {
      await widget.bootstrap.windowCoordinator.showMain();
    } else if (message.type == WindowMessageType.openQuickNote) {
      await _showQuickNote();
    } else if (message.type == WindowMessageType.stickySourceChanged) {
      _stickyPreferences = StickyPreferences(
        source: StickySourceType.values.byName(
          message.payload['source']! as String,
        ),
        sourceId: message.payload['sourceId'] as String?,
        opacity: _stickyPreferences.opacity,
        compact: _stickyPreferences.compact,
        showMetadata: _stickyPreferences.showMetadata,
        collapseCompleted: _stickyPreferences.collapseCompleted,
        borderless: _stickyPreferences.borderless,
      );
      await widget.bootstrap.stickyPreferencesStore.save(_stickyPreferences);
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.stickyPreferencesChanged) {
      _stickyPreferences = StickyPreferences.fromJson(message.payload);
      await widget.bootstrap.stickyPreferencesStore.save(_stickyPreferences);
    } else if (message.type == WindowMessageType.stickyRefresh) {
      await _broadcastSnapshot();
    } else if (message.type == WindowMessageType.noteCreate) {
      final document = await _notes!.create(
        title: message.payload['title']! as String,
        body: message.payload['body']! as String,
        projectNodeId: message.payload['projectNodeId'] as String?,
        linkedTaskId: message.payload['linkedTaskId'] as String?,
      );
      await _broadcastNote(
        document,
        message.requestId,
        message.payload['saveGeneration'] as int? ?? 0,
      );
    } else if (message.type == WindowMessageType.noteOpen) {
      await _broadcastNote(
        await _notes!.open(message.payload['id']! as String),
        message.requestId,
        0,
      );
    } else if (message.type == WindowMessageType.noteUpdate ||
        message.type == WindowMessageType.noteAutosave ||
        message.type == WindowMessageType.noteManualSave) {
      final ack = await _notes!.save(
        NoteSaveRequest(
          noteId: message.payload['id']! as String,
          title: message.payload['title']! as String,
          body: message.payload['body']! as String,
          expectedRevision: message.payload['revision']! as int,
          requestId: message.requestId,
          saveGeneration: message.payload['saveGeneration']! as int,
          projectNodeId: message.payload['projectNodeId'] as String?,
          linkedTaskId: message.payload['linkedTaskId'] as String?,
        ),
      );
      await widget.bootstrap.windowCoordinator.broadcast(
        WindowEnvelope(
          type: WindowMessageType.noteSaveAck,
          requestId: message.requestId,
          sourceWindowId: 'main',
          payload: {
            'id': ack.note.id,
            'revision': ack.note.revision,
            'saveGeneration': ack.saveGeneration,
          },
          timestamp: widget.bootstrap.clock.now(),
        ),
      );
    } else if (message.type == WindowMessageType.noteRename) {
      final note = await _notes!.rename(
        message.payload['id']! as String,
        message.payload['title']! as String,
        revision: message.payload['revision']! as int,
      );
      await _broadcastNote(await _notes!.open(note.id), message.requestId, 0);
    } else if (message.type == WindowMessageType.noteArchive) {
      final note = await _notes!.archive(
        message.payload['id']! as String,
        revision: message.payload['revision']! as int,
      );
      await _broadcastNote(await _notes!.open(note.id), message.requestId, 0);
    } else if (message.type == WindowMessageType.noteTrash) {
      final note = await _notes!.trash(
        message.payload['id']! as String,
        revision: message.payload['revision']! as int,
      );
      await _broadcastNote(await _notes!.open(note.id), message.requestId, 0);
    } else if (message.type == WindowMessageType.noteRestore) {
      final id = message.payload['id']! as String;
      final current = (await _notes!.all()).firstWhere((note) => note.id == id);
      final note = current.deletedAt != null
          ? await _notes!.restoreFromTrash(
              id,
              revision: message.payload['revision']! as int,
            )
          : await _notes!.restore(
              id,
              revision: message.payload['revision']! as int,
            );
      await _broadcastNote(await _notes!.open(note.id), message.requestId, 0);
    } else if (message.type == WindowMessageType.geometryChanged) {
      final store = message.payload['role'] == 'quickNote'
          ? widget.bootstrap.quickNoteGeometryStore
          : widget.bootstrap.geometryStore;
      await store.save(WindowGeometry.fromJson(message.payload));
    } else if (message.type == WindowMessageType.stickyState &&
        message.payload['visible'] == false) {
      await widget.bootstrap.windowCoordinator.hideSticky();
    } else {
      throw const TaskMutationException(
        TaskMutationErrorCode.unsupported,
        'This sticky command is not supported.',
      );
    }
    return null;
  }

  Future<void> _broadcastSnapshot() async {
    final coordinator = _coordinator;
    final vault = widget.bootstrap.vault;
    if (coordinator == null || vault == null) return;
    // Trash/archive completion policies move a task out of the active set
    // the moment it is completed. Include those rows so the sticky window
    // can keep showing today's completions struck through instead of
    // making them vanish without feedback.
    final tasks = await coordinator.tasks
        .watch(
          const TaskSearchFilter(
            includeCompleted: true,
            includeArchived: true,
            includeTrash: true,
          ),
        )
        .first;
    final now = widget.bootstrap.clock.now();
    final localNow = now.toLocal();
    bool completedToday(Task task) {
      final completed = task.completedAt?.toLocal();
      return completed != null &&
          completed.year == localNow.year &&
          completed.month == localNow.month &&
          completed.day == localNow.day;
    }

    final todayTasks = tasks.where((task) {
      if ((task.deletedAt != null || task.archivedAt != null) &&
          !(task.isCompleted && completedToday(task))) {
        return false;
      }
      if (task.isCompleted && task.completedAt != null) {
        return switch (_stickyPreferences.source) {
          StickySourceType.today => completedToday(task),
          StickySourceType.project || StickySourceType.folderOrList =>
            task.projectNodeId == _stickyPreferences.sourceId,
          StickySourceType.pinned => task.isPinned,
          _ => false,
        };
      }
      return const StickySourceFilter().matches(task, _stickyPreferences, now);
    }).toList();
    final allNodes = await coordinator.projects.all();
    final projectNames = {for (final node in allNodes) node.id: node.name};
    final snapshot = StickyTaskSnapshot(
      sequence: ++_snapshotSequence,
      vaultId: vault.manifest.id,
      tasks: todayTasks
          .map(
            (task) => StickyTaskSnapshotItem(
              id: task.id,
              title: task.title,
              priority: task.priority.name,
              completed: task.isCompleted,
              due: task.dueAt?.toUtc().toIso8601String(),
              revision: task.revision,
              project: task.projectNodeId == null
                  ? null
                  : projectNames[task.projectNodeId],
            ),
          )
          .toList(),
    );
    final sources = allNodes
        .where(
          (node) =>
              node.archivedAt == null &&
              node.deletedAt == null &&
              node.type != ProjectNodeType.workspace,
        )
        .map(
          (node) => {'id': node.id, 'name': node.name, 'type': node.type.name},
        )
        .toList();
    await widget.bootstrap.windowCoordinator.broadcast(
      WindowEnvelope(
        type: WindowMessageType.taskSnapshot,
        requestId: const Uuid().v4(),
        sourceWindowId: 'main',
        payload: {...snapshot.toPayload(), 'sources': sources},
        timestamp: widget.bootstrap.clock.now(),
      ),
    );
  }

  Future<void> _runAudioSmoke() async {
    final root = Platform.environment['EPHTODO_AUDIO_SMOKE_ROOT']!;
    await File(
      '$root${Platform.pathSeparator}audio-smoke-started.json',
    ).writeAsString(
      jsonEncode({
        'workspaceReady': true,
        'databaseOpenCount': DatabaseOpenAudit.openCount,
      }),
    );
    try {
      await _audio!.start().timeout(const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _audio!.recorder.pause();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _audio!.recorder.resume();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final item = await _audio!.stop(title: 'Fictional WAV smoke');
      await _audio!.playback.playWav(_audio!.resolve(item.relativeFilePath));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _audio!.playback.stop();
      await File(
        '$root${Platform.pathSeparator}audio-smoke.json',
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'recorded': true,
          'pausedAndResumed': true,
          'playedThroughWinmm': true,
          'mimeType': item.mimeType,
          'fileSize': item.fileSize,
          'durationMs': item.durationMs,
          'revision': item.revision,
        }),
      );
    } on Object catch (error) {
      await File(
        '$root${Platform.pathSeparator}audio-smoke.json',
      ).writeAsString(
        jsonEncode({
          'recorded': false,
          'errorType': error.runtimeType.toString(),
        }),
      );
    }
  }

  Future<void> _showQuickNote() =>
      widget.bootstrap.windowCoordinator.showQuickNote(
        const WindowGeometry(x: 180, y: 140, width: 620, height: 640),
      );

  Future<void> _broadcastLocale() =>
      widget.bootstrap.windowCoordinator.broadcast(
        WindowEnvelope(
          type: WindowMessageType.localeChanged,
          requestId: const Uuid().v4(),
          sourceWindowId: 'main',
          payload: {'locale': _settings.localeCode},
          timestamp: widget.bootstrap.clock.now(),
        ),
      );

  Future<void> _broadcastTheme() =>
      widget.bootstrap.windowCoordinator.broadcast(
        WindowEnvelope(
          type: WindowMessageType.themeChanged,
          requestId: const Uuid().v4(),
          sourceWindowId: 'main',
          payload: {'themeId': _settings.themeId},
          timestamp: widget.bootstrap.clock.now(),
        ),
      );

  Future<void> _broadcastNote(
    NoteDocument document,
    String requestId,
    int saveGeneration,
  ) => widget.bootstrap.windowCoordinator.broadcast(
    WindowEnvelope(
      type: WindowMessageType.noteStateSnapshot,
      requestId: requestId,
      sourceWindowId: 'main',
      payload: {
        'id': document.note.id,
        'title': document.note.title,
        'body': document.body,
        'revision': document.note.revision,
        'projectNodeId': document.note.projectNodeId,
        'linkedTaskId': document.note.linkedTaskId,
        'saveGeneration': saveGeneration,
      },
      timestamp: widget.bootstrap.clock.now(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final coordinator = _coordinator;
    if (coordinator == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ProviderScope(
      overrides: [taskCoordinatorProvider.overrideWithValue(coordinator)],
      child: Phase2Workspace(
        coordinator: coordinator,
        clock: widget.bootstrap.clock.now,
        settings: _settings,
        noteRepository: _notes,
        audioCoordinator: _audio,
        syncSettings: _sync,
        backupService: _backups,
        onOpenQuickNote: _showQuickNote,
        externalTaskId: _externalTaskId,
        externalTaskRequestId: _externalTaskRequestId,
        onShowSticky: () async {
          await widget.bootstrap.windowCoordinator.showSticky(
            await widget.bootstrap.geometryStore.load(),
          );
          await _broadcastSnapshot();
        },
        onSettingsChanged: (settings) async {
          final localeChanged = settings.localeCode != _settings.localeCode;
          final themeChanged = settings.themeId != _settings.themeId;
          _settings = settings;
          await widget.onSettingsChanged(settings);
          if (localeChanged) await _broadcastLocale();
          if (themeChanged) await _broadcastTheme();
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rollover?.dispose();
    unawaited(_eventSubscription?.cancel());
    unawaited(_coordinator?.dispose());
    unawaited(_audio?.dispose());
    unawaited(_sync?.dispose());
    _bus?.dispose();
    super.dispose();
  }
}

final class StickyFoundationShell extends StatefulWidget {
  const StickyFoundationShell({
    super.key,
    required this.clock,
    this.onLocaleChanged,
    this.onThemeChanged,
  });
  final DateTime Function() clock;
  final void Function(String localeCode)? onLocaleChanged;
  final void Function(String themeId)? onThemeChanged;

  @override
  State<StickyFoundationShell> createState() => _StickyFoundationShellState();
}

final class _StickyFoundationShellState extends State<StickyFoundationShell> {
  late final MultiWindowCommandBus _bus;
  late final MultiWindowSecondaryClient _client;
  StreamSubscription<void>? _geometrySubscription;
  StreamSubscription<void>? _closeSubscription;
  StreamSubscription<WindowEnvelope>? _messageSubscription;
  final _title = TextEditingController();
  List<StickyTaskSnapshotItem> _tasks = const [];
  List<Map<String, Object?>> _sources = const [];
  final _snapshots = StreamController<StickyTaskSnapshot>.broadcast();
  StickyTaskSnapshot? _latestSnapshot;
  String _automationStep = 'notStarted';
  Object? _automationAck;
  StickyPreferences _preferences = const StickyPreferences();

  @override
  void initState() {
    super.initState();
    _bus = MultiWindowCommandBus();
    _client = MultiWindowSecondaryClient();
    _messageSubscription = _bus.messages.listen((message) {
      if (message.type == WindowMessageType.taskSnapshot) {
        final snapshot = StickyTaskSnapshot.fromPayload(message.payload);
        _latestSnapshot = snapshot;
        _snapshots.add(snapshot);
        final sources = message.payload['sources'];
        if (sources is List) {
          _sources = sources
              .whereType<Map>()
              .map((item) => item.cast<String, Object?>())
              .toList();
        }
        if (mounted) setState(() => _tasks = snapshot.tasks);
      } else if (message.type == WindowMessageType.stickyState) {
        _preferences = StickyPreferences.fromJson(message.payload);
        unawaited(_client.setOpacity(_preferences.safeOpacity));
        unawaited(_client.setBorderless(_preferences.borderless));
        if (mounted) setState(() {});
      } else if (message.type == WindowMessageType.localeChanged) {
        widget.onLocaleChanged?.call(message.payload['locale']! as String);
      } else if (message.type == WindowMessageType.themeChanged) {
        widget.onThemeChanged?.call(message.payload['themeId']! as String);
      }
    });
    _geometrySubscription = _client.geometryChanges.listen(
      (_) => unawaited(_sendGeometry()),
    );
    _closeSubscription = _client.closeRequests.listen(
      (_) => unawaited(_hide()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ready()));
  }

  Future<void> _ready() async {
    await _client.initializeSticky();
    final response = await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.lifecycleReady,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: const {'role': 'sticky', 'health': 'ready'},
        timestamp: widget.clock(),
      ),
    );
    if (response is Map && response['ok'] == true) {
      await _client.sendToMain(
        WindowEnvelope(
          type: WindowMessageType.taskSnapshotRequest,
          requestId: const Uuid().v4(),
          sourceWindowId: _client.windowId,
          payload: const {},
          timestamp: widget.clock(),
        ),
      );
      if (Platform.environment['EPHTODO_PHASE2_SMOKE_ROOT'] != null) {
        unawaited(
          _runAutomation(Platform.environment['EPHTODO_PHASE2_SMOKE_ROOT']!),
        );
      } else if (Platform.environment['EPHTODO_PHASE34_SMOKE_ROOT'] != null) {
        unawaited(
          _runAutomation(Platform.environment['EPHTODO_PHASE34_SMOKE_ROOT']!),
        );
      }
    }
  }

  Future<StickyTaskSnapshot> _waitForTask(
    bool Function(StickyTaskSnapshotItem task) matches,
  ) async {
    final current = _latestSnapshot;
    if (current != null && current.tasks.any(matches)) {
      return current;
    }
    final completer = Completer<StickyTaskSnapshot>();
    late final StreamSubscription<StickyTaskSnapshot> subscription;
    subscription = _snapshots.stream.listen((snapshot) {
      if (!completer.isCompleted && snapshot.tasks.any(matches)) {
        completer.complete(snapshot);
        unawaited(subscription.cancel());
      }
    });
    final afterSubscribe = _latestSnapshot;
    if (afterSubscribe != null && afterSubscribe.tasks.any(matches)) {
      completer.complete(afterSubscribe);
      await subscription.cancel();
    }
    return completer.future.timeout(const Duration(seconds: 20));
  }

  Future<void> _runAutomation(String root) async {
    try {
      await _runAutomationBody(root);
    } on Object catch (error) {
      await File('$root${Platform.pathSeparator}failure.json').writeAsString(
        jsonEncode({
          'engineRole': DatabaseOpenAudit.engineRole,
          'stickyDatabaseOpenCount': DatabaseOpenAudit.openCount,
          'errorType': error.runtimeType.toString(),
          'message': error.toString(),
          'step': _automationStep,
          'ack': _automationAck,
        }),
      );
    }
  }

  Future<void> _runAutomationBody(String root) async {
    final stage =
        int.tryParse(
          Platform.environment['EPHTODO_PHASE2_SMOKE_STAGE'] ??
              Platform.environment['EPHTODO_PHASE34_SMOKE_STAGE'] ??
              '',
        ) ??
        1;
    const title = 'Fictional sticky IPC task';
    Map<Object?, Object?>? createAck;
    Map<Object?, Object?>? completeAck;
    StickyTaskSnapshot snapshot;
    if (stage == 1) {
      _automationStep = 'sendingCreate';
      createAck =
          await _client.sendToMain(
                WindowEnvelope(
                  type: WindowMessageType.taskCreate,
                  requestId: const Uuid().v4(),
                  sourceWindowId: _client.windowId,
                  payload: const {'title': title},
                  timestamp: widget.clock(),
                ),
              )
              as Map<Object?, Object?>?;
      _automationAck = createAck;
      _automationStep = 'waitingCreatedSnapshot';
      snapshot = await _waitForTask((task) => task.title == title);
      final created = snapshot.tasks.firstWhere((task) => task.title == title);
      completeAck =
          await _client.sendToMain(
                WindowEnvelope(
                  type: WindowMessageType.taskComplete,
                  requestId: const Uuid().v4(),
                  sourceWindowId: _client.windowId,
                  payload: {'id': created.id, 'revision': created.revision},
                  timestamp: widget.clock(),
                ),
              )
              as Map<Object?, Object?>?;
      _automationAck = completeAck;
      if (completeAck?['ok'] != true) {
        throw StateError('Sticky completion command was rejected');
      }
      _automationStep = 'waitingCompletedSnapshot';
      snapshot = await _waitForTask(
        (task) => task.title == title && task.completed,
      );
    } else {
      _automationStep = 'waitingRestartSnapshot';
      snapshot = await _waitForTask(
        (task) => task.title == title && task.completed,
      );
    }
    final task = snapshot.tasks.firstWhere((task) => task.title == title);
    await _sendGeometry();
    _automationStep = 'hideShow';
    final hideShowAck =
        await _client.sendToMain(
              WindowEnvelope(
                type: WindowMessageType.lifecycleHealth,
                requestId: const Uuid().v4(),
                sourceWindowId: _client.windowId,
                payload: const {'action': 'hideShow'},
                timestamp: widget.clock(),
              ),
            )
            as Map<Object?, Object?>?;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final geometry = await _client.currentGeometry();
    final evidence = {
      'stage': stage,
      'protocolVersion': windowProtocolVersion,
      'engineRole': DatabaseOpenAudit.engineRole,
      'stickyDatabaseOpenCount': DatabaseOpenAudit.openCount,
      'createAcknowledged': createAck?['ok'] ?? stage == 2,
      'completeAcknowledged': completeAck?['ok'] ?? stage == 2,
      'snapshotReceived': true,
      'hideShowAcknowledged': hideShowAck?['ok'] == true,
      'persistedAfterRestart': stage == 2,
      'task': {
        'idPresent': task.id.isNotEmpty,
        'title': title,
        'completed': task.completed,
        'revision': task.revision,
      },
      'geometry': geometry.toJson(),
      'checkedAtUtc': DateTime.now().toUtc().toIso8601String(),
    };
    await File(
      '$root${Platform.pathSeparator}stage$stage.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
  }

  Future<void> _sendGeometry() async {
    final geometry = await _client.currentGeometry();
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.geometryChanged,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: geometry.toJson(),
        timestamp: widget.clock(),
      ),
    );
  }

  Future<void> _hide() async {
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.stickyState,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: const {'visible': false},
        timestamp: widget.clock(),
      ),
    );
    await _client.hide();
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).newProject),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).name,
          ),
          onSubmitted: (_) => Navigator.pop(context, true),
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
    final name = controller.text.trim();
    if (accepted == true && name.isNotEmpty) {
      final ack =
          await _client.sendToMain(
                WindowEnvelope(
                  type: WindowMessageType.projectCreate,
                  requestId: const Uuid().v4(),
                  sourceWindowId: _client.windowId,
                  payload: {'name': name},
                  timestamp: widget.clock(),
                ),
              )
              as Map<Object?, Object?>?;
      final projectId = ack?['projectId'];
      if (ack?['ok'] == true && projectId is String) {
        await _source(StickySourceType.project, projectId);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  Future<void> _createTask() async {
    final value = _title.text.trim();
    if (value.isEmpty) return;
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.taskCreate,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: {'title': value},
        timestamp: widget.clock(),
      ),
    );
    _title.clear();
  }

  Future<void> _toggle(StickyTaskSnapshotItem task) => _client
      .sendToMain(
        WindowEnvelope(
          type: task.completed
              ? WindowMessageType.taskReopen
              : WindowMessageType.taskComplete,
          requestId: const Uuid().v4(),
          sourceWindowId: _client.windowId,
          payload: {'id': task.id, 'revision': task.revision},
          timestamp: widget.clock(),
        ),
      )
      .then((_) {});

  Future<bool> _confirmTrash(StickyTaskSnapshotItem task) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.areYouSure),
        content: Text(l10n.confirmTrashTask),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.sendToTrash),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    final response = await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.taskTrash,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: {'id': task.id, 'revision': task.revision},
        timestamp: widget.clock(),
      ),
    );
    final ok = response is! Map || response['ok'] != false;
    if (ok && mounted) {
      setState(() => _tasks = _tasks.where((item) => item.id != task.id).toList());
    }
    return ok;
  }

  String _sourceLabel(AppLocalizations l10n, StickySourceType source) =>
      switch (source) {
        StickySourceType.today => l10n.stickySourceToday,
        StickySourceType.tomorrow => l10n.stickySourceTomorrow,
        StickySourceType.thisWeek => l10n.stickySourceThisWeek,
        StickySourceType.project => l10n.stickySourceProject,
        StickySourceType.folderOrList => l10n.stickySourceFolderOrList,
        StickySourceType.pinned => l10n.stickySourcePinned,
        StickySourceType.savedFilter => l10n.filter,
      };

  Future<void> _source(StickySourceType source, [String? sourceId]) async {
    _preferences = StickyPreferences(
      source: source,
      sourceId: sourceId,
      opacity: _preferences.opacity,
      compact: _preferences.compact,
      showMetadata: _preferences.showMetadata,
      collapseCompleted: _preferences.collapseCompleted,
      borderless: _preferences.borderless,
    );
    // Clear immediately so the UI reflects the new filter while the main
    // window recomputes and broadcasts the matching snapshot.
    setState(() => _tasks = const []);
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.stickySourceChanged,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: {'source': source.name, 'sourceId': sourceId},
        timestamp: widget.clock(),
      ),
    );
  }

  Future<void> _updatePreferences(StickyPreferences preferences) async {
    _preferences = preferences;
    await _client.setOpacity(preferences.safeOpacity);
    await _client.setCompact(preferences.compact);
    await _client.setBorderless(preferences.borderless);
    if (mounted) setState(() {});
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.stickyPreferencesChanged,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: preferences.toJson(),
        timestamp: widget.clock(),
      ),
    );
  }

  Future<void> _simpleCommand(WindowMessageType type) => _client
      .sendToMain(
        WindowEnvelope(
          type: type,
          requestId: const Uuid().v4(),
          sourceWindowId: _client.windowId,
          payload: const {},
          timestamp: widget.clock(),
        ),
      )
      .then((_) {});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final l10n = AppLocalizations.of(context);
    final visibleTasks = _preferences.collapseCompleted
        ? _tasks.where((task) => !task.completed).toList()
        : _tasks;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.border),
          boxShadow: [BoxShadow(color: tokens.shadow, blurRadius: 18)],
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.drag_indicator, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<StickySourceType>(
                      value: _preferences.source,
                      isDense: true,
                      items: StickySourceType.values
                          .where(
                            (value) => value != StickySourceType.savedFilter,
                          )
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(_sourceLabel(l10n, value)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) unawaited(_source(value));
                      },
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.settings,
                  onSelected: (action) {
                    if (action == 'main') {
                      unawaited(_simpleCommand(WindowMessageType.openMain));
                    } else if (action == 'quickNote') {
                      unawaited(
                        _simpleCommand(WindowMessageType.openQuickNote),
                      );
                    } else if (action == 'compact') {
                      unawaited(
                        _updatePreferences(
                          StickyPreferences(
                            source: _preferences.source,
                            sourceId: _preferences.sourceId,
                            opacity: _preferences.opacity,
                            compact: !_preferences.compact,
                            showMetadata: _preferences.showMetadata,
                            collapseCompleted: _preferences.collapseCompleted,
                            borderless: _preferences.borderless,
                          ),
                        ),
                      );
                    } else if (action == 'completed') {
                      unawaited(
                        _updatePreferences(
                          StickyPreferences(
                            source: _preferences.source,
                            sourceId: _preferences.sourceId,
                            opacity: _preferences.opacity,
                            compact: _preferences.compact,
                            showMetadata: _preferences.showMetadata,
                            collapseCompleted: !_preferences.collapseCompleted,
                            borderless: _preferences.borderless,
                          ),
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'main', child: Text(l10n.openMain)),
                    PopupMenuItem(
                      value: 'quickNote',
                      child: Text(l10n.openQuickNote),
                    ),
                    PopupMenuItem(
                      value: 'compact',
                      child: Text(l10n.compactMode),
                    ),
                    PopupMenuItem(
                      value: 'completed',
                      child: Text(l10n.collapseCompleted),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: l10n.hideSticky,
                  onPressed: _hide,
                  icon: const Icon(Icons.close, size: 17),
                ),
              ],
            ),
            if (_preferences.source == StickySourceType.project ||
                _preferences.source == StickySourceType.folderOrList)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_preferences.sourceId),
                        initialValue:
                            _sources.any(
                              (source) => source['id'] == _preferences.sourceId,
                            )
                            ? _preferences.sourceId
                            : null,
                        isDense: true,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.projectList,
                        ),
                        items: _sources
                            .where(
                              (source) =>
                                  _preferences.source ==
                                      StickySourceType.project
                                  ? source['type'] ==
                                        ProjectNodeType.project.name
                                  : source['type'] ==
                                            ProjectNodeType.folder.name ||
                                        source['type'] ==
                                            ProjectNodeType.taskList.name,
                            )
                            .map(
                              (source) => DropdownMenuItem<String>(
                                value: source['id']! as String,
                                child: Text(
                                  source['name']! as String,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            unawaited(_source(_preferences.source, value)),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.newProject,
                      onPressed: () => unawaited(_createProject()),
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    onSubmitted: (_) => _createTask(),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).taskTitle,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _createTask,
                  tooltip: AppLocalizations.of(context).add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.opacity, size: 14),
                Expanded(
                  child: Slider(
                    min: .65,
                    max: 1,
                    value: _preferences.safeOpacity,
                    onChanged: (value) => _updatePreferences(
                      StickyPreferences(
                        source: _preferences.source,
                        sourceId: _preferences.sourceId,
                        opacity: value,
                        compact: _preferences.compact,
                        showMetadata: _preferences.showMetadata,
                        collapseCompleted: _preferences.collapseCompleted,
                        borderless: _preferences.borderless,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: visibleTasks.isEmpty
                  ? Center(
                      child: Text(
                        _preferences.source == StickySourceType.today
                            ? l10n.stickyEmpty
                            : l10n.stickyEmptyFiltered,
                      ),
                    )
                  : ListView(
                      children: [
                        for (final task in visibleTasks)
                          Dismissible(
                            key: ValueKey('sticky-dismiss-${task.id}'),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) => _confirmTrash(task),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 12),
                              color: tokens.danger,
                              child: const Icon(
                                Icons.delete_outline,
                                size: 17,
                              ),
                            ),
                            child: InkWell(
                              onTap: () => _toggle(task),
                              onDoubleTap: () => _client.sendToMain(
                                WindowEnvelope(
                                  type: WindowMessageType.taskOpen,
                                  requestId: const Uuid().v4(),
                                  sourceWindowId: _client.windowId,
                                  payload: {
                                    'id': task.id,
                                    'revision': task.revision,
                                  },
                                  timestamp: widget.clock(),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: tokens.border),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      task.completed
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      size: 17,
                                      color: task.completed
                                          ? tokens.success
                                          : tokens.secondaryText,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            task.title,
                                            style: TextStyle(
                                              decoration: task.completed
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                          if (_preferences.showMetadata &&
                                              task.due != null)
                                            Text(
                                              DateTime.parse(task.due!)
                                                  .toLocal()
                                                  .toIso8601String()
                                                  .split('T')
                                                  .first,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (task.project != null)
                                      Text(
                                        task.project!,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_geometrySubscription?.cancel());
    unawaited(_closeSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_snapshots.close());
    _title.dispose();
    _client.dispose();
    _bus.dispose();
    super.dispose();
  }
}

final class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(AppThemeId.obsidianBlack),
    builder: (context, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return Theme(
        data: buildAppTheme(
          AppThemeId.obsidianBlack,
          reducedMotion: reduceMotion,
        ),
        child: child ?? const SizedBox.shrink(),
      );
    },
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('ephtodo could not start safely.'),
              const SizedBox(height: 8),
              Text(error.runtimeType.toString()),
            ],
          ),
        ),
      ),
    ),
  );
}
