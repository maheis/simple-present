import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SqliteStorage {
  late final String _storageRoot;

  Future<void> init({required bool debugMode}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folderName = debugMode ? 'simplepresent-debug' : 'simplepresent';
    final sub = Directory('${dir.path}/$folderName');
    try {
      if (!await sub.exists()) await sub.create(recursive: true);
    } catch (_) {}

    // Legacy migration removed: time entries are expected to reside under
    // the `simplepresent` application subfolder. No automatic migration
    // from the documents root is performed.

    _storageRoot = sub.path;
  }

  String _filePath(String name) {
    return '$_storageRoot/$name';
  }

  Future<File> _fileFor(String name) async {
    return File(_filePath(name));
  }

  Future<Map<String, dynamic>> _readJsonMap(String name) async {
    final f = await _fileFor(name);
    if (!await f.exists()) return <String, dynamic>{};
    final text = await f.readAsString();
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Future<void> _writeJson(String name, Object value) async {
    final f = await _fileFor(name);
    await f.parent.create(recursive: true);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(value));
  }

  List<Map<String, dynamic>> readTaskList(String listName) {
    try {
      final f = File(_filePath(listName));
      if (!f.existsSync()) return const [];
      final decoded = jsonDecode(f.readAsStringSync());
      if (decoded is! List) return const [];
        return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void writeTaskList(String listName, List<Map<String, dynamic>> items) {
    unawaited(_writeJson(listName, items));
  }

  bool taskListExists(String listName) {
    return File(_filePath(listName)).existsSync();
  }

  String? read(String name) {
    try {
      final f = File(_filePath(name));
      if (!f.existsSync()) return null;
      return f.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  void write(String name, String content) {
    unawaited(() async {
      final f = await _fileFor(name);
      await f.parent.create(recursive: true);
      await f.writeAsString(content);
    }());
  }

  bool exists(String name) {
    return File(_filePath(name)).existsSync();
  }

  void dispose() {}

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
      final all = await _readJsonMap('simplepresent_time_entries.json');
      final list = (all[date] is List) ? List<dynamic>.from(all[date] as List) : <dynamic>[];
      list.add(<String, dynamic>{
        'task_id': taskId,
        'task_text': taskText,
        'task_done': taskDone ? 1 : 0,
        'task_in_progress': taskInProgress ? 1 : 0,
        'stopwatch_seconds': stopwatchSeconds,
        'work_minutes': workMinutes,
        'recorded_at': now,
      });
      all[date] = list;
      await _writeJson('simplepresent_time_entries.json', all);
    }());
  }

  List<Map<String, dynamic>> getTimeEntriesForDate(String date) {
    try {
      final all = _readJsonMapSync('simplepresent_time_entries.json');
      final raw = all[date];
      if (raw is! List) return const [];
        return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<String> getTimeEntryDates() {
    try {
      final all = _readJsonMapSync('simplepresent_time_entries.json');
      final dates = all.keys.toList();
      dates.sort((a, b) => b.compareTo(a));
      return dates;
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _readJsonMapSync(String name) {
    final f = File(_filePath(name));
    if (!f.existsSync()) return <String, dynamic>{};
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }
}
