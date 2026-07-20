import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../l10n/app_localizations.dart';
import '../../tasks/domain/task_models.dart';
import '../application/note_repository.dart';
import '../domain/note_models.dart';

final class NotesPage extends StatefulWidget {
  const NotesPage({
    super.key,
    required this.repository,
    required this.onOpenQuickNote,
    this.projects,
  });
  final NoteRepository repository;
  final Future<void> Function() onOpenQuickNote;
  final Stream<List<ProjectNode>>? projects;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

final class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  final _title = TextEditingController();
  final _body = TextEditingController();
  StreamSubscription<List<Note>>? _subscription;
  StreamSubscription<List<ProjectNode>>? _projectSubscription;
  List<Note> _notes = const [];
  List<ProjectNode> _projects = const [];
  Note? _selected;
  Timer? _autosave;
  int _generation = 0;
  bool _saving = false;
  bool _applyingDocument = false;
  NoteLifecycle _lifecycle = NoteLifecycle.active;
  String? _projectNodeId;
  String? _linkedTaskId;

  @override
  void initState() {
    super.initState();
    _watch();
    _projectSubscription = widget.projects?.listen((nodes) {
      if (mounted) {
        setState(
          () => _projects = nodes
              .where((node) => node.type != ProjectNodeType.workspace)
              .toList(),
        );
      }
    });
    _title.addListener(_changed);
    _body.addListener(_changed);
  }

  void _watch() {
    unawaited(_subscription?.cancel());
    _subscription = widget.repository
        .watch(query: _search.text, lifecycle: _lifecycle)
        .listen((notes) {
          if (mounted) setState(() => _notes = notes);
        });
  }

  void _changed() {
    if (_selected == null || _applyingDocument) return;
    _generation++;
    _autosave?.cancel();
    _autosave = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_save()),
    );
    setState(() => _saving = true);
  }

  Future<void> _select(Note note) async {
    _autosave?.cancel();
    final document = await widget.repository.open(note.id);
    _applyingDocument = true;
    _selected = document.note;
    _title.text = document.note.title;
    _body.text = document.body;
    _projectNodeId = document.note.projectNodeId;
    _linkedTaskId = document.note.linkedTaskId;
    _applyingDocument = false;
    _saving = false;
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final document = await widget.repository.create(
      title: AppLocalizations.of(context).newNote,
    );
    await _select(document.note);
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    final generation = _generation;
    try {
      final ack = await widget.repository.save(
        NoteSaveRequest(
          noteId: selected.id,
          title: _title.text,
          body: _body.text,
          expectedRevision: selected.revision,
          requestId: const Uuid().v4(),
          saveGeneration: generation,
          projectNodeId: _projectNodeId,
          linkedTaskId: _linkedTaskId,
        ),
      );
      if (ack.saveGeneration == _generation) {
        _selected = ack.note;
        _saving = false;
        if (mounted) setState(() {});
      }
    } on NoteException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).databaseError)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        SizedBox(
          width: 290,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => _watch(),
                  decoration: InputDecoration(
                    hintText: l10n.searchNotes,
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SegmentedButton<NoteLifecycle>(
                  segments: [
                    ButtonSegment(
                      value: NoteLifecycle.active,
                      label: Text(l10n.notes),
                    ),
                    ButtonSegment(
                      value: NoteLifecycle.archived,
                      label: Text(l10n.archive),
                    ),
                    ButtonSegment(
                      value: NoteLifecycle.trash,
                      label: Text(l10n.trash),
                    ),
                  ],
                  selected: {_lifecycle},
                  onSelectionChanged: (values) {
                    _lifecycle = values.single;
                    _watch();
                    setState(() {});
                  },
                ),
              ),
              Expanded(
                child: _notes.isEmpty
                    ? Center(child: Text(l10n.noNotes))
                    : ListView.builder(
                        itemCount: _notes.length,
                        itemBuilder: (context, index) {
                          final note = _notes[index];
                          final projectName = note.projectNodeId == null
                              ? null
                              : _projects
                                    .where((node) => node.id == note.projectNodeId)
                                    .map((node) => node.name)
                                    .firstOrNull;
                          return Builder(
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
                                      value: 'assign',
                                      child: Text(
                                        projectName == null
                                            ? l10n.assignToProject
                                            : '${l10n.assignToProject} ($projectName)',
                                      ),
                                    ),
                                    if (note.lifecycle == NoteLifecycle.active)
                                      PopupMenuItem(
                                        value: 'archive',
                                        child: Text(l10n.archive),
                                      ),
                                    if (note.lifecycle != NoteLifecycle.active)
                                      PopupMenuItem(
                                        value: 'restore',
                                        child: Text(l10n.restore),
                                      ),
                                    if (note.deletedAt == null)
                                      PopupMenuItem(
                                        value: 'trash',
                                        child: Text(l10n.sendToTrash),
                                      ),
                                    if (note.deletedAt != null)
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text(l10n.deletePermanently),
                                      ),
                                  ],
                                );
                                if (!mounted || action == null) return;
                                if (action == 'assign') {
                                  if (!context.mounted) return;
                                  final selected = await showDialog<String?>(
                                    context: context,
                                    builder: (context) => SimpleDialog(
                                      title: Text(l10n.assignToProject),
                                      children: [
                                        SimpleDialogOption(
                                          onPressed: () =>
                                              Navigator.pop(context, ''),
                                          child: Text(l10n.noProject),
                                        ),
                                        for (final project in _projects)
                                          SimpleDialogOption(
                                            onPressed: () => Navigator.pop(
                                              context,
                                              project.id,
                                            ),
                                            child: Text(project.name),
                                          ),
                                      ],
                                    ),
                                  );
                                  if (selected == null) return;
                                  await _select(note);
                                  _projectNodeId =
                                      selected.isEmpty ? null : selected;
                                  await _save();
                                } else if (action == 'archive') {
                                  await widget.repository.archive(
                                    note.id,
                                    revision: note.revision,
                                  );
                                } else if (action == 'restore') {
                                  if (note.deletedAt != null) {
                                    await widget.repository.restoreFromTrash(
                                      note.id,
                                      revision: note.revision,
                                    );
                                  } else {
                                    await widget.repository.restore(
                                      note.id,
                                      revision: note.revision,
                                    );
                                  }
                                } else if (action == 'trash') {
                                  await widget.repository.trash(
                                    note.id,
                                    revision: note.revision,
                                  );
                                } else if (action == 'delete') {
                                  await widget.repository.permanentlyDelete(
                                    note.id,
                                  );
                                }
                              },
                              child: ListTile(
                                dense: true,
                                selected: note.id == _selected?.id,
                                title: Text(note.title, maxLines: 1),
                                subtitle: Text(
                                  [
                                    note.updatedAt
                                        .toLocal()
                                        .toIso8601String()
                                        .split('T')
                                        .first,
                                    ?projectName,
                                  ].join(' · '),
                                ),
                                onTap: () => _select(note),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.note_add_outlined),
                        label: Text(l10n.newNote),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: l10n.openQuickNote,
                      onPressed: widget.onOpenQuickNote,
                      icon: const Icon(Icons.open_in_new),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? Center(child: Text(l10n.selectNote))
              : Column(
                  children: [
                    TextField(
                      controller: _title,
                      decoration: InputDecoration(
                        hintText: l10n.noteTitle,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(18),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonFormField<String?>(
                        key: ValueKey(
                          'note-project-${_selected?.id}-$_projectNodeId',
                        ),
                        initialValue:
                            _projects.any(
                              (node) => node.id == _projectNodeId,
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
                          for (final node in _projects)
                            DropdownMenuItem<String?>(
                              value: node.id,
                              child: Text(
                                node.name,
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
                    const Divider(height: 1),
                    Expanded(
                      child: TextField(
                        controller: _body,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlign: TextAlign.start,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: l10n.noteBody,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(18),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          Text(_saving ? l10n.saving : l10n.saved),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => _save(),
                            icon: const Icon(Icons.save_outlined, size: 16),
                            label: Text(l10n.save),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _autosave?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_projectSubscription?.cancel());
    _search.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }
}
