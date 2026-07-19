import '../domain/sync_models.dart';

abstract interface class SyncWriteCoordinator {
  Stream<SyncEvent> get events;

  Future<List<SyncDevice>> devices();
  Future<SyncDevice?> device(String id);
  Future<SyncDevice> approveDevice(PendingPairing request);
  Future<void> revokeDevice(String id);
  Future<void> touchDevice(String id, {bool synchronized = false});

  Future<SyncPullPage> pull({
    required String deviceId,
    required int afterSequence,
    required int pageSize,
    required Set<SyncEntityType> entityTypes,
  });

  Future<List<SyncMutationResult>> push({
    required String deviceId,
    required List<SyncMutation> mutations,
  });

  Future<int> latestSequence();
  Future<List<Map<String, Object?>>> unresolvedConflicts();
  Future<void> dispose();
}
