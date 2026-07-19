import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import 'task_item.dart';

class StickyScreen extends StatefulWidget {
  const StickyScreen({super.key, this.runAutomation = false});

  final bool runAutomation;

  @override
  State<StickyScreen> createState() => _StickyScreenState();
}

class _StickyScreenState extends State<StickyScreen> with WindowListener {
  final _taskController = TextEditingController();
  List<TaskItem> _tasks = const [];
  String _status = 'Connecting to main writer…';
  double? _lastCommandRoundTripMs;
  bool _alwaysOnTop = false;

  @override
  void initState() {
    super.initState();
    MultiWindowManager.current.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_configureAndConnect());
    });
  }

  Future<void> _configureAndConnect() async {
    debugPrint('PHASE0_STICKY_START automation=${widget.runAutomation}');
    await MultiWindowManager.current.setAlwaysOnTop(true);
    await MultiWindowManager.current.setPreventClose(true);
    final topmost = await MultiWindowManager.current.isAlwaysOnTop();
    final response = await MultiWindowManager.current.invokeMethodToWindow(
      0,
      'sticky.ready',
      {'windowId': MultiWindowManager.current.id},
    );
    if (!mounted) return;
    setState(() {
      _alwaysOnTop = topmost;
      _status = response is Map && response['ok'] == true
          ? 'IPC connected. SQLite writes owned by main.'
          : 'Main IPC handshake failed: $response';
    });
    if (widget.runAutomation) {
      await MultiWindowManager.current.setPosition(const Offset(1320, 120));
      await MultiWindowManager.current.setSize(const Size(380, 520));
      await _persistGeometry();
      await _sendCommand('task.create', {
        'title': 'Secondary IPC single-writer proof',
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await MultiWindowManager.current
          .invokeMethodToWindow(0, 'automation.report', {
            'nativeTopmost': _alwaysOnTop,
            'secondaryToMainRoundTripMs': _lastCommandRoundTripMs,
            'secondaryObservedTaskCount': _tasks.length,
          });
      await MultiWindowManager.current.invokeMethodToWindow(
        0,
        'sticky.hide',
        null,
      );
    }
  }

  @override
  Future<dynamic> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    if (eventName == 'tasks.snapshot') {
      final args = arguments as Map;
      final rawTasks = args['tasks'] as List;
      final receivedAt = DateTime.now().microsecondsSinceEpoch;
      if (mounted) {
        setState(() {
          _tasks = rawTasks
              .map(
                (json) =>
                    TaskItem.fromJson((json as Map).cast<Object?, Object?>()),
              )
              .toList(growable: false);
          _status = 'Received ${_tasks.length} task(s) from main.';
        });
      }
      return {'receivedAtMicros': receivedAt};
    }
    return {'ok': false, 'error': 'Unknown event: $eventName'};
  }

  Future<void> _sendCommand(String command, Map<String, Object?> args) async {
    final stopwatch = Stopwatch()..start();
    final response = await MultiWindowManager.current.invokeMethodToWindow(
      0,
      command,
      args,
    );
    stopwatch.stop();
    if (!mounted) return;
    setState(() {
      _lastCommandRoundTripMs = stopwatch.elapsedMicroseconds.toDouble() / 1000;
      _status = response is Map && response['ok'] == true
          ? '$command persisted by main writer.'
          : '$command failed: $response';
    });
  }

  Future<void> _persistGeometry() async {
    final position = await MultiWindowManager.current.getPosition();
    final size = await MultiWindowManager.current.getSize();
    await MultiWindowManager.current.invokeMethodToWindow(
      0,
      'sticky.geometry',
      {
        'x': position.dx,
        'y': position.dy,
        'width': size.width,
        'height': size.height,
      },
    );
  }

  @override
  void onWindowMoved([int? windowId]) {
    unawaited(_persistGeometry());
  }

  @override
  void onWindowResized([int? windowId]) {
    unawaited(_persistGeometry());
  }

  @override
  void onWindowClose([int? windowId]) {
    unawaited(
      MultiWindowManager.current.invokeMethodToWindow(0, 'sticky.hide', null),
    );
  }

  @override
  void dispose() {
    MultiWindowManager.current.removeListener(this);
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff101114),
      appBar: AppBar(
        backgroundColor: const Color(0xff17191d),
        foregroundColor: Colors.white,
        title: const Text('ephtodo sticky PoC'),
        actions: [
          IconButton(
            tooltip: 'Hide (main remains running)',
            onPressed: () => MultiWindowManager.current.invokeMethodToWindow(
              0,
              'sticky.hide',
              null,
            ),
            icon: const Icon(Icons.visibility_off_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Icon(
                _alwaysOnTop ? Icons.push_pin : Icons.warning_amber,
                color: _alwaysOnTop ? Colors.greenAccent : Colors.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _alwaysOnTop
                      ? 'Native topmost flag active'
                      : 'Topmost verification failed',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.white70)),
          if (_lastCommandRoundTripMs != null)
            Text(
              'Last secondary → main round trip: '
              '${_lastCommandRoundTripMs!.toStringAsFixed(2)} ms',
              style: const TextStyle(color: Colors.white54),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _taskController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Quick add through main writer',
              labelStyle: TextStyle(color: Colors.white60),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (title) async {
              await _sendCommand('task.create', {'title': title});
              _taskController.clear();
            },
          ),
          const SizedBox(height: 12),
          for (final task in _tasks)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: task.completed,
              title: Text(
                task.title,
                style: TextStyle(
                  color: Colors.white,
                  decoration: task.completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              onChanged: (value) => _sendCommand('task.complete', {
                'id': task.id,
                'completed': value ?? false,
              }),
            ),
        ],
      ),
    );
  }
}
