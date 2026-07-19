enum AudioRecorderState { idle, recording, paused }

abstract interface class AudioRecorderService {
  AudioRecorderState get state;
  Future<bool> hasPermission();
  Future<void> startWav(String absoluteTemporaryPath);
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
  Future<void> cancel();
  Future<void> dispose();
}

/// Playback stays replaceable so WinMM PlaySoundW limitations never leak into
/// feature code. PlaySoundW has no seek, volume, pause, or completion events.
abstract interface class AudioPlaybackService {
  Future<void> playWav(String absolutePath);
  Future<void> stop();
}

abstract interface class AudioFileService {
  Future<int> size(String absolutePath);
  Future<void> finalize(String temporaryPath, String destinationPath);
  Future<void> delete(String absolutePath);
  Future<List<String>> cleanOrphanedTemporaryFiles(String audioDirectory);
}
