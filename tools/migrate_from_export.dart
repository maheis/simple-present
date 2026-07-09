#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:sembast/sembast_io.dart';
import 'package:path/path.dart' as p;

final _listsStore = StoreRef<String, Object?>('lists');

void usage() {
  print(
      'migrate_from_export.dart --export <file> --storage-dir <folder> [--debug]');
  print(
      'Writes lists from the single-file JSON export into the sembast DB located at <storage-dir>/simplepresent.db');
}

Future<int> main(List<String> args) async {
  String? exportPath;
  String? storageDir;
  var debug = false;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--export' && i + 1 < args.length) {
      exportPath = args[++i];
    } else if (a == '--storage-dir' && i + 1 < args.length) {
      storageDir = args[++i];
    } else if (a == '--debug') {
      debug = true;
    } else if (a == '--help' || a == '-h') {
      usage();
      return 0;
    }
  }

  if (exportPath == null || storageDir == null) {
    usage();
    return 2;
  }

  final exportFile = File(exportPath);
  if (!await exportFile.exists()) {
    stderr.writeln('Export file not found: $exportPath');
    return 2;
  }

  final storageFolder = Directory(storageDir);
  if (!await storageFolder.exists()) {
    stderr.writeln('Storage dir does not exist: $storageDir');
    return 2;
  }

  final dbPath = p.join(storageFolder.path, 'simplepresent.db');
  final db = await databaseFactoryIo.openDatabase(dbPath);

  try {
    final text = await exportFile.readAsString();
    final data = jsonDecode(text) as Map<String, dynamic>;

    final today = (data['today'] is List)
        ? List<Map<String, dynamic>>.from(data['today'])
        : <Map<String, dynamic>>[];
    final backlog = (data['backlog'] is List)
        ? List<Map<String, dynamic>>.from(data['backlog'])
        : <Map<String, dynamic>>[];
    final done = (data['done'] is List)
        ? List<Map<String, dynamic>>.from(data['done'])
        : <Map<String, dynamic>>[];
    final trash = (data['trash'] is List)
        ? List<Map<String, dynamic>>.from(data['trash'])
        : <Map<String, dynamic>>[];

    final prefix = debug ? 'debug_' : '';
    final todayKey = '${prefix}simplepresent_today.json';
    final backlogKey = '${prefix}simplepresent_backlog.json';
    final doneKey = '${prefix}simplepresent_done.json';
    final trashKey = '${prefix}simplepresent_trash.json';

    print('Importing into DB: $dbPath');
    await db.transaction((txn) async {
      await _listsStore.record(todayKey).put(txn, today);
      await _listsStore.record(backlogKey).put(txn, backlog);
      await _listsStore.record(doneKey).put(txn, done);
      await _listsStore.record(trashKey).put(txn, trash);
    });

    print(
        'Imported: today=${today.length}, backlog=${backlog.length}, done=${done.length}, trash=${trash.length}');
    return 0;
  } catch (e, st) {
    stderr.writeln('Migration failed: $e\n$st');
    return 1;
  } finally {
    await db.close();
  }
}
