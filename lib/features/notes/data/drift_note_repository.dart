import 'dart:convert';
import 'dart:io';

// ignore_for_file: prefer_initializing_formals

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../core/foundation/foundation.dart';
import '../../../core/vault/vault_service.dart';
import '../application/note_repository.dart';
import '../domain/note_models.dart';

final class DriftNoteRepository implements NoteRepository {
  DriftNoteRepository({
    required db.AppDatabase database,
    required VaultHandle vault,
    required VaultService vaultService,
    required Clock clock,
    required String deviceId,
  }) : _database = database,
       _vault = vault,
       _vaultService = vaultService,
       _clock = clock,
       _deviceId = deviceId;

  final db.AppDatabase _database;
  final VaultHandle _vault;
  final VaultService _vaultService;
  final Clock _clock;
  final String _deviceId;
  static const _uuid = Uuid();
  final Map<String, int> _latestSaveGeneration = {};

  Note _model(db.Note row) => Note(
    id: row.id,
    title: row.title,
    relativeFilePath: row.relativeFilePath,
    contentHash: row.contentHash ?? '',
    projectNodeId: row.projectNodeId,
    linkedTaskId: row.linkedTaskId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    archivedAt: row.archivedAt,
    deletedAt: row.deletedAt,
    revision: row.revision,
  );

  String _path(String relative) {
    if (relative != 'notes' &&
        !relative.startsWith('notes${p.separator}') &&
        !relative.startsWith('notes/')) {
      throw const NoteException(
        NoteFailureCode.pathUnsafe,
        'Note path is outside the notes directory.',
      );
    }
    try {
      return _vaultService.resolveInside(_vault, p.normalize(relative));
    } on VaultException {
      throw const NoteException(
        NoteFailureCode.pathUnsafe,
        'Note path is unsafe.',
      );
    }
  }

  Future<db.Note> _row(String id) async {
    final row = await (_database.select(
      _database.notes,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw const NoteException(NoteFailureCode.missing, 'Note not found.');
    }
    return row;
  }

  @override
  Stream<List<Note>> watch({String query = '', NoteLifecycle? lifecycle}) {
    final select = _database.select(_database.notes);
    switch (lifecycle) {
      case NoteLifecycle.active:
        select.where((row) => row.archivedAt.isNull() & row.deletedAt.isNull());
      case NoteLifecycle.archived:
        select.where(
          (row) => row.archivedAt.isNotNull() & row.deletedAt.isNull(),
        );
      case NoteLifecycle.trash:
        select.where((row) => row.deletedAt.isNotNull());
      case null:
        break;
    }
    select.orderBy([(row) => OrderingTerm.desc(row.updatedAt)]);
    return select.watch().asyncMap((rows) async {
      final lower = query.trim().toLowerCase();
      if (lower.isEmpty) return rows.map(_model).toList();
      final result = <Note>[];
      for (final row in rows) {
        if (row.title.toLowerCase().contains(lower)) {
          result.add(_model(row));
          continue;
        }
        final file = File(_path(row.relativeFilePath));
        if (await file.exists() &&
            (await file.readAsString()).toLowerCase().contains(lower)) {
          result.add(_model(row));
        }
      }
      return result;
    });
  }

  @override
  Future<List<Note>> all() async =>
      (await _database.select(_database.notes).get()).map(_model).toList();

  @override
  Future<NoteDocument> open(String id) async {
    final row = await _row(id);
    final file = File(_path(row.relativeFilePath));
    if (!await file.exists()) {
      throw const NoteException(
        NoteFailureCode.fileMissing,
        'The note file is missing.',
      );
    }
    return NoteDocument(note: _model(row), body: await file.readAsString());
  }

  @override
  Future<NoteDocument> create({
    required String title,
    String body = '',
    String? projectNodeId,
    String? linkedTaskId,
  }) async {
    final id = _uuid.v4();
    final safeTitle = Note.validateTitle(title);
    final relative = await _uniqueRelative(safeTitle, id);
    final now = _clock.now();
    await _atomicWrite(relative, body);
    try {
      await _database.transaction(() async {
        await _database
            .into(_database.notes)
            .insert(
              db.NotesCompanion.insert(
                id: id,
                projectNodeId: Value(projectNodeId),
                linkedTaskId: Value(linkedTaskId),
                title: safeTitle,
                relativeFilePath: relative,
                contentHash: Value(_hash(body)),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _change(id, 'create', 1, _hash(body));
      });
    } catch (_) {
      await File(
        _path(relative),
      ).delete().catchError((_) => File(_path(relative)));
      rethrow;
    }
    return open(id);
  }

  @override
  Future<NoteSaveAck> save(NoteSaveRequest request) async {
    final row = await _row(request.noteId);
    final latest = _latestSaveGeneration[request.noteId] ?? -1;
    if (request.saveGeneration < latest) {
      throw const NoteException(
        NoteFailureCode.staleSave,
        'A newer save already exists.',
      );
    }
    if (row.revision != request.expectedRevision) {
      throw const NoteException(
        NoteFailureCode.staleRevision,
        'The note changed in another view.',
      );
    }
    _latestSaveGeneration[request.noteId] = request.saveGeneration;
    final oldBody = await File(_path(row.relativeFilePath)).readAsString();
    final oldHash = row.contentHash;
    await _atomicWrite(row.relativeFilePath, request.body);
    final now = _clock.now();
    final revision = row.revision + 1;
    try {
      await _database.transaction(() async {
        final changed =
            await (_database.update(_database.notes)..where(
                  (candidate) =>
                      candidate.id.equals(row.id) &
                      candidate.revision.equals(row.revision),
                ))
                .write(
                  db.NotesCompanion(
                    title: Value(Note.validateTitle(request.title)),
                    projectNodeId: Value(request.projectNodeId),
                    linkedTaskId: Value(request.linkedTaskId),
                    contentHash: Value(_hash(request.body)),
                    updatedAt: Value(now),
                    revision: Value(revision),
                  ),
                );
        if (changed != 1) {
          throw const NoteException(
            NoteFailureCode.staleRevision,
            'The note changed in another view.',
          );
        }
        await _change(row.id, 'update', revision, _hash(request.body));
      });
    } catch (_) {
      await _atomicWrite(row.relativeFilePath, oldBody);
      if (oldHash == null) {
        // Metadata remains authoritative and unchanged.
      }
      rethrow;
    }
    return NoteSaveAck(
      note: _model(await _row(row.id)),
      requestId: request.requestId,
      saveGeneration: request.saveGeneration,
    );
  }

  @override
  Future<Note> rename(String id, String title, {required int revision}) async {
    final current = await open(id);
    final relative = await _uniqueRelative(title, id);
    final from = File(_path(current.note.relativeFilePath));
    final to = File(_path(relative));
    await to.parent.create(recursive: true);
    await from.rename(to.path);
    try {
      await _database.transaction(() async {
        final changed =
            await (_database.update(_database.notes)..where(
                  (row) => row.id.equals(id) & row.revision.equals(revision),
                ))
                .write(
                  db.NotesCompanion(
                    title: Value(Note.validateTitle(title)),
                    relativeFilePath: Value(relative),
                    updatedAt: Value(_clock.now()),
                    revision: Value(revision + 1),
                  ),
                );
        if (changed != 1) {
          throw const NoteException(
            NoteFailureCode.staleRevision,
            'The note changed in another view.',
          );
        }
        await _change(id, 'rename', revision + 1, current.note.contentHash);
      });
    } catch (_) {
      await to.rename(from.path);
      rethrow;
    }
    return _model(await _row(id));
  }

  Future<Note> _lifecycle(
    String id,
    int revision,
    String operation, {
    bool archive = false,
    bool trash = false,
    bool clearArchive = false,
    bool clearTrash = false,
  }) async {
    final row = await _row(id);
    if (row.revision != revision) {
      throw const NoteException(
        NoteFailureCode.staleRevision,
        'The note changed in another view.',
      );
    }
    final now = _clock.now();
    await _database.transaction(() async {
      final changed =
          await (_database.update(_database.notes)..where(
                (candidate) =>
                    candidate.id.equals(id) &
                    candidate.revision.equals(revision),
              ))
              .write(
                db.NotesCompanion(
                  archivedAt: Value(
                    clearArchive ? null : (archive ? now : row.archivedAt),
                  ),
                  deletedAt: Value(
                    clearTrash ? null : (trash ? now : row.deletedAt),
                  ),
                  updatedAt: Value(now),
                  revision: Value(revision + 1),
                ),
              );
      if (changed != 1) {
        throw const NoteException(
          NoteFailureCode.staleRevision,
          'The note changed in another view.',
        );
      }
      await _change(id, operation, revision + 1, row.contentHash);
    });
    return _model(await _row(id));
  }

  @override
  Future<Note> archive(String id, {required int revision}) =>
      _lifecycle(id, revision, 'archive', archive: true);
  @override
  Future<Note> restore(String id, {required int revision}) =>
      _lifecycle(id, revision, 'restore', clearArchive: true);
  @override
  Future<Note> trash(String id, {required int revision}) =>
      _lifecycle(id, revision, 'trash', trash: true);
  @override
  Future<Note> restoreFromTrash(String id, {required int revision}) =>
      _lifecycle(id, revision, 'restoreTrash', clearTrash: true);

  @override
  Future<void> permanentlyDelete(String id) async {
    final row = await _row(id);
    if (row.deletedAt == null) {
      throw const NoteException(
        NoteFailureCode.notInTrash,
        'Only notes in Trash can be permanently deleted.',
      );
    }
    final file = File(_path(row.relativeFilePath));
    final quarantine = File('${file.path}.deleting');
    if (await file.exists()) await file.rename(quarantine.path);
    try {
      await _database.transaction(() async {
        await (_database.delete(
          _database.notes,
        )..where((candidate) => candidate.id.equals(id))).go();
        await _change(id, 'permanentDelete', row.revision + 1, row.contentHash);
      });
      if (await quarantine.exists()) await quarantine.delete();
    } catch (_) {
      if (await quarantine.exists()) await quarantine.rename(file.path);
      rethrow;
    }
  }

  @override
  Future<List<String>> recover() async {
    final actions = <String>[];
    final notesDirectory = Directory(_path('notes'));
    await notesDirectory.create(recursive: true);
    final rows = await all();
    final owned = rows
        .map((note) => p.normalize(note.relativeFilePath))
        .toSet();
    await for (final entity in notesDirectory.list()) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: _vault.root);
      if (relative.endsWith('.tmp')) {
        await entity.delete();
        actions.add('removedInterruptedAutosave');
      } else if (relative.endsWith('.md') && !owned.contains(relative)) {
        actions.add('orphanNoteFile');
      }
    }
    for (final note in rows) {
      if (!await File(_path(note.relativeFilePath)).exists()) {
        actions.add('missingNoteFile:${note.id}');
      }
    }
    return actions;
  }

  Future<String> _uniqueRelative(String title, String id) async {
    final slug = Note.validateTitle(title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = slug.isEmpty ? 'note' : slug;
    var relative = p.join('notes', '$base.md');
    var suffix = 2;
    while (await File(_path(relative)).exists()) {
      relative = p.join('notes', '$base-$suffix.md');
      suffix++;
    }
    return relative == p.join('notes', '$base.md') && base == 'note'
        ? p.join('notes', 'note-${id.substring(0, 8)}.md')
        : relative;
  }

  Future<void> _atomicWrite(String relative, String body) async {
    final destination = File(_path(relative));
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.${_uuid.v4()}.tmp');
    final sink = temporary.openWrite();
    sink.write(body);
    await sink.flush();
    await sink.close();
    final backup = File('${destination.path}.bak');
    if (await destination.exists()) await destination.rename(backup.path);
    try {
      await temporary.rename(destination.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists()) await backup.rename(destination.path);
      rethrow;
    }
  }

  String _hash(String body) => sha256.convert(utf8.encode(body)).toString();

  Future<void> _change(
    String id,
    String operation,
    int revision,
    String? hash,
  ) => _database
      .into(_database.changeLogs)
      .insert(
        db.ChangeLogsCompanion.insert(
          entityType: 'note',
          entityId: id,
          operation: operation,
          revision: revision,
          changedAt: _clock.now(),
          deviceId: _deviceId,
          payloadHash: Value(hash),
        ),
      );
}
