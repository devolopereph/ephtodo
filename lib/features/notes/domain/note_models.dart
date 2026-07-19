enum NoteLifecycle { active, archived, trash }

enum NoteFailureCode {
  invalidTitle,
  missing,
  staleRevision,
  staleSave,
  pathUnsafe,
  vaultUnavailable,
  fileMissing,
  fileOperation,
  notInTrash,
}

final class NoteException implements Exception {
  const NoteException(this.code, this.message);
  final NoteFailureCode code;
  final String message;

  @override
  String toString() => 'NoteException(${code.name})';
}

final class Note {
  const Note({
    required this.id,
    required this.title,
    required this.relativeFilePath,
    required this.contentHash,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    this.projectNodeId,
    this.linkedTaskId,
    this.archivedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String relativeFilePath;
  final String contentHash;
  final String? projectNodeId;
  final String? linkedTaskId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final DateTime? deletedAt;
  final int revision;

  NoteLifecycle get lifecycle => deletedAt != null
      ? NoteLifecycle.trash
      : archivedAt != null
      ? NoteLifecycle.archived
      : NoteLifecycle.active;

  static String validateTitle(String value) {
    final title = value.trim();
    if (title.isEmpty || title.length > 240) {
      throw const NoteException(
        NoteFailureCode.invalidTitle,
        'A note title must contain 1–240 characters.',
      );
    }
    return title;
  }
}

final class NoteDocument {
  const NoteDocument({required this.note, required this.body});
  final Note note;
  final String body;
}

final class NoteSaveRequest {
  const NoteSaveRequest({
    required this.noteId,
    required this.title,
    required this.body,
    required this.expectedRevision,
    required this.requestId,
    required this.saveGeneration,
    this.projectNodeId,
    this.linkedTaskId,
  });

  final String noteId;
  final String title;
  final String body;
  final int expectedRevision;
  final String requestId;
  final int saveGeneration;
  final String? projectNodeId;
  final String? linkedTaskId;
}

final class NoteSaveAck {
  const NoteSaveAck({
    required this.note,
    required this.requestId,
    required this.saveGeneration,
  });
  final Note note;
  final String requestId;
  final int saveGeneration;
}
