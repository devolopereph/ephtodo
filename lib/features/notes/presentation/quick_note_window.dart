import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../core/foundation/foundation.dart';
import '../../../core/windowing/multi_window_adapter.dart';
import '../../../core/windowing/window_protocol.dart';
import '../../../l10n/app_localizations.dart';

final class QuickNoteWindow extends StatefulWidget {
  const QuickNoteWindow({
    super.key,
    required this.clock,
    this.onLocaleChanged,
    this.onThemeChanged,
  });
  final DateTime Function() clock;
  final void Function(String localeCode)? onLocaleChanged;
  final void Function(String themeId)? onThemeChanged;

  @override
  State<QuickNoteWindow> createState() => _QuickNoteWindowState();
}

final class _QuickNoteWindowState extends State<QuickNoteWindow> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final MultiWindowCommandBus _bus;
  late final MultiWindowSecondaryClient _client;
  StreamSubscription<WindowEnvelope>? _messages;
  StreamSubscription<void>? _geometry;
  StreamSubscription<void>? _close;
  Timer? _debounce;
  String? _noteId;
  int _revision = 0;
  int _generation = 0;
  int _acknowledgedGeneration = 0;
  bool _vaultAvailable = true;
  bool _applyingSnapshot = false;
  String? _projectNodeId;
  String? _linkedTaskId;
  List<Map<String, Object?>> _projects = const [];

  @override
  void initState() {
    super.initState();
    DatabaseOpenAudit.configure('quickNote');
    _bus = MultiWindowCommandBus();
    _client = MultiWindowSecondaryClient();
    _messages = _bus.messages.listen(_receive);
    _geometry = _client.geometryChanges.listen(
      (_) => unawaited(_saveGeometry()),
    );
    _close = _client.closeRequests.listen((_) => unawaited(_hide()));
    _title.addListener(_changed);
    _body.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_ready()));
  }

  Future<void> _ready() async {
    await _client.initializeQuickNote();
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.lifecycleReady,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: const {'role': 'quickNote', 'health': 'ready'},
        timestamp: widget.clock(),
      ),
    );
    if (Platform.environment['EPHTODO_PHASE34_SMOKE_ROOT'] != null) {
      _title.text = 'Fictional restart note';
      _body.text = 'Fictional autosave body';
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _save(manual: true);
    }
  }

  void _receive(WindowEnvelope message) {
    if (message.type == WindowMessageType.vaultState) {
      setState(() => _vaultAvailable = message.payload['available'] == true);
    } else if (message.type == WindowMessageType.localeChanged) {
      widget.onLocaleChanged?.call(message.payload['locale']! as String);
    } else if (message.type == WindowMessageType.themeChanged) {
      widget.onThemeChanged?.call(message.payload['themeId']! as String);
    } else if (message.type == WindowMessageType.taskSnapshot) {
      final sources = message.payload['sources'];
      if (sources is List) {
        _projects = sources
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList();
        if (mounted) setState(() {});
      }
    } else if (message.type == WindowMessageType.noteStateSnapshot) {
      final generation = message.payload['saveGeneration'] as int? ?? 0;
      if (generation < _generation && _noteId != null) return;
      _applyingSnapshot = true;
      _noteId = message.payload['id'] as String?;
      _revision = message.payload['revision'] as int? ?? 0;
      _acknowledgedGeneration = generation;
      _title.text = message.payload['title'] as String? ?? '';
      _body.text = message.payload['body'] as String? ?? '';
      _projectNodeId = message.payload['projectNodeId'] as String?;
      _linkedTaskId = message.payload['linkedTaskId'] as String?;
      _applyingSnapshot = false;
      if (mounted) setState(() {});
      unawaited(_writeAutomationEvidence());
    } else if (message.type == WindowMessageType.noteSaveAck) {
      final generation = message.payload['saveGeneration'] as int? ?? 0;
      if (generation >= _acknowledgedGeneration) {
        _acknowledgedGeneration = generation;
        _revision = message.payload['revision'] as int? ?? _revision;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _writeAutomationEvidence() async {
    final root = Platform.environment['EPHTODO_PHASE34_SMOKE_ROOT'];
    if (root == null || _noteId == null) return;
    await File('$root${Platform.pathSeparator}quick-note.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'noteCreatedThroughTypedIpc': true,
        'noteIdPresent': _noteId!.isNotEmpty,
        'revision': _revision,
        'saveGeneration': _acknowledgedGeneration,
        'bodyLength': _body.text.length,
        'engineRole': DatabaseOpenAudit.engineRole,
        'secondaryDatabaseOpenCount': DatabaseOpenAudit.openCount,
      }),
    );
  }

  void _changed() {
    if (_applyingSnapshot) return;
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_save()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _save({bool manual = false}) async {
    if (!_vaultAvailable) return;
    final title = _title.text.trim().isEmpty
        ? AppLocalizations.of(context).newNote
        : _title.text.trim();
    final id = _noteId;
    final request = WindowEnvelope(
      type: id == null
          ? WindowMessageType.noteCreate
          : manual
          ? WindowMessageType.noteManualSave
          : WindowMessageType.noteAutosave,
      requestId: const Uuid().v4(),
      sourceWindowId: _client.windowId,
      payload: id == null
          ? {
              'title': title,
              'body': _body.text,
              'saveGeneration': _generation,
              'projectNodeId': _projectNodeId,
              'linkedTaskId': _linkedTaskId,
            }
          : {
              'id': id,
              'title': title,
              'body': _body.text,
              'revision': _revision,
              'saveGeneration': _generation,
              'projectNodeId': _projectNodeId,
              'linkedTaskId': _linkedTaskId,
            },
      timestamp: widget.clock(),
    );
    final ack = await _client.sendToMain(request);
    if (ack is Map && ack['ok'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).databaseError)),
      );
    }
  }

  Future<void> _saveGeometry() async {
    await _client.sendToMain(
      WindowEnvelope(
        type: WindowMessageType.geometryChanged,
        requestId: const Uuid().v4(),
        sourceWindowId: _client.windowId,
        payload: {
          ...(await _client.currentGeometry()).toJson(),
          'role': 'quickNote',
        },
        timestamp: widget.clock(),
      ),
    );
  }

  Future<void> _hide() async {
    await _save(manual: true);
    await _client.hide();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final words = _body.text.trim().isEmpty
        ? 0
        : _body.text.trim().split(RegExp(r'\s+')).length;
    final saving = _generation > _acknowledgedGeneration;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): _SaveIntent(),
        SingleActivator(LogicalKeyboardKey.keyZ, control: true): UndoTextIntent(
          SelectionChangedCause.keyboard,
        ),
        SingleActivator(LogicalKeyboardKey.keyY, control: true): RedoTextIntent(
          SelectionChangedCause.keyboard,
        ),
      },
      child: Actions(
        actions: {
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) {
              unawaited(_save(manual: true));
              return null;
            },
          ),
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _title,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: l10n.noteTitle,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.save,
                        onPressed: () => _save(manual: true),
                        icon: const Icon(Icons.save_outlined),
                      ),
                      IconButton(
                        tooltip: l10n.hideSticky,
                        onPressed: _hide,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (!_vaultAvailable)
                  MaterialBanner(
                    content: Text(l10n.vaultUnavailable),
                    actions: const [SizedBox.shrink()],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: DropdownButtonFormField<String?>(
                    key: ValueKey('quick-note-project-$_projectNodeId'),
                    initialValue:
                        _projects.any(
                          (project) => project['id'] == _projectNodeId,
                        )
                        ? _projectNodeId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.projectOptional,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.noProject),
                      ),
                      for (final project in _projects)
                        DropdownMenuItem<String?>(
                          value: project['id']! as String,
                          child: Text(
                            project['name']! as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      _projectNodeId = value;
                      _changed();
                    },
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _body,
                    enabled: _vaultAvailable,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlign: TextAlign.start,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(height: 1.5),
                    decoration: InputDecoration(
                      hintText: l10n.noteBody,
                      contentPadding: const EdgeInsets.all(18),
                      border: InputBorder.none,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Text(saving ? l10n.saving : l10n.saved),
                      const Spacer(),
                      Text(
                        '$words ${l10n.words} · ${_body.text.length} ${l10n.characters}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_messages?.cancel());
    unawaited(_geometry?.cancel());
    unawaited(_close?.cancel());
    _title.dispose();
    _body.dispose();
    _client.dispose();
    _bus.dispose();
    super.dispose();
  }
}

final class _SaveIntent extends Intent {
  const _SaveIntent();
}
