import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

typedef _PlaySoundWNative =
    Int32 Function(Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound);
typedef _PlaySoundWDart =
    int Function(Pointer<Utf16> pszSound, int hmod, int fdwSound);

/// WAV playback through winmm.dll `PlaySoundW`.
///
/// Phase 0 initially used the `audioplayers` package, but its Windows
/// implementation emits platform-channel events from a non-platform thread,
/// which corrupts the Flutter engine and crashes the process
/// (0xc0000005 in flutter_windows.dll) seconds after playback. A direct
/// Win32 call has no such thread hazard and needs no extra native plugin.
class _WinmmPlayer {
  _WinmmPlayer()
    : _playSound = DynamicLibrary.open(
        'winmm.dll',
      ).lookupFunction<_PlaySoundWNative, _PlaySoundWDart>('PlaySoundW');

  final _PlaySoundWDart _playSound;

  static const _sndAsync = 0x0001;
  static const _sndNoDefault = 0x0002;
  static const _sndFilename = 0x00020000;

  bool play(String path) {
    final native = path.toNativeUtf16();
    try {
      return _playSound(native, 0, _sndFilename | _sndAsync | _sndNoDefault) !=
          0;
    } finally {
      calloc.free(native);
    }
  }

  void stop() {
    _playSound(nullptr, 0, 0);
  }
}

class AudioPocService {
  final AudioRecorder _recorder = AudioRecorder();
  final _WinmmPlayer _player = _WinmmPlayer();

  String? lastRecordingPath;

  Future<List<InputDevice>> listInputDevices() => _recorder.listInputDevices();

  Future<void> start(String vaultPath, {InputDevice? device}) async {
    final audioDirectory = Directory(p.join(vaultPath, 'audio'));
    await audioDirectory.create(recursive: true);
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final output = p.join(audioDirectory.path, 'phase0-$timestamp.wav');
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 44100,
        numChannels: 1,
        device: device,
      ),
      path: output,
    );
    lastRecordingPath = output;
  }

  Future<void> pause() => _recorder.pause();

  Future<void> resume() => _recorder.resume();

  Future<String?> stop() async {
    final path = await _recorder.stop();
    if (path != null) {
      lastRecordingPath = path;
    }
    return path;
  }

  Future<void> play() async {
    final path = lastRecordingPath;
    if (path == null || !await File(path).exists()) {
      throw StateError('No WAV recording is available for playback.');
    }
    if (!_player.play(path)) {
      throw StateError('PlaySoundW rejected the WAV file.');
    }
  }

  Future<void> stopPlayback() async {
    _player.stop();
  }

  Future<void> dispose() async {
    _player.stop();
    await _recorder.dispose();
  }
}
