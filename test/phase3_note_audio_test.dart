import 'dart:io';

import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:ephtodo/core/vault/vault_service.dart';
import 'package:ephtodo/core/windowing/window_protocol.dart';
import 'package:ephtodo/features/audio/application/audio_coordinator.dart';
import 'package:ephtodo/features/audio/data/windows_audio_services.dart';
import 'package:ephtodo/features/audio/domain/audio_models.dart';
import 'package:ephtodo/features/audio/domain/audio_services.dart';
import 'package:ephtodo/features/notes/data/drift_note_repository.dart';
import 'package:ephtodo/features/notes/domain/note_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory parent;
  late VaultHandle vault;
  late VaultService vaultService;
  late AppDatabase database;
  late DriftNoteRepository notes;
  late AudioCoordinator Function(AudioRecorderService) makeAudio;
  final clock = FixedClock(DateTime.utc(2026, 7, 19, 12));

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('ephtodo-phase3-');
    vaultService = VaultService(const LocalFileSystem(), clock);
    vault = await vaultService.createInParent(parent.path);
    database = AppDatabase(NativeDatabase.memory());
    notes = DriftNoteRepository(
      database: database,
      vault: vault,
      vaultService: vaultService,
      clock: clock,
      deviceId: 'fictional-device',
    );
    makeAudio = (recorder) => AudioCoordinator(
      database: database,
      vault: vault,
      vaultService: vaultService,
      clock: clock,
      deviceId: 'fictional-device',
      recorder: recorder,
      playback: _FakePlayback(),
      files: const LocalAudioFileService(),
    );
  });

  tearDown(() async {
    await database.close();
    if (await parent.exists()) await parent.delete(recursive: true);
  });

  test('note create read save hash revision and change log', () async {
    final created = await notes.create(title: 'Fictional', body: 'First body');
    final ack = await notes.save(
      NoteSaveRequest(
        noteId: created.note.id,
        title: 'Fictional',
        body: 'Second body',
        expectedRevision: 1,
        requestId: 'request-1',
        saveGeneration: 1,
      ),
    );
    expect(ack.note.revision, 2);
    expect((await notes.open(created.note.id)).body, 'Second body');
    expect(ack.note.contentHash, isNotEmpty);
    expect(await database.select(database.changeLogs).get(), hasLength(2));
  });

  test('note filename collisions are resolved without overwrite', () async {
    final first = await notes.create(title: 'Same title', body: 'first');
    final second = await notes.create(title: 'Same title', body: 'second');
    expect(first.note.relativeFilePath, isNot(second.note.relativeFilePath));
    expect((await notes.open(first.note.id)).body, 'first');
  });

  test(
    'note search includes file body without requiring title match',
    () async {
      await notes.create(title: 'Unrelated title', body: 'needle in body');
      final result = await notes.watch(query: 'needle').first;
      expect(result.single.title, 'Unrelated title');
    },
  );

  test('stale save cannot overwrite newer note content', () async {
    final created = await notes.create(title: 'Safe', body: 'original');
    await notes.save(
      NoteSaveRequest(
        noteId: created.note.id,
        title: created.note.title,
        body: 'new',
        expectedRevision: 1,
        requestId: 'new',
        saveGeneration: 2,
      ),
    );
    await expectLater(
      notes.save(
        NoteSaveRequest(
          noteId: created.note.id,
          title: created.note.title,
          body: 'stale',
          expectedRevision: 1,
          requestId: 'stale',
          saveGeneration: 1,
        ),
      ),
      throwsA(isA<NoteException>()),
    );
    expect((await notes.open(created.note.id)).body, 'new');
  });

  test('stale rename rolls the file move back', () async {
    final created = await notes.create(title: 'Original', body: 'safe');
    final saved = await notes.save(
      NoteSaveRequest(
        noteId: created.note.id,
        title: created.note.title,
        body: 'newer',
        expectedRevision: created.note.revision,
        requestId: 'newer-save',
        saveGeneration: 1,
      ),
    );
    await expectLater(
      notes.rename(created.note.id, 'Stale rename', revision: 1),
      throwsA(
        isA<NoteException>().having(
          (error) => error.code,
          'code',
          NoteFailureCode.staleRevision,
        ),
      ),
    );
    final reopened = await notes.open(created.note.id);
    expect(reopened.note.relativeFilePath, saved.note.relativeFilePath);
    expect(reopened.body, 'newer');
  });

  test('note archive trash restore and permanent-delete eligibility', () async {
    var note = (await notes.create(title: 'Lifecycle')).note;
    await expectLater(
      notes.permanentlyDelete(note.id),
      throwsA(isA<NoteException>()),
    );
    note = await notes.archive(note.id, revision: note.revision);
    note = await notes.restore(note.id, revision: note.revision);
    note = await notes.trash(note.id, revision: note.revision);
    note = await notes.restoreFromTrash(note.id, revision: note.revision);
    note = await notes.trash(note.id, revision: note.revision);
    await notes.permanentlyDelete(note.id);
    expect(await notes.all(), isEmpty);
  });

  test(
    'note recovery reports missing metadata files and cleans temp files',
    () async {
      final note = (await notes.create(title: 'Recovery')).note;
      await File(
        vaultService.resolveInside(vault, note.relativeFilePath),
      ).delete();
      final temp = File(p.join(vault.root, 'notes', 'interrupted.tmp'));
      await temp.writeAsString('temporary');
      final actions = await notes.recover();
      expect(actions, contains('removedInterruptedAutosave'));
      expect(
        actions.any((action) => action.startsWith('missingNoteFile:')),
        isTrue,
      );
    },
  );

  test(
    'audio recording finalizes WAV metadata and rejects direct delete',
    () async {
      final recorder = _FakeRecorder(bytes: List.filled(100, 1));
      final audio = makeAudio(recorder);
      await audio.start();
      final item = await audio.stop(title: 'Fictional audio');
      expect(item.mimeType, 'audio/wav');
      expect(item.fileSize, 100);
      expect(File(audio.resolve(item.relativeFilePath)).existsSync(), isTrue);
      await expectLater(
        audio.permanentlyDelete(item.id),
        throwsA(isA<AudioNoteException>()),
      );
      await audio.trash(item.id, revision: item.revision);
      await audio.permanentlyDelete(item.id);
      expect(File(audio.resolve(item.relativeFilePath)).existsSync(), isFalse);
      await audio.dispose();
    },
  );

  test('audio pause resume cancel and orphan cleanup are safe', () async {
    final recorder = _FakeRecorder(bytes: List.filled(100, 1));
    final audio = makeAudio(recorder);
    await audio.start();
    await recorder.pause();
    expect(recorder.state, AudioRecorderState.paused);
    await recorder.resume();
    expect(recorder.state, AudioRecorderState.recording);
    await audio.cancel();
    expect(recorder.state, AudioRecorderState.idle);
    final orphan = File(p.join(vault.root, 'audio', '.orphan.recording'));
    await orphan.writeAsBytes([1, 2, 3]);
    expect(await audio.recover(), contains('.orphan.recording'));
    await audio.dispose();
  });

  test('audio permission denial and Trash restore are explicit', () async {
    final denied = makeAudio(
      _FakeRecorder(bytes: List.filled(100, 1), permission: false),
    );
    await expectLater(
      denied.start(),
      throwsA(
        isA<AudioNoteException>().having(
          (error) => error.code,
          'code',
          AudioFailureCode.permissionDenied,
        ),
      ),
    );
    await denied.dispose();

    final audio = makeAudio(_FakeRecorder(bytes: List.filled(100, 1)));
    await audio.start();
    final item = await audio.stop(title: 'Restorable');
    await audio.trash(item.id, revision: item.revision);
    await audio.restoreFromTrash(item.id, revision: item.revision + 1);
    final restored = await audio.watch().first;
    expect(restored.single.id, item.id);
    expect(restored.single.revision, item.revision + 2);
    await audio.dispose();
  });

  test('zero-byte audio is rejected without metadata', () async {
    final audio = makeAudio(_FakeRecorder(bytes: const []));
    await audio.start();
    await expectLater(
      audio.stop(title: 'Empty'),
      throwsA(
        isA<AudioNoteException>().having(
          (error) => error.code,
          'code',
          AudioFailureCode.zeroByte,
        ),
      ),
    );
    expect(await database.select(database.audioNotes).get(), isEmpty);
    await audio.dispose();
  });

  test('Quick Note IPC serializes saves and rejects malformed payloads', () {
    final message = WindowEnvelope(
      type: WindowMessageType.noteAutosave,
      requestId: 'fictional-save',
      sourceWindowId: 'quick-note',
      payload: const {
        'id': 'note-1',
        'title': 'Fictional',
        'body': 'Body is not logged',
        'revision': 2,
        'saveGeneration': 4,
      },
      timestamp: clock.now(),
    );
    expect(
      WindowEnvelope.decode(message.encode()).type,
      WindowMessageType.noteAutosave,
    );
    expect(
      () => WindowEnvelope.fromJson({
        ...message.toJson(),
        'payload': {'id': 'note-1'},
      }),
      throwsA(isA<WindowProtocolException>()),
    );
    for (final lifecycle in [
      WindowMessageType.noteRename,
      WindowMessageType.noteArchive,
      WindowMessageType.noteTrash,
      WindowMessageType.noteRestore,
    ]) {
      final payload = lifecycle == WindowMessageType.noteRename
          ? <String, Object?>{'id': 'note-1', 'title': 'Renamed', 'revision': 2}
          : <String, Object?>{'id': 'note-1', 'revision': 2};
      final envelope = WindowEnvelope(
        type: lifecycle,
        requestId: 'fictional-${lifecycle.name}',
        sourceWindowId: 'quick-note',
        payload: payload,
        timestamp: clock.now(),
      );
      expect(WindowEnvelope.decode(envelope.encode()).type, lifecycle);
    }
  });
}

final class _FakeRecorder implements AudioRecorderService {
  _FakeRecorder({required this.bytes, this.permission = true});
  final List<int> bytes;
  final bool permission;
  String? path;
  AudioRecorderState _state = AudioRecorderState.idle;

  @override
  AudioRecorderState get state => _state;
  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<void> startWav(String absoluteTemporaryPath) async {
    path = absoluteTemporaryPath;
    await File(absoluteTemporaryPath).writeAsBytes(bytes);
    _state = AudioRecorderState.recording;
  }

  @override
  Future<void> pause() async => _state = AudioRecorderState.paused;
  @override
  Future<void> resume() async => _state = AudioRecorderState.recording;
  @override
  Future<String?> stop() async {
    _state = AudioRecorderState.idle;
    return path;
  }

  @override
  Future<void> cancel() async {
    _state = AudioRecorderState.idle;
  }

  @override
  Future<void> dispose() async {}
}

final class _FakePlayback implements AudioPlaybackService {
  @override
  Future<void> playWav(String absolutePath) async {}
  @override
  Future<void> stop() async {}
}
