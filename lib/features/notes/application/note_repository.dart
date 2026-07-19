import '../domain/note_models.dart';

abstract interface class NoteRepository {
  Stream<List<Note>> watch({String query = '', NoteLifecycle? lifecycle});
  Future<List<Note>> all();
  Future<NoteDocument> open(String id);
  Future<NoteDocument> create({
    required String title,
    String body = '',
    String? projectNodeId,
    String? linkedTaskId,
  });
  Future<NoteSaveAck> save(NoteSaveRequest request);
  Future<Note> rename(String id, String title, {required int revision});
  Future<Note> archive(String id, {required int revision});
  Future<Note> restore(String id, {required int revision});
  Future<Note> trash(String id, {required int revision});
  Future<Note> restoreFromTrash(String id, {required int revision});
  Future<void> permanentlyDelete(String id);
  Future<List<String>> recover();
}
