enum AudioFailureCode {
  unavailable,
  permissionDenied,
  invalidState,
  zeroByte,
  pathUnsafe,
  missing,
  notInTrash,
  fileOperation,
}

final class AudioNoteException implements Exception {
  const AudioNoteException(this.code, this.message);
  final AudioFailureCode code;
  final String message;
}

final class AudioNote {
  const AudioNote({
    required this.id,
    required this.title,
    required this.relativeFilePath,
    required this.durationMs,
    required this.mimeType,
    required this.fileSize,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.projectNodeId,
    this.linkedTaskId,
    this.linkedNoteId,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String relativeFilePath;
  final int durationMs;
  final String mimeType;
  final int fileSize;
  final String? projectNodeId;
  final String? linkedTaskId;
  final String? linkedNoteId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;
}
