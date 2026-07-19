import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../foundation/foundation.dart';

part 'app_database.g.dart';

class Vaults extends Table {
  TextColumn get id => text()();
  IntColumn get schemaVersion => integer()();
  TextColumn get displayName => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get deviceId => text()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProjectNodes extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(ProjectNodes, #id)();
  TextColumn get nodeType => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().nullable()();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId =>
      text().withDefault(const Constant('local'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get parentTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get projectNodeId =>
      text().nullable().references(ProjectNodes, #id)();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  TextColumn get recurrenceRule => text().nullable()();
  RealColumn get sortOrder => real().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId => text()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get colorToken => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId =>
      text().withDefault(const Constant('local'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskTags extends Table {
  TextColumn get taskId => text().references(Tasks, #id)();
  TextColumn get tagId => text().references(Tags, #id)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId =>
      text().withDefault(const Constant('local'))();
  @override
  Set<Column<Object>> get primaryKey => {taskId, tagId};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get projectNodeId =>
      text().nullable().references(ProjectNodes, #id)();
  TextColumn get linkedTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get title => text()();
  TextColumn get relativeFilePath => text().unique()();
  TextColumn get contentHash => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId =>
      text().withDefault(const Constant('local'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AudioNotes extends Table {
  TextColumn get id => text()();
  TextColumn get projectNodeId =>
      text().nullable().references(ProjectNodes, #id)();
  TextColumn get linkedTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get linkedNoteId => text().nullable().references(Notes, #id)();
  TextColumn get title => text()();
  TextColumn get relativeFilePath => text().unique()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get mimeType => text().withDefault(const Constant('audio/wav'))();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId =>
      text().withDefault(const Constant('local'))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerType => text()();
  TextColumn get ownerId => text()();
  TextColumn get fileName => text()();
  TextColumn get relativeFilePath => text().unique()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get fileSize => integer()();
  TextColumn get contentHash => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get scope => text().withDefault(const Constant('vault'))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get originatingDeviceId =>
      text().withDefault(const Constant('local'))();
  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get fingerprint => text().nullable()();
  TextColumn get scopes =>
      text().withDefault(const Constant('sync.read,sync.write'))();
  DateTimeColumn get pairedAt => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get lastSynchronizedAt => dateTime().nullable()();
  DateTimeColumn get revokedAt => dateTime().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ChangeLogs extends Table {
  IntColumn get sequence => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  IntColumn get revision => integer()();
  DateTimeColumn get changedAt => dateTime()();
  TextColumn get deviceId => text()();
  TextColumn get payloadHash => text().nullable()();
}

class ConflictRecords extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get localRevision => integer()();
  IntColumn get remoteRevision => integer()();
  TextColumn get conflictType => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolution => text().nullable()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

class SyncMutationReceipts extends Table {
  TextColumn get deviceId => text()();
  TextColumn get mutationId => text()();
  TextColumn get resultJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {deviceId, mutationId};
}

@DriftDatabase(
  tables: [
    Vaults,
    ProjectNodes,
    Tasks,
    Tags,
    TaskTags,
    Notes,
    AudioNotes,
    Attachments,
    AppPreferences,
    Devices,
    ChangeLogs,
    ConflictRecords,
    SyncMutationReceipts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor) {
    DatabaseOpenAudit.recordOpen();
  }

  factory AppDatabase.open(String databasePath) => AppDatabase(
    LazyDatabase(() async {
      await File(databasePath).parent.create(recursive: true);
      return NativeDatabase.createInBackground(File(databasePath));
    }),
  );

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createIndexes();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await customStatement(
          "UPDATE tasks SET status = 'open' WHERE status = 'inbox'",
        );
        await _createIndexes();
      }
      if (from < 3) {
        await migrator.addColumn(
          projectNodes,
          projectNodes.originatingDeviceId,
        );
        await migrator.addColumn(tags, tags.deletedAt);
        await migrator.addColumn(tags, tags.revision);
        await migrator.addColumn(tags, tags.originatingDeviceId);
        await migrator.addColumn(taskTags, taskTags.updatedAt);
        await migrator.addColumn(taskTags, taskTags.deletedAt);
        await migrator.addColumn(taskTags, taskTags.revision);
        await migrator.addColumn(taskTags, taskTags.originatingDeviceId);
        await migrator.addColumn(notes, notes.originatingDeviceId);
        await migrator.addColumn(audioNotes, audioNotes.originatingDeviceId);
        await migrator.addColumn(appPreferences, appPreferences.deletedAt);
        await migrator.addColumn(appPreferences, appPreferences.revision);
        await migrator.addColumn(
          appPreferences,
          appPreferences.originatingDeviceId,
        );
        await migrator.addColumn(devices, devices.scopes);
        await migrator.addColumn(devices, devices.lastSynchronizedAt);
        await migrator.createTable(syncMutationReceipts);
        await _createIndexes();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA synchronous = NORMAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_due_status_idx '
      'ON tasks (due_at, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_start_idx ON tasks (start_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_project_sort_idx '
      'ON tasks (project_node_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_lifecycle_idx '
      'ON tasks (deleted_at, archived_at, completed_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_title_idx ON tasks (title COLLATE NOCASE)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS project_parent_sort_idx '
      'ON project_nodes (parent_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS project_name_idx '
      'ON project_nodes (name COLLATE NOCASE)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS change_entity_idx '
      'ON change_logs (entity_type, entity_id, sequence)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS change_sequence_type_idx '
      'ON change_logs (sequence, entity_type)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS conflict_unresolved_idx '
      'ON conflict_records (resolved_at, created_at)',
    );
  }
}
