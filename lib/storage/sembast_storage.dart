import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

int dailyTimeEntryDelta(int currentTotal, int previousTotal) {
  return currentTotal > previousTotal ? currentTotal - previousTotal : 0;
}

Map<String, dynamic> normalizeLegacyTimeEntry(
  Map<String, dynamic> entry, {
  required int previousStopwatchSeconds,
  required int previousWorkMinutes,
}) {
  final normalized = Map<String, dynamic>.from(entry);
  final stopwatchTotal =
      int.tryParse((entry['total_stopwatch_seconds'] ?? '').toString());
  final workTotal =
      int.tryParse((entry['total_work_minutes'] ?? '').toString());
  final stopwatchValue =
      int.tryParse((entry['stopwatch_seconds'] ?? 0).toString()) ?? 0;
  final workValue = int.tryParse((entry['work_minutes'] ?? 0).toString()) ?? 0;

  if (stopwatchTotal == null) {
    normalized['stopwatch_seconds'] =
        dailyTimeEntryDelta(stopwatchValue, previousStopwatchSeconds);
    normalized['total_stopwatch_seconds'] = stopwatchValue;
  }
  if (workTotal == null) {
    normalized['work_minutes'] =
        dailyTimeEntryDelta(workValue, previousWorkMinutes);
    normalized['total_work_minutes'] = workValue;
  }
  return normalized;
}

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
    _migrateLegacyTimeEntries();
  }

  Future<void> refresh() async {
    final currentDb = _db;
    if (_dbPath.isEmpty) return;
    try {
      await currentDb?.close();
    } catch (_) {}
    try {
      _db = await databaseFactoryIo.openDatabase(_dbPath);
    } catch (_) {
      _db = currentDb;
    }
    final db = _db;
    if (db == null) return;
    _listsCache.clear();
    _rawCache.clear();
    _timeCache.clear();

    try {
      final recs = await _listsStore.find(db);
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

    try {
      final recs = await _rawStore.find(db);
      for (final r in recs) {
        final key = r.key;
        final val = r.value;
        if (val is String) _rawCache[key] = val;
      }
    } catch (_) {}

    try {
      final recs = await _timeStore.find(db);
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
    _migrateLegacyTimeEntries();
  }

  void _migrateLegacyTimeEntries() {
    final dates = _timeCache.keys.toList()..sort();
    final stopwatchTotals = <String, int>{};
    final workTotals = <String, int>{};
    for (final date in dates) {
      final entries = _timeCache[date] ?? const <Map<String, dynamic>>[];
      var changed = false;
      final normalizedEntries = <Map<String, dynamic>>[];
      for (final entry in entries) {
        final taskId = entry['task_id']?.toString() ?? '';
        final normalized = normalizeLegacyTimeEntry(
          entry,
          previousStopwatchSeconds: stopwatchTotals[taskId] ?? 0,
          previousWorkMinutes: workTotals[taskId] ?? 0,
        );
        changed = changed ||
            !entry.containsKey('total_stopwatch_seconds') ||
            !entry.containsKey('total_work_minutes');
        final stopwatchTotal = int.tryParse(
                normalized['total_stopwatch_seconds']?.toString() ?? '') ??
            0;
        final workTotal =
            int.tryParse(normalized['total_work_minutes']?.toString() ?? '') ??
                0;
        if (taskId.isNotEmpty) {
          stopwatchTotals[taskId] = stopwatchTotal;
          workTotals[taskId] = workTotal;
        }
        normalizedEntries.add(normalized);
      }
      if (!changed) continue;
      _timeCache[date] = normalizedEntries;
      unawaited(() async {
        try {
          await _timeStore.record(date).put(_db!, normalizedEntries);
        } catch (_) {}
      }());
    }
  }

  List<Map<String, dynamic>> readTaskList(String listName) {
    final key = _canonicalKey(listName);
    final list = _listsCache[key];
    if (list == null) return const [];
    // Return a defensive copy
    return List<Map<String, dynamic>>.from(
        list.map((m) => Map<String, dynamic>.from(m)));
  }

  Future<void> writeTaskList(
      String listName, List<Map<String, dynamic>> items) {
    final key = _canonicalKey(listName);
    // update cache
    _listsCache[key] = List<Map<String, dynamic>>.from(
        items.map((m) => Map<String, dynamic>.from(m)));
    // persist async
    return () async {
      try {
        await _listsStore.record(key).put(_db!, items);
      } catch (_) {}
    }();
  }

  bool taskListExists(String listName) {
    return _listsCache.containsKey(_canonicalKey(listName));
  }

  String? read(String name) {
    return _rawCache[_canonicalKey(name)];
  }

  void write(String name, String content) {
    unawaited(writeAsync(name, content).catchError((_) {}));
  }

  Future<void> writeAsync(String name, String content) async {
    final key = _canonicalKey(name);
    _rawCache[key] = content;
    await _rawStore.record(key).put(_db!, content);
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
    bool valuesAreDaily = false,
    int? totalStopwatchSeconds,
    int? totalWorkMinutes,
  }) {
    unawaited(() async {
      final now = recordedAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      final list = _timeCache[date] ?? <Map<String, dynamic>>[];
      var previousStopwatchSeconds = 0;
      var previousWorkMinutes = 0;
      if (!valuesAreDaily) {
        final previousDates = _timeCache.keys
            .where((entryDate) => entryDate.compareTo(date) < 0)
            .toList()
          ..sort((a, b) => b.compareTo(a));
        for (final previousDate in previousDates) {
          final previousEntries = _timeCache[previousDate] ?? const [];
          Map<String, dynamic>? previousEntry;
          for (final candidate in previousEntries) {
            if (candidate['task_id']?.toString() == taskId) {
              previousEntry = candidate;
              break;
            }
          }
          if (previousEntry == null) continue;
          previousStopwatchSeconds = int.tryParse(
                  (previousEntry['total_stopwatch_seconds'] ??
                          previousEntry['stopwatch_seconds'] ??
                          0)
                      .toString()) ??
              0;
          previousWorkMinutes = int.tryParse(
                  (previousEntry['total_work_minutes'] ??
                          previousEntry['work_minutes'] ??
                          0)
                      .toString()) ??
              0;
          break;
        }
      }
      final cumulativeStopwatchSeconds =
          totalStopwatchSeconds ?? stopwatchSeconds;
      final cumulativeWorkMinutes = totalWorkMinutes ?? workMinutes;
      final entry = <String, dynamic>{
        'task_id': taskId,
        'task_text': taskText,
        'task_done': taskDone ? 1 : 0,
        'task_in_progress': taskInProgress ? 1 : 0,
        'stopwatch_seconds': valuesAreDaily
            ? stopwatchSeconds
            : dailyTimeEntryDelta(
                cumulativeStopwatchSeconds, previousStopwatchSeconds),
        'work_minutes': valuesAreDaily
            ? workMinutes
            : dailyTimeEntryDelta(cumulativeWorkMinutes, previousWorkMinutes),
        'total_stopwatch_seconds': cumulativeStopwatchSeconds,
        'total_work_minutes': cumulativeWorkMinutes,
        'recorded_at': now,
      };
      final newList = List<Map<String, dynamic>>.from(list);
      final existingIndex =
          newList.indexWhere((item) => item['task_id']?.toString() == taskId);
      if (existingIndex >= 0) {
        final existingRecordedAt = int.tryParse(
                newList[existingIndex]['recorded_at']?.toString() ?? '') ??
            0;
        if (existingRecordedAt > now) return;
        newList[existingIndex] = entry;
      } else {
        newList.add(entry);
      }
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
