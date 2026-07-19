import 'dart:io';

// ignore_for_file: prefer_initializing_formals

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart' as db;
import '../../../core/foundation/foundation.dart';
import '../../../core/vault/vault_service.dart';
import '../domain/audio_models.dart';
import '../domain/audio_services.dart';

final class AudioCoordinator {
  AudioCoordinator({
    required db.AppDatabase database,
    required VaultHandle vault,
    required VaultService vaultService,
    required Clock clock,
    required String deviceId,
    required this.recorder,
    required this.playback,
    required this.files,
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
  final AudioRecorderService recorder;
  final AudioPlaybackService playback;
  final AudioFileService files;
  static const _uuid = Uuid();
  DateTime? _startedAt;
  DateTime? _pausedAt;
  Duration _pausedDuration = Duration.zero;
  String? _temporaryPath;

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final end = _pausedAt ?? _clock.now();
    final value = end.difference(started) - _pausedDuration;
    return value.isNegative ? Duration.zero : value;
  }

  AudioNote _model(db.AudioNote row) => AudioNote(
    id: row.id,
    title: row.title,
    relativeFilePath: row.relativeFilePath,
    durationMs: row.durationMs,
    mimeType: row.mimeType,
    fileSize: row.fileSize,
    projectNodeId: row.projectNodeId,
    linkedTaskId: row.linkedTaskId,
    linkedNoteId: row.linkedNoteId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    revision: row.revision,
  );

  String resolve(String relative) {
    if (relative != 'audio' &&
        !relative.startsWith('audio${p.separator}') &&
        !relative.startsWith('audio/')) {
      throw const AudioNoteException(
        AudioFailureCode.pathUnsafe,
        'Audio path is outside the audio directory.',
      );
    }
    try {
      return _vaultService.resolveInside(_vault, relative);
    } on VaultException {
      throw const AudioNoteException(
        AudioFailureCode.pathUnsafe,
        'Audio path is unsafe.',
      );
    }
  }

  Stream<List<AudioNote>> watch({bool includeTrash = false}) {
    final query = _database.select(_database.audioNotes);
    if (!includeTrash) query.where((row) => row.deletedAt.isNull());
    query.orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    return query.watch().map((rows) => rows.map(_model).toList());
  }

  Future<void> start() async {
    if (!await recorder.hasPermission()) {
      throw const AudioNoteException(
        AudioFailureCode.permissionDenied,
        'Microphone permission is unavailable.',
      );
    }
    final relative = p.join('audio', '.${_uuid.v4()}.recording.wav');
    final temporaryPath = resolve(relative);
    await recorder.startWav(temporaryPath);
    _temporaryPath = temporaryPath;
    _startedAt = _clock.now();
    _pausedAt = null;
    _pausedDuration = Duration.zero;
  }

  Future<void> pause() async {
    if (recorder.state != AudioRecorderState.recording) return;
    await recorder.pause();
    _pausedAt = _clock.now();
  }

  Future<void> resume() async {
    if (recorder.state != AudioRecorderState.paused) return;
    await recorder.resume();
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedDuration += _clock.now().difference(pausedAt);
    }
    _pausedAt = null;
  }

  Future<AudioNote> stop({
    required String title,
    String? projectNodeId,
    String? linkedTaskId,
    String? linkedNoteId,
  }) async {
    final temporary = await recorder.stop() ?? _temporaryPath;
    final started = _startedAt;
    final pausedAt = _pausedAt;
    final pausedDuration =
        _pausedDuration +
        (pausedAt == null ? Duration.zero : _clock.now().difference(pausedAt));
    _temporaryPath = null;
    _startedAt = null;
    _pausedAt = null;
    _pausedDuration = Duration.zero;
    if (temporary == null || started == null) {
      throw const AudioNoteException(
        AudioFailureCode.invalidState,
        'No recording is active.',
      );
    }
    final size = await files.size(temporary);
    if (size <= 44) {
      await File(temporary).delete().catchError((_) => File(temporary));
      throw const AudioNoteException(
        AudioFailureCode.zeroByte,
        'Empty recordings are rejected.',
      );
    }
    final id = _uuid.v4();
    final relative = p.join(
      'audio',
      'recording-${_clock.now().toUtc().toIso8601String().replaceAll(':', '-')}-${id.substring(0, 8)}.wav',
    );
    final destination = resolve(relative);
    await files.finalize(temporary, destination);
    final now = _clock.now();
    final duration = (now.difference(started) - pausedDuration).inMilliseconds
        .clamp(0, 86400000);
    try {
      await _database.transaction(() async {
        await _database
            .into(_database.audioNotes)
            .insert(
              db.AudioNotesCompanion.insert(
                id: id,
                projectNodeId: Value(projectNodeId),
                linkedTaskId: Value(linkedTaskId),
                linkedNoteId: Value(linkedNoteId),
                title: title.trim().isEmpty ? 'Audio note' : title.trim(),
                relativeFilePath: relative,
                durationMs: Value(duration),
                fileSize: Value(size),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _change(id, 'create', 1);
      });
    } catch (_) {
      await files.delete(destination).catchError((_) {});
      rethrow;
    }
    return _model(
      await (_database.select(
        _database.audioNotes,
      )..where((row) => row.id.equals(id))).getSingle(),
    );
  }

  Future<void> cancel() async {
    await recorder.cancel();
    final temporary = _temporaryPath;
    _temporaryPath = null;
    _startedAt = null;
    _pausedAt = null;
    _pausedDuration = Duration.zero;
    if (temporary != null && await File(temporary).exists()) {
      await files.delete(temporary);
    }
  }

  Future<AudioNote> rename(
    String id,
    String title, {
    required int revision,
  }) async {
    final now = _clock.now();
    await _database.transaction(() async {
      final changed =
          await (_database.update(_database.audioNotes)..where(
                (row) => row.id.equals(id) & row.revision.equals(revision),
              ))
              .write(
                db.AudioNotesCompanion(
                  title: Value(
                    title.trim().isEmpty ? 'Audio note' : title.trim(),
                  ),
                  updatedAt: Value(now),
                  revision: Value(revision + 1),
                ),
              );
      if (changed != 1) throw StateError('Stale audio revision.');
      await _change(id, 'rename', revision + 1);
    });
    return _model(
      await (_database.select(
        _database.audioNotes,
      )..where((row) => row.id.equals(id))).getSingle(),
    );
  }

  Future<AudioNote> assignProject(
    String id, {
    required int revision,
    String? projectNodeId,
  }) async {
    final now = _clock.now();
    await _database.transaction(() async {
      final changed =
          await (_database.update(_database.audioNotes)..where(
                (row) => row.id.equals(id) & row.revision.equals(revision),
              ))
              .write(
                db.AudioNotesCompanion(
                  projectNodeId: Value(projectNodeId),
                  updatedAt: Value(now),
                  revision: Value(revision + 1),
                ),
              );
      if (changed != 1) throw StateError('Stale audio revision.');
      await _change(id, 'assignProject', revision + 1);
    });
    return _model(
      await (_database.select(
        _database.audioNotes,
      )..where((row) => row.id.equals(id))).getSingle(),
    );
  }

  Future<void> trash(String id, {required int revision}) async {
    await _database.transaction(() async {
      await (_database.update(
        _database.audioNotes,
      )..where((row) => row.id.equals(id))).write(
        db.AudioNotesCompanion(
          deletedAt: Value(_clock.now()),
          updatedAt: Value(_clock.now()),
          revision: Value(revision + 1),
        ),
      );
      await _change(id, 'trash', revision + 1);
    });
  }

  Future<void> restoreFromTrash(String id, {required int revision}) async {
    await _database.transaction(() async {
      final changed =
          await (_database.update(_database.audioNotes)..where(
                (row) =>
                    row.id.equals(id) &
                    row.revision.equals(revision) &
                    row.deletedAt.isNotNull(),
              ))
              .write(
                db.AudioNotesCompanion(
                  deletedAt: const Value(null),
                  updatedAt: Value(_clock.now()),
                  revision: Value(revision + 1),
                ),
              );
      if (changed != 1) {
        throw const AudioNoteException(
          AudioFailureCode.invalidState,
          'Audio note is stale or is not in Trash.',
        );
      }
      await _change(id, 'restoreTrash', revision + 1);
    });
  }

  Future<void> permanentlyDelete(String id) async {
    final row = await (_database.select(
      _database.audioNotes,
    )..where((candidate) => candidate.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    if (row.deletedAt == null) {
      throw const AudioNoteException(
        AudioFailureCode.notInTrash,
        'Audio must be in Trash before permanent deletion.',
      );
    }
    final path = resolve(row.relativeFilePath);
    final quarantine = '$path.deleting';
    if (await File(path).exists()) await File(path).rename(quarantine);
    try {
      await _database.transaction(() async {
        await (_database.delete(
          _database.audioNotes,
        )..where((candidate) => candidate.id.equals(id))).go();
        await _change(id, 'permanentDelete', row.revision + 1);
      });
      if (await File(quarantine).exists()) await files.delete(quarantine);
    } catch (_) {
      if (await File(quarantine).exists()) await File(quarantine).rename(path);
      rethrow;
    }
  }

  Future<List<String>> recover() =>
      files.cleanOrphanedTemporaryFiles(resolve('audio'));

  Future<void> dispose() async {
    if (recorder.state != AudioRecorderState.idle) await cancel();
    await playback.stop();
    await recorder.dispose();
  }

  Future<void> _change(String id, String operation, int revision) => _database
      .into(_database.changeLogs)
      .insert(
        db.ChangeLogsCompanion.insert(
          entityType: 'audioNote',
          entityId: id,
          operation: operation,
          revision: revision,
          changedAt: _clock.now(),
          deviceId: _deviceId,
        ),
      );
}
