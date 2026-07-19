import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import 'app_state_store.dart';
import 'audio_poc_service.dart';
import 'database_writer.dart';
import 'task_item.dart';
import 'vault_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.automatedVaultParent});

  final String? automatedVaultParent;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  final _taskController = TextEditingController();
  final _vaultService = VaultService();
  final _audio = AudioPocService();

  AppStateStore? _stateStore;
  MainDatabaseWriter? _writer;
  List<TaskItem> _tasks = const [];
  MultiWindowManager? _stickyWindow;
  String _status = 'Initializing app-local state…';
  String _audioStatus = 'Not recording';
  bool _recording = false;
  bool _recordingPaused = false;
  int? _lastPropagationMicros;
  final Map<String, Object?> _automationReport = {};

  @override
  void initState() {
    super.initState();
    MultiWindowManager.current.addListener(this);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final store = await AppStateStore.open();
    if (!mounted) return;
    setState(() {
      _stateStore = store;
      _status = store.vaultPath == null
          ? 'Select a parent directory to create/open ephtodo-vault.'
          : 'Revalidating the previously selected vault…';
    });
    if (widget.automatedVaultParent != null) {
      debugPrint('PHASE0_AUTOMATION_MAIN_START');
      try {
        await _automationCheckpoint('validating vault');
        final validation = await _vaultService.createOrOpen(
          widget.automatedVaultParent!,
        );
        await _automationCheckpoint(
          'vault validation: ${validation.isValid} ${validation.message}',
        );
        if (validation.isValid) {
          await _activateVault(validation);
          await _automationCheckpoint('vault activated');
          await _openOrShowSticky();
          await _automationCheckpoint('sticky create requested');
        } else if (mounted) {
          setState(() => _status = validation.message);
        }
      } catch (error, stackTrace) {
        await _automationCheckpoint('ERROR $error\n$stackTrace');
      }
      return;
    }
    if (store.vaultPath != null) {
      final validation = await _vaultService.createOrOpen(store.vaultPath!);
      if (validation.isValid) {
        await _activateVault(validation);
      } else if (mounted) {
        setState(() => _status = validation.message);
      }
    }
  }

  Future<void> _pickVault() async {
    final selected = await _vaultService.pickParentDirectory();
    if (selected == null) {
      setState(() => _status = 'Vault selection cancelled.');
      return;
    }
    final validation = await _vaultService.createOrOpen(selected);
    if (!validation.isValid) {
      setState(() => _status = validation.message);
      return;
    }
    await _activateVault(validation);
  }

  Future<void> _activateVault(VaultValidation validation) async {
    _writer?.close();
    final writer = MainDatabaseWriter.open(validation.path);
    final tasks = writer.loadTasks();
    final store = _stateStore!;
    store.vaultPath = validation.path;
    await store.save();
    if (!mounted) {
      writer.close();
      return;
    }
    setState(() {
      _writer = writer;
      _tasks = tasks;
      _status = '${validation.message}\n${validation.path}';
    });
    await _broadcastTasks();
  }

  Future<void> _openOrShowSticky() async {
    if (_writer == null) {
      setState(() => _status = 'Select a valid vault before opening sticky.');
      return;
    }
    final existing = _stickyWindow;
    if (existing != null) {
      await existing.show(inactive: true);
      return;
    }
    final geometry = _stateStore!.geometry;
    final window = await MultiWindowManager.createWindow([
      'sticky',
      jsonEncode(geometry.toJson()),
      if (widget.automatedVaultParent != null) 'automation',
    ]);
    if (window == null) {
      setState(() => _status = 'Secondary window creation failed.');
      return;
    }
    _stickyWindow = window;
    setState(() => _status = 'Sticky window ${window.id} created.');
  }

  Future<void> _hideSticky() async {
    await _stickyWindow?.hide();
    if (mounted) setState(() => _status = 'Sticky hidden; main remains alive.');
  }

  Future<TaskItem> _createTask(String title) async {
    final writer = _writer;
    if (writer == null) throw StateError('No vault is active.');
    final task = writer.createTask(title);
    _tasks = writer.loadTasks();
    if (mounted) setState(() {});
    await _broadcastTasks();
    return task;
  }

  Future<TaskItem> _setCompleted(String id, bool completed) async {
    final writer = _writer;
    if (writer == null) throw StateError('No vault is active.');
    final task = writer.setCompleted(id, completed);
    _tasks = writer.loadTasks();
    if (mounted) setState(() {});
    await _broadcastTasks();
    return task;
  }

  Future<void> _broadcastTasks() async {
    final sticky = _stickyWindow;
    if (sticky == null) return;
    final sentAt = DateTime.now().microsecondsSinceEpoch;
    try {
      final response = await MultiWindowManager.current
          .invokeMethodToWindow(sticky.id, 'tasks.snapshot', {
            'tasks': _tasks.map((task) => task.toJson()).toList(),
            'sentAtMicros': sentAt,
          });
      if (response is Map) {
        final receivedAt = response['receivedAtMicros'] as int?;
        if (receivedAt != null && mounted) {
          setState(() => _lastPropagationMicros = receivedAt - sentAt);
        }
      }
    } catch (error) {
      if (mounted) setState(() => _status = 'IPC broadcast failed: $error');
    }
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    try {
      switch (eventName) {
        case 'sticky.ready':
          _stickyWindow = MultiWindowManager.fromWindowId(fromWindowId);
          await _broadcastTasks();
          return {'ok': true};
        case 'task.create':
          final args = arguments as Map;
          final task = await _createTask(args['title'] as String);
          return {'ok': true, 'task': task.toJson()};
        case 'task.complete':
          final args = arguments as Map;
          final task = await _setCompleted(
            args['id'] as String,
            args['completed'] as bool,
          );
          return {'ok': true, 'task': task.toJson()};
        case 'sticky.geometry':
          final args = arguments as Map;
          _stateStore!.geometry = StickyGeometry(
            x: (args['x'] as num).toDouble(),
            y: (args['y'] as num).toDouble(),
            width: (args['width'] as num).toDouble(),
            height: (args['height'] as num).toDouble(),
          );
          await _stateStore!.save();
          return {'ok': true};
        case 'sticky.hide':
          await _hideSticky();
          if (widget.automatedVaultParent != null) {
            final sticky = _stickyWindow!;
            _automationReport['hiddenWithoutProcessExit'] = !await sticky
                .isVisible();
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await sticky.show(inactive: true);
            await Future<void>.delayed(const Duration(milliseconds: 500));
            _automationReport['shownAgain'] = await sticky.isVisible();
            await _writeAutomationReport();
          }
          return {'ok': true};
        case 'automation.report':
          debugPrint('PHASE0_AUTOMATION_REPORT_RECEIVED=$arguments');
          _automationReport.addAll(
            (arguments as Map).map(
              (key, value) => MapEntry(key.toString(), value as Object?),
            ),
          );
          _automationReport['mainTaskCount'] = _tasks.length;
          _automationReport['mainToSecondaryMicros'] = _lastPropagationMicros;
          await _runAutomatedAudioCheck();
          await _writeAutomationReport();
          return {'ok': true};
      }
    } catch (error) {
      return {'ok': false, 'error': error.toString()};
    }
    return {'ok': false, 'error': 'Unknown command: $eventName'};
  }

  Future<void> _startRecording() async {
    final vaultPath = _stateStore?.vaultPath;
    if (vaultPath == null) return;
    try {
      final devices = await _audio.listInputDevices();
      await _audio.start(vaultPath, device: devices.firstOrNull);
      setState(() {
        _recording = true;
        _recordingPaused = false;
        _audioStatus =
            'Recording WAV${devices.isEmpty ? '' : ' from ${devices.first.label}'}';
      });
    } catch (error) {
      setState(() => _audioStatus = 'Recording failed: $error');
    }
  }

  Future<void> _pauseOrResumeRecording() async {
    try {
      if (_recordingPaused) {
        await _audio.resume();
      } else {
        await _audio.pause();
      }
      setState(() {
        _recordingPaused = !_recordingPaused;
        _audioStatus = _recordingPaused ? 'Recording paused' : 'Recording WAV';
      });
    } catch (error) {
      setState(() => _audioStatus = 'Pause/resume failed: $error');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audio.stop();
      setState(() {
        _recording = false;
        _recordingPaused = false;
        _audioStatus = 'Saved WAV: $path';
      });
    } catch (error) {
      setState(() => _audioStatus = 'Stop failed: $error');
    }
  }

  Future<void> _playRecording() async {
    try {
      await _audio.play();
      setState(() => _audioStatus = 'Playing ${_audio.lastRecordingPath}');
    } catch (error) {
      setState(() => _audioStatus = 'Playback failed: $error');
    }
  }

  Future<void> _runAutomatedAudioCheck() async {
    debugPrint('PHASE0_AUDIO_CHECK_START');
    if (Platform.environment['PHASE0_SKIP_AUDIO'] == '1') {
      _automationReport['audioSkipped'] = true;
      return;
    }
    final vaultPath = _stateStore?.vaultPath;
    if (vaultPath == null) return;
    try {
      final devices = await _audio.listInputDevices();
      _automationReport['audioInputDevices'] = devices
          .map((device) => device.label)
          .toList();
      await _audio.start(vaultPath, device: devices.firstOrNull);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await _audio.pause();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _audio.resume();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final recordingPath = await _audio.stop();
      final recording = recordingPath == null ? null : File(recordingPath);
      _automationReport['audioPath'] = recordingPath;
      _automationReport['audioBytes'] = recording == null
          ? 0
          : await recording.length();
      await _audio.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _audio.stopPlayback();
      _automationReport['audioPlaybackStarted'] = true;
    } catch (error) {
      _automationReport['audioError'] = error.toString();
    }
  }

  Future<void> _writeAutomationReport() async {
    final parent = widget.automatedVaultParent;
    if (parent == null) return;
    final file = File('$parent/phase0-automation-report.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ..._automationReport,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'vaultPath': _stateStore?.vaultPath,
        'stickyGeometry': _stateStore?.geometry.toJson(),
      }),
      flush: true,
    );
    debugPrint('PHASE0_REPORT_WRITTEN=${file.path}');
  }

  Future<void> _automationCheckpoint(String message) async {
    final parent = widget.automatedVaultParent;
    if (parent == null) return;
    await File('$parent/phase0-automation.log').writeAsString(
      '${DateTime.now().toUtc().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  void dispose() {
    MultiWindowManager.current.removeListener(this);
    _taskController.dispose();
    _writer?.close();
    unawaited(_audio.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ephtodo — Phase 0 native capability lab'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(_status, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _pickVault,
                child: const Text('Select / create vault'),
              ),
              FilledButton.tonal(
                onPressed: _openOrShowSticky,
                child: const Text('Show sticky'),
              ),
              OutlinedButton(
                onPressed: _stickyWindow == null ? null : _hideSticky,
                child: const Text('Hide sticky'),
              ),
            ],
          ),
          if (_lastPropagationMicros != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Last main → sticky delivery: '
                '${(_lastPropagationMicros! / 1000).toStringAsFixed(2)} ms',
              ),
            ),
          const Divider(height: 40),
          Text(
            'Single-writer task PoC',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taskController,
                  decoration: const InputDecoration(
                    labelText: 'Task title',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) async {
                    await _createTask(_taskController.text);
                    _taskController.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _writer == null
                    ? null
                    : () async {
                        await _createTask(_taskController.text);
                        _taskController.clear();
                      },
                child: const Text('Add'),
              ),
            ],
          ),
          for (final task in _tasks)
            CheckboxListTile(
              value: task.completed,
              title: Text(task.title),
              subtitle: Text(task.id),
              onChanged: (value) => _setCompleted(task.id, value ?? false),
            ),
          const Divider(height: 40),
          Text(
            'Native WAV audio PoC',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(_audioStatus),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: _writer == null || _recording
                    ? null
                    : _startRecording,
                child: const Text('Record WAV'),
              ),
              OutlinedButton(
                onPressed: _recording ? _pauseOrResumeRecording : null,
                child: Text(_recordingPaused ? 'Resume' : 'Pause'),
              ),
              OutlinedButton(
                onPressed: _recording ? _stopRecording : null,
                child: const Text('Stop'),
              ),
              OutlinedButton(
                onPressed: _recording ? null : _playRecording,
                child: const Text('Play'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
