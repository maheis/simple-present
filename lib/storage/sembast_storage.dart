import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// A simple Sembast-backed storage that exposes the same minimal API the
/// app expects from the original file-based `SembastStorage` class. It keeps
/// an in-memory cache so read methods remain synchronous for compatibility.
class SembastStorage {
  late final String _storageRoot;
  late final String _dbPath;
  Database? _db;
  Database? _settingsDb;

  // Stores: 'lists' -> map filename -> List<dynamic>
  final _listsStore = StoreRef<String, Object?>('lists');
  // 'raw' for arbitrary string blobs (settings, notes)
  final _rawStore = StoreRef<String, Object?>('raw');
  // 'time_entries' -> map date -> List<dynamic>
  final _timeStore = StoreRef<String, Object?>('time_entries');

  // In-memory caches to keep APIs synchronous where the app expects it.
  final Map<String, List<Map<String, dynamic>>> _listsCache = {};
  final Map<String, String> _rawCache = {};
  final Map<String, String> _settingsCache = {};
  final Map<String, List<Map<String, dynamic>>> _timeCache = {};

  String _canonicalKey(String key) {
    var k = key.trim();
    if (k.startsWith('debug_')) k = k.substring('debug_'.length);
    return k;
  }

  List<String> _keyFallbacks(String key) {
    final canonical = _canonicalKey(key);
    // Read both canonical and legacy debug_-prefixed keys for compatibility.
    return <String>[canonical, 'debug_$canonical'];
  }

  String _listBaseName(String key) {
    var k = key.trim().toLowerCase();
    if (k.startsWith('debug_')) k = k.substring('debug_'.length);
    if (k.contains('/')) {
      final parts = k.split('/');
      k = parts.isNotEmpty ? parts.last : k;
    }
    if (k.endsWith('.json')) k = k.substring(0, k.length - 5);
    if (k.startsWith('simplepresent_'))
      k = k.substring('simplepresent_'.length);
    return k;
  }

  String? _resolveListCacheKey(String requested) {
    for (final key in _keyFallbacks(requested)) {
      if (_listsCache.containsKey(key)) return key;
    }

    final wantedBase = _listBaseName(requested);
    if (wantedBase.isEmpty) return null;
    for (final key in _listsCache.keys) {
      if (_listBaseName(key) == wantedBase) return key;
    }
    return null;
  }

  List<Map<String, dynamic>>? _readListFromDbFileFallback(String requested) {
    try {
      final dbFile = File(_dbPath);
      if (!dbFile.existsSync()) return null;

      final wantedKeys = <String>{..._keyFallbacks(requested)};
      final wantedBase = _listBaseName(requested);

      String? matchedKey;
      List<Map<String, dynamic>>? matchedList;

      for (final line in dbFile.readAsLinesSync()) {
        final t = line.trim();
        if (t.isEmpty || !t.startsWith('{')) continue;

        dynamic decoded;
        try {
          decoded = jsonDecode(t);
        } catch (_) {
          continue;
        }
        if (decoded is! Map) continue;

        final store = decoded['store']?.toString() ?? '';
        if (store != 'lists') continue;

        final key = decoded['key']?.toString() ?? '';
        if (key.isEmpty) continue;

        final keyMatches = wantedKeys.contains(key) ||
            (wantedBase.isNotEmpty && _listBaseName(key) == wantedBase);
        if (!keyMatches) continue;

        final value = decoded['value'];
        if (value is! List) continue;

        matchedKey = key;
        matchedList = value
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }

      if (matchedKey != null && matchedList != null) {
        _listsCache[matchedKey] = matchedList;
        return matchedList;
      }
    } catch (_) {}
    return null;
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

    // Open a dedicated settings DB for per-key settings to improve
    // performance when writing many small setting entries.
    try {
      _settingsDb = await databaseFactoryIo
          .openDatabase(p.join(_storageRoot, 'simplepresent_settings.db'));
      // Load settings cache
      try {
        final recs = await _rawStore.find(_settingsDb!);
        for (final r in recs) {
          final key = r.key;
          final val = r.value;
          if (val is String) _settingsCache[key] = val;
        }
      } catch (_) {}
    } catch (_) {
      _settingsDb = null;
    }

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
    final resolvedKey = _resolveListCacheKey(listName);
    var list = resolvedKey == null ? null : _listsCache[resolvedKey];
    list ??= _readListFromDbFileFallback(listName);
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
    return _resolveListCacheKey(listName) != null;
  }

  String? read(String name) {
    for (final key in _keyFallbacks(name)) {
      final val = _rawCache[key];
      if (val != null) return val;
    }
    return null;
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
    return _keyFallbacks(name).any(_rawCache.containsKey);
  }

  /// Delete a raw value from the storage (both cache and persistent store).
  void deleteRaw(String name) {
    for (final key in _keyFallbacks(name)) {
      _rawCache.remove(key);
      _settingsCache.remove(key);
      unawaited(() async {
        try {
          await _rawStore.record(key).delete(_db!);
        } catch (_) {}
      }());
      if (_settingsDb != null) {
        unawaited(() async {
          try {
            await _rawStore.record(key).delete(_settingsDb!);
          } catch (_) {}
        }());
      }
    }
  }

  /// Read a single setting (JSON-decoded if possible) stored under [key].
  dynamic readSetting(String key) {
    final k = _canonicalKey(key);
    final val =
        _settingsCache.containsKey(k) ? _settingsCache[k] : _rawCache[k];
    if (val == null) return null;
    try {
      return jsonDecode(val);
    } catch (_) {
      return val;
    }
  }

  /// Write a setting value under [key]. The value is JSON-encoded.
  void writeSetting(String key, dynamic value) {
    final k = _canonicalKey(key);
    final encoded = jsonEncode(value);
    _settingsCache[k] = encoded;
    unawaited(() async {
      try {
        if (_settingsDb != null) {
          await _rawStore.record(k).put(_settingsDb!, encoded);
        } else {
          await _rawStore.record(k).put(_db!, encoded);
        }
      } catch (_) {}
    }());
  }

  /// Read all settings available in the raw cache and return a decoded map.
  Map<String, dynamic> readAllSettings() {
    final out = <String, dynamic>{};
    // Prefer settings cache (dedicated DB). Fall back to raw cache entries.
    for (final entry in _settingsCache.entries) {
      try {
        out[entry.key] = jsonDecode(entry.value);
      } catch (_) {
        out[entry.key] = entry.value;
      }
    }
    for (final entry in _rawCache.entries) {
      if (out.containsKey(entry.key)) continue;
      try {
        out[entry.key] = jsonDecode(entry.value);
      } catch (_) {
        out[entry.key] = entry.value;
      }
    }
    return out;
  }

  void dispose() {
    unawaited(() async {
      try {
        await _db?.close();
        try {
          await _settingsDb?.close();
        } catch (_) {}
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
