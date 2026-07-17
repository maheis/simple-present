import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// A simple Sembast-backed storage for task lists, raw blobs, and time entries.
/// It keeps an in-memory cache so read methods remain synchronous.
class SembastStorage {
  late final String _storageRoot;
  late final String _dbPath;
  Database? _db;

  // Stores: 'lists' -> map filename -> List<dynamic>
  final _listsStore = StoreRef<String, Object?>('lists');
  // 'raw' for arbitrary string blobs (settings, notes)
  final _rawStore = StoreRef<String, Object?>('raw');
  // 'time_entries' -> map date -> List<dynamic>
  final _timeStore = StoreRef<String, Object?>('time_entries');

  // In-memory caches to keep APIs synchronous where the app expects it.
  final Map<String, List<Map<String, dynamic>>> _listsCache = {};
  final Map<String, String> _rawCache = {};
  final Map<String, List<Map<String, dynamic>>> _timeCache = {};

  String _canonicalKey(String key) {
    return key.trim();
  }

  Future<void> init({required bool debugMode}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folderName = debugMode ? 'simplepresent-debug' : 'simplepresent';
    final sub = Directory(p.join(dir.path, folderName));
    try {
      if (!await sub.exists()) await sub.create(recursive: true);
    } catch (_) {}
    _storageRoot = sub.path;

    _dbPath = p.join(_storageRoot, 'simplepresent.db');
    _db = await databaseFactoryIo.openDatabase(_dbPath);

    // Load lists
    try {
      final recs = await _listsStore.find(_db!);
      for (final r in recs) {
        final key = r.key;
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
        final key = r.key;
        final val = r.value;
        if (val is String) _rawCache[key] = val;
      }
    } catch (_) {}
    // Load time entries
    try {
      final recs = await _timeStore.find(_db!);
      for (final r in recs) {
        final key = r.key;
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
    final key = _canonicalKey(listName);
    final list = _listsCache[key];
    if (list == null) return const [];
    // Return a defensive copy
    return List<Map<String, dynamic>>.from(
        list.map((m) => Map<String, dynamic>.from(m)));
  }

  void writeTaskList(String listName, List<Map<String, dynamic>> items) {
    final key = _canonicalKey(listName);
    // update cache
    _listsCache[key] = List<Map<String, dynamic>>.from(
        items.map((m) => Map<String, dynamic>.from(m)));
    // persist async
    unawaited(() async {
      try {
        await _listsStore.record(key).put(_db!, items);
      } catch (_) {}
    }());
  }

  bool taskListExists(String listName) {
    return _listsCache.containsKey(_canonicalKey(listName));
  }

  String? read(String name) {
    return _rawCache[_canonicalKey(name)];
  }

  void write(String name, String content) {
    final key = _canonicalKey(name);
    _rawCache[key] = content;
    unawaited(() async {
      try {
        await _rawStore.record(key).put(_db!, content);
      } catch (_) {}
    }());
  }

  bool exists(String name) {
    return _rawCache.containsKey(_canonicalKey(name));
  }

  /// Delete a raw value from the storage (both cache and persistent store).
  void deleteRaw(String name) {
    unawaited(deleteRawAsync(name));
  }

  Future<void> deleteRawAsync(String name) async {
    final key = _canonicalKey(name);
    _rawCache.remove(key);
    try {
      await _rawStore.record(key).delete(_db!);
    } catch (_) {}
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
    return List<Map<String, dynamic>>.from(
        list.map((m) => Map<String, dynamic>.from(m)));
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
