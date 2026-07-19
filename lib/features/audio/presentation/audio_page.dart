import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../tasks/domain/task_models.dart';
import '../application/audio_coordinator.dart';
import '../domain/audio_models.dart';
import '../domain/audio_services.dart';

final class AudioPage extends StatefulWidget {
  const AudioPage({
    super.key,
    required this.coordinator,
    this.projects,
  });
  final AudioCoordinator coordinator;
  final Stream<List<ProjectNode>>? projects;

  @override
  State<AudioPage> createState() => _AudioPageState();
}

final class _AudioPageState extends State<AudioPage> {
  StreamSubscription<List<AudioNote>>? _subscription;
  StreamSubscription<List<ProjectNode>>? _projectSubscription;
  List<AudioNote> _items = const [];
  List<ProjectNode> _projects = const [];
  Timer? _timer;
  Timer? _playbackTimer;
  Duration _elapsed = Duration.zero;
  String? _error;
  String? _playingId;

  @override
  void initState() {
    super.initState();
    _subscription = widget.coordinator.watch().listen((items) {
      if (mounted) setState(() => _items = items);
    });
    _projectSubscription = widget.projects?.listen((nodes) {
      if (mounted) {
        setState(
          () => _projects = nodes
              .where((node) => node.type != ProjectNodeType.workspace)
              .toList(),
        );
      }
    });
  }

  Future<void> _start() async {
    try {
      await widget.coordinator.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _elapsed = widget.coordinator.elapsed);
        }
      });
      setState(() => _error = null);
    } on Object catch (error) {
      setState(() => _error = error.runtimeType.toString());
    }
  }

  Future<void> _stop() async {
    _timer?.cancel();
    try {
      await widget.coordinator.stop(title: AppLocalizations.of(context).audio);
      setState(() {
        _elapsed = Duration.zero;
      });
    } on Object catch (error) {
      setState(() => _error = error.runtimeType.toString());
    }
  }

  Future<void> _play(AudioNote item) async {
    _playbackTimer?.cancel();
    await widget.coordinator.playback.stop();
    await widget.coordinator.playback.playWav(
      widget.coordinator.resolve(item.relativeFilePath),
    );
    setState(() => _playingId = item.id);
    // WinMM PlaySoundW has no completion callback; hide Stop after duration.
    final ms = item.durationMs <= 0 ? 1000 : item.durationMs;
    _playbackTimer = Timer(Duration(milliseconds: ms + 250), () {
      if (mounted && _playingId == item.id) {
        setState(() => _playingId = null);
      }
    });
  }

  Future<void> _stopPlayback() async {
    _playbackTimer?.cancel();
    await widget.coordinator.playback.stop();
    if (mounted) setState(() => _playingId = null);
  }

  Future<void> _showContextMenu(
    BuildContext tileContext,
    Offset globalPosition,
    AudioNote item,
  ) async {
    final l10n = AppLocalizations.of(context);
    final projectNames = {
      for (final project in _projects) project.id: project.name,
    };
    final action = await showMenu<String>(
      context: tileContext,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
        PopupMenuItem(
          value: 'move',
          child: Text(
            item.projectNodeId == null
                ? l10n.moveToProject
                : '${l10n.moveToProject} (${projectNames[item.projectNodeId] ?? l10n.noProject})',
          ),
        ),
        PopupMenuItem(value: 'trash', child: Text(l10n.sendToTrash)),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      final controller = TextEditingController(text: item.title);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.rename),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.save),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await widget.coordinator.rename(
          item.id,
          controller.text,
          revision: item.revision,
        );
      }
    } else if (action == 'move') {
      final selected = await showDialog<String?>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(l10n.moveToProject),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(l10n.noProject),
            ),
            for (final project in _projects)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, project.id),
                child: Text(project.name),
              ),
          ],
        ),
      );
      if (selected == null) return;
      await widget.coordinator.assignProject(
        item.id,
        revision: item.revision,
        projectNodeId: selected.isEmpty ? null : selected,
      );
    } else if (action == 'trash') {
      await widget.coordinator.trash(item.id, revision: item.revision);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.coordinator.recorder.state;
    final projectNames = {
      for (final project in _projects) project.id: project.name,
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text(l10n.audio, style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            if (state == AudioRecorderState.idle)
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.mic_none),
                label: Text(l10n.record),
              )
            else ...[
              Text(
                '${_elapsed.inMinutes.toString().padLeft(2, '0')}:'
                '${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
              ),
              IconButton(
                tooltip: state == AudioRecorderState.paused
                    ? l10n.resume
                    : l10n.pause,
                onPressed: () async {
                  state == AudioRecorderState.paused
                      ? await widget.coordinator.resume()
                      : await widget.coordinator.pause();
                  setState(() {});
                },
                icon: Icon(
                  state == AudioRecorderState.paused
                      ? Icons.play_arrow
                      : Icons.pause,
                ),
              ),
              IconButton(
                tooltip: l10n.stop,
                onPressed: _stop,
                icon: const Icon(Icons.stop),
              ),
              IconButton(
                tooltip: l10n.cancel,
                onPressed: () async {
                  _timer?.cancel();
                  await widget.coordinator.cancel();
                  setState(() {
                    _elapsed = Duration.zero;
                  });
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('${l10n.audioError}: $_error'),
          ),
        const SizedBox(height: 12),
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(l10n.noAudio)),
          ),
        for (final item in _items)
          Builder(
            builder: (tileContext) => GestureDetector(
              onSecondaryTapDown: (details) => _showContextMenu(
                tileContext,
                details.globalPosition,
                item,
              ),
              child: ListTile(
                leading: IconButton(
                  tooltip: l10n.play,
                  onPressed: () => _play(item),
                  icon: Icon(
                    _playingId == item.id ? Icons.stop : Icons.play_arrow,
                  ),
                ),
                onTap: () =>
                    _playingId == item.id ? _stopPlayback() : _play(item),
                title: Text(item.title),
                subtitle: Text(
                  [
                    '${(item.durationMs / 1000).toStringAsFixed(1)} s',
                    '${item.fileSize} B',
                    item.mimeType,
                    if (item.projectNodeId != null)
                      projectNames[item.projectNodeId] ?? l10n.noProject,
                  ].join(' · '),
                ),
                trailing: _playingId == item.id
                    ? IconButton(
                        tooltip: l10n.stop,
                        onPressed: _stopPlayback,
                        icon: const Icon(Icons.stop),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playbackTimer?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_projectSubscription?.cancel());
    super.dispose();
  }
}
