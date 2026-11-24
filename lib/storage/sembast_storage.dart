import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:simple_present/time_booking.dart';

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
  final _timeBookingsStore = StoreRef<String, Object?>('time_bookings');
  final _activeTimersStore = StoreRef<String, Object?>('active_time_sessions');
  final _worklogStore = StoreRef<String, Object?>('task_worklog');
  final _worklogStateStore = StoreRef<String, Object?>('task_worklog_state');

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
    await _migrateLegacyTimeEntries();
    await _migrateLegacyTimeBookings();
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
    await _migrateLegacyTimeEntries();
    await _migrateLegacyTimeBookings();
  }

  Future<void> _migrateLegacyTimeEntries() async {
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
      await _timeStore.record(date).put(_db!, normalizedEntries);
    }
  }

  Future<void> _migrateLegacyTimeBookings() async {
    const markerKey = 'time_bookings_migration_v1';
    try {
      final marker = await _rawStore.record(markerKey).get(_db!);
      if (marker == 'done') return;

      await _db!.transaction((transaction) async {
        final transactionMarker =
            await _rawStore.record(markerKey).get(transaction);
        if (transactionMarker == 'done') return;

        final records = await _timeStore.find(transaction);
        for (final record in records) {
          if (record.value is! List) continue;
          for (final rawEntry in (record.value as List).whereType<Map>()) {
            final entry = Map<String, dynamic>.from(rawEntry);
            final taskId = entry['task_id']?.toString() ?? '';
            if (taskId.isEmpty) continue;

            final workMinutes =
                int.tryParse(entry['work_minutes']?.toString() ?? '') ?? 0;
            final stopwatchSeconds =
                int.tryParse(entry['stopwatch_seconds']?.toString() ?? '') ?? 0;
            final roundedStopwatchMinutes = stopwatchSeconds <= 0
                ? 0
                : ((stopwatchSeconds + (15 * 60) - 1) ~/ (15 * 60)) * 15;
            final bookedMinutes = workMinutes + roundedStopwatchMinutes;
            if (bookedMinutes <= 0) continue;

            final id =
                'legacy-${record.key}-${base64Url.encode(utf8.encode(taskId))}';
            if (await _timeBookingsStore.record(id).get(transaction) != null) {
              continue;
            }
            final recordedAt =
                int.tryParse(entry['recorded_at']?.toString() ?? '') ?? 0;
            final bookedAt = recordedAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(recordedAt * 1000)
                : DateTime.tryParse('${record.key}T12:00') ?? DateTime.now();
            final booking = TimeBooking(
              id: id,
              bookingDate: record.key,
              bookingTime:
                  '${bookedAt.hour.toString().padLeft(2, '0')}:${bookedAt.minute.toString().padLeft(2, '0')}',
              bookedMinutes: bookedMinutes,
              taskId: taskId,
              taskText: entry['task_text']?.toString() ?? '(gelöschte Aufgabe)',
            );
            await _timeBookingsStore
                .record(id)
                .put(transaction, booking.toJson());
          }
        }
        await _rawStore.record(markerKey).put(transaction, 'done');
      });
      _rawCache[markerKey] = 'done';
    } catch (_) {}
  }

  Future<void> startTaskTimer({
    required String taskId,
    required String taskText,
    DateTime? now,
  }) async {
    final startedAt = now ?? DateTime.now();
    await _db!.transaction((transaction) async {
      if (await _activeTimersStore.record(taskId).get(transaction) != null) {
        return;
      }
      await _activeTimersStore.record(taskId).put(transaction, {
        'id': '${startedAt.microsecondsSinceEpoch}-$taskId',
        'task_id': taskId,
        'task_text': taskText,
        'started_at': startedAt.toIso8601String(),
      });
    });
  }

  Future<Map<String, dynamic>?> readTaskTimer(String taskId) async {
    final value = await _activeTimersStore.record(taskId).get(_db!);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<TimeBooking> _timerBookings(Map<String, dynamic> timer, DateTime now) {
    final startedAt = DateTime.tryParse(timer['started_at']?.toString() ?? '');
    if (startedAt == null) return [];
    return splitTrackedTime(
      sessionId: timer['id'].toString(),
      taskId: timer['task_id'].toString(),
      taskText: timer['task_text'].toString(),
      startedAt: startedAt,
      endedAt: now,
    );
  }

  Future<void> stopTaskTimer(String taskId, {DateTime? now}) async {
    final stoppedAt = now ?? DateTime.now();
    await _db!.transaction((transaction) async {
      final raw = await _activeTimersStore.record(taskId).get(transaction);
      if (raw is! Map) return;
      for (final booking
          in _timerBookings(Map<String, dynamic>.from(raw), stoppedAt)) {
        await _timeBookingsStore
            .record(booking.id)
            .put(transaction, booking.toJson());
      }
      await _activeTimersStore.record(taskId).delete(transaction);
    });
  }

  Future<void> resetTaskTimer(String taskId) async {
    await _db!.transaction((transaction) async {
      await _activeTimersStore.record(taskId).delete(transaction);
      final records = await _timeBookingsStore.find(transaction);
      for (final record in records) {
        if (record.value is! Map) continue;
        final booking = TimeBooking.fromJson(
            Map<String, dynamic>.from(record.value as Map));
        if (booking.taskId != taskId || booking.trackedSeconds <= 0) continue;
        if (booking.bookedMinutes <= 0) {
          await _timeBookingsStore.record(record.key).delete(transaction);
        } else {
          final updated = Map<String, dynamic>.from(record.value as Map)
            ..remove('tracked_seconds');
          await _timeBookingsStore.record(record.key).put(transaction, updated);
        }
      }
    });
  }

  Future<List<TimeBooking>> readTimeBookings(
      {bool includeRunning = false}) async {
    final bookings = await _db!.transaction((transaction) async {
      final records = await _timeBookingsStore.find(transaction);
      final byId = <String, TimeBooking>{};
      for (final record in records) {
        if (record.value is Map) {
          final booking = TimeBooking.fromJson(
              Map<String, dynamic>.from(record.value as Map));
          byId[booking.id] = booking;
        }
      }
      if (includeRunning) {
        final now = DateTime.now();
        final timers = await _activeTimersStore.find(transaction);
        for (final timer in timers) {
          if (timer.value is Map) {
            for (final booking in _timerBookings(
                Map<String, dynamic>.from(timer.value as Map), now)) {
              byId[booking.id] = booking;
            }
          }
        }
      }
      return byId.values.toList();
    });
    bookings.sort((a, b) {
      final dateCompare = b.bookingDate.compareTo(a.bookingDate);
      return dateCompare != 0
          ? dateCompare
          : b.bookingTime.compareTo(a.bookingTime);
    });
    return bookings;
  }

  Future<void> saveTimeBooking(TimeBooking booking) async {
    if (booking.id.isEmpty ||
        booking.taskId.isEmpty ||
        booking.bookingDate.isEmpty ||
        booking.bookingTime.isEmpty ||
        (booking.bookedMinutes <= 0 && booking.trackedSeconds <= 0)) {
      throw ArgumentError('Invalid time booking');
    }
    await _timeBookingsStore.record(booking.id).put(_db!, booking.toJson());
  }

  Future<void> deleteTimeBooking(String id) async {
    await _timeBookingsStore.record(id).delete(_db!);
  }

  Future<List<Map<String, dynamic>>> exportTimeBookings() async {
    final bookings = await readTimeBookings(includeRunning: true);
    return bookings.map((booking) => booking.toJson()).toList();
  }

  Future<void> importTimeBookings(List<dynamic> entries,
      {bool merge = false}) async {
    await _db!.transaction((transaction) async {
      if (!merge) await _timeBookingsStore.delete(transaction);
      for (final raw in entries.whereType<Map>()) {
        final booking = TimeBooking.fromJson(Map<String, dynamic>.from(raw));
        if (booking.id.isEmpty ||
            booking.taskId.isEmpty ||
            (booking.bookedMinutes <= 0 && booking.trackedSeconds <= 0)) {
          continue;
        }
        await _timeBookingsStore
            .record(booking.id)
            .put(transaction, booking.toJson());
      }
    });
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
      String listName, List<Map<String, dynamic>> items) async {
    final key = _canonicalKey(listName);
    final snapshot = (jsonDecode(jsonEncode(items)) as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    await _db!.transaction((transaction) async {
      final stored = await _listsStore.record(key).get(transaction);
      final previousItems = stored is List
          ? stored.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
      final previousById = {
        for (final item in previousItems) item['id']?.toString(): item,
      };
      final currentIds = snapshot.map((item) => item['id']?.toString()).toSet();
      final sameMembers = previousItems.length == snapshot.length &&
          previousById.keys.toSet().containsAll(currentIds);
      final timestamp = DateTime.now().toUtc().toIso8601String();

      Future<void> append(String taskId, Map<String, dynamic> event) async {
        await _appendWorklogEntry(transaction, taskId, {
          'timestamp': timestamp,
          ...event,
        });
      }

      for (var index = 0; index < snapshot.length; index++) {
        final item = snapshot[index];
        final taskId = item['id']?.toString() ?? '';
        if (taskId.isEmpty) continue;
        final rawState =
            await _worklogStateStore.record(taskId).get(transaction);
        Map<String, dynamic>? state =
            rawState is Map ? Map<String, dynamic>.from(rawState) : null;
        if (state == null) {
          final lists = await _listsStore.find(transaction);
          for (final list in lists) {
            if (list.value is! List) continue;
            for (final candidate in (list.value as List).whereType<Map>()) {
              if (candidate['id']?.toString() == taskId) {
                state = {'task': candidate, 'list': list.key, 'present': true};
                break;
              }
            }
            if (state != null) break;
          }
        }
        final before = state?['task'] is Map
            ? Map<String, dynamic>.from(state!['task'] as Map)
            : <String, dynamic>{};
        final changes = <String, dynamic>{};
        for (final field in {...before.keys, ...item.keys}..remove('id')) {
          if (jsonEncode(before[field]) != jsonEncode(item[field])) {
            changes[field] = {'before': before[field], 'after': item[field]};
          }
        }
        final moved = state != null && state['list'] != key;
        final restored = state != null && !moved && state['present'] == false;
        final oldIndex = previousItems
            .indexWhere((previous) => previous['id']?.toString() == taskId);
        final reordered = sameMembers && oldIndex >= 0 && oldIndex != index;
        if (state == null ||
            moved ||
            restored ||
            changes.isNotEmpty ||
            reordered) {
          await append(taskId, {
            'action': state == null
                ? 'created'
                : moved
                    ? 'moved'
                    : restored
                        ? 'restored'
                        : reordered && changes.isEmpty
                            ? 'reordered'
                            : 'changed',
            'task_text': item['text'],
            'list': key,
            if (moved) 'from_list': state['list'],
            if (reordered) 'position': {'before': oldIndex, 'after': index},
            'changes': changes,
          });
        }
        await _worklogStateStore.record(taskId).put(transaction, {
          'task': item,
          'list': key,
          'present': true,
        });
      }
      for (final previous in previousItems) {
        final taskId = previous['id']?.toString() ?? '';
        if (taskId.isEmpty || currentIds.contains(taskId)) continue;
        final state = await _worklogStateStore.record(taskId).get(transaction);
        if (state is Map && state['list'] != key) continue;
        await append(taskId, {
          'action': 'removed',
          'task_text': previous['text'],
          'list': key,
          'changes': <String, dynamic>{},
        });
        await _worklogStateStore.record(taskId).put(transaction, {
          'task': previous,
          'list': key,
          'present': false,
        });
      }
      await _listsStore.record(key).put(transaction, snapshot);
    });
    _listsCache[key] = snapshot;
  }

  Future<List<Map<String, dynamic>>> readTaskWorklog(String taskId) async {
    final raw = await _worklogStore.record(taskId).get(_db!);
    return raw is List
        ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : [];
  }

  Future<void> _appendWorklogEntry(
      DatabaseClient client, String taskId, Map<String, dynamic> event) async {
    final raw = await _worklogStore.record(taskId).get(client);
    final entries = raw is List ? List<Object?>.from(raw) : <Object?>[];
    entries.add({
      'id':
          '${DateTime.now().microsecondsSinceEpoch}-$taskId-${entries.length}',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      ...event,
    });
    await _worklogStore.record(taskId).put(client, entries);
  }

  Future<Map<String, dynamic>> exportWorklogs() async {
    final records = await _worklogStore.find(_db!);
    return {for (final record in records) record.key: record.value};
  }

  Future<void> importWorklogs(Map<String, dynamic> histories) async {
    await _db!.transaction((transaction) async {
      for (final history in histories.entries) {
        if (history.value is! List) continue;
        final raw = await _worklogStore.record(history.key).get(transaction);
        final entries = raw is List
            ? raw.whereType<Map>().map(Map<String, dynamic>.from).toList()
            : <Map<String, dynamic>>[];
        final knownIds = entries.map((entry) => entry['id']).toSet();
        for (final entry in (history.value as List).whereType<Map>()) {
          final id = entry['id'];
          if (id is! String || id.isEmpty || !knownIds.add(id)) continue;
          if (DateTime.tryParse((entry['timestamp'] ?? '').toString()) ==
              null) {
            continue;
          }
          entries.add(Map<String, dynamic>.from(entry));
        }
        await _worklogStore.record(history.key).put(transaction, entries);
      }
    });
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

  Future<void> upsertTimeEntry({
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
    return () async {
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
        await _db!.transaction((transaction) async {
          final changes = <String, dynamic>{};
          final previous = existingIndex >= 0 ? list[existingIndex] : null;
          for (final field in ['stopwatch_seconds', 'work_minutes']) {
            final before = previous?[field] ?? 0;
            if (before != entry[field]) {
              changes['booked_$field'] = {
                'before': before,
                'after': entry[field]
              };
            }
          }
          if (changes.isNotEmpty) {
            await _appendWorklogEntry(transaction, taskId, {
              'action': 'time_booked',
              'date': date,
              'task_text': taskText,
              'changes': changes,
            });
          }
          await _timeStore.record(date).put(transaction, newList);
        });
      } catch (_) {}
    }();
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
