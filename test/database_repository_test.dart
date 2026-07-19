import 'dart:io';

import 'package:drift/native.dart';
import 'package:ephtodo/core/database/app_database.dart';
import 'package:ephtodo/core/database/preferences_repository.dart';
import 'package:ephtodo/core/foundation/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase database;
  final clock = FixedClock(DateTime.utc(2026, 7, 19, 12));

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('creates current Drift tables and indexes', () async {
    final objects = await database
        .customSelect(
          "SELECT name, type FROM sqlite_master "
          "WHERE type IN ('table', 'index')",
        )
        .get();
    final names = objects.map((row) => row.read<String>('name')).toSet();
    expect(database.schemaVersion, 3);
    expect(
      names,
      containsAll([
        'vaults',
        'project_nodes',
        'tasks',
        'tags',
        'task_tags',
        'notes',
        'audio_notes',
        'attachments',
        'app_preferences',
        'devices',
        'change_logs',
        'conflict_records',
        'sync_mutation_receipts',
        'task_due_status_idx',
        'project_parent_sort_idx',
        'change_entity_idx',
        'change_sequence_type_idx',
        'conflict_unresolved_idx',
      ]),
    );
  });

  test(
    'preference repository persists onboarding resume and policies',
    () async {
      final preferences = DriftPreferencesRepository(database, clock);
      final repository = OnboardingRepository(preferences);
      const expected = OnboardingSettings(
        step: 5,
        completionPolicy: CompletionPolicy.archive,
        trashRetention: TrashRetentionPolicy.never,
        themeId: 'midnightIndigo',
      );
      await repository.save(expected);
      final loaded = await repository.load();

      expect(loaded.step, 5);
      expect(loaded.completionPolicy, CompletionPolicy.archive);
      expect(loaded.trashRetention, TrashRetentionPolicy.never);
      expect(loaded.themeId, 'midnightIndigo');
    },
  );

  test('completion choices and trash cutoff remain deterministic', () {
    expect(CompletionPolicy.values, hasLength(3));
    expect(trashPurgeCutoff(TrashRetentionPolicy.never, clock), isNull);
    expect(
      trashPurgeCutoff(TrashRetentionPolicy.thirtyDays, clock),
      DateTime.utc(2026, 6, 19, 12),
    );
  });

  test('migrates a version 2 database to sync schema version 3', () async {
    await database.close();
    final root = await Directory.systemTemp.createTemp('ephtodo-migration-');
    addTearDown(() => root.delete(recursive: true));
    final path = p.join(root.path, 'migration.sqlite');
    final initial = AppDatabase.open(path);
    await initial.customSelect('SELECT 1').getSingle();
    await initial.close();

    final legacy = sqlite3.open(path);
    for (final statement in [
      'ALTER TABLE project_nodes DROP COLUMN originating_device_id',
      'ALTER TABLE tags DROP COLUMN deleted_at',
      'ALTER TABLE tags DROP COLUMN revision',
      'ALTER TABLE tags DROP COLUMN originating_device_id',
      'ALTER TABLE task_tags DROP COLUMN updated_at',
      'ALTER TABLE task_tags DROP COLUMN deleted_at',
      'ALTER TABLE task_tags DROP COLUMN revision',
      'ALTER TABLE task_tags DROP COLUMN originating_device_id',
      'ALTER TABLE notes DROP COLUMN originating_device_id',
      'ALTER TABLE audio_notes DROP COLUMN originating_device_id',
      'ALTER TABLE app_preferences DROP COLUMN deleted_at',
      'ALTER TABLE app_preferences DROP COLUMN revision',
      'ALTER TABLE app_preferences DROP COLUMN originating_device_id',
      'ALTER TABLE devices DROP COLUMN scopes',
      'ALTER TABLE devices DROP COLUMN last_synchronized_at',
      'DROP TABLE sync_mutation_receipts',
      'PRAGMA user_version = 2',
    ]) {
      legacy.execute(statement);
    }
    legacy.close();

    final migrated = AppDatabase.open(path);
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').getSingle();
    final tagColumns = await migrated
        .customSelect('PRAGMA table_info(tags)')
        .get();
    final deviceColumns = await migrated
        .customSelect('PRAGMA table_info(devices)')
        .get();
    final receiptTable = await migrated
        .customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'sync_mutation_receipts'",
        )
        .getSingleOrNull();

    expect(
      tagColumns.map((row) => row.read<String>('name')),
      containsAll(['deleted_at', 'revision', 'originating_device_id']),
    );
    expect(
      deviceColumns.map((row) => row.read<String>('name')),
      containsAll(['scopes', 'last_synchronized_at']),
    );
    expect(receiptTable, isNotNull);
    expect(
      await migrated
          .customSelect('PRAGMA user_version')
          .getSingle()
          .then((row) => row.read<int>('user_version')),
      3,
    );
  });
}
