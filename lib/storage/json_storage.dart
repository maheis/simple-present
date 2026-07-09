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
    // Shim file for backward compatibility.
    // The real Sembast-backed implementation lives in `sembast_storage.dart`.
    export 'sembast_storage.dart';
      if (!await sub.exists()) await sub.create(recursive: true);
