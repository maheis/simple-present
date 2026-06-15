import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class SqliteStorage {
  Database? _db;
  late final String _dbPath;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _dbPath = '${dir.path}/simplepresent.db';

    final dbFile = File(_dbPath);
    final bool existed = await dbFile.exists();

    _db = sqlite3.open(_dbPath);
    _createTablesIfNeeded();

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
  }

  Future<void> _migrateJsonFiles(Directory dir) async {
    final candidates = [
      'simplepresent_today.json',
      'simplepresent_done.json',
      'simplepresent_backlog.json',
      'simplepresent_trash.json',
      'simplepresent_settings.json',
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

    final listNames = <String>{
      'simplepresent_today.json',
      'simplepresent_done.json',
      'simplepresent_backlog.json',
      'simplepresent_trash.json',
      'debug_simplepresent_today.json',
      'debug_simplepresent_done.json',
      'debug_simplepresent_backlog.json',
      'debug_simplepresent_trash.json',
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
}
