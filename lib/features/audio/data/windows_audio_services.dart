import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../domain/audio_services.dart';

final class RecordAudioRecorderService implements AudioRecorderService {
  RecordAudioRecorderService({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  AudioRecorderState _state = AudioRecorderState.idle;
  String? _temporaryPath;

  @override
  AudioRecorderState get state => _state;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> startWav(String absoluteTemporaryPath) async {
    if (_state != AudioRecorderState.idle) {
      throw StateError('Recorder is already active.');
    }
    await Directory(p.dirname(absoluteTemporaryPath)).create(recursive: true);
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: absoluteTemporaryPath,
    );
    _temporaryPath = absoluteTemporaryPath;
    _state = AudioRecorderState.recording;
  }

  @override
  Future<void> pause() async {
    if (_state != AudioRecorderState.recording) return;
    await _recorder.pause();
    _state = AudioRecorderState.paused;
  }

  @override
  Future<void> resume() async {
    if (_state != AudioRecorderState.paused) return;
    await _recorder.resume();
    _state = AudioRecorderState.recording;
  }

  @override
  Future<String?> stop() async {
    if (_state == AudioRecorderState.idle) return null;
    final path = await _recorder.stop();
    _state = AudioRecorderState.idle;
    _temporaryPath = null;
    return path;
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    final path = _temporaryPath;
    _state = AudioRecorderState.idle;
    _temporaryPath = null;
    if (path != null) await File(path).delete().catchError((_) => File(path));
  }

  @override
  Future<void> dispose() async {
    if (_state != AudioRecorderState.idle) await cancel();
    await _recorder.dispose();
  }
}

typedef _PlaySoundNative = Int32 Function(Pointer<Utf16>, IntPtr, Uint32);
typedef _PlaySoundDart = int Function(Pointer<Utf16>, int, int);

final class WinmmAudioPlaybackService implements AudioPlaybackService {
  WinmmAudioPlaybackService()
    : _playSound = DynamicLibrary.open(
        'winmm.dll',
      ).lookupFunction<_PlaySoundNative, _PlaySoundDart>('PlaySoundW');

  final _PlaySoundDart _playSound;
  static const _sndAsync = 0x0001;
  static const _sndFilename = 0x00020000;
  static const _sndPurge = 0x0040;

  @override
  Future<void> playWav(String absolutePath) async {
    if (!await File(absolutePath).exists()) {
      throw FileSystemException('Audio file is missing.');
    }
    final pointer = absolutePath.toNativeUtf16();
    try {
      if (_playSound(pointer, 0, _sndAsync | _sndFilename) == 0) {
        throw StateError('PlaySoundW rejected the WAV file.');
      }
    } finally {
      calloc.free(pointer);
    }
  }

  @override
  Future<void> stop() async {
    final empty = ''.toNativeUtf16();
    try {
      _playSound(empty, 0, _sndPurge);
    } finally {
      calloc.free(empty);
    }
  }
}

final class LocalAudioFileService implements AudioFileService {
  const LocalAudioFileService();

  @override
  Future<int> size(String absolutePath) => File(absolutePath).length();

  @override
  Future<void> finalize(String temporaryPath, String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    if (await destination.exists()) {
      throw const FileSystemException('Audio filename collision.');
    }
    await File(temporaryPath).rename(destinationPath);
  }

  @override
  Future<void> delete(String absolutePath) => File(absolutePath).delete();

  @override
  Future<List<String>> cleanOrphanedTemporaryFiles(
    String audioDirectory,
  ) async {
    final removed = <String>[];
    final directory = Directory(audioDirectory);
    if (!await directory.exists()) return removed;
    await for (final entity in directory.list()) {
      if (entity is File &&
          (entity.path.endsWith('.recording') ||
              entity.path.endsWith('.recording.wav'))) {
        await entity.delete();
        removed.add(p.basename(entity.path));
      }
    }
    return removed;
  }
}
