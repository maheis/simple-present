import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class SqliteStorage {
  Database? _db;
  late final String _dbPath;
  bool _debugMode = false;

  Future<void> init({required bool debugMode}) async {
    _debugMode = debugMode;
    final dir = await getApplicationDocumentsDirectory();
    final dbFileName = _debugMode ? 'debug_simplepresent.db' : 'simplepresent.db';
    _dbPath = '${dir.path}/$dbFileName';

    final dbFile = File(_dbPath);
    final bool existed = await dbFile.exists();

    _db = sqlite3.open(_dbPath);
    _createTablesIfNeeded();
    _ensureTimeEntryColumns();

    if (!existed) {
      // First start with DB: migrate JSON files from disk.
      await _migrateJsonFiles(dir);
    }

    // Ensure normalized task table is populated (also handles older DB layouts).
    await _migrateLegacyListsToTasks(dir);
  }

  void _createTablesIfNeeded() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS kv_store (
        name TEXT PRIMARY KEY,
        content TEXT NOT NULL
      );
    ''');

    // Legacy table from previous migration step; keep for backward compatibility.
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS lists (
        name TEXT PRIMARY KEY,
        content TEXT NOT NULL
      );
    ''');

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        list_name TEXT NOT NULL,
        task_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        PRIMARY KEY(list_name, task_id)
      );
    ''');

    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_tasks_list_order ON tasks(list_name, sort_order);',
    );

    // Dedicated time tracking table — survives task moves between lists.
    // Use an autoincrement primary key so multiple time windows per task/date
    // can be recorded as separate rows. Older DBs used a composite PK
    // (task_id, date) which prevented appending multiple entries.
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS time_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id   TEXT NOT NULL,
        date      TEXT NOT NULL,
        task_text TEXT NOT NULL DEFAULT '',
        task_done INTEGER NOT NULL DEFAULT 0,
        task_in_progress INTEGER NOT NULL DEFAULT 0,
        stopwatch_seconds INTEGER NOT NULL DEFAULT 0,
        work_minutes      INTEGER NOT NULL DEFAULT 0,
        recorded_at       INTEGER NOT NULL DEFAULT 0
      );
    ''');
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_time_entries_date ON time_entries(date);',
    );
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_time_entries_task ON time_entries(task_id);',
    );
    _db!.execute(
      'CREATE INDEX IF NOT EXISTS idx_time_entries_done ON time_entries(task_done, date);',
    );
  }

  Future<void> _migrateJsonFiles(Directory dir) async {
    final prefix = _debugMode ? 'debug_' : '';
    final candidates = [
      '${prefix}simplepresent_today.json',
      '${prefix}simplepresent_done.json',
      '${prefix}simplepresent_backlog.json',
      '${prefix}simplepresent_trash.json',
      '${prefix}simplepresent_settings.json',
    ];

    for (final name in candidates) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) {
        try {
          final text = await f.readAsString();
          // Validate JSON
          jsonDecode(text);
          _db!.execute('INSERT OR REPLACE INTO kv_store(name, content) VALUES(?, ?);', [name, text]);
          _db!.execute('INSERT OR REPLACE INTO lists(name, content) VALUES(?, ?);', [name, text]);
        } catch (_) {
          // ignore invalid JSON or read errors
        }
      } else {
        // ensure default empty list for list files
        if (name.endsWith('.json') && name != 'simplepresent_settings.json') {
          _db!.execute('INSERT OR IGNORE INTO kv_store(name, content) VALUES(?, ?);', [name, '[]']);
          _db!.execute('INSERT OR IGNORE INTO lists(name, content) VALUES(?, ?);', [name, '[]']);
        }
      }
    }
  }

  Future<void> _migrateLegacyListsToTasks(Directory dir) async {
    final countRs = _db!.select('SELECT COUNT(*) AS c FROM tasks;');
    final existingCount = (countRs.first['c'] as int?) ?? 0;
    if (existingCount > 0) return;

    final prefix = _debugMode ? 'debug_' : '';
    final listNames = <String>{
      '${prefix}simplepresent_today.json',
      '${prefix}simplepresent_done.json',
      '${prefix}simplepresent_backlog.json',
      '${prefix}simplepresent_trash.json',
    };

    for (final listName in listNames) {
      String? raw;

      final kv = _db!.select('SELECT content FROM kv_store WHERE name = ? LIMIT 1;', [listName]);
      if (kv.isNotEmpty) {
        raw = kv.first['content'] as String?;
      }

      if (raw == null) {
        final legacy = _db!.select('SELECT content FROM lists WHERE name = ? LIMIT 1;', [listName]);
        if (legacy.isNotEmpty) {
          raw = legacy.first['content'] as String?;
        }
      }

      if (raw == null) {
        final f = File('${dir.path}/$listName');
        if (await f.exists()) {
          try {
            raw = await f.readAsString();
          } catch (_) {
            raw = null;
          }
        }
      }

      if (raw == null) continue;

      List<dynamic> parsed;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        parsed = decoded;
      } catch (_) {
        continue;
      }

      _db!.execute('DELETE FROM tasks WHERE list_name = ?;', [listName]);
      final insert = _db!.prepare(
        'INSERT OR REPLACE INTO tasks(list_name, task_id, sort_order, payload_json) VALUES(?, ?, ?, ?);',
      );
      try {
        for (var i = 0; i < parsed.length; i++) {
          final entry = parsed[i];
          if (entry is! Map) continue;
          final map = Map<String, dynamic>.from(entry.cast<String, dynamic>());
          final taskId = (map['id'] ?? '').toString();
          if (taskId.isEmpty) continue;
          final payload = jsonEncode(map);
          insert.execute([listName, taskId, i, payload]);
        }
      } finally {
        insert.dispose();
      }
    }
  }

  Future<void> _ensureTimeEntryColumns() async {
    final columns = <String>{};
    try {
      final rows = _db!.select('PRAGMA table_info(time_entries);');
      for (final row in rows) {
        final name = (row['name'] ?? '').toString();
        if (name.isNotEmpty) columns.add(name);
      }
    } catch (_) {
      return;
    }

    // If the existing table uses a composite primary key (task_id, date),
    // migrate to the new schema with an autoincrement id so we can append
    // multiple time windows per day for the same task.
    try {
      final rows = _db!.select('PRAGMA table_info(time_entries);');
      var hasId = false;
      var pkTaskId = false;
      var pkDate = false;
      for (final row in rows) {
        final name = (row['name'] ?? '').toString();
        final pk = (row['pk'] is int) ? (row['pk'] as int) : int.tryParse((row['pk'] ?? '').toString()) ?? 0;
        if (name == 'id') hasId = true;
        if (name == 'task_id' && pk > 0) pkTaskId = true;
        if (name == 'date' && pk > 0) pkDate = true;
      }
      if (!hasId && (pkTaskId && pkDate)) {
        // perform migration: create new table, copy data, replace
        _db!.execute('BEGIN TRANSACTION;');
        _db!.execute('''
          CREATE TABLE IF NOT EXISTS time_entries_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id   TEXT NOT NULL,
            date      TEXT NOT NULL,
            task_text TEXT NOT NULL DEFAULT '',
            task_done INTEGER NOT NULL DEFAULT 0,
            task_in_progress INTEGER NOT NULL DEFAULT 0,
            stopwatch_seconds INTEGER NOT NULL DEFAULT 0,
            work_minutes      INTEGER NOT NULL DEFAULT 0,
            recorded_at       INTEGER NOT NULL DEFAULT 0
          );
        ''');
        _db!.execute('INSERT INTO time_entries_new(task_id, date, task_text, task_done, task_in_progress, stopwatch_seconds, work_minutes, recorded_at) SELECT task_id, date, task_text, task_done, task_in_progress, stopwatch_seconds, work_minutes, recorded_at FROM time_entries;');
        _db!.execute('DROP TABLE time_entries;');
        _db!.execute('ALTER TABLE time_entries_new RENAME TO time_entries;');
        _db!.execute('COMMIT;');
      }
    } catch (_) {
      try {
        _db!.execute('ROLLBACK;');
      } catch (_) {}
    }

    void addColumnIfMissing(String columnSql, String name) {
      if (!columns.contains(name)) {
        _db!.execute('ALTER TABLE time_entries ADD COLUMN $columnSql;');
      }
    }

    addColumnIfMissing('task_done INTEGER NOT NULL DEFAULT 0', 'task_done');
    addColumnIfMissing(
        'task_in_progress INTEGER NOT NULL DEFAULT 0', 'task_in_progress');
  }

  List<Map<String, dynamic>> readTaskList(String listName) {
    final rows = _db!.select(
      'SELECT payload_json FROM tasks WHERE list_name = ? ORDER BY sort_order ASC;',
      [listName],
    );
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final payload = (row['payload_json'] ?? '').toString();
      if (payload.isEmpty) continue;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          out.add(decoded);
        }
      } catch (_) {}
    }
    return out;
  }

  void writeTaskList(String listName, List<Map<String, dynamic>> items) {
    _db!.execute('BEGIN TRANSACTION;');
    try {
      _db!.execute('DELETE FROM tasks WHERE list_name = ?;', [listName]);
      final insert = _db!.prepare(
        'INSERT OR REPLACE INTO tasks(list_name, task_id, sort_order, payload_json) VALUES(?, ?, ?, ?);',
      );
      try {
        for (var i = 0; i < items.length; i++) {
          final map = items[i];
          final taskId = (map['id'] ?? '').toString();
          if (taskId.isEmpty) continue;
          insert.execute([listName, taskId, i, jsonEncode(map)]);
        }
      } finally {
        insert.dispose();
      }
      _db!.execute('COMMIT;');
    } catch (_) {
      _db!.execute('ROLLBACK;');
      rethrow;
    }
  }

  bool taskListExists(String listName) {
    final rs = _db!.select(
      'SELECT 1 FROM tasks WHERE list_name = ? LIMIT 1;',
      [listName],
    );
    return rs.isNotEmpty;
  }

  String? read(String name) {
    final stmt = _db!.prepare('SELECT content FROM kv_store WHERE name = ?');
    try {
      final result = stmt.select([name]);
      if (result.isEmpty) return null;
      return result.first['content'] as String;
    } finally {
      stmt.dispose();
    }
  }

  void write(String name, String content) {
    _db!.execute('INSERT OR REPLACE INTO kv_store(name, content) VALUES(?, ?);', [name, content]);
  }

  bool exists(String name) {
    final stmt = _db!.prepare('SELECT 1 FROM kv_store WHERE name = ? LIMIT 1');
    try {
      final result = stmt.select([name]);
      return result.isNotEmpty;
    } finally {
      stmt.dispose();
    }
  }

  void dispose() {
    _db?.dispose();
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // Time-entry persistence
  // ---------------------------------------------------------------------------

  /// Upsert a time-entry row for [taskId] on [date] (YYYY-MM-DD).
  /// Replaces the stored values completely — caller passes the current totals.
  void upsertTimeEntry({
    required String taskId,
    required String taskText,
    required String date,
    required bool taskDone,
    required bool taskInProgress,
    required int stopwatchSeconds,
    required int workMinutes,
    int? recordedAt,
  }) {
    final now = recordedAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    // Insert a new time-entry row. We intentionally append entries so each
    // recorded time window is preserved for the given date. Aggregation
    // per-day is performed when reading entries for the stats view.
    _db!.execute(
      '''
      INSERT INTO time_entries(task_id, date, task_text, task_done, task_in_progress, stopwatch_seconds, work_minutes, recorded_at)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [taskId, date, taskText, taskDone ? 1 : 0, taskInProgress ? 1 : 0, stopwatchSeconds, workMinutes, now],
    );
  }

  /// Returns all time-entry rows for [date] (YYYY-MM-DD), ordered by recorded_at.
  List<Map<String, dynamic>> getTimeEntriesForDate(String date) {
    final rows = _db!.select(
      'SELECT task_id, task_text, task_done, task_in_progress, stopwatch_seconds, work_minutes, recorded_at '
      'FROM time_entries WHERE date = ? ORDER BY recorded_at ASC;',
      [date],
    );
    return rows.map((r) => {
      'task_id': r['task_id'] as String,
      'task_text': r['task_text'] as String,
      'task_done': (r['task_done'] as int?) ?? 0,
      'task_in_progress': (r['task_in_progress'] as int?) ?? 0,
      'stopwatch_seconds': (r['stopwatch_seconds'] as int?) ?? 0,
      'work_minutes': (r['work_minutes'] as int?) ?? 0,
      'recorded_at': (r['recorded_at'] as int?) ?? 0,
    }).toList();
  }

  /// Returns all distinct dates that have at least one time entry, most recent first.
  List<String> getTimeEntryDates() {
    final rows = _db!.select(
      'SELECT DISTINCT date FROM time_entries ORDER BY date DESC;',
    );
    return rows.map((r) => (r['date'] as String)).toList();
  }
}
