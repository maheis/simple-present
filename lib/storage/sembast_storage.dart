import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

/// A simple Sembast-backed storage that exposes the same minimal API the
/// app expects from the original file-based `SqliteStorage` class. It keeps
/// an in-memory cache so read methods remain synchronous for compatibility.
class SqliteStorage {
  late final String _storageRoot;
  Database? _db;

  // Stores: 'lists' -> map filename -> List<dynamic>
  final _listsStore = stringMapStoreFactory.store('lists');
  // 'raw' for arbitrary string blobs (settings, notes)
  final _rawStore = stringMapStoreFactory.store('raw');
  // 'time_entries' -> map date -> List<dynamic>
  final _timeStore = stringMapStoreFactory.store('time_entries');

  // In-memory caches to keep APIs synchronous where the app expects it.
  final Map<String, List<Map<String, dynamic>>> _listsCache = {};
  final Map<String, String> _rawCache = {};
  final Map<String, List<Map<String, dynamic>>> _timeCache = {};

  Future<void> init({required bool debugMode}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folderName = debugMode ? 'simplepresent-debug' : 'simplepresent';
    final sub = Directory(p.join(dir.path, folderName));
    try {
      if (!await sub.exists()) await sub.create(recursive: true);
    } catch (_) {}
    _storageRoot = sub.path;

    final dbPath = p.join(_storageRoot, 'simplepresent.db');
    _db = await databaseFactoryIo.openDatabase(dbPath);

    // Load lists
    try {
      final recs = await _listsStore.find(_db!);
      for (final r in recs) {
        final key = r.key as String;
        final val = r.value;
        if (val is List) {
          _listsCache[key] = val
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      }
    } catch (_) {}

    // Load raw blobs
    try {
      final recs = await _rawStore.find(_db!);
      for (final r in recs) {
        final key = r.key as String;
        final val = r.value;
        if (val is String) _rawCache[key] = val;
      }
    } catch (_) {}

    // Load time entries
    try {
      final recs = await _timeStore.find(_db!);
      for (final r in recs) {
        final key = r.key as String;
        final val = r.value;
        if (val is List) {
          _timeCache[key] = val
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> readTaskList(String listName) {
    final list = _listsCache[listName];
    if (list == null) return const [];
    // Return a defensive copy
    return List<Map<String, dynamic>>.from(list.map((m) => Map.from(m)));
  }

  void writeTaskList(String listName, List<Map<String, dynamic>> items) {
    // update cache
    _listsCache[listName] = List<Map<String, dynamic>>.from(
        items.map((m) => Map<String, dynamic>.from(m)));
    // persist async
    unawaited(() async {
      try {
        await _listsStore.record(listName).put(_db!, items);
      } catch (_) {}
    }());
  }

  bool taskListExists(String listName) {
    return _listsCache.containsKey(listName);
  }

  String? read(String name) {
    return _rawCache[name];
  }

  void write(String name, String content) {
    _rawCache[name] = content;
    unawaited(() async {
      try {
        await _rawStore.record(name).put(_db!, content);
      } catch (_) {}
    }());
  }

  bool exists(String name) {
    return _rawCache.containsKey(name);
  }

  void dispose() {
    unawaited(() async {
      try {
        await _db?.close();
      } catch (_) {}
    }());
  }

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
    unawaited(() async {
      final now = recordedAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      final list = _timeCache[date] ?? <Map<String, dynamic>>[];
      final entry = <String, dynamic>{
        'task_id': taskId,
        'task_text': taskText,
        'task_done': taskDone ? 1 : 0,
        'task_in_progress': taskInProgress ? 1 : 0,
        'stopwatch_seconds': stopwatchSeconds,
        'work_minutes': workMinutes,
        'recorded_at': now,
      };
      final newList = List<Map<String, dynamic>>.from(list)..add(entry);
      _timeCache[date] = newList;
      try {
        await _timeStore.record(date).put(_db!, newList);
      } catch (_) {}
    }());
  }

  List<Map<String, dynamic>> getTimeEntriesForDate(String date) {
    final list = _timeCache[date];
    if (list == null) return const [];
    return List<Map<String, dynamic>>.from(list.map((m) => Map.from(m)));
  }

  List<String> getTimeEntryDates() {
    try {
      final dates = _timeCache.keys.toList();
      dates.sort((a, b) => b.compareTo(a));
      return dates;
    } catch (_) {
      return const [];
    }
  }
}
