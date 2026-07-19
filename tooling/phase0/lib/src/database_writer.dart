import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'task_item.dart';

/// The only SQLite writer in the Phase 0 process.
///
/// This class is created exclusively by the main Flutter engine. Secondary
/// windows submit commands over IPC and never open the database.
class MainDatabaseWriter {
  MainDatabaseWriter._(this._database);

  final Database _database;
  static const _uuid = Uuid();

  static MainDatabaseWriter open(String vaultPath) {
    final databaseDirectory = Directory(p.join(vaultPath, 'database'))
      ..createSync(recursive: true);
    final database = sqlite3.open(
      p.join(databaseDirectory.path, 'ephtodo-phase0.sqlite'),
    );
    database.execute('PRAGMA journal_mode = WAL;');
    database.execute('PRAGMA synchronous = NORMAL;');
    database.execute('PRAGMA busy_timeout = 5000;');
    database.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        updated_at_micros INTEGER NOT NULL
      );
    ''');
    return MainDatabaseWriter._(database);
  }

  List<TaskItem> loadTasks() {
    final rows = _database.select(
      'SELECT id, title, completed, updated_at_micros '
      'FROM tasks ORDER BY updated_at_micros DESC',
    );
    return [
      for (final row in rows)
        TaskItem(
          id: row['id'] as String,
          title: row['title'] as String,
          completed: (row['completed'] as int) == 1,
          updatedAtMicros: row['updated_at_micros'] as int,
        ),
    ];
  }

  TaskItem createTask(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Task title cannot be empty.');
    }
    final task = TaskItem(
      id: _uuid.v4(),
      title: trimmed,
      completed: false,
      updatedAtMicros: DateTime.now().microsecondsSinceEpoch,
    );
    _database.execute(
      'INSERT INTO tasks (id, title, completed, updated_at_micros) '
      'VALUES (?, ?, ?, ?)',
      [task.id, task.title, 0, task.updatedAtMicros],
    );
    return task;
  }

  TaskItem setCompleted(String id, bool completed) {
    final updatedAtMicros = DateTime.now().microsecondsSinceEpoch;
    _database.execute(
      'UPDATE tasks SET completed = ?, updated_at_micros = ? WHERE id = ?',
      [completed ? 1 : 0, updatedAtMicros, id],
    );
    final rows = _database.select(
      'SELECT id, title, completed, updated_at_micros FROM tasks WHERE id = ?',
      [id],
    );
    if (rows.isEmpty) {
      throw StateError('Task does not exist: $id');
    }
    final row = rows.single;
    return TaskItem(
      id: row['id'] as String,
      title: row['title'] as String,
      completed: (row['completed'] as int) == 1,
      updatedAtMicros: row['updated_at_micros'] as int,
    );
  }

  void close() => _database.close();
}
