import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:path_provider/path_provider.dart';
import 'package:simple_present/sync/cloud_sync_client.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:simple_present/storage/sqlite_storage.dart';

// sentinel to indicate "no change" in copyWith optional parameters
const _noChange = Object();

const String kClientVersion = '0.1.0';

List<int>? _parseVersionParts(String raw) {
  var normalized = raw.trim();
  if (normalized.isEmpty) return null;
  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1);
  }
  final core = normalized.split('-').first;
  final parts = core.split('.');
  if (parts.isEmpty) return null;
  final out = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null) return null;
    out.add(v);
  }
  return out;
}

int _compareVersions(String a, String b) {
  final left = _parseVersionParts(a);
  final right = _parseVersionParts(b);
  if (left == null || right == null) return 0;

  final maxLen = math.max(left.length, right.length);
  for (var i = 0; i < maxLen; i++) {
    final lv = i < left.length ? left[i] : 0;
    final rv = i < right.length ? right[i] : 0;
    if (lv < rv) return -1;
    if (lv > rv) return 1;
  }
  return 0;
}

bool _isClientOlderThanServer(String clientVersion, String serverVersion) {
  return _compareVersions(clientVersion, serverVersion) < 0;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  runApp(const SimplePresentApp());
}

class SimplePresentApp extends StatelessWidget {
  const SimplePresentApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimplePresent',
      locale: const Locale('de', 'DE'),
      theme: ThemeData(
        fontFamily: 'OpenDyslexic',
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class TaskStep {
  TaskStep({
    required this.id,
    required this.text,
    this.done = false,
  });

  final String id;
  final String text;
  final bool done;

  TaskStep copyWith({
    String? id,
    String? text,
    bool? done,
  }) {
    return TaskStep(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
      };

  static TaskStep fromJson(dynamic json) {
    if (json is String) {
      final genId =
          '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
      return TaskStep(id: genId, text: json, done: false);
    }
    final map = json as Map<String, dynamic>;
    final String id = (map['id'] ?? map['uid'] ?? '').toString();
    final String useId = id.isNotEmpty
        ? id
        : '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    return TaskStep(
      id: useId,
      text: (map['text'] ?? '').toString(),
      done: map['done'] == true,
    );
  }
}

class TaskItem {
  TaskItem({
    required this.id,
    required this.text,
    this.done = false,
    this.important = false,
    this.inProgress = false,
    this.completedAt,
    this.inProgressAt,
    this.importantAt,
    this.createdAt,
    this.scheduledAt,
    this.notes,
    this.subtasks = const [],
    this.stopwatchAccumulatedSeconds = 0,
    this.stopwatchRunning = false,
    this.stopwatchStartedAt,
    this.workMinutes = 0,
  });

  final String id;

  final String text;
  final bool done;
  final bool important;
  final bool inProgress;
  final DateTime? completedAt; // timestamp when marked done
  final DateTime? inProgressAt; // timestamp when marked in progress
  final DateTime? importantAt; // timestamp when marked important
  final DateTime? createdAt; // timestamp when created
  final DateTime? scheduledAt; // optional scheduled date/time
  final String? notes;
  final List<TaskStep> subtasks;
  // Stopwatch state per task
  final int
      stopwatchAccumulatedSeconds; // total seconds accumulated when not running
  final bool stopwatchRunning;
  final DateTime? stopwatchStartedAt;
  // manually recorded minutes (rounded suggestions accumulate here)
  final int workMinutes;

  TaskItem copyWith({
    String? id,
    String? text,
    bool? done,
    bool? important,
    bool? inProgress,
    Object? completedAt = _noChange,
    Object? inProgressAt = _noChange,
    Object? importantAt = _noChange,
    Object? createdAt = _noChange,
    Object? scheduledAt = _noChange,
    String? notes,
    List<TaskStep>? subtasks,
    int? stopwatchAccumulatedSeconds,
    bool? stopwatchRunning,
    Object? stopwatchStartedAt = _noChange,
    int? workMinutes,
  }) {
    return TaskItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      important: important ?? this.important,
      inProgress: inProgress ?? this.inProgress,
      completedAt: identical(completedAt, _noChange)
          ? this.completedAt
          : (completedAt == null ? null : (completedAt as DateTime)),
      inProgressAt: identical(inProgressAt, _noChange)
          ? this.inProgressAt
          : (inProgressAt == null ? null : (inProgressAt as DateTime)),
      importantAt: identical(importantAt, _noChange)
          ? this.importantAt
          : (importantAt == null ? null : (importantAt as DateTime)),
      createdAt: identical(createdAt, _noChange)
          ? this.createdAt
          : (createdAt == null ? null : (createdAt as DateTime)),
      scheduledAt: identical(scheduledAt, _noChange)
          ? this.scheduledAt
          : (scheduledAt == null ? null : (scheduledAt as DateTime)),
      notes: notes ?? this.notes,
      subtasks: subtasks ?? this.subtasks,
      stopwatchAccumulatedSeconds:
          stopwatchAccumulatedSeconds ?? this.stopwatchAccumulatedSeconds,
      stopwatchRunning: stopwatchRunning ?? this.stopwatchRunning,
      stopwatchStartedAt: identical(stopwatchStartedAt, _noChange)
          ? this.stopwatchStartedAt
          : (stopwatchStartedAt == null
              ? null
              : (stopwatchStartedAt as DateTime)),
      workMinutes: workMinutes ?? this.workMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'important': important,
        'inProgress': inProgress,
        // English field names
        'created_at': createdAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'in_progress_at': inProgressAt?.toIso8601String(),
        'important_at': importantAt?.toIso8601String(),
        'scheduled_at': scheduledAt?.toIso8601String(),
        'notes': notes,
        'subtasks': subtasks.map((step) => step.toJson()).toList(),
        'stopwatch_seconds': stopwatchAccumulatedSeconds,
        'stopwatch_running': stopwatchRunning,
        'stopwatch_started_at': stopwatchStartedAt?.toIso8601String(),
        'work_minutes': workMinutes,
      };

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return null;
    }
  }

  static TaskItem fromJson(dynamic json) {
    // Backward compatible with old string-only storage.
    if (json is String) {
      // generate id for legacy entries
      final genId =
          '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
      return TaskItem(id: genId, text: json, done: false);
    }
    final map = json as Map<String, dynamic>;
    final String id = (map['id'] ?? map['uid'] ?? '').toString();
    final String useId = id.isNotEmpty
        ? id
        : '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    return TaskItem(
      id: useId,
      text: (map['text'] ?? '').toString(),
      done: map['done'] == true,
      important: map['important'] == true,
      inProgress: map['inProgress'] == true || map['in_arbeit'] == true,
      // support both new english keys and older german/variant keys
      createdAt: _parseDate(map['created_at'] ?? map['createdAt']),
      scheduledAt: _parseDate(map['scheduled_at'] ??
          map['scheduledAt'] ??
          map['termin'] ??
          map['due_at']),
      completedAt: _parseDate(map['completed_at'] ??
          map['erledigt_am'] ??
          map['done_at'] ??
          map['doneAt']),
      inProgressAt: _parseDate(map['in_progress_at'] ??
          map['in_arbeit_am'] ??
          map['inArbeitAt'] ??
          map['in_progress_at']),
      importantAt: _parseDate(
          map['important_at'] ?? map['wichtig_am'] ?? map['important_at']),
      notes: (map['notes'] ?? map['note'] ?? '').toString(),
      subtasks: () {
        final raw = map['subtasks'] ?? map['steps'] ?? const [];
        if (raw is List) {
          return raw.map(TaskStep.fromJson).toList();
        }
        return const <TaskStep>[];
      }(),
      stopwatchAccumulatedSeconds: (map['stopwatch_seconds'] is int)
          ? map['stopwatch_seconds'] as int
          : int.tryParse((map['stopwatch_seconds'] ?? '').toString()) ?? 0,
      stopwatchRunning: map['stopwatch_running'] == true,
      stopwatchStartedAt:
          _parseDate(map['stopwatch_started_at'] ?? map['stopwatchStartedAt']),
      workMinutes: (map['work_minutes'] is int)
          ? map['work_minutes'] as int
          : int.tryParse((map['work_minutes'] ?? '').toString()) ?? 0,
    );
  }
}

class _HomePageState extends State<HomePage> {
  final List<TaskItem> _today = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  final Set<int> _expanded = <int>{};
  final Map<int, TextEditingController> _editControllers = {};
  final Map<int, TextEditingController> _notesControllers = {};
  final Map<String, TextEditingController> _subtaskInputControllers = {};
  final Map<String, FocusNode> _subtaskFocusNodes = {};
  final Map<String, TextEditingController> _workControllers = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  // SQLite storage (migrates JSON files on first init)
  final _sqliteStorage = SqliteStorage();
  bool _useSqlite = false;
  Timer? _idleTimer;
  Timer? _attentionTimer;
  int _idleMinutes = 45;
  int _attentionMinutes = 60;
  Timer? _reminderTimer;
  int _reminderMinutes = 75;
  Timer? _urgentTimer;
  int _urgentMinutes = 90;
  bool _idleSoundEnabled = true;
  bool _attentionSoundEnabled = true;
  bool _attentionFlashEnabled = true;
  bool _reminderSoundEnabled = true;
  bool _reminderNotifyEnabled = true;
  bool _idleFlashEnabled = false;
  // play sound for scheduled task reminders (15min / due)
  bool _scheduledReminderSoundEnabled = true;
  bool _idleNotifyEnabled = false;
  bool _idleBringToFrontEnabled = false;
  bool _attentionNotifyEnabled = false;
  bool _attentionBringToFrontEnabled = false;
  bool _reminderFlashEnabled = false;
  bool _reminderBringToFrontEnabled = false;
  bool _urgentFlashEnabled = false;
  bool _urgentSoundEnabled = true;
  bool _urgentNotifyEnabled = true;
  bool _urgentBringToFrontEnabled = true;
  bool _swipeEnabled = true;
  bool _magnetEnabled = false;
  // threshold (px) within which window will snap to screen edge
  final int _magnetThreshold = 37;
  String _fontFamily = 'OpenDyslexic';
  // Fired flags to ensure each reminder type fires only once per inactivity period
  bool _idleFired = false;
  bool _attentionFired = false;
  bool _reminderFired = false;
  bool _urgentFired = false;
  final MethodChannel _nativeWindowChannel =
      const MethodChannel('simple_present/window');
  Timer? _scheduledCheckTimer;
  Timer? _windowWatcherTimer;
  Timer? _autoSwitchTimer;
  final Duration _autoSwitchDuration = const Duration(minutes: 3);
  Timer? _stopwatchTicker;
  Map<String, int>? _lastSavedWindowGeom;
  final Set<String> _notified15 = <String>{};
  final Set<String> _notifiedDue = <String>{};
  final Set<int> _swiping = <int>{};
  bool _minimalViewMode = false;
  Map<String, int>? _windowBeforeMinimal;

  // When debugging, prepend filenames with 'debug_' so test data doesn't mix
  String _storage(String name) => kDebugMode ? 'debug_$name' : name;

  // Zoom state: tile height and font scaling
  double _tileHeight = 52.0;
  final double _defaultTileHeight = 52.0;
  final double _minTileHeight = 0.1; // allow very small tiles
  double _fontScale = 1.0;
  final double _minFontScale = 0.01;
  final double _baseFontSize = 15.0; // used when scaling text down
  double _uiTextScaleFactor = 1.0;
  final double _minUiTextScaleFactor = 0.5;
  final double _maxUiTextScaleFactor = 1.6;
  double _tileHeightStart = 52.0;
  double _fontScaleStart = 1.0;
  bool _alwaysOnTop = false;
  final String _appTitle = 'SimplePresent';
  String _cloudServerUrl = '';
  String _cloudAccountId = '';
  String _cloudDeviceId = '';
  String _cloudToken = '';
  String _cloudWordPhrase = '';
  String _cloudDeviceName = Platform.localHostname;
  String _cloudPIN = '';
  String _serverVersion = '';
  bool _versionWarningShown = false;
  Timer? _cloudPullTimer;
  bool _cloudSyncBusy = false;
  bool _applyingCloudState = false;
  int _cloudStateVersion = 1;
  int _cloudLastSyncModifiedAt = 0;
  Set<String> _cloudKnownTodayIds = <String>{};
  Set<String> _cloudKnownBacklogIds = <String>{};
  Set<String> _cloudKnownDoneIds = <String>{};

  Duration get _idleDuration => Duration(minutes: _idleMinutes.clamp(1, 720));
  Duration get _attentionDuration =>
      Duration(minutes: _attentionMinutes.clamp(1, 720));
  Duration get _reminderDuration =>
      Duration(minutes: _reminderMinutes.clamp(1, 720));
  Duration get _urgentDuration =>
      Duration(minutes: _urgentMinutes.clamp(1, 720));

  double _fontScaleForTileHeight(double tileHeight) {
    if (tileHeight >= 1.0) return 1.0;
    return math.max(tileHeight, _minFontScale);
  }

  double _clampUiTextScaleFactor(double value) {
    return value.clamp(_minUiTextScaleFactor, _maxUiTextScaleFactor).toDouble();
  }

  TextStyle _fontTextStyle([TextStyle style = const TextStyle()]) {
    return style.copyWith(fontFamily: _fontFamily);
  }

  // Toggle which file is shown: false = today, true = done
  bool _showingDone = false;
  // Backlog view toggle
  bool _showingBacklog = false;
  String _currentFile = 'simplepresent_today.json';

  late final Future<void> _initFuture = _initializeApp();

  @override
  void initState() {
    super.initState();
    // Start watching window geometry after startup
    _startWindowWatcher();
    _startIdleTimer();
    _startAttentionTimer();
    _startReminderTimer();
    _startUrgentTimer();
    _startAutoSwitchTimer();
    _startScheduledChecker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocus.requestFocus();
      }
    });
    // listen for any keyboard activity to reset idle timers
    try {
      RawKeyboard.instance.addListener(_rawKeyListener);
    } catch (_) {}
    // Start a short ticker to update stopwatch displays every second
    _stopwatchTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _rawKeyListener(RawKeyEvent ev) {
    _registerActivity();
  }

  Future<Directory> get _appDir async {
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  }

  Future<File> _fileFor(String name) async {
    final dir = await _appDir;
    return File('${dir.path}/$name');
  }

  Future<void> _ensureListFile(String filename) async {
    try {
      if (_useSqlite) {
        if (!_sqliteStorage.taskListExists(filename)) {
          _sqliteStorage.writeTaskList(filename, const <Map<String, dynamic>>[]);
        }
        return;
      }
      final f = await _fileFor(filename);
      if (!await f.exists()) {
        await f.writeAsString('[]');
      }
    } catch (_) {}
  }

  Future<void> _ensureInitialFiles() async {
    await _ensureListFile(_storage('simplepresent_today.json'));
    await _ensureListFile(_storage('simplepresent_done.json'));
    await _ensureListFile(_storage('simplepresent_backlog.json'));
    await _ensureListFile(_storage('simplepresent_trash.json'));
  }

  Future<void> _initializeApp() async {
    // ensure current file respects debug mode
    _currentFile = _storage('simplepresent_today.json');
    // initialize sqlite storage and migrate JSON files if needed
    try {
      await _sqliteStorage.init(debugMode: kDebugMode);
      _useSqlite = true;
    } catch (_) {
      _useSqlite = false;
    }
    await _loadSettings();
    await _ensureInitialFiles();

    // Ensure daily reset: when app is started the first time on a new day,
    // move all open (not done) tasks from Today into Backlog (bottom->top),
    // leave Done tasks in their file. Persist a lastRunDate in settings.
    try {
      Map<String, dynamic> settings = {};
      try {
        if (_useSqlite) {
          final txt = _sqliteStorage.read(_storage('simplepresent_settings.json'));
          if (txt != null) settings = jsonDecode(txt) as Map<String, dynamic>;
        } else {
          final settingsFile = await _fileFor(_storage('simplepresent_settings.json'));
          if (await settingsFile.exists()) {
            try {
              settings = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
            } catch (_) {
              settings = {};
            }
          }
        }
      } catch (_) {
        settings = {};
      }
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastRun = settings['lastRunDate'] as String?;
      if (lastRun != todayKey) {
        // First run today -> migrate open tasks from today -> backlog
        final List<TaskItem> todayList = [];
        await _loadList(_storage('simplepresent_today.json'), todayList);
        final List<TaskItem> movedToDone = [];
        int movedToBacklogCount = 0;
        if (todayList.isNotEmpty) {
          final List<TaskItem> backlogList = [];
          await _loadList(_storage('simplepresent_backlog.json'), backlogList);
          final List<TaskItem> doneList = [];
          await _loadList(_storage('simplepresent_done.json'), doneList);

          // Move tasks from today: open tasks -> backlog (bottom->top), done tasks -> done
          for (int i = todayList.length - 1; i >= 0; i--) {
            final t = todayList[i];
            if (!t.done) {
              backlogList.add(t);
              movedToBacklogCount++;
            } else {
              movedToDone.add(t);
            }
          }

          // Persist updated backlog and done, then clear today
          await _saveList(_storage('simplepresent_backlog.json'), backlogList);
          if (movedToDone.isNotEmpty) {
            // append moved done tasks to existing done list (preserve existing order)
            doneList.addAll(movedToDone
                .reversed); // reverse to keep original top->bottom order
            await _saveList(_storage('simplepresent_done.json'), doneList);
          }
          await _saveList(_storage('simplepresent_today.json'), <TaskItem>[]);
        }
        settings['lastRunDate'] = todayKey;
        final enc = const JsonEncoder.withIndent('  ');
        try {
          // reload current view to ensure UI reflects changes
          await _loadToday();
          final encoded = enc.convert(settings);
          if (_useSqlite) {
            _sqliteStorage.write(_storage('simplepresent_settings.json'), encoded);
          } else {
            final settingsFile =
                await _fileFor(_storage('simplepresent_settings.json'));
            await settingsFile.writeAsString(encoded);
          }
        } catch (_) {}
        // Show a short summary toast after first frame if any tasks were moved
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final movedDoneCount = movedToDone.length;
          if (movedToBacklogCount > 0 || movedDoneCount > 0) {
            final parts = <String>[];
            if (movedToBacklogCount > 0)
              parts.add('$movedToBacklogCount moved to Backlog');
            if (movedDoneCount > 0) parts.add('$movedDoneCount moved to Done');
            _showTopToast(parts.join(', '));
          }
        });
      }
    } catch (_) {}

    await _loadToday();
    await _syncPullFromCloud();
    unawaited(_fetchServerVersion());
    _startCloudPullTimer();
  }

  Future<void> _loadList(String filename, List<TaskItem> target) async {
    target.clear();
    try {
      if (_useSqlite) {
        final rows = _sqliteStorage.readTaskList(filename);
        target.addAll(rows.map(TaskItem.fromJson));
        return;
      }
      final f = await _fileFor(filename);
      if (await f.exists()) {
        final text = await f.readAsString();
        final data = jsonDecode(text) as List<dynamic>;
        target.addAll(data.map(TaskItem.fromJson));
      }
    } catch (_) {}
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _appendDone(List<TaskItem> items) async {
    if (items.isEmpty) return;
    try {
      final List<TaskItem> existing = [];
      await _loadList(_storage('simplepresent_done.json'), existing);
      existing.addAll(items);
      await _saveList(_storage('simplepresent_done.json'), existing);
    } catch (_) {}
  }

  Future<void> _saveList(String filename, List<TaskItem> source,
      {bool triggerCloudSync = true}) async {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      final text = encoder.convert(source.map((e) => e.toJson()).toList());
      if (_useSqlite) {
        _sqliteStorage.writeTaskList(
          filename,
          source.map((e) => e.toJson()).toList(),
        );
      } else {
        final f = await _fileFor(filename);
        await f.writeAsString(text);
      }
      if (triggerCloudSync) {
        unawaited(_syncPushToCloud(filename, source));
      }
    } catch (_) {}
  }

  Future<void> _loadToday() async {
    await _loadList(_currentFile, _today);
    setState(() {});
  }

  Future<void> _saveToday() async {
    await _saveList(_currentFile, _today);
  }

  bool get _cloudSyncConfigured {
    return _cloudServerUrl.trim().isNotEmpty &&
        _cloudAccountId.trim().isNotEmpty &&
        _cloudDeviceId.trim().isNotEmpty &&
      _cloudToken.trim().isNotEmpty &&
      _cloudWordPhrase.trim().isNotEmpty;
  }

  Future<void> _applyCloudStatePayload(Map<String, dynamic> payload) async {
    final rawToday = payload['today'];
    final rawBacklog = payload['backlog'];
    final rawDone = payload['done'];
    if (rawToday is! List || rawBacklog is! List || rawDone is! List) {
      return;
    }

    final today = rawToday.map(TaskItem.fromJson).toList();
    final backlog = rawBacklog.map(TaskItem.fromJson).toList();
    final done = rawDone.map(TaskItem.fromJson).toList();

    _applyingCloudState = true;
    try {
      await _saveList(_storage('simplepresent_today.json'), today,
          triggerCloudSync: false);
      await _saveList(_storage('simplepresent_backlog.json'), backlog,
          triggerCloudSync: false);
      await _saveList(_storage('simplepresent_done.json'), done,
          triggerCloudSync: false);
      await _loadToday();
    } finally {
      _applyingCloudState = false;
    }
  }

  String? _cloudListNameForFilename(String filename) {
    if (filename.contains('simplepresent_today.json')) return 'today';
    if (filename.contains('simplepresent_backlog.json')) return 'backlog';
    if (filename.contains('simplepresent_done.json')) return 'done';
    return null;
  }

  Set<String> _knownIdSetForList(String listName) {
    if (listName == 'today') return _cloudKnownTodayIds;
    if (listName == 'backlog') return _cloudKnownBacklogIds;
    return _cloudKnownDoneIds;
  }

  Future<void> _syncPushToCloud(String filename, List<TaskItem> source) async {
    if (!_cloudSyncConfigured || _cloudSyncBusy || _applyingCloudState) return;
    final listName = _cloudListNameForFilename(filename);
    if (listName == null) return;

    _cloudSyncBusy = true;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
      );
      final modifiedAt = DateTime.now().millisecondsSinceEpoch;
      _cloudStateVersion += 1;

      final currentIds = source.map((t) => t.id).toSet();
      final knownIds = _knownIdSetForList(listName);
      final removedIds = knownIds.difference(currentIds).toList();

      final items = <Map<String, dynamic>>[];
      for (var i = 0; i < source.length; i++) {
        final task = source[i];
        final encryptedPayload = await CloudSyncClient.encryptStatePayload(
          payload: <String, dynamic>{
            'task': task.toJson(),
            'list': listName,
            'position': i,
          },
          phrase: _cloudWordPhrase,
        );
        items.add(<String, dynamic>{
          'id': 'task:${task.id}',
          'payload': encryptedPayload,
          'modified_at': modifiedAt,
          'tombstone': false,
          'origin_device_id': _cloudDeviceId.trim(),
          'version': _cloudStateVersion,
        });
      }

      for (final removed in removedIds) {
        items.add(<String, dynamic>{
          'id': 'task:$removed',
          'payload': <String, dynamic>{'reason': 'removed'},
          'modified_at': modifiedAt,
          'tombstone': true,
          'origin_device_id': _cloudDeviceId.trim(),
          'version': _cloudStateVersion,
        });
      }

      await client.pushItems(
        accountId: _cloudAccountId.trim(),
        token: _cloudToken.trim(),
        items: items,
      );

      knownIds
        ..clear()
        ..addAll(currentIds);
      _cloudLastSyncModifiedAt = modifiedAt;
      await _saveSettings();
    } catch (_) {
      // Keep app responsive; cloud sync errors are non-fatal.
    } finally {
      _cloudSyncBusy = false;
    }
  }

  Future<void> _fetchServerVersion() async {
    if (_cloudServerUrl.trim().isEmpty) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
      );
      final health = await client.getHealth();
      if (health != null && mounted) {
        final isOutdated = _isClientOlderThanServer(kClientVersion, health);
        setState(() => _serverVersion = health);
        if (isOutdated && !_versionWarningShown) {
          _versionWarningShown = true;
          _showTopToast(
              'Warnung: Client-Version $kClientVersion ist älter als Server-Version $health.');
        }
      }
    } catch (_) {
      // Fehler beim Abrufen der Version ignorieren
    }
  }

  Future<void> _syncPullFromCloud() async {
    if (!_cloudSyncConfigured || _cloudSyncBusy) return;
    _cloudSyncBusy = true;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
      );
      final pulledItems = await client.pullChangedItems(
        token: _cloudToken.trim(),
        since: _cloudLastSyncModifiedAt,
      );
      if (pulledItems.isEmpty) return;

      final today = <TaskItem>[];
      final backlog = <TaskItem>[];
      final done = <TaskItem>[];
      await _loadList(_storage('simplepresent_today.json'), today);
      await _loadList(_storage('simplepresent_backlog.json'), backlog);
      await _loadList(_storage('simplepresent_done.json'), done);

      final listMap = <String, List<TaskItem>>{
        'today': today,
        'backlog': backlog,
        'done': done,
      };

      _applyingCloudState = true;
      var maxModifiedAt = _cloudLastSyncModifiedAt;
      var appliedLegacyFullState = false;
      try {
        for (final item in pulledItems) {
          if (item.modifiedAt > maxModifiedAt) maxModifiedAt = item.modifiedAt;
          if (item.version > _cloudStateVersion) _cloudStateVersion = item.version;

          final taskId = item.id.startsWith('task:') ? item.id.substring(5) : item.id;
          if (taskId.isEmpty) continue;

          if (item.tombstone) {
            for (final list in listMap.values) {
              list.removeWhere((t) => t.id == taskId);
            }
            _cloudKnownTodayIds.remove(taskId);
            _cloudKnownBacklogIds.remove(taskId);
            _cloudKnownDoneIds.remove(taskId);
            continue;
          }

          Map<String, dynamic> payload;
          if ((item.payload['enc'] ?? '') == 'v1') {
            payload = await CloudSyncClient.decryptStatePayload(
              encryptedPayload: item.payload,
              phrase: _cloudWordPhrase,
            );
          } else {
            payload = item.payload;
          }

          // Backward compatibility with previous full-state payload format.
          if (payload.containsKey('today') &&
              payload.containsKey('backlog') &&
              payload.containsKey('done')) {
            await _applyCloudStatePayload(payload);
            appliedLegacyFullState = true;
            break;
          }

          final taskRaw = payload['task'];
          final listName = (payload['list'] ?? '').toString();
          final position = (payload['position'] is num)
              ? (payload['position'] as num).toInt()
              : int.tryParse(payload['position']?.toString() ?? '') ?? 0;
          if (taskRaw is! Map || !listMap.containsKey(listName)) continue;

          final task = TaskItem.fromJson(Map<String, dynamic>.from(taskRaw.cast<String, dynamic>()));

          for (final list in listMap.values) {
            list.removeWhere((t) => t.id == task.id);
          }

          final target = listMap[listName]!;
          final insertPos = position.clamp(0, target.length);
          target.insert(insertPos, task);

          _cloudKnownTodayIds.remove(task.id);
          _cloudKnownBacklogIds.remove(task.id);
          _cloudKnownDoneIds.remove(task.id);
          _knownIdSetForList(listName).add(task.id);
        }

        if (!appliedLegacyFullState) {
          await _saveList(_storage('simplepresent_today.json'), today,
            triggerCloudSync: false);
          await _saveList(_storage('simplepresent_backlog.json'), backlog,
            triggerCloudSync: false);
          await _saveList(_storage('simplepresent_done.json'), done,
            triggerCloudSync: false);
          await _loadToday();
        }
      } finally {
        _applyingCloudState = false;
      }

      _cloudLastSyncModifiedAt = maxModifiedAt;
      await _saveSettings();
    } catch (_) {
      // Keep app responsive; cloud sync errors are non-fatal.
    } finally {
      _cloudSyncBusy = false;
    }
  }

  void _startCloudPullTimer() {
    _cloudPullTimer?.cancel();
    _cloudPullTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncPullFromCloud();
    });
  }

  Future<void> _switchFile(bool showDone) async {
    _showingDone = showDone;
    _showingBacklog = false;
    _currentFile = showDone
        ? _storage('simplepresent_done.json')
        : _storage('simplepresent_today.json');
    // clear expanded/edit state
    _expanded.clear();
    for (final c in _editControllers.values) {
      c.dispose();
    }
    _editControllers.clear();
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    _notesControllers.clear();
    if (_showingDone) _inputFocus.unfocus();
    await _loadToday();
  }

  Future<void> _switchToBacklog() async {
    _showingBacklog = true;
    _showingDone = false;
    _currentFile = _storage('simplepresent_backlog.json');
    // clear expanded/edit state
    _expanded.clear();
    for (final c in _editControllers.values) {
      c.dispose();
    }
    _editControllers.clear();
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    _notesControllers.clear();
    await _loadToday();
  }

  Future<void> _cycleView(bool forward) async {
    // Order: 0 = today, 1 = backlog, 2 = done
    final idx = _showingBacklog ? 1 : (_showingDone ? 2 : 0);
    final next = (idx + (forward ? 1 : 2)) % 3; // +2 is same as -1 mod 3
    if (next == 0) {
      await _switchFile(false);
    } else if (next == 1) {
      await _switchToBacklog();
    } else {
      await _switchFile(true);
    }
  }

  Future<void> _loadSettings() async {
    try {
      Map<String, dynamic> data = {};
      if (_useSqlite) {
        final txt = _sqliteStorage.read(_storage('simplepresent_settings.json'));
        if (txt == null) return;
        data = jsonDecode(txt) as Map<String, dynamic>;
      } else {
        final f = await _fileFor(_storage('simplepresent_settings.json'));
        if (!await f.exists()) return;
        data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
      int readInt(String key, int fallback) {
        final v = data[key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? fallback;
      }

      bool readBool(String key, bool fallback) {
        final v = data[key];
        if (v is bool) return v;
        if (v is num) return v != 0;
        final s = (v?.toString() ?? '').toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
        return fallback;
      }

      double readDouble(String key, double fallback) {
        final v = data[key];
        if (v is num) return v.toDouble();
        return double.tryParse(v?.toString() ?? '') ?? fallback;
      }

      if (data.containsKey('tileHeight')) {
        final v = data['tileHeight'];
        if (v is num) {
          setState(() => _tileHeight = v.toDouble());
        }
      }
      if (data.containsKey('fontScale')) {
        final v = data['fontScale'];
        if (v is num) {
          setState(() => _fontScale = v.toDouble());
        }
      }
      setState(() {
        _fontScale = _fontScaleForTileHeight(_tileHeight);
        _idleMinutes = readInt('idleMinutes', _idleMinutes);
        _attentionMinutes = readInt('attentionMinutes', _attentionMinutes);
        _reminderMinutes = readInt('reminderMinutes', _reminderMinutes);
        _urgentMinutes = readInt('urgentMinutes', _urgentMinutes);
        _idleSoundEnabled = readBool('idleSoundEnabled', _idleSoundEnabled);
        _idleFlashEnabled = readBool('idleFlashEnabled', _idleFlashEnabled);
        _idleNotifyEnabled = readBool('idleNotifyEnabled', _idleNotifyEnabled);
        _idleBringToFrontEnabled =
            readBool('idleBringToFrontEnabled', _idleBringToFrontEnabled);
        _attentionSoundEnabled =
            readBool('attentionSoundEnabled', _attentionSoundEnabled);
        _attentionFlashEnabled =
            readBool('attentionFlashEnabled', _attentionFlashEnabled);
        _attentionNotifyEnabled =
            readBool('attentionNotifyEnabled', _attentionNotifyEnabled);
        _attentionBringToFrontEnabled = readBool(
            'attentionBringToFrontEnabled', _attentionBringToFrontEnabled);
        _reminderSoundEnabled =
            readBool('reminderSoundEnabled', _reminderSoundEnabled);
        _reminderNotifyEnabled =
            readBool('reminderNotifyEnabled', _reminderNotifyEnabled);
        _reminderFlashEnabled =
            readBool('reminderFlashEnabled', _reminderFlashEnabled);
        _reminderBringToFrontEnabled = readBool(
            'reminderBringToFrontEnabled', _reminderBringToFrontEnabled);
        _scheduledReminderSoundEnabled = readBool('scheduledReminderSoundEnabled', _scheduledReminderSoundEnabled);
        _urgentSoundEnabled =
            readBool('urgentSoundEnabled', _urgentSoundEnabled);
        _urgentNotifyEnabled =
            readBool('urgentNotifyEnabled', _urgentNotifyEnabled);
        _urgentFlashEnabled =
            readBool('urgentFlashEnabled', _urgentFlashEnabled);
        _urgentBringToFrontEnabled =
            readBool('urgentBringToFrontEnabled', _urgentBringToFrontEnabled);
        _swipeEnabled = readBool('swipeEnabled', _swipeEnabled);
        _magnetEnabled = readBool('magnetEnabled', _magnetEnabled);
        _uiTextScaleFactor =
            _clampUiTextScaleFactor(readDouble('uiTextScaleFactor', 1.0));
        final font = data['fontFamily'];
        if (font is String && font.isNotEmpty) {
          _fontFamily = font;
        }
        final serverUrl = data['cloudServerUrl'];
        if (serverUrl is String) {
          _cloudServerUrl = serverUrl;
        }
        final accountId = data['cloudAccountId'];
        if (accountId is String) {
          _cloudAccountId = accountId;
        }
        final deviceId = data['cloudDeviceId'];
        if (deviceId is String) {
          _cloudDeviceId = deviceId;
        }
        final token = data['cloudToken'];
        if (token is String) {
          _cloudToken = token;
        }
        final phrase = data['cloudWordPhrase'];
        if (phrase is String) {
          _cloudWordPhrase = phrase;
        }
        final deviceName = data['cloudDeviceName'];
        if (deviceName is String && deviceName.isNotEmpty) {
          _cloudDeviceName = deviceName;
        }
        final cloudPin = data['cloudPIN'];
        if (cloudPin is String) {
          _cloudPIN = cloudPin;
        }
        final cloudVersion = data['cloudStateVersion'];
        if (cloudVersion is num) {
          _cloudStateVersion = cloudVersion.toInt();
        }
        final cloudModifiedAt = data['cloudLastSyncModifiedAt'];
        if (cloudModifiedAt is num) {
          _cloudLastSyncModifiedAt = cloudModifiedAt.toInt();
        }
        final knownToday = data['cloudKnownTodayIds'];
        if (knownToday is List) {
          _cloudKnownTodayIds = knownToday.map((e) => e.toString()).toSet();
        }
        final knownBacklog = data['cloudKnownBacklogIds'];
        if (knownBacklog is List) {
          _cloudKnownBacklogIds =
              knownBacklog.map((e) => e.toString()).toSet();
        }
        final knownDone = data['cloudKnownDoneIds'];
        if (knownDone is List) {
          _cloudKnownDoneIds = knownDone.map((e) => e.toString()).toSet();
        }
      });
      if (data.containsKey('window')) {
        try {
          final w = data['window'];
          if (w is Map) {
            final wm = Map<String, int>.from(w
                .cast<String, dynamic>()
                .map((k, v) => MapEntry(k, (v as num).toInt())));
            await _validateAndApplyWindow(wm);
            if (w.containsKey('always_on_top')) {
              final val = w['always_on_top'];
              _alwaysOnTop = (val == true) || (val is num && (val as num) != 0);
            }
          }
        } catch (_) {}
      }
      // Load persisted notified sets so reminders don't fire again after restart
      try {
        if (data.containsKey('notified15')) {
          final list = data['notified15'];
          if (list is List) {
            _notified15.clear();
            for (final e in list) {
              _notified15.add(e.toString());
            }
          }
        }
        if (data.containsKey('notifiedDue')) {
          final list = data['notifiedDue'];
          if (list is List) {
            _notifiedDue.clear();
            for (final e in list) {
              _notifiedDue.add(e.toString());
            }
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _validateAndApplyWindow(Map<String, int> w) async {
    try {
      final screen = await _nativeWindowChannel.invokeMethod('getScreenSize');
      int sw = 0, sh = 0;
      if (screen is Map) {
        sw = (screen['width'] is int)
            ? screen['width'] as int
            : (screen['width'] is double
                ? (screen['width'] as double).toInt()
                : int.parse(screen['width'].toString()));
        sh = (screen['height'] is int)
            ? screen['height'] as int
            : (screen['height'] is double
                ? (screen['height'] as double).toInt()
                : int.parse(screen['height'].toString()));
      }
      int x = w['x'] ?? 0;
      int y = w['y'] ?? 0;
      int width = w['width'] ?? 800;
      int height = w['height'] ?? 600;
      final maximized = (w['maximized'] ?? 0) == 1 || w['maximized'] == true;

      bool valid = true;
      if (sw > 0 && sh > 0) {
        // Consider it invalid if window is entirely off-screen or absurdly large
        if (x < -sw || y < -sh || x > sw || y > sh) valid = false;
        if (width <= 0 || height <= 0 || width > sw * 4 || height > sh * 4)
          valid = false;
      }
      if (!valid) {
        // center it on primary screen
        if (sw > 0 && sh > 0) {
          x = ((sw - width) / 2).toInt();
          y = ((sh - height) / 2).toInt();
        } else {
          x = 100;
          y = 100;
        }
      }

      final payload = <String, dynamic>{
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'maximized': maximized,
        'always_on_top': (_alwaysOnTop || (w['always_on_top'] == 1))
      };
      await _nativeWindowChannel.invokeMethod('setWindowGeometry', payload);
    } catch (_) {
      // fallback: try to set geometry directly
      try {
        await _nativeWindowChannel.invokeMethod('setWindowGeometry', w);
      } catch (_) {}
    }
  }

  Future<void> _saveSettings() async {
    await _saveSettingsWithGeom(null);
  }

  Future<void> _saveSettingsWithGeom(Map<String, dynamic>? geom) async {
    try {
      final f = await _fileFor(_storage('simplepresent_settings.json'));
      final out = <String, dynamic>{
        'tileHeight': _tileHeight,
        'fontScale': _fontScale,
        'idleMinutes': _idleMinutes,
        'attentionMinutes': _attentionMinutes,
        'reminderMinutes': _reminderMinutes,
        'urgentMinutes': _urgentMinutes,
        'idleSoundEnabled': _idleSoundEnabled,
        'idleFlashEnabled': _idleFlashEnabled,
        'idleNotifyEnabled': _idleNotifyEnabled,
        'idleBringToFrontEnabled': _idleBringToFrontEnabled,
        'attentionSoundEnabled': _attentionSoundEnabled,
        'attentionFlashEnabled': _attentionFlashEnabled,
        'attentionNotifyEnabled': _attentionNotifyEnabled,
        'attentionBringToFrontEnabled': _attentionBringToFrontEnabled,
        'reminderSoundEnabled': _reminderSoundEnabled,
        'reminderNotifyEnabled': _reminderNotifyEnabled,
        'reminderFlashEnabled': _reminderFlashEnabled,
        'reminderBringToFrontEnabled': _reminderBringToFrontEnabled,
        'urgentSoundEnabled': _urgentSoundEnabled,
        'urgentFlashEnabled': _urgentFlashEnabled,
        'urgentNotifyEnabled': _urgentNotifyEnabled,
        'urgentBringToFrontEnabled': _urgentBringToFrontEnabled,
        'swipeEnabled': _swipeEnabled,
          'magnetEnabled': _magnetEnabled,
        'uiTextScaleFactor': _uiTextScaleFactor,
        'fontFamily': _fontFamily,
        'cloudServerUrl': _cloudServerUrl,
        'cloudAccountId': _cloudAccountId,
        'cloudDeviceId': _cloudDeviceId,
        'cloudToken': _cloudToken,
        'cloudWordPhrase': _cloudWordPhrase,
        'cloudDeviceName': _cloudDeviceName,
        'cloudPIN': _cloudPIN,
        'cloudStateVersion': _cloudStateVersion,
        'cloudLastSyncModifiedAt': _cloudLastSyncModifiedAt,
        'cloudKnownTodayIds': _cloudKnownTodayIds.toList(),
        'cloudKnownBacklogIds': _cloudKnownBacklogIds.toList(),
        'cloudKnownDoneIds': _cloudKnownDoneIds.toList(),
        'scheduledReminderSoundEnabled': _scheduledReminderSoundEnabled,
      };

      // Preserve lastRunDate if present in existing settings so daily-reset runs only once per day
      try {
        if (_useSqlite) {
          final existingText =
              _sqliteStorage.read(_storage('simplepresent_settings.json'));
          if (existingText != null) {
            final existing = jsonDecode(existingText);
            if (existing is Map && existing.containsKey('lastRunDate')) {
              out['lastRunDate'] = existing['lastRunDate'];
            }
          }
        } else {
          if (await f.exists()) {
            final existing = jsonDecode(await f.readAsString());
            if (existing is Map && existing.containsKey('lastRunDate')) {
              out['lastRunDate'] = existing['lastRunDate'];
            }
          }
        }
      } catch (_) {}

      try {
        Map<String, dynamic>? useGeom;
        if (geom != null) {
          useGeom = geom.cast<String, dynamic>();
        } else {
          // Only capture the window geometry when the HomePage is the
          // currently visible main route. This prevents saving sizes from
          // transient dialogs (settings, stats, etc.). If HomePage is not
          // current, keep the previously persisted window geometry intact.
          final isMainRoute = ModalRoute.of(context)?.isCurrent ?? true;
          if (isMainRoute) {
            final g =
                await _nativeWindowChannel.invokeMethod('getWindowGeometry');
            if (g is Map)
              useGeom = Map<String, dynamic>.from(g.cast<String, dynamic>());
          }
        }
        if (useGeom != null) out['window'] = useGeom;
      } catch (_) {}
      // Persist current notification flags as lists so restarts don't re-notify
      out['notified15'] = _notified15.toList();
      out['notifiedDue'] = _notifiedDue.toList();
      final encoder = const JsonEncoder.withIndent('  ');
      final encoded = encoder.convert(out);
      if (_useSqlite) {
        _sqliteStorage.write(_storage('simplepresent_settings.json'), encoded);
      } else {
        await f.writeAsString(encoded);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      RawKeyboard.instance.removeListener(_rawKeyListener);
    } catch (_) {}
    _windowWatcherTimer?.cancel();
    _saveSettings();
    _controller.dispose();
    _inputFocus.dispose();
    _audioPlayer.dispose();
    _idleTimer?.cancel();
    _attentionTimer?.cancel();
    _reminderTimer?.cancel();
    _urgentTimer?.cancel();
    _autoSwitchTimer?.cancel();
    _scheduledCheckTimer?.cancel();
    _cloudPullTimer?.cancel();
    for (final c in _editControllers.values) {
      c.dispose();
    }
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    for (final c in _subtaskInputControllers.values) {
      c.dispose();
    }
    for (final f in _subtaskFocusNodes.values) {
      try {
        f.dispose();
      } catch (_) {}
    }
    for (final c in _workControllers.values) {
      c.dispose();
    }
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _stopwatchTicker?.cancel();
    _sqliteStorage.dispose();
    super.dispose();
  }

  Future<void> _setMinimalViewMode(bool enable) async {
    if (_minimalViewMode == enable) return;

    if (enable) {
      try {
        final geom =
            await _nativeWindowChannel.invokeMethod('getWindowGeometry');
        if (geom is Map) {
          final norm = <String, int>{};
          for (final e in geom.entries) {
            final k = e.key.toString();
            final v = e.value;
            if (v is int) {
              norm[k] = v;
            } else if (v is double) {
              norm[k] = v.toInt();
            } else {
              norm[k] = int.tryParse(v.toString()) ?? 0;
            }
          }
          // Prefer the last saved user geometry if available (this reflects the
          // last user-drawn size); fall back to the immediate geometry we just
          // queried.
          final Map<String, int> orig = _lastSavedWindowGeom != null
              ? Map<String, int>.from(_lastSavedWindowGeom!)
              : norm;
          _windowBeforeMinimal = Map<String, int>.from(orig);

          // Determine how many tasks will be shown in the minimal view and
          // size the window accordingly. Use a per-item height and a small
          // base so the window fits the content without wasted space.
          final visibleCount = _today
              .where((t) => t.inProgress && !t.done)
              .length
              .clamp(1, 20);
          const int perItemHeight = 56;
          final targetHeight = (13 + (visibleCount * perItemHeight)).clamp(120, 1200);
          // Compute a compact width informed by the number of visible items
          // but never larger than the original width. Start from a sensible
          // minimum and grow moderately with more items.
          final int origWidth = orig['width'] ?? 700;
          int targetWidth = 320 + (visibleCount * 20);
          targetWidth = math.max(320, targetWidth);
          targetWidth = math.min(origWidth, targetWidth);
          await _nativeWindowChannel.invokeMethod('setWindowGeometry', {
            'x': orig['x'] ?? norm['x'] ?? 0,
            'y': orig['y'] ?? norm['y'] ?? 0,
            'width': targetWidth,
            'height': targetHeight,
          });
        }
      } catch (_) {}
    } else {
      try {
        final restore = _windowBeforeMinimal;
        if (restore != null) {
          await _nativeWindowChannel.invokeMethod('setWindowGeometry', {
            'x': restore['x'] ?? 0,
            'y': restore['y'] ?? 0,
            'width': restore['width'] ?? 700,
            'height': restore['height'] ?? 500,
          });
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _minimalViewMode = enable;
    });
  }

  Future<void> _toggleMinimalViewMode() async {
    await _setMinimalViewMode(!_minimalViewMode);
  }

  String _taskNotifyKey(TaskItem t) {
    final sched = t.scheduledAt?.toIso8601String() ?? '';
    return '${t.id}|$sched';
  }

  void _startScheduledChecker() {
    _scheduledCheckTimer?.cancel();
    _scheduledCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      final now = DateTime.now();
      for (final t in _today) {
        // Do not remind for tasks without schedule or already completed
        if (t.scheduledAt == null) continue;
        if (t.done) continue;
        final diff = t.scheduledAt!.difference(now);
        final key = _taskNotifyKey(t);
        // 15-minute warning
        if (!diff.isNegative &&
            diff.inMinutes <= 15 &&
            !_notified15.contains(key)) {
          _notified15.add(key);
          try {
            if (_scheduledReminderSoundEnabled) {
              await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
            }
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('notify', <String, String>{
              'title': _appTitle,
              'body': 'due in 15 minutes: ${t.text}',
              'icon': 'assets/icons/icon.png',
            });
          } catch (_) {}
          // Persist notified flags so restart doesn't re-notify
          try {
            await _saveSettingsWithGeom(_lastSavedWindowGeom);
          } catch (_) {}
        }
        // At due time or overdue (first time)
        if (diff.inSeconds <= 0 && !_notifiedDue.contains(key)) {
          _notifiedDue.add(key);
          try {
            if (_scheduledReminderSoundEnabled) {
              await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
            }
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('notify', <String, String>{
              'title': _appTitle,
              'body': 'due: ${t.text}',
              'icon': 'assets/icons/icon.png',
            });
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('bringToFront');
          } catch (_) {}
          // Persist notified flags so restart doesn't re-notify
          try {
            await _saveSettingsWithGeom(_lastSavedWindowGeom);
          } catch (_) {}
        }
      }
    });
  }

  void _startAutoSwitchTimer() {
    try {
      _autoSwitchTimer?.cancel();
    } catch (_) {}
    _autoSwitchTimer = Timer(_autoSwitchDuration, () async {
      if (!mounted) return;
      // If we are not showing Today (either Backlog or Done), switch back to Today
      if (_showingDone || _showingBacklog) {
        try {
          await _switchFile(false);
        } catch (_) {}
      }
    });
  }

  int _elapsedSecondsFor(TaskItem t) {
    var acc = t.stopwatchAccumulatedSeconds;
    if (t.stopwatchRunning && t.stopwatchStartedAt != null) {
      acc += DateTime.now().difference(t.stopwatchStartedAt!).inSeconds;
    }
    return acc;
  }

  Future<void> _startStopwatch(int index) async {
    final t = _today[index];
    if (t.stopwatchRunning) return;
    setState(() => _today[index] =
        t.copyWith(stopwatchRunning: true, stopwatchStartedAt: DateTime.now()));
    await _saveToday();
  }

  Future<void> _stopStopwatch(int index) async {
    final t = _today[index];
    if (!t.stopwatchRunning) return;
    final started = t.stopwatchStartedAt ?? DateTime.now();
    final added = DateTime.now().difference(started).inSeconds;
    final newAccum = t.stopwatchAccumulatedSeconds + added;
    setState(() => _today[index] = t.copyWith(
        stopwatchRunning: false,
        stopwatchStartedAt: null,
        stopwatchAccumulatedSeconds: newAccum));
    await _saveToday();
  }

  Future<void> _resetStopwatch(int index) async {
    final t = _today[index];
    setState(() => _today[index] = t.copyWith(
        stopwatchRunning: false,
        stopwatchStartedAt: null,
        stopwatchAccumulatedSeconds: 0));
    await _saveToday();
  }

  void _startWindowWatcher() {
    _windowWatcherTimer?.cancel();
    _windowWatcherTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      try {
        final geom =
            await _nativeWindowChannel.invokeMethod('getWindowGeometry');
        if (geom is Map) {
          // normalize ints
          final norm = <String, int>{};
          for (final e in geom.entries) {
            final k = e.key.toString();
            final v = e.value;
            if (v is int)
              norm[k] = v;
            else if (v is double)
              norm[k] = v.toInt();
            else
              norm[k] = int.tryParse(v.toString()) ?? 0;
          
          // Apply magnet snapping if enabled (may update norm)
          try {
            final applied = await _applyMagnetIfNeeded(Map<String, int>.from(norm));
            norm.clear();
            norm.addAll(applied);
          } catch (_) {}
          }
          // Only update the saved main-window geometry when the HomePage
          // route is the current (main) route. This avoids capturing
          // transient dialog/settings window sizes.
          final isMainRoute = ModalRoute.of(context)?.isCurrent ?? true;
          if (isMainRoute) {
            if (_lastSavedWindowGeom == null ||
                !mapEquals(_lastSavedWindowGeom, norm)) {
              _lastSavedWindowGeom = Map<String, int>.from(norm);
              await _saveSettingsWithGeom(_lastSavedWindowGeom);
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<Map<String, int>> _applyMagnetIfNeeded(Map<String, int> norm) async {
    try {
      if (!kIsWeb) {
        // Only apply on desktop platforms
        try {
          if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) return norm;
        } catch (_) {
          return norm;
        }
      } else {
        return norm;
      }

      if (!_magnetEnabled) return norm;

      // Skip if window appears maximized
      final maximized = (norm['maximized'] ?? 0) == 1 || norm['maximized'] == 1;
      if (maximized) return norm;

      final screen = await _nativeWindowChannel.invokeMethod('getScreenSize');
      int sw = 0, sh = 0;
      if (screen is Map) {
        sw = (screen['width'] is int)
            ? screen['width'] as int
            : (screen['width'] is double
                ? (screen['width'] as double).toInt()
                : int.parse(screen['width'].toString()));
        sh = (screen['height'] is int)
            ? screen['height'] as int
            : (screen['height'] is double
                ? (screen['height'] as double).toInt()
                : int.parse(screen['height'].toString()));
      }

      final x = norm['x'] ?? 0;
      final y = norm['y'] ?? 0;
      final width = norm['width'] ?? 800;
      final height = norm['height'] ?? 600;

      final int threshold = _magnetThreshold;
      int snappedX = x;
      int snappedY = y;

      // Left
      if ((x - 0).abs() <= threshold) snappedX = 0;
      // Right
      if (sw > 0) {
        final rightX = sw - width;
        if ((rightX - x).abs() <= threshold) snappedX = rightX;
      }
      // Top
      if ((y - 0).abs() <= threshold) snappedY = 0;
      // Bottom
      if (sh > 0) {
        final bottomY = sh - height;
        if ((bottomY - y).abs() <= threshold) snappedY = bottomY;
      }

      if (snappedX != x || snappedY != y) {
        final payload = <String, dynamic>{
          'x': snappedX,
          'y': snappedY,
          'width': width,
          'height': height,
        };
        try {
          await _nativeWindowChannel.invokeMethod('setWindowGeometry', payload);
          norm['x'] = snappedX;
          norm['y'] = snappedY;
        } catch (_) {}
      }
    } catch (_) {}
    return norm;
  }

  Future<void> _openStats() async {
    // load today/backlog/done lists and open stats page
    final List<TaskItem> combined = [];
    final List<TaskItem> todayList = [];
    final List<TaskItem> backlogList = [];
    final List<TaskItem> doneList = [];
    await _loadList(_storage('simplepresent_today.json'), todayList);
    await _loadList(_storage('simplepresent_backlog.json'), backlogList);
    await _loadList(_storage('simplepresent_done.json'), doneList);
    combined.addAll(todayList);
    combined.addAll(backlogList);
    combined.addAll(doneList);

    // Normalize: tasks marked done but missing completedAt are considered completed now
    final normalized = combined.map((t) {
      if (t.done && t.completedAt == null) {
        return t.copyWith(completedAt: DateTime.now());
      }
      return t;
    }).toList();

    if (!mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (ctx) => StatsPage(doneList: normalized)));
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (ctx) => SettingsPage(
          initial: <String, dynamic>{
            'idleMinutes': _idleMinutes,
            'attentionMinutes': _attentionMinutes,
            'reminderMinutes': _reminderMinutes,
            'urgentMinutes': _urgentMinutes,
            'idleSoundEnabled': _idleSoundEnabled,
            'idleFlashEnabled': _idleFlashEnabled,
            'idleNotifyEnabled': _idleNotifyEnabled,
            'idleBringToFrontEnabled': _idleBringToFrontEnabled,
            'attentionSoundEnabled': _attentionSoundEnabled,
            'attentionFlashEnabled': _attentionFlashEnabled,
            'attentionNotifyEnabled': _attentionNotifyEnabled,
            'attentionBringToFrontEnabled': _attentionBringToFrontEnabled,
            'reminderSoundEnabled': _reminderSoundEnabled,
            'reminderNotifyEnabled': _reminderNotifyEnabled,
            'reminderFlashEnabled': _reminderFlashEnabled,
            'reminderBringToFrontEnabled': _reminderBringToFrontEnabled,
            'urgentSoundEnabled': _urgentSoundEnabled,
            'urgentFlashEnabled': _urgentFlashEnabled,
            'urgentNotifyEnabled': _urgentNotifyEnabled,
            'urgentBringToFrontEnabled': _urgentBringToFrontEnabled,
            'swipeEnabled': _swipeEnabled,
            'magnetEnabled': _magnetEnabled,
            'uiTextScaleFactor': _uiTextScaleFactor,
            'fontFamily': _fontFamily,
            'cloudServerUrl': _cloudServerUrl,
            'cloudAccountId': _cloudAccountId,
            'cloudDeviceId': _cloudDeviceId,
            'cloudToken': _cloudToken,
            'cloudWordPhrase': _cloudWordPhrase,
            'cloudDeviceName': _cloudDeviceName,
            'cloudPIN': _cloudPIN,
            'scheduledReminderSoundEnabled': _scheduledReminderSoundEnabled,
          },
        ),
      ),
    );
    if (!mounted || result == null) return;

    int clampMin(dynamic v, int fallback) {
      final parsed = (v is int) ? v : int.tryParse(v?.toString() ?? '');
      if (parsed == null) return fallback;
      return parsed.clamp(1, 720);
    }

    double clampTextScale(dynamic v, double fallback) {
      final parsed =
          (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '');
      if (parsed == null) return fallback;
      return _clampUiTextScaleFactor(parsed);
    }

    setState(() {
      _idleMinutes = clampMin(result['idleMinutes'], _idleMinutes);
      _attentionMinutes =
          clampMin(result['attentionMinutes'], _attentionMinutes);
      _reminderMinutes = clampMin(result['reminderMinutes'], _reminderMinutes);
      _urgentMinutes = clampMin(result['urgentMinutes'], _urgentMinutes);
      _idleSoundEnabled = result['idleSoundEnabled'] == true;
      _idleFlashEnabled = result['idleFlashEnabled'] == true;
      _idleNotifyEnabled = result['idleNotifyEnabled'] == true;
      _idleBringToFrontEnabled = result['idleBringToFrontEnabled'] == true;
      _attentionSoundEnabled = result['attentionSoundEnabled'] == true;
      _attentionFlashEnabled = result['attentionFlashEnabled'] == true;
      _attentionNotifyEnabled = result['attentionNotifyEnabled'] == true;
      _attentionBringToFrontEnabled =
          result['attentionBringToFrontEnabled'] == true;
      _reminderSoundEnabled = result['reminderSoundEnabled'] == true;
      _reminderNotifyEnabled = result['reminderNotifyEnabled'] == true;
      _reminderFlashEnabled = result['reminderFlashEnabled'] == true;
      _reminderBringToFrontEnabled =
          result['reminderBringToFrontEnabled'] == true;
        _scheduledReminderSoundEnabled = result['scheduledReminderSoundEnabled'] == true;
      _urgentSoundEnabled = result['urgentSoundEnabled'] == true;
      _urgentFlashEnabled = result['urgentFlashEnabled'] == true;
      _urgentNotifyEnabled = result['urgentNotifyEnabled'] == true;
      _urgentBringToFrontEnabled = result['urgentBringToFrontEnabled'] == true;
      _swipeEnabled = result['swipeEnabled'] == true;
      _magnetEnabled = result['magnetEnabled'] == true;
      _uiTextScaleFactor =
          clampTextScale(result['uiTextScaleFactor'], _uiTextScaleFactor);
      if (result['fontFamily'] is String &&
          (result['fontFamily'] as String).isNotEmpty) {
        _fontFamily = result['fontFamily'] as String;
      }
      if (result['cloudServerUrl'] is String) {
        _cloudServerUrl = result['cloudServerUrl'] as String;
      }
      if (result['cloudAccountId'] is String) {
        _cloudAccountId = result['cloudAccountId'] as String;
      }
      if (result['cloudDeviceId'] is String) {
        _cloudDeviceId = result['cloudDeviceId'] as String;
      }
      if (result['cloudToken'] is String) {
        _cloudToken = result['cloudToken'] as String;
      }
      if (result['cloudWordPhrase'] is String) {
        _cloudWordPhrase = result['cloudWordPhrase'] as String;
      }
      if (result['cloudDeviceName'] is String &&
          (result['cloudDeviceName'] as String).isNotEmpty) {
        _cloudDeviceName = result['cloudDeviceName'] as String;
      }
      if (result['cloudPIN'] is String) {
        _cloudPIN = result['cloudPIN'] as String;
      }
    });

    _registerActivity();
    await _saveSettings();
    _startCloudPullTimer();
    unawaited(_syncPullFromCloud());
    unawaited(_fetchServerVersion());
    _showTopToast('settings saved');
  }

  void _toggleExpanded(int index) {
    if (_expanded.contains(index)) {
      // collapsing: save edited title/notes before collapsing
      _saveEditedTitle(index);
      setState(() {
        _expanded.remove(index);
      });
    } else {
      setState(() {
        _expanded.add(index);
        _editControllers.putIfAbsent(index, () {
          final c = TextEditingController(text: _today[index].text.trim());
          c.addListener(() {
            if (mounted) setState(() {});
          });
          return c;
        });
        _notesControllers.putIfAbsent(index, () {
          final n = TextEditingController(text: _today[index].notes ?? '');
          n.addListener(() {
            if (mounted) setState(() {});
          });
          return n;
        });
      });
    }
    _registerActivity();
  }

  Future<void> _saveEditedTitle(int index) async {
    final titleCtrl = _editControllers[index];
    final notesCtrl = _notesControllers[index];
    if (titleCtrl == null || notesCtrl == null) return;
    final newText = titleCtrl.text.trim();
    final newNotes = notesCtrl.text;
    if (newText.isEmpty) return;
    setState(() {
      var updated = _today[index].copyWith(text: newText, notes: newNotes);
      final workCtrl = _workControllers[updated.id];
      if (workCtrl != null) {
        final parsed = int.tryParse(workCtrl.text.trim());
        if (parsed != null) {
          updated = updated.copyWith(workMinutes: parsed);
        }
      }
      _today[index] = updated;
    });
    _saveToday();

    // If the task has a scheduled date and it's not today, move it to backlog
    final scheduled = _today[index].scheduledAt;
    if (scheduled != null && !_isSameDay(scheduled, DateTime.now())) {
      await _moveToBacklogByIndex(index);
      return;
    }

    _showTopToast('task updated');
    _registerActivity();
  }

  void _addSubtask(int taskIndex, TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final task = _today[taskIndex];
    final step = TaskStep(
      id: '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}',
      text: text,
    );
    setState(() {
      _today[taskIndex] = task.copyWith(subtasks: [...task.subtasks, step]);
    });
    controller.clear();
    // Return focus to the subtask input so the user can add another subtask quickly
    try {
      _subtaskFocusNodes[task.id]?.requestFocus();
    } catch (_) {}
    _saveToday();
    _registerActivity();
  }

  void _updateSubtask(
    int taskIndex,
    String subtaskId, {
    String? text,
    bool? done,
  }) {
    final task = _today[taskIndex];
    final updated = task.subtasks.map((step) {
      if (step.id != subtaskId) return step;
      return step.copyWith(
        text: text,
        done: done,
      );
    }).toList();
    setState(() {
      _today[taskIndex] = task.copyWith(subtasks: updated);
    });
    _saveToday();
    _registerActivity();
  }

  void _removeSubtask(int taskIndex, String subtaskId) {
    final task = _today[taskIndex];
    setState(() {
      _today[taskIndex] = task.copyWith(
        subtasks: task.subtasks.where((step) => step.id != subtaskId).toList(),
      );
    });
    _saveToday();
    _registerActivity();
  }

  void _reorderSubtasks(int taskIndex, int oldIndex, int newIndex) {
    final task = _today[taskIndex];
    final list = List<TaskStep>.from(task.subtasks);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    setState(() {
      _today[taskIndex] = task.copyWith(subtasks: list);
    });
    _saveToday();
    _registerActivity();
  }

  Future<void> _pickSchedule(int index) async {
    final now = DateTime.now();
    final initial = _today[index].scheduledAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null) return;
    final TimeOfDay suggestedNextHour =
        TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    final TimeOfDay initialTime = _today[index].scheduledAt != null
        ? TimeOfDay.fromDateTime(initial)
        : suggestedNextHour;
    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (time == null) return;
    final scheduled =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(
        () => _today[index] = _today[index].copyWith(scheduledAt: scheduled));
    await _saveToday();

    // If scheduled date is not today, move to backlog automatically
    if (!_isSameDay(scheduled, DateTime.now())) {
      await _moveToBacklogByIndex(index);
      return;
    }

    _showTopToast('schedule set');
    // clear any prior notifications for this task so reminders can be re-scheduled
    final idPrefix = '${_today[index].id}|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
    _registerActivity();
    try {
      await _saveSettingsWithGeom(_lastSavedWindowGeom);
    } catch (_) {}
  }

  Future<void> _moveFromBacklog(int index) async {
    try {
      final item = _today[index];
      setState(() {
        _today.removeAt(index);
        _expanded.clear();
      });
      await _saveToday(); // persist removal from backlog file

      final List<TaskItem> todayList = [];
      await _loadList(_storage('simplepresent_today.json'), todayList);
      todayList.insert(0, item.copyWith(done: false, inProgress: false));
      await _saveList('simplepresent_today.json', todayList);

      _showTopToast('task moved to today');
    } catch (_) {
      _showTopToast('failed to move task to today');
    }
    _registerActivity();
  }

  Future<void> _moveToBacklogByIndex(int index) async {
    try {
      final item = _today[index];
      setState(() {
        _today.removeAt(index);
        _expanded.clear();
      });
      await _saveToday(); // persist removal from today

      final List<TaskItem> backlogList = [];
      await _loadList('simplepresent_backlog.json', backlogList);
      // insert at top so task appears first in backlog
      backlogList.insert(0, item.copyWith(done: false, inProgress: false));
      await _saveList('simplepresent_backlog.json', backlogList);
      // If we're currently showing backlog, reload to reflect the new top item
      if (_showingBacklog || _currentFile == 'simplepresent_backlog.json') {
        await _loadToday();
      }
      _showTopToast('task moved to backlog');
    } catch (_) {
      _showTopToast('failed to move task to backlog');
    }
    _registerActivity();
  }

  Future<void> _moveToBacklog(int index) async {
    try {
      final item = _today[index];
      setState(() {
        _today.removeAt(index);
        _expanded.clear();
      });
      await _saveToday(); // persist removal from today

      final List<TaskItem> backlogList = [];
      await _loadList('simplepresent_backlog.json', backlogList);
      // append to backlog at end
      backlogList.add(item.copyWith(done: false, inProgress: false));
      await _saveList('simplepresent_backlog.json', backlogList);

      _showTopToast('task moved to backlog');
    } catch (_) {
      _showTopToast('failed to move task to backlog');
    }
    _registerActivity();
  }

  Future<void> _clearSchedule(int index) async {
    // capture id before mutating list item
    final id = _today[index].id;
    // clear in-memory and save current view
    setState(() => _today[index] = _today[index].copyWith(scheduledAt: null));
    await _saveToday();
    _showTopToast('schedule cleared');
    final idPrefix2 = '$id|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix2));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix2));
    _registerActivity();

    // Ensure persisted lists also have the schedule cleared for this task id
    try {
      final files = [
        'simplepresent_today.json',
        'simplepresent_backlog.json',
        'simplepresent_done.json'
      ];
      final changedFiles = <String>[];
      for (final f in files) {
        final List<TaskItem> list = [];
        await _loadList(f, list);
        var changed = false;
        for (var i = 0; i < list.length; i++) {
          final t = list[i];
          if (t.id == id && t.scheduledAt != null) {
            list[i] = t.copyWith(scheduledAt: null);
            changed = true;
          }
        }
        if (changed) {
          await _saveList(f, list);
          changedFiles.add(f);
          // read back the saved file and capture the task snippet for debugging
          try {
            String? savedText;
            if (_useSqlite) {
              savedText = _sqliteStorage.read(f);
            } else {
              final savedFile = await _fileFor(f);
              if (await savedFile.exists()) {
                savedText = await savedFile.readAsString();
              }
            }
            if (savedText != null) {
              // try to extract the JSON object for this id
              final idIndex = savedText.indexOf('"id": "${id}"');
              String snippet = '';
              if (idIndex >= 0) {
                // find the enclosing braces around this object
                final start = savedText.lastIndexOf('{', idIndex);
                final end = savedText.indexOf('}', idIndex);
                if (start >= 0 && end >= 0 && end > start) {
                  snippet = savedText.substring(start, end + 1);
                }
              }
              final logFile2 =
                  await _fileFor('simplepresent_clear_schedule.log');
              final now2 = DateTime.now().toIso8601String();
              final entry2 =
                  '$now2 | post-save snippet for $f id=$id | snippet=${snippet.replaceAll("\n", " ")}\n';
              if (await logFile2.exists()) {
                await logFile2.writeAsString(entry2, mode: FileMode.append);
              } else {
                await logFile2.writeAsString(entry2);
              }
            }
          } catch (_) {}
        }
      }
      // reload view so UI reflects persisted changes
      await _loadToday();

      // write a debug log in app dir to help diagnose persistence mismatches
      try {
        final logFile = await _fileFor('simplepresent_clear_schedule.log');
        final now = DateTime.now().toIso8601String();
        final entry =
            '$now | cleared schedule for id=$id | changed=${changedFiles.join(',')}' +
                '\n';
        if (await logFile.exists()) {
          await logFile.writeAsString(entry, mode: FileMode.append);
        } else {
          await logFile.writeAsString(entry);
        }
      } catch (_) {}
    } catch (_) {}
    try {
      await _saveSettingsWithGeom(_lastSavedWindowGeom);
    } catch (_) {}
  }

  void _showTopToast(String message) {
    _toastTimer?.cancel();
    _toastEntry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    _toastEntry = OverlayEntry(
      builder: (ctx) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, left: 12, right: 12),
            child: TweenAnimationBuilder<Offset>(
              duration: const Duration(milliseconds: 260),
              tween: Tween(begin: const Offset(0, -1), end: Offset.zero),
              curve: Curves.easeOutCubic,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
              builder: (context, offset, child) {
                return Transform.translate(
                  offset: Offset(0, offset.dy * 60),
                  child: child,
                );
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(milliseconds: 1650), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  void _addToToday([String? text]) {
    // Use the main input controller as source of truth to avoid cases where
    // other focused edit fields provide conflicting text.
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    // Prevent controller/index mismatch: collapse expanded editors and dispose their controllers
    if (_expanded.isNotEmpty) {
      for (final c in _editControllers.values) {
        try {
          c.dispose();
        } catch (_) {}
      }
      _editControllers.clear();
      for (final c in _notesControllers.values) {
        try {
          c.dispose();
        } catch (_) {}
      }
      _notesControllers.clear();
      _expanded.clear();
    }
    setState(() {
      _today.insert(
          0,
          TaskItem(
              id: '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}',
              text: input,
              done: false,
              createdAt: DateTime.now(),
              notes: ''));
      _controller.clear();
    });
    _saveToday();
    _inputFocus.requestFocus();
    _registerActivity();
  }

  Future<void> _setDone(int index, bool value) async {
    // If we're in the Done view and the user unchecks done, move the task back to Today
    final original = _today[index];
    if (!value && _currentFile == 'simplepresent_done.json') {
      try {
        final restored = original.copyWith(done: false, completedAt: null);
        setState(() {
          _today.removeAt(index);
          _expanded.clear();
        });
        await _saveToday(); // persist removal from done file

        final List<TaskItem> todayList = [];
        await _loadList('simplepresent_today.json', todayList);
        todayList.insert(0, restored);
        await _saveList('simplepresent_today.json', todayList);

        _showTopToast('task moved to today');
      } catch (_) {
        _showTopToast('failed to move task');
      }
      _registerActivity();
      return;
    }

    // If we're in the Backlog view and the user marks a task done, move it to Done list
    if (value && _currentFile == 'simplepresent_backlog.json') {
      try {
        // stop running stopwatch for this task before moving to Done
        await _stopStopwatch(index);
        final finalTask = _today[index];
        final moved =
            finalTask.copyWith(done: true, completedAt: DateTime.now());
        setState(() {
          _today.removeAt(index);
          _expanded.clear();
        });
        await _saveToday(); // persist removal from backlog
        await _appendDone([moved]);
        _showTopToast('task moved to done');
        _playDading();
      } catch (_) {
        _showTopToast('failed to move task to done');
      }
      _registerActivity();
      return;
    }

    setState(() {
      final t = _today[index];
      // When marking done, clear inProgress
      _today[index] = t.copyWith(
        done: value,
        inProgress: value ? false : t.inProgress,
        completedAt: value ? DateTime.now() : t.completedAt,
      );
    });
    // If marked done, stop the stopwatch and persist
    if (value == true) {
      await _stopStopwatch(index);
    }
    _saveToday();
    // clear notification flags for this task (by id)
    final t = _today[index];
    final idPrefix = '${t.id}|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
    // Play a friendly sound when a task is marked done
    if (value == true) {
      _playDading();
    }
    _registerActivity();
    try {
      await _saveSettingsWithGeom(_lastSavedWindowGeom);
    } catch (_) {}
  }

  Future<void> _playDading() async {
    try {
      // Try to play bundled asset: assets/sounds/ding.mp3
      await _audioPlayer.play(AssetSource('sounds/ding.mp3'));
    } catch (e) {
      // Fallback to system click if asset missing or playback fails
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> _removeFromToday(int index) async {
    final removed = _today[index];
    setState(() {
      _today.removeAt(index);
    });
    await _saveToday();
    // Move the removed task into the trash file instead of permanent delete
    try {
      final List<TaskItem> trash = [];
      await _loadList('simplepresent_trash.json', trash);
      trash.add(removed);
      await _saveList('simplepresent_trash.json', trash);
    } catch (_) {}
    // Clear any pending notification flags for this task (use text match)
    final idPrefix = '${removed.id}|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
    _registerActivity();
    try {
      await _saveSettingsWithGeom(_lastSavedWindowGeom);
    } catch (_) {}
  }

  void _registerActivity() {
    // Reset idle timer on user activity
    try {
      _idleTimer?.cancel();
      _attentionTimer?.cancel();
      _reminderTimer?.cancel();
    } catch (_) {}
    // Reset fired flags so reminders can fire again after activity
    _idleFired = false;
    _attentionFired = false;
    _reminderFired = false;
    _urgentFired = false;
    _startIdleTimer();
    _startAttentionTimer();
    _startReminderTimer();
    _startUrgentTimer();
    _startAutoSwitchTimer();
  }

  Color _scheduleIconColor(DateTime scheduledAt) {
    final now = DateTime.now();
    final diffSec = scheduledAt.difference(now).inSeconds.toDouble();
    const threeHours = 3 * 3600.0;
    if (diffSec >= threeHours) return Colors.green;
    if (diffSec >= 0) {
      final r = 1.0 - (diffSec / threeHours); // 0 at 3h, 1 at 0h
      return Color.lerp(Colors.green, Colors.blue, r) ?? Colors.blue;
    }
    final overdueSec = diffSec.abs();
    if (overdueSec >= threeHours) return Colors.red;
    final r2 = math.min(1.0, overdueSec / threeHours);
    return Color.lerp(Colors.blue, Colors.red, r2) ?? Colors.red;
  }

  void _startIdleTimer() {
    _idleTimer = Timer(_idleDuration, () async {
      if (_idleFired) return;
      if (_idleSoundEnabled) {
        try {
          await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        } catch (_) {
          SystemSound.play(SystemSoundType.alert);
        }
      }
      if (_idleFlashEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('flashTaskbar');
        } catch (_) {}
      }
      if (_idleNotifyEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('notify', <String, String>{
            'title': _appTitle,
            'body': 'You have been inactive for $_idleMinutes minutes',
            'icon': 'assets/icons/icon.png',
          });
        } catch (_) {}
      }
      if (_idleBringToFrontEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('bringToFront');
        } catch (_) {}
      }
      _idleFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  void _startAttentionTimer() {
    _attentionTimer = Timer(_attentionDuration, () async {
      if (_attentionFired) return;
      if (_attentionSoundEnabled) {
        try {
          await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        } catch (_) {}
      }
      if (_attentionFlashEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('flashTaskbar');
        } catch (_) {}
      }
      if (_attentionNotifyEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('notify', <String, String>{
            'title': _appTitle,
            'body': 'You have been inactive for $_attentionMinutes minutes',
            'icon': 'assets/icons/icon.png',
          });
        } catch (_) {}
      }
      if (_attentionBringToFrontEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('bringToFront');
        } catch (_) {}
      }
      _attentionFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  void _startReminderTimer() {
    _reminderTimer = Timer(_reminderDuration, () async {
      if (_reminderFired) return;
      if (_reminderSoundEnabled) {
        try {
          await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        } catch (_) {}
      }
      if (_reminderFlashEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('flashTaskbar');
        } catch (_) {}
      }
      if (_reminderNotifyEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('notify', <String, String>{
            'title': _appTitle,
            'body': 'You have been inactive for $_reminderMinutes minutes',
            'icon': 'assets/icons/icon.png',
          });
        } catch (_) {}
      }
      if (_reminderBringToFrontEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('bringToFront');
        } catch (_) {}
      }
      _reminderFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  void _startUrgentTimer() {
    _urgentTimer = Timer(_urgentDuration, () async {
      if (_urgentFired) return;
      if (_urgentSoundEnabled) {
        try {
          await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        } catch (_) {}
      }
      if (_urgentFlashEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('flashTaskbar');
        } catch (_) {}
      }
      if (_urgentNotifyEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('notify', <String, String>{
            'title': _appTitle,
            'body': 'You have been inactive for $_urgentMinutes minutes',
            'icon': 'assets/icons/icon.png',
          });
        } catch (_) {}
      }
      if (_urgentBringToFrontEnabled) {
        try {
          await _nativeWindowChannel.invokeMethod('bringToFront');
        } catch (_) {}
      }
      _urgentFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(_uiTextScaleFactor)),
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: _fontFamily),
          primaryTextTheme:
              baseTheme.primaryTextTheme.apply(fontFamily: _fontFamily),
        ),
        child: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snap) {
            return Scaffold(
              body: Stack(
                children: [
                  Listener(
                onPointerDown: (_) => _registerActivity(),
                onPointerSignal: (ps) {
                  if (ps is PointerScrollEvent) {
                    final ctrl = RawKeyboard.instance.keysPressed
                            .contains(LogicalKeyboardKey.controlLeft) ||
                        RawKeyboard.instance.keysPressed
                            .contains(LogicalKeyboardKey.controlRight);
                    if (!ctrl) return;
                    final delta = ps.scrollDelta.dy;
                    final step = delta.abs() * 0.08;
                    if (delta > 0) {
                      // zoom out
                      final candidate = (_tileHeight - step)
                          .clamp(_minTileHeight, _defaultTileHeight);
                      setState(() {
                        _tileHeight = candidate;
                        _fontScale = _fontScaleForTileHeight(_tileHeight);
                      });
                    } else {
                      // zoom in
                      final candidate = (_tileHeight + step)
                          .clamp(_minTileHeight, _defaultTileHeight);
                      setState(() {
                        _tileHeight = candidate;
                        _fontScale = _fontScaleForTileHeight(_tileHeight);
                      });
                    }
                  }
                },
                child: GestureDetector(
                  onScaleStart: (d) {
                    _tileHeightStart = _tileHeight;
                    _fontScaleStart = _fontScale;
                  },
                  onScaleUpdate: (d) {
                    if (d.scale == 0.0 || d.scale.isNaN) return;
                    final newHeight = (_tileHeightStart * d.scale)
                        .clamp(_minTileHeight, double.infinity);
                    setState(() {
                      _tileHeight = newHeight;
                      _fontScale = _fontScaleForTileHeight(_tileHeight);
                    });
                  },
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _inputFocus.requestFocus();
                    _registerActivity();
                  },
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: (!_minimalViewMode && Platform.isAndroid)
                            ? MediaQuery.of(context).padding.top
                            : 0.0,
                      ),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: _minimalViewMode
                              ? const EdgeInsets.fromLTRB(8, 8, 6, 8)
                              : const EdgeInsets.fromLTRB(12, 22, 6, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: _minimalViewMode
                                    ? const SizedBox.shrink(
                                        key: ValueKey('header_hidden'))
                                    : Row(
                                        key: const ValueKey('header_visible'),
                                children: [
                                  // Left arrow moved to the far left of the header row
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_ios),
                                    tooltip: 'Previous',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      await _cycleView(false);
                                    },
                                  ),
                                  Expanded(
                                    child: LayoutBuilder(
                                        builder: (ctx, constraints) {
                                      // Styles used for measurement and rendering
                                      final titleStyle = const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                      ).copyWith(fontFamily: _fontFamily);
                                      final combined = TextSpan(
                                        text: _showingBacklog
                                            ? 'backlog'
                                            : (_showingDone ? 'done' : 'today'),
                                        style: titleStyle,
                                      );

                                      // Measure required width for the combined text
                                      final tp = TextPainter(
                                          text: combined,
                                          textDirection:
                                              Directionality.of(context),
                                          textScaleFactor:
                                              MediaQuery.textScaleFactorOf(
                                                  context));
                                      tp.layout();
                                      final textWidth = tp.width;

                                      const double iconSize =
                                          28.0; // size allocated for the icon when fully shown
                                      const double iconGap = 8.0;
                                      final available = constraints.maxWidth;

                                      final showIconFully =
                                          (textWidth + iconSize + iconGap) <=
                                              available;

                                      return SizedBox(
                                        height: 40,
                                        child: Stack(
                                          alignment: Alignment.centerLeft,
                                          children: [
                                            // Icon placed on the left; when not enough space we keep it behind the text and fade it
                                            Positioned(
                                              left: 0,
                                              top: 6,
                                              child: AnimatedOpacity(
                                                duration: const Duration(
                                                    milliseconds: 250),
                                                opacity:
                                                    showIconFully ? 1.0 : 0.18,
                                                child: Image.asset(
                                                  _showingBacklog
                                                      ? 'assets/icons/backlog.png'
                                                      : (_showingDone
                                                          ? 'assets/icons/done.png'
                                                          : 'assets/icons/today.png'),
                                                  width: iconSize,
                                                  height: iconSize,
                                                ),
                                              ),
                                            ),
                                            // Title text — when icon is fully shown we add left padding so text sits beside the icon,
                                            // otherwise we let the text occupy full width and visually overlap the faded icon.
                                            Padding(
                                              padding: EdgeInsets.only(
                                                  left: showIconFully
                                                      ? (iconSize + iconGap)
                                                      : 0,
                                                  right: 4.0),
                                              child: RichText(
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                text: combined,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.bar_chart),
                                        tooltip: 'Statistics',
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6.0),
                                        constraints: const BoxConstraints(
                                            minWidth: 28, minHeight: 28),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () async {
                                          await _openStats();
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.settings),
                                        tooltip: 'Settings',
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6.0),
                                        constraints: const BoxConstraints(
                                            minWidth: 28, minHeight: 28),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () async {
                                          await _openSettings();
                                        },
                                      ),
                                      IconButton(
                                        icon:
                                            const Icon(Icons.arrow_forward_ios),
                                        tooltip: 'Next',
                                        padding: const EdgeInsets.only(
                                            left: 6.0, right: 0.0),
                                        constraints: const BoxConstraints(
                                            minWidth: 28, minHeight: 28),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () async {
                                          await _cycleView(true);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                                      ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                height: _minimalViewMode ? 0.0 : 8.0,
                              ),
                              Expanded(
                                child: _today.isEmpty
                                    ? Center(
                                        child: Text(_showingBacklog
                                            ? 'No backlog tasks'
                                            : (_showingDone
                                                ? 'No archived tasks'
                                                : 'No tasks for today')))
                                    : Builder(builder: (ctx) {
                                        // Build grouped list preserving insertion order within groups
                                        final bucketOverdue = <MapEntry<int,
                                            TaskItem>>[]; // tasks past their scheduled time
                                        final bucketImportantInProgress =
                                            <MapEntry<int, TaskItem>>[];
                                        final bucketInProgress =
                                            <MapEntry<int, TaskItem>>[];
                                        final bucketImportant =
                                            <MapEntry<int, TaskItem>>[];
                                        final bucketDueIn1h =
                                            <MapEntry<int, TaskItem>>[];
                                        final bucketRest = <MapEntry<int,
                                            TaskItem>>[]; // rest (insertion order)
                                        final bucketDone = <MapEntry<int,
                                            TaskItem>>[]; // done tasks (always bottom)

                                        final now = DateTime.now();
                                        final entries = _today
                                          .asMap()
                                          .entries
                                          .where((e) =>
                                            !_minimalViewMode ||
                                            (e.value.inProgress &&
                                              !e.value.done));
                                        for (final e in entries) {
                                          final t = e.value;
                                          if (t.done) {
                                            bucketDone.add(e);
                                            continue;
                                          }
                                          final hasSchedule =
                                              t.scheduledAt != null;
                                          final diff = hasSchedule
                                              ? t.scheduledAt!.difference(now)
                                              : null;
                                          final isOverdue =
                                              hasSchedule && diff!.isNegative;
                                          final dueWithin1h = hasSchedule &&
                                              !diff!.isNegative &&
                                              diff.inMinutes <= 60;

                                          if (isOverdue) {
                                            bucketOverdue.add(e);
                                            continue;
                                          }
                                          if (t.important && t.inProgress) {
                                            bucketImportantInProgress.add(e);
                                            continue;
                                          }
                                          if (t.inProgress) {
                                            bucketInProgress.add(e);
                                            continue;
                                          }
                                          if (t.important) {
                                            bucketImportant.add(e);
                                            continue;
                                          }
                                          if (dueWithin1h) {
                                            bucketDueIn1h.add(e);
                                            continue;
                                          }
                                          bucketRest.add(e);
                                        }

                                        final sorted = [
                                          ...bucketOverdue,
                                          ...bucketImportantInProgress,
                                          ...bucketInProgress,
                                          ...bucketImportant,
                                          ...bucketDueIn1h,
                                          ...bucketRest,
                                          ...bucketDone,
                                        ];

                                        return ReorderableListView(
                                          buildDefaultDragHandles: false,
                                          onReorder: (oldIndex, newIndex) {
                                            // Normalize indices as in ReorderableListView behavior
                                            if (newIndex > oldIndex)
                                              newIndex -= 1;
                                            final srcEntry = sorted[oldIndex];
                                            final dstEntry = sorted[newIndex];
                                            // Determine bucket membership for src and dst
                                            int bucketOf(
                                                MapEntry<int, TaskItem> e) {
                                              if (bucketOverdue.contains(e))
                                                return 0;
                                              if (bucketImportantInProgress
                                                  .contains(e)) return 1;
                                              if (bucketInProgress.contains(e))
                                                return 2;
                                              if (bucketImportant.contains(e))
                                                return 3;
                                              if (bucketDueIn1h.contains(e))
                                                return 4;
                                              if (bucketRest.contains(e))
                                                return 5;
                                              return 6; // done
                                            }

                                            final srcBucket =
                                                bucketOf(srcEntry);
                                            final dstBucket =
                                                bucketOf(dstEntry);
                                            if (srcBucket != dstBucket) {
                                              _showTopToast(
                                                  'Reorder allowed only within the same group');
                                              return;
                                            }

                                            // Work on the specific bucket list
                                            List<MapEntry<int, TaskItem>>
                                                targetBucket;
                                            switch (srcBucket) {
                                              case 0:
                                                targetBucket = bucketOverdue;
                                                break;
                                              case 1:
                                                targetBucket =
                                                    bucketImportantInProgress;
                                                break;
                                              case 2:
                                                targetBucket = bucketInProgress;
                                                break;
                                              case 3:
                                                targetBucket = bucketImportant;
                                                break;
                                              case 4:
                                                targetBucket = bucketDueIn1h;
                                                break;
                                              case 5:
                                                targetBucket = bucketRest;
                                                break;
                                              default:
                                                targetBucket = bucketDone;
                                            }

                                            final srcPos =
                                                targetBucket.indexWhere((e) =>
                                                    e.key == srcEntry.key &&
                                                    e.value.text ==
                                                        srcEntry.value.text);
                                            if (srcPos == -1) return;

                                            // Compute destination position within the bucket by counting how many entries from start of sorted up to newIndex belong to this bucket
                                            int dstPos = 0;
                                            for (int i = 0; i < newIndex; i++) {
                                              if (bucketOf(sorted[i]) ==
                                                  srcBucket) dstPos++;
                                            }

                                            // Adjust if moving forward within bucket
                                            if (dstPos > srcPos) dstPos -= 1;

                                            setState(() {
                                              // reorder within the targetBucket
                                              final moved =
                                                  targetBucket.removeAt(srcPos);
                                              targetBucket.insert(
                                                  dstPos.clamp(
                                                      0, targetBucket.length),
                                                  moved);

                                              // rebuild _today preserving bucket concatenation order
                                              final newOrder = <TaskItem>[];
                                              void appendBucket(
                                                      List<
                                                              MapEntry<int,
                                                                  TaskItem>>
                                                          b) =>
                                                  newOrder.addAll(
                                                      b.map((e) => e.value));
                                              appendBucket(bucketOverdue);
                                              appendBucket(
                                                  bucketImportantInProgress);
                                              appendBucket(bucketInProgress);
                                              appendBucket(bucketImportant);
                                              appendBucket(bucketDueIn1h);
                                              appendBucket(bucketRest);
                                              appendBucket(bucketDone);
                                              _today.clear();
                                              _today.addAll(newOrder);
                                              _saveToday();
                                            });
                                          },
                                          children: List.generate(sorted.length,
                                              (vi) {
                                            final originalIndex =
                                                sorted[vi].key;
                                            final task = sorted[vi].value;
                                            final completedSubtasks = task
                                                .subtasks
                                                .where((step) => step.done)
                                                .length;
                                            final totalSubtasks =
                                                task.subtasks.length;
                                            final i = originalIndex;
                                            if (_minimalViewMode) {
                                              return Card(
                                                key: ValueKey(
                                                    'mini_${i}_${task.id}'),
                                                color: task.inProgress
                                                    ? Colors.green
                                                        .withOpacity(0.10)
                                                    : null,
                                                child: ListTile(
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          vertical: ((_tileHeight -
                                                                          _baseFontSize) /
                                                                      2)
                                                                  .clamp(
                                                                      0.0,
                                                                      40.0),
                                                          horizontal: 12),
                                                  title: Text(
                                                    task.text,
                                                    style: _fontTextStyle(
                                                      TextStyle(
                                                        fontSize: _baseFontSize,
                                                        fontWeight:
                                                            FontWeight.normal,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }
                                            return Dismissible(
                                              key: ValueKey(
                                                  'today_${i}_${task.text}_${task.done}'),
                                              background: Container(
                                                color: Colors.green,
                                                alignment: Alignment.centerLeft,
                                                padding: const EdgeInsets.only(
                                                    left: 20),
                                                child: (_showingBacklog ||
                                                        _currentFile ==
                                                            'simplepresent_backlog.json')
                                                    ? Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                              Icons
                                                                  .arrow_circle_left,
                                                              color:
                                                                  Colors.white,
                                                              size: 20),
                                                          const SizedBox(
                                                              width: 8),
                                                          const Text(
                                                              'moved to today',
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600)),
                                                        ],
                                                      )
                                                    : (_today[i].inProgress
                                                        ? Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                  Icons
                                                                      .check_circle,
                                                                  color: Colors
                                                                      .white),
                                                              const SizedBox(
                                                                  width: 8),
                                                              const Text('done',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600)),
                                                            ],
                                                          )
                                                        : Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                  Icons
                                                                      .construction,
                                                                  color: Colors
                                                                      .white,
                                                                  size: 18),
                                                              const SizedBox(
                                                                  width: 8),
                                                              const Text(
                                                                  'in progress',
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600)),
                                                            ],
                                                          )),
                                              ),
                                              secondaryBackground: Container(
                                                color: (_today[i].inProgress &&
                                                        !_today[i].done)
                                                    ? Colors.transparent
                                                    : Colors.red,
                                                alignment:
                                                    Alignment.centerRight,
                                                // align delete icon where the star sits (far right)
                                                padding: const EdgeInsets.only(
                                                    right: 12),
                                                child: (_today[i].inProgress &&
                                                        !_today[i].done)
                                                    ? Text(
                                                        'open',
                                                        style: TextStyle(
                                                          decoration:
                                                              TextDecoration
                                                                  .lineThrough,
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurface,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      )
                                                    : const Icon(Icons.delete,
                                                        color: Colors.white),
                                              ),
                                              confirmDismiss:
                                                  (direction) async {
                                                final t = _today[i];
                                                if (direction ==
                                                    DismissDirection
                                                        .startToEnd) {
                                                  // In Backlog view: Right swipe -> move to Today
                                                  if (_currentFile ==
                                                          'simplepresent_backlog.json' ||
                                                      _showingBacklog) {
                                                    await _moveFromBacklog(i);
                                                    return false;
                                                  }
                                                  // Right swipe (Today view): 1st -> set inProgress, 2nd -> set done
                                                  if (!t.inProgress &&
                                                      !t.done) {
                                                    setState(() => _today[i] =
                                                        t.copyWith(
                                                            inProgress: true,
                                                            inProgressAt:
                                                                DateTime
                                                                    .now()));
                                                    _saveToday();
                                                    _showTopToast(
                                                        'task marked in progress');
                                                  } else if (t.inProgress &&
                                                      !t.done) {
                                                    _setDone(i, true);
                                                    _showTopToast(
                                                        'task marked done');
                                                  }
                                                  return false;
                                                }
                                                // Left swipe: if task is inProgress -> unset inProgress, do not delete
                                                if (t.inProgress && !t.done) {
                                                  setState(() => _today[i] =
                                                      t.copyWith(
                                                          inProgress: false,
                                                          inProgressAt: null));
                                                  _saveToday();
                                                  _showTopToast(
                                                      'task marked not in progress');
                                                  return false;
                                                }
                                                // Otherwise ask for delete confirmation
                                                final shouldDelete =
                                                    await showDialog<bool>(
                                                  context: context,
                                                  builder: (dialogContext) =>
                                                      AlertDialog(
                                                    title: const Text(
                                                        'delete task?'),
                                                    content: Text(
                                                        'delete "${_today[i].text}"?'),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                                    dialogContext)
                                                                .pop(false),
                                                        child: const Text(
                                                            'cancel'),
                                                      ),
                                                      FilledButton(
                                                        autofocus: true,
                                                        onPressed: () =>
                                                            Navigator.of(
                                                                    dialogContext)
                                                                .pop(true),
                                                        child: const Text(
                                                            'delete'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                return shouldDelete == true;
                                              },
                                              direction: _swipeEnabled
                                                  ? (!task.done
                                                      ? DismissDirection
                                                          .horizontal
                                                      : DismissDirection
                                                          .endToStart)
                                                  : DismissDirection.none,
                                              onDismissed: (_) =>
                                                  _removeFromToday(i),
                                              child: Column(
                                                children: [
                                                  Card(
                                                    color: task.inProgress
                                                        ? Colors.green
                                                            .withOpacity(0.10)
                                                        : null,
                                                    child: ListTile(
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                              vertical:
                                                                  ((_tileHeight -
                                                                              _baseFontSize) /
                                                                          2)
                                                                      .clamp(
                                                                          0.0,
                                                                          40.0),
                                                              horizontal: 12),
                                                      onTap: () =>
                                                          _toggleExpanded(i),
                                                      leading: IconButton(
                                                        tooltip: 'done',
                                                        icon: Icon(task.done
                                                            ? Icons
                                                                .radio_button_checked
                                                            : Icons
                                                                .radio_button_unchecked),
                                                        onPressed: () =>
                                                            _setDone(
                                                                i, !task.done),
                                                      ),
                                                      title: Row(
                                                        children: [
                                                          Expanded(
                                                            child: _expanded
                                                                    .contains(i)
                                                                ? const SizedBox
                                                                    .shrink()
                                                                : Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        task.text,
                                                                        style:
                                                                            _fontTextStyle(
                                                                          TextStyle(
                                                                            fontSize:
                                                                                _baseFontSize,
                                                                            fontWeight:
                                                                                FontWeight.normal,
                                                                            decoration: task.done
                                                                                ? TextDecoration.lineThrough
                                                                                : TextDecoration.none,
                                                                            color: task.done
                                                                                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
                                                                                : Theme.of(context).colorScheme.onSurface,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      if (totalSubtasks >
                                                                          0)
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              top: 2.0),
                                                                          child:
                                                                              Text(
                                                                            '$completedSubtasks/$totalSubtasks',
                                                                            style:
                                                                                TextStyle(
                                                                              fontSize: 12,
                                                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      if (task.done &&
                                                                          task.completedAt !=
                                                                              null)
                                                                        Padding(
                                                                          padding: const EdgeInsets
                                                                              .only(
                                                                              top: 4.0),
                                                                          child:
                                                                              Text(
                                                                            'completed: ${DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!)}',
                                                                            style:
                                                                                TextStyle(
                                                                              fontSize: 12,
                                                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      if (task
                                                                          .done)
                                                                        Builder(builder:
                                                                            (ctx) {
                                                                          // Sum manual "workMinutes" and stopwatch elapsed minutes,
                                                                          // rounding stopwatch up to 15-minute blocks.
                                                                          final secs = _elapsedSecondsFor(task);
                                                                          const blockSec = 15 * 60;
                                                                          final blocks = secs > 0 ? ((secs + blockSec - 1) ~/ blockSec) : 0;
                                                                          final accumulatedMinutes = blocks * 15;
                                                                          final manual = task.workMinutes ?? 0;
                                                                          final totalMinutes = manual + accumulatedMinutes;
                                                                          if (totalMinutes <= 0) return const SizedBox.shrink();
                                                                          final hours = totalMinutes ~/ 60;
                                                                          final mins = totalMinutes % 60;
                                                                          final label = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
                                                                          return Padding(
                                                                            padding: const EdgeInsets.only(top: 4.0),
                                                                            child: Text(
                                                                              'spent: $label',
                                                                              style: TextStyle(
                                                                                fontSize: 12,
                                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                              ),
                                                                            ),
                                                                          );
                                                                        }),
                                                                    ],
                                                                  ),
                                                          ),
                                                            const SizedBox(width: 2),
                                                          // Right aligned icons: scheduled+time, in-progress, save (when expanded), star (far right)
                                                          Opacity(
                                                            opacity: _swiping
                                                                    .contains(i)
                                                                ? 0.0
                                                                : 1.0,
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                if (task.scheduledAt !=
                                                                    null)
                                                                  Tooltip(
                                                                    message: DateFormat(
                                                                            'yyyy-MM-dd HH:mm')
                                                                        .format(
                                                                            task.scheduledAt!),
                                                                    child:
                                                                        InkWell(
                                                                      onTap: () =>
                                                                          _pickSchedule(
                                                                              i),
                                                                      child:
                                                                          Row(
                                                                        mainAxisSize:
                                                                            MainAxisSize.min,
                                                                        children: [
                                                                          Icon(
                                                                              Icons.event,
                                                                              color: _scheduleIconColor(task.scheduledAt!),
                                                                              size: 16),
                                                                          const SizedBox(
                                                                              width: 4),
                                                                          Text(
                                                                            DateFormat('HH:mm').format(task.scheduledAt!),
                                                                            style:
                                                                                TextStyle(fontSize: 11, color: _scheduleIconColor(task.scheduledAt!)),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                if (_currentFile ==
                                                                        'simplepresent_backlog.json' ||
                                                                    _showingBacklog)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(left: 4.0, right: 2.0),
                                                                    child: IconButton(
                                                                      padding: const EdgeInsets.all(4),
                                                                      constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                                                      tooltip: 'move to today',
                                                                      icon: const Icon(Icons.arrow_circle_left, size: 20),
                                                                      onPressed: () async {
                                                                        await _moveFromBacklog(i);
                                                                      },
                                                                    ),
                                                                  ),
                                                                if (!_showingBacklog &&
                                                                    !_showingDone)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(left: 2.0, right: 2.0),
                                                                    child: Tooltip(
                                                                      message: task.stopwatchRunning ? 'stopwatch running' : 'stopwatch',
                                                                      child: IconButton(
                                                                        padding: const EdgeInsets.all(4),
                                                                        constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                                                        iconSize: 18,
                                                                        onPressed: () async {
                                                                          if (task.stopwatchRunning) {
                                                                            await _stopStopwatch(i);
                                                                          } else {
                                                                            await _startStopwatch(i);
                                                                          }
                                                                        },
                                                                        icon: Icon(
                                                                          Icons.timer,
                                                                          color: task.stopwatchRunning ? Colors.redAccent : Theme.of(context).colorScheme.onSurfaceVariant,
                                                                          size: 18,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                Padding(
                                                                  padding: const EdgeInsets.only(left: 2.0, right: 2.0),
                                                                  child: IconButton(
                                                                    padding: const EdgeInsets.all(4),
                                                                    constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                                                    tooltip: task.inProgress && !task.done ? 'remove in progress' : 'mark in progress',
                                                                    icon: Icon(
                                                                      Icons.construction,
                                                                      color: (task.inProgress && !task.done) ? Colors.greenAccent.shade200 : Theme.of(context).colorScheme.onSurfaceVariant,
                                                                      size: 18,
                                                                    ),
                                                                    onPressed: () async {
                                                                      final task = _today[i];
                                                                      final wasInProgress = task.inProgress;
                                                                      final now = !wasInProgress ? DateTime.now() : null;

                                                                      // If the task is done and we're showing the Done list, move it back to Today as in-progress
                                                                      if (task.done && _currentFile == 'simplepresent_done.json') {
                                                                        try {
                                                                          final restored = task.copyWith(done: false, inProgress: true, inProgressAt: DateTime.now(), completedAt: null);
                                                                          setState(() {
                                                                            _today.removeAt(i);
                                                                            _expanded.clear();
                                                                          });
                                                                          await _saveToday(); // persist removal from done file

                                                                          final List<TaskItem> todayList = [];
                                                                          await _loadList(_storage('simplepresent_today.json'), todayList);
                                                                          todayList.insert(0, restored);
                                                                          await _saveList('simplepresent_today.json', todayList);

                                                                          _showTopToast('task moved to today (in progress)');
                                                                        } catch (_) {
                                                                          _showTopToast('failed to move task');
                                                                        }
                                                                        _registerActivity();
                                                                        return;
                                                                      }

                                                                      // Normal toggle for non-Done views (or done tasks in other views)
                                                                      setState(() {
                                                                        _today[i] = _today[i].copyWith(
                                                                          inProgress: !wasInProgress,
                                                                          inProgressAt: now,
                                                                          // ensure a task marked in-progress is not still marked done
                                                                          done: task.done && !wasInProgress ? false : task.done,
                                                                          completedAt: task.done && !wasInProgress ? null : task.completedAt,
                                                                        );

                                                                        if (wasInProgress && !_today[i].inProgress) {
                                                                          final moved = _today.removeAt(i);
                                                                          int insertAt = 0;
                                                                          final now2 = DateTime.now();
                                                                          for (final t in _today) {
                                                                            if (t.done) break;
                                                                            final hasSchedule = t.scheduledAt != null;
                                                                            final diff = hasSchedule ? t.scheduledAt!.difference(now2) : null;
                                                                            final isOverdue = hasSchedule && diff!.isNegative;
                                                                            if (isOverdue) {
                                                                              insertAt++;
                                                                              continue;
                                                                            }
                                                                            if (t.important && t.inProgress) {
                                                                              insertAt++;
                                                                              continue;
                                                                            }
                                                                            if (t.inProgress) {
                                                                              insertAt++;
                                                                              continue;
                                                                            }
                                                                            if (t.important) {
                                                                              insertAt++;
                                                                              continue;
                                                                            }
                                                                            break;
                                                                          }
                                                                          _today.insert(insertAt, moved);
                                                                        }
                                                                      });
                                                                      await _saveToday();
                                                                      _registerActivity();
                                                                    },
                                                                  ),
                                                                ),
                                                                if (_expanded
                                                                    .contains(
                                                                        i))
                                                                  Builder(
                                                                      builder:
                                                                          (_) {
                                                                    final titleCtrl =
                                                                        _editControllers[
                                                                            i];
                                                                    final notesCtrl =
                                                                        _notesControllers[
                                                                            i];
                                                                    final isDirty = (titleCtrl !=
                                                                                null &&
                                                                            titleCtrl.text.trim() !=
                                                                                task.text
                                                                                    .trim()) ||
                                                                        (notesCtrl !=
                                                                                null &&
                                                                            notesCtrl.text !=
                                                                                (task.notes ?? ''));
                                                                    return IconButton(
                                                                      tooltip:
                                                                          'Save',
                                                                      icon: Icon(
                                                                          Icons
                                                                              .check,
                                                                          color: isDirty
                                                                              ? Colors.red
                                                                              : Colors.white),
                                                                      onPressed:
                                                                          () =>
                                                                              _saveEditedTitle(i),
                                                                    );
                                                                  }),
                                                                IconButton(
                                                                  tooltip:
                                                                      'Important',
                                                                  icon: Icon(
                                                                      task.important
                                                                          ? Icons
                                                                              .star
                                                                          : Icons
                                                                              .star_border,
                                                                      color: task.important
                                                                          ? Colors
                                                                              .amber
                                                                          : Theme.of(context)
                                                                              .colorScheme
                                                                              .onSurfaceVariant),
                                                                  onPressed:
                                                                      () {
                                                                    final now = !_today[i]
                                                                            .important
                                                                        ? DateTime
                                                                            .now()
                                                                        : _today[i]
                                                                            .importantAt;
                                                                    setState(() => _today[
                                                                        i] = _today[
                                                                            i]
                                                                        .copyWith(
                                                                            important:
                                                                                !_today[i].important,
                                                                            importantAt: now));
                                                                    _saveToday();
                                                                  },
                                                                ),
                                                                // Custom D&D handle (reduced left padding)
                                                                Padding(
                                                                  padding: const EdgeInsets.only(left: 2.0),
                                                                  child: Opacity(
                                                                    opacity: _swiping.contains(i) ? 0.0 : 1.0,
                                                                    child: ReorderableDragStartListener(
                                                                      index: vi,
                                                                      child: const Icon(Icons.drag_handle, size: 18),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  if (_expanded.contains(i))
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 14.0,
                                                          vertical: 8.0),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          // Editable title in expanded area
                                                          TextField(
                                                            controller:
                                                                _editControllers
                                                                    .putIfAbsent(
                                                                        i, () {
                                                              final c =
                                                                  TextEditingController(
                                                                      text: task
                                                                          .text);
                                                              c.addListener(() {
                                                                if (mounted)
                                                                  setState(
                                                                      () {});
                                                              });
                                                              return c;
                                                            }),
                                                            autofocus: true,
                                                            decoration:
                                                                const InputDecoration(
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              hintText: 'title',
                                                            ),
                                                            onSubmitted: (_) =>
                                                                _saveEditedTitle(
                                                                    i),
                                                          ),
                                                          const SizedBox(
                                                              height: 8),
                                                          // Notes field (moved above timestamps)
                                                          TextField(
                                                            controller:
                                                                _notesControllers
                                                                    .putIfAbsent(
                                                                        i, () {
                                                              final n =
                                                                  TextEditingController(
                                                                      text: task
                                                                              .notes ??
                                                                          '');
                                                              n.addListener(() {
                                                                if (mounted)
                                                                  setState(
                                                                      () {});
                                                              });
                                                              return n;
                                                            }),
                                                            keyboardType:
                                                                TextInputType
                                                                    .multiline,
                                                            minLines: 3,
                                                            maxLines: null,
                                                            decoration:
                                                                const InputDecoration(
                                                              border:
                                                                  OutlineInputBorder(),
                                                              hintText: 'notes',
                                                            ),
                                                            onSubmitted: (_) =>
                                                                _saveEditedTitle(
                                                                    i),
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child:
                                                                    TextField(
                                                                  controller:
                                                                      _subtaskInputControllers
                                                                          .putIfAbsent(
                                                                    task.id,
                                                                    () =>
                                                                        TextEditingController(),
                                                                  ),
                                                                  focusNode: _subtaskFocusNodes
                                                                      .putIfAbsent(
                                                                          task
                                                                              .id,
                                                                          () =>
                                                                              FocusNode()),
                                                                  decoration:
                                                                      const InputDecoration(
                                                                    border:
                                                                        OutlineInputBorder(),
                                                                    hintText:
                                                                        'add subtask',
                                                                  ),
                                                                  onSubmitted: (_) =>
                                                                      _addSubtask(
                                                                          i,
                                                                          _subtaskInputControllers[
                                                                              task.id]!),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              FilledButton(
                                                                onPressed: () =>
                                                                    _addSubtask(
                                                                        i,
                                                                        _subtaskInputControllers[
                                                                            task.id]!),
                                                                child:
                                                                    const Text(
                                                                        '+'),
                                                              ),
                                                            ],
                                                          ),
                                                          if (task.subtasks
                                                              .isNotEmpty)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      top: 12),
                                                              child: SizedBox(
                                                                // let the ReorderableListView size to its children
                                                                child:
                                                                    ReorderableListView(
                                                                  buildDefaultDragHandles:
                                                                      false,
                                                                  shrinkWrap:
                                                                      true,
                                                                  physics:
                                                                      const NeverScrollableScrollPhysics(),
                                                                  onReorder: (oldIndex,
                                                                          newIndex) =>
                                                                      _reorderSubtasks(
                                                                          i,
                                                                          oldIndex,
                                                                          newIndex),
                                                                  children: [
                                                                    for (int sidx =
                                                                            0;
                                                                        sidx <
                                                                            task.subtasks.length;
                                                                        sidx++)
                                                                      () {
                                                                        final step =
                                                                            task.subtasks[sidx];
                                                                        return Card(
                                                                          key: ValueKey(
                                                                              'subtask_${task.id}_${step.id}'),
                                                                          child:
                                                                              ListTile(
                                                                            dense:
                                                                                true,
                                                                            leading:
                                                                                Checkbox(
                                                                              value: step.done,
                                                                              onChanged: (value) => _updateSubtask(i, step.id, done: value ?? false),
                                                                            ),
                                                                            title:
                                                                                TextFormField(
                                                                              initialValue: step.text,
                                                                              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                                                              onChanged: (value) => _updateSubtask(i, step.id, text: value),
                                                                            ),
                                                                            trailing:
                                                                                Row(
                                                                              mainAxisSize: MainAxisSize.min,
                                                                              children: [
                                                                                IconButton(
                                                                                  tooltip: 'delete step',
                                                                                  icon: const Icon(Icons.close),
                                                                                  onPressed: () => _removeSubtask(i, step.id),
                                                                                ),
                                                                                ReorderableDragStartListener(
                                                                                  index: sidx,
                                                                                  child: const Padding(
                                                                                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                                                                                    child: Icon(Icons.drag_handle),
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        );
                                                                      }(),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          const SizedBox(
                                                              height: 10),
                                                          // Stopwatch display and controls
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                    bottom:
                                                                        8.0),
                                                            child: Row(
                                                              children: [
                                                                Text(() {
                                                                  final s =
                                                                      _elapsedSecondsFor(
                                                                          task);
                                                                  final hh = (s ~/
                                                                          3600)
                                                                      .toString()
                                                                      .padLeft(
                                                                          2,
                                                                          '0');
                                                                  final mm = ((s %
                                                                              3600) ~/
                                                                          60)
                                                                      .toString()
                                                                      .padLeft(
                                                                          2,
                                                                          '0');
                                                                  final ss = (s %
                                                                          60)
                                                                      .toString()
                                                                      .padLeft(
                                                                          2,
                                                                          '0');
                                                                  return 'stopwatch: $hh:$mm:$ss';
                                                                }()),
                                                                const SizedBox(
                                                                    width: 8),
                                                                IconButton(
                                                                  tooltip:
                                                                      'start',
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .play_arrow),
                                                                  onPressed: task
                                                                          .stopwatchRunning
                                                                      ? null
                                                                      : () =>
                                                                          _startStopwatch(
                                                                              i),
                                                                ),
                                                                IconButton(
                                                                  tooltip:
                                                                      'stop',
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .stop),
                                                                  onPressed: task
                                                                          .stopwatchRunning
                                                                      ? () =>
                                                                          _stopStopwatch(
                                                                              i)
                                                                      : null,
                                                                ),
                                                                IconButton(
                                                                  tooltip:
                                                                      'reset',
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .restart_alt),
                                                                  onPressed: (task.stopwatchAccumulatedSeconds >
                                                                              0 ||
                                                                          task
                                                                              .stopwatchRunning)
                                                                      ? () =>
                                                                          _resetStopwatch(
                                                                              i)
                                                                      : null,
                                                                ),
                                                                const SizedBox(
                                                                    width: 12),
                                                                // Manual time entry (time spent) shown to the right of the stopwatch buttons
                                                                Flexible(
                                                                  child:
                                                                      ConstrainedBox(
                                                                    constraints:
                                                                        const BoxConstraints(
                                                                            maxWidth:
                                                                                220),
                                                                    child:
                                                                        TextField(
                                                                      controller:
                                                                          _workControllers.putIfAbsent(
                                                                              task.id,
                                                                              () {
                                                                        final initial = task.workMinutes >
                                                                                0
                                                                            ? task.workMinutes.toString()
                                                                            : '';
                                                                        final c =
                                                                            TextEditingController(text: initial);
                                                                        c.addListener(
                                                                            () {
                                                                          if (mounted)
                                                                            setState(() {});
                                                                        });
                                                                        return c;
                                                                      }),
                                                                      keyboardType:
                                                                          TextInputType
                                                                              .number,
                                                                      decoration: const InputDecoration(
                                                                          border:
                                                                              OutlineInputBorder(),
                                                                          hintText:
                                                                              'time spent'),
                                                                      onTap:
                                                                          () {
                                                                        // Manual entry only: do not auto-suggest stopwatch time here.
                                                                      },
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),

                                                          Text(
                                                              'created: ${task.createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.createdAt!) : '-'}'),
                                                          const SizedBox(
                                                              height: 6),
                                                          Text(
                                                              'in progress: ${task.inProgressAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.inProgressAt!) : '-'}'),
                                                          const SizedBox(
                                                              height: 6),
                                                          if (task.done &&
                                                              task.completedAt !=
                                                                  null)
                                                            Text(
                                                                'completed: ${DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!)}'),
                                                          const SizedBox(
                                                              height: 6),
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  "scheduled: ${task.scheduledAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.scheduledAt!) : '-'}",
                                                                ),
                                                              ),
                                                              IconButton(
                                                                tooltip:
                                                                    'set schedule',
                                                                icon: const Icon(
                                                                    Icons
                                                                        .calendar_today),
                                                                onPressed: () =>
                                                                    _pickSchedule(
                                                                        i),
                                                              ),
                                                              if (task.scheduledAt !=
                                                                  null)
                                                                IconButton(
                                                                  tooltip:
                                                                      'clear schedule',
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .clear),
                                                                  onPressed: () =>
                                                                      _clearSchedule(
                                                                          i),
                                                                ),
                                                              if (!_showingBacklog &&
                                                                  !_showingDone &&
                                                                  !task.done)
                                                                IconButton(
                                                                  tooltip:
                                                                      'move to backlog',
                                                                  icon: const Icon(
                                                                      Icons
                                                                          .arrow_circle_right),
                                                                  onPressed:
                                                                      () async {
                                                                    await _moveToBacklog(
                                                                        i);
                                                                  },
                                                                ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }),
                                        );
                                      }),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _minimalViewMode
                            ? const SizedBox.shrink(
                                key: ValueKey('composer_hidden'))
                            : SafeArea(
                                key: const ValueKey('composer_visible'),
                                top: false,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _controller,
                                          focusNode: _inputFocus,
                                          autofocus: !_showingDone,
                                          enabled: !_showingDone,
                                          textInputAction: TextInputAction.done,
                                          decoration: InputDecoration(
                                            hintText: _showingDone
                                                ? null
                                                : (_showingBacklog
                                                    ? 'new task for later'
                                                    : 'new task for today'),
                                            border: const OutlineInputBorder(),
                                          ),
                                          onSubmitted:
                                              _showingDone ? null : _addToToday,
                                          onTapOutside: (_) =>
                                              _inputFocus.requestFocus(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        onPressed: _showingDone
                                            ? null
                                            : () => _addToToday(_controller.text),
                                        child: const Icon(Icons.add),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
                  if (Platform.isWindows)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => ScaleTransition(
                          scale: animation,
                          child: FadeTransition(opacity: animation, child: child),
                        ),
                        child: Tooltip(
                          key: ValueKey<bool>(_alwaysOnTop),
                          message: _alwaysOnTop
                              ? 'Unpin window'
                              : 'Pin window on top',
                          child: Material(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () async {
                                final newVal = !_alwaysOnTop;
                                try {
                                  await _nativeWindowChannel
                                      .invokeMethod(
                                          'setWindowGeometry',
                                          <String, dynamic>{
                                        'always_on_top': newVal
                                      });
                                  setState(() =>
                                      _alwaysOnTop = newVal);
                                  await _saveSettings();
                                  _showTopToast(newVal
                                      ? 'Window pinned'
                                      : 'Window unpinned');
                                } catch (_) {}
                              },
                              child: SizedBox(
                                width: 28,
                                height: 28,
                                child: Icon(
                                  _alwaysOnTop
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 2,
                    right: Platform.isWindows ? 34 : 2,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Tooltip(
                        key: ValueKey<bool>(_minimalViewMode),
                        message: _minimalViewMode
                            ? 'minimal mode off'
                            : 'minimal mode on',
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _toggleMinimalViewMode,
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: Icon(
                                _minimalViewMode
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.doneList});
  final List<TaskItem> doneList;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initial});

  final Map<String, dynamic> initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late int idleMinutes;
  late int attentionMinutes;
  late int reminderMinutes;
  late int urgentMinutes;
  late bool idleSoundEnabled;
  late bool idleFlashEnabled;
  late bool idleNotifyEnabled;
  late bool idleBringToFrontEnabled;
  late bool attentionSoundEnabled;
  late bool attentionFlashEnabled;
  late bool attentionNotifyEnabled;
  late bool attentionBringToFrontEnabled;
  late bool reminderSoundEnabled;
  late bool reminderNotifyEnabled;
  late bool reminderFlashEnabled;
  late bool reminderBringToFrontEnabled;
  late bool urgentSoundEnabled;
  late bool urgentNotifyEnabled;
  late bool urgentFlashEnabled;
  late bool urgentBringToFrontEnabled;
  late bool swipeEnabled;
  late bool magnetEnabled;
  late bool scheduledReminderSoundEnabled;
  late double textScaleFactor;
  late String fontFamily;
  late String cloudServerUrl;
  late String cloudAccountId;
  late String cloudDeviceId;
  late String cloudToken;
  late String cloudWordPhrase;
  late String cloudDeviceName;
  late String cloudPIN;
  String _cloudStatus = '';
  String _serverVersion = '';
  String _versionWarning = '';
  bool _cloudBusy = false;
  late int _initialIdleMinutes;
  late int _initialAttentionMinutes;
  late int _initialReminderMinutes;
  late int _initialUrgentMinutes;
  late bool _initialIdleSoundEnabled;
  late bool _initialIdleFlashEnabled;
  late bool _initialIdleNotifyEnabled;
  late bool _initialIdleBringToFrontEnabled;
  late bool _initialAttentionSoundEnabled;
  late bool _initialAttentionFlashEnabled;
  late bool _initialAttentionNotifyEnabled;
  late bool _initialAttentionBringToFrontEnabled;
  late bool _initialReminderSoundEnabled;
  late bool _initialReminderNotifyEnabled;
  late bool _initialReminderFlashEnabled;
  late bool _initialReminderBringToFrontEnabled;
  late bool _initialUrgentSoundEnabled;
  late bool _initialUrgentNotifyEnabled;
  late bool _initialUrgentFlashEnabled;
  late bool _initialUrgentBringToFrontEnabled;
  late bool _initialSwipeEnabled;
  late bool _initialMagnetEnabled;
  late bool _initialScheduledReminderSoundEnabled;
  late double _initialTextScaleFactor;
  late String _initialFontFamily;
  late String _initialCloudServerUrl;
  late String _initialCloudAccountId;
  late String _initialCloudDeviceId;
  late String _initialCloudToken;
  late String _initialCloudWordPhrase;
  late String _initialCloudDeviceName;
  late String _initialCloudPIN;

  @override
  void initState() {
    super.initState();
    int readInt(String key, int fallback) {
      final v = widget.initial[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    bool readBool(String key, bool fallback) {
      final v = widget.initial[key];
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = (v?.toString() ?? '').toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
      return fallback;
    }

    String readString(String key, String fallback) {
      final v = widget.initial[key];
      if (v is String && v.isNotEmpty) return v;
      return fallback;
    }

    double readDouble(String key, double fallback) {
      final v = widget.initial[key];
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? fallback;
    }

    idleMinutes = readInt('idleMinutes', 45).clamp(1, 720);
    attentionMinutes = readInt('attentionMinutes', 60).clamp(1, 720);
    reminderMinutes = readInt('reminderMinutes', 75).clamp(1, 720);
    urgentMinutes = readInt('urgentMinutes', 90).clamp(1, 720);
    idleSoundEnabled = readBool('idleSoundEnabled', true);
    idleFlashEnabled = readBool('idleFlashEnabled', false);
    idleNotifyEnabled = readBool('idleNotifyEnabled', false);
    idleBringToFrontEnabled = readBool('idleBringToFrontEnabled', false);
    attentionSoundEnabled = readBool('attentionSoundEnabled', true);
    attentionFlashEnabled = readBool('attentionFlashEnabled', true);
    attentionNotifyEnabled = readBool('attentionNotifyEnabled', false);
    attentionBringToFrontEnabled =
        readBool('attentionBringToFrontEnabled', false);
    reminderSoundEnabled = readBool('reminderSoundEnabled', true);
    reminderNotifyEnabled = readBool('reminderNotifyEnabled', true);
    reminderFlashEnabled = readBool('reminderFlashEnabled', false);
    reminderBringToFrontEnabled =
        readBool('reminderBringToFrontEnabled', false);
    urgentSoundEnabled = readBool('urgentSoundEnabled', true);
    urgentNotifyEnabled = readBool('urgentNotifyEnabled', true);
    urgentBringToFrontEnabled = readBool('urgentBringToFrontEnabled', true);
    urgentFlashEnabled = readBool('urgentFlashEnabled', false);
    swipeEnabled = readBool('swipeEnabled', true);
    magnetEnabled = readBool('magnetEnabled', false);
    scheduledReminderSoundEnabled = readBool('scheduledReminderSoundEnabled', true);
    textScaleFactor = readDouble('uiTextScaleFactor', 1.0).clamp(0.5, 1.6);
    fontFamily = readString('fontFamily', 'OpenDyslexic');
    cloudServerUrl = readString('cloudServerUrl', '');
    cloudAccountId = readString('cloudAccountId', '');
    cloudDeviceId = readString('cloudDeviceId', '');
    cloudToken = readString('cloudToken', '');
    cloudWordPhrase = readString('cloudWordPhrase', '');
    cloudDeviceName = readString('cloudDeviceName', Platform.localHostname);
    cloudPIN = readString('cloudPIN', '');
    // Save initial values to detect changes
    _initialIdleMinutes = idleMinutes;
    _initialAttentionMinutes = attentionMinutes;
    _initialReminderMinutes = reminderMinutes;
    _initialUrgentMinutes = urgentMinutes;
    _initialIdleSoundEnabled = idleSoundEnabled;
    _initialIdleFlashEnabled = idleFlashEnabled;
    _initialIdleNotifyEnabled = idleNotifyEnabled;
    _initialIdleBringToFrontEnabled = idleBringToFrontEnabled;
    _initialAttentionSoundEnabled = attentionSoundEnabled;
    _initialAttentionFlashEnabled = attentionFlashEnabled;
    _initialAttentionNotifyEnabled = attentionNotifyEnabled;
    _initialAttentionBringToFrontEnabled = attentionBringToFrontEnabled;
    _initialReminderSoundEnabled = reminderSoundEnabled;
    _initialReminderNotifyEnabled = reminderNotifyEnabled;
    _initialReminderFlashEnabled = reminderFlashEnabled;
    _initialReminderBringToFrontEnabled = reminderBringToFrontEnabled;
    _initialUrgentSoundEnabled = urgentSoundEnabled;
    _initialUrgentNotifyEnabled = urgentNotifyEnabled;
    _initialUrgentFlashEnabled = urgentFlashEnabled;
    _initialUrgentBringToFrontEnabled = urgentBringToFrontEnabled;
    _initialSwipeEnabled = swipeEnabled;
    _initialMagnetEnabled = magnetEnabled;
    _initialScheduledReminderSoundEnabled = scheduledReminderSoundEnabled;
    _initialTextScaleFactor = textScaleFactor;
    _initialFontFamily = fontFamily;
    _initialCloudServerUrl = cloudServerUrl;
    _initialCloudAccountId = cloudAccountId;
    _initialCloudDeviceId = cloudDeviceId;
    _initialCloudToken = cloudToken;
    _initialCloudWordPhrase = cloudWordPhrase;
    _initialCloudDeviceName = cloudDeviceName;
    _initialCloudPIN = cloudPIN;
    _fetchServerVersionInSettings();
  }

  Future<void> _fetchServerVersionInSettings() async {
    if (cloudServerUrl.trim().isEmpty) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: cloudServerUrl.trim(),
      );
      final version = await client.getHealth();
      if (version != null && mounted) {
        setState(() {
          _serverVersion = version;
          _versionWarning = _isClientOlderThanServer(kClientVersion, version)
              ? 'Warnung: Client ist älter als Server. Bitte Client aktualisieren.'
              : '';
        });
      }
    } catch (_) {
      // Ignore version fetch errors
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges()) {
      return true;
    }
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Änderungen nicht gespeichert'),
        content: const Text('Es gibt ungespeicherte Einstellungen. Wirklich verlassen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }

  bool _hasChanges() {
    return idleMinutes != _initialIdleMinutes ||
        attentionMinutes != _initialAttentionMinutes ||
        reminderMinutes != _initialReminderMinutes ||
        urgentMinutes != _initialUrgentMinutes ||
        idleSoundEnabled != _initialIdleSoundEnabled ||
        idleFlashEnabled != _initialIdleFlashEnabled ||
        idleNotifyEnabled != _initialIdleNotifyEnabled ||
        idleBringToFrontEnabled != _initialIdleBringToFrontEnabled ||
        attentionSoundEnabled != _initialAttentionSoundEnabled ||
        attentionFlashEnabled != _initialAttentionFlashEnabled ||
        attentionNotifyEnabled != _initialAttentionNotifyEnabled ||
        attentionBringToFrontEnabled != _initialAttentionBringToFrontEnabled ||
        reminderSoundEnabled != _initialReminderSoundEnabled ||
        reminderNotifyEnabled != _initialReminderNotifyEnabled ||
        reminderFlashEnabled != _initialReminderFlashEnabled ||
        reminderBringToFrontEnabled != _initialReminderBringToFrontEnabled ||
        urgentSoundEnabled != _initialUrgentSoundEnabled ||
        scheduledReminderSoundEnabled != _initialScheduledReminderSoundEnabled ||
        urgentFlashEnabled != _initialUrgentFlashEnabled ||
        urgentNotifyEnabled != _initialUrgentNotifyEnabled ||
        urgentBringToFrontEnabled != _initialUrgentBringToFrontEnabled ||
        swipeEnabled != _initialSwipeEnabled ||
        magnetEnabled != _initialMagnetEnabled ||
        textScaleFactor != _initialTextScaleFactor ||
        fontFamily != _initialFontFamily ||
        cloudServerUrl != _initialCloudServerUrl ||
        cloudAccountId != _initialCloudAccountId ||
        cloudDeviceId != _initialCloudDeviceId ||
        cloudToken != _initialCloudToken ||
        cloudWordPhrase != _initialCloudWordPhrase ||
        cloudDeviceName != _initialCloudDeviceName ||
        cloudPIN != _initialCloudPIN;
  }

  String _normalizedServerUrl() {
    final trimmed = cloudServerUrl.trim();
    if (trimmed.isEmpty) {
      throw Exception('Server URL fehlt.');
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  Future<void> _suggestPhrase() async {
    setState(() {
      cloudWordPhrase = CloudSyncClient.suggestWordPhrase();
      _cloudStatus = 'Neue 9-Wort-Phrase vorgeschlagen.';
    });
  }

  /// Shows a dialog with a QR code that encodes the pairing URI.
  /// Other devices can scan this to get server URL + account ID pre-filled.
  void _showPairingQr() {
    if (cloudServerUrl.isEmpty || cloudAccountId.isEmpty) {
      setState(() => _cloudStatus =
          'Bitte zuerst Gerät registrieren (Server-URL + Account ID werden benötigt).');
      return;
    }
    final uri = Uri(
      scheme: 'simplepresent',
      host: 'pair',
      queryParameters: {
        'server': cloudServerUrl,
        'account': cloudAccountId,
        'phrase': cloudWordPhrase,
      },
    ).toString();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Weiteres Gerät anbinden',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Scanne diesen QR-Code auf dem neuen Gerät, um Server-URL und Account ID zu übertragen. '
                    'Die 9-Wort-Phrase wird ebenfalls übertragen.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: QrImageView(
                        data: uri,
                        version: QrVersions.auto,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    uri,
                    style: const TextStyle(fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: uri));
                          if (!mounted) return;
                          setState(() {
                            _cloudStatus =
                                'Pairing-Link in Zwischenablage kopiert.';
                          });
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Link kopieren'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Schließen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the camera scanner, reads a simplepresent:// pairing URI
  /// and pre-fills server URL + account ID.
  void _applyPairingUri(String raw, {required String sourceLabel}) {
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme != 'simplepresent' || uri.host != 'pair') {
        setState(() => _cloudStatus = 'Ungültiger Pairing-Link ($sourceLabel).');
        return;
      }
      final server = uri.queryParameters['server'] ?? '';
      final account = uri.queryParameters['account'] ?? '';
      final phrase = uri.queryParameters['phrase'] ?? '';
      if (server.isEmpty || account.isEmpty || phrase.isEmpty) {
        setState(() => _cloudStatus = 'Pairing-Link unvollständig ($sourceLabel).');
        return;
      }
      setState(() {
        cloudServerUrl = server;
        cloudAccountId = account;
        cloudWordPhrase = phrase;
        _cloudStatus =
            'Server-URL, Account ID und 9-Wort-Phrase übernommen ($sourceLabel). Jetzt "Gerät anbinden" tippen.';
      });
    } catch (_) {
      setState(() => _cloudStatus = 'Pairing-Link konnte nicht gelesen werden ($sourceLabel).');
    }
  }

  Future<void> _scanPairingQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const _QrScannerPage(),
      ),
    );
    if (result == null || !mounted) return;
    _applyPairingUri(result, sourceLabel: 'QR-Code');
  }

  Future<void> _pastePairingLink() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _cloudStatus = 'Zwischenablage ist leer.');
      return;
    }
    _applyPairingUri(text, sourceLabel: 'Zwischenablage');
  }

  Future<void> _registerFirstDevice() async {
    try {
      setState(() {
        _cloudBusy = true;
        _cloudStatus = '';
      });
      if (cloudPIN.isEmpty || cloudPIN.length < 4) {
        setState(() {
          _cloudStatus = 'PIN muss mindestens 4 Zeichen lang sein.';
          _cloudBusy = false;
        });
        return;
      }
      final client = CloudSyncClient(serverBaseUrl: _normalizedServerUrl());
      final result = await client.registerFirstClient(
        deviceName: cloudDeviceName.trim().isEmpty
            ? Platform.localHostname
            : cloudDeviceName.trim(),
        phrase: cloudWordPhrase,
        pin: cloudPIN,
      );
      setState(() {
        cloudAccountId = result.accountId;
        cloudDeviceId = result.deviceId;
        cloudToken = result.token;
        _cloudStatus = 'Erstgerät registriert.';
      });
    } catch (e) {
      setState(() {
        _cloudStatus = 'Register fehlgeschlagen: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cloudBusy = false;
        });
      }
    }
  }

  Future<void> _pairDevice() async {
    try {
      setState(() {
        _cloudBusy = true;
        _cloudStatus = '';
      });
      if (cloudPIN.isEmpty) {
        setState(() {
          _cloudStatus = 'PIN erforderlich zum Pairing.';
          _cloudBusy = false;
        });
        return;
      }
      final client = CloudSyncClient(serverBaseUrl: _normalizedServerUrl());
      final result = await client.pairClient(
        accountId: cloudAccountId.trim(),
        deviceName: cloudDeviceName.trim().isEmpty
            ? Platform.localHostname
            : cloudDeviceName.trim(),
        phrase: cloudWordPhrase,
        pin: cloudPIN,
      );
      setState(() {
        cloudDeviceId = result.deviceId;
        cloudToken = result.token;
        _cloudStatus = 'Gerät erfolgreich angebunden.';
      });
    } catch (e) {
      setState(() {
        _cloudStatus = 'Pairing fehlgeschlagen: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cloudBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    int safe(int v) => v.clamp(1, 720);
    final hasChanges = _hasChanges();
    final baseTheme = Theme.of(context);

    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScaleFactor)),
      child: Theme(
        data: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: fontFamily),
          primaryTextTheme:
              baseTheme.primaryTextTheme.apply(fontFamily: fontFamily),
        ),
        child: PopScope(
          canPop: !_hasChanges(),
          onPopInvoked: (didPop) async {
            if (didPop) return;
            final shouldLeave = await _onWillPop();
            if (shouldLeave && mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
          appBar: AppBar(
            title: const Text('settings'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(<String, dynamic>{
                    'idleMinutes': safe(idleMinutes),
                    'attentionMinutes': safe(attentionMinutes),
                    'reminderMinutes': safe(reminderMinutes),
                    'urgentMinutes': safe(urgentMinutes),
                    'idleSoundEnabled': idleSoundEnabled,
                    'idleFlashEnabled': idleFlashEnabled,
                    'idleNotifyEnabled': idleNotifyEnabled,
                    'idleBringToFrontEnabled': idleBringToFrontEnabled,
                    'attentionSoundEnabled': attentionSoundEnabled,
                    'attentionFlashEnabled': attentionFlashEnabled,
                    'attentionNotifyEnabled': attentionNotifyEnabled,
                    'attentionBringToFrontEnabled':
                        attentionBringToFrontEnabled,
                    'reminderSoundEnabled': reminderSoundEnabled,
                    'reminderNotifyEnabled': reminderNotifyEnabled,
                    'reminderFlashEnabled': reminderFlashEnabled,
                    'reminderBringToFrontEnabled': reminderBringToFrontEnabled,
                    'urgentSoundEnabled': urgentSoundEnabled,
                    'urgentFlashEnabled': urgentFlashEnabled,
                    'urgentNotifyEnabled': urgentNotifyEnabled,
                    'urgentBringToFrontEnabled': urgentBringToFrontEnabled,
                    'swipeEnabled': swipeEnabled,
                                'magnetEnabled': magnetEnabled,
                                'scheduledReminderSoundEnabled': scheduledReminderSoundEnabled,
                    'uiTextScaleFactor': textScaleFactor,
                    'fontFamily': fontFamily,
                    'cloudServerUrl': cloudServerUrl,
                    'cloudAccountId': cloudAccountId,
                    'cloudDeviceId': cloudDeviceId,
                    'cloudToken': cloudToken,
                    'cloudWordPhrase': cloudWordPhrase,
                    'cloudDeviceName': cloudDeviceName,
                    'cloudPIN': cloudPIN,
                  });
                },
                child: Text(
                  'save',
                  style: TextStyle(
                    color: hasChanges ? Colors.red : null,
                    fontWeight:
                        hasChanges ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('font',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('font:'),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: fontFamily,
                    items: const [
                      DropdownMenuItem(
                          value: 'OpenDyslexic', child: Text('OpenDyslexic')),
                      DropdownMenuItem(
                          value: 'OpenSans', child: Text('OpenSans')),
                      DropdownMenuItem(
                          value: 'NotoSans', child: Text('NotoSans')),
                      DropdownMenuItem(
                          value: 'CourierPrime', child: Text('CourierPrime')),
                      DropdownMenuItem(value: 'Ubuntu', child: Text('Ubuntu')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => fontFamily = value);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'font size: ${(textScaleFactor * 100).round()}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Slider(
                value: textScaleFactor,
                min: 0.5,
                max: 1.6,
                divisions: 22,
                label: '${(textScaleFactor * 100).round()}%',
                onChanged: (value) {
                  setState(() => textScaleFactor = value);
                },
              ),
              const Text('range: 50% to 160%'),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              const Text('inactivity reminders',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _ReminderStageCard(
                title: '45 min',
                minutes: idleMinutes,
                onMinutesChanged: (v) => setState(() => idleMinutes = safe(v)),
                soundEnabled: idleSoundEnabled,
                onSoundChanged: (v) => setState(() => idleSoundEnabled = v),
                flashEnabled: idleFlashEnabled,
                onFlashChanged: (v) => setState(() => idleFlashEnabled = v),
                notifyEnabled: idleNotifyEnabled,
                onNotifyChanged: (v) => setState(() => idleNotifyEnabled = v),
                bringToFrontEnabled: idleBringToFrontEnabled,
                onBringToFrontChanged: (v) =>
                    setState(() => idleBringToFrontEnabled = v),
              ),
              _ReminderStageCard(
                title: '60 min',
                minutes: attentionMinutes,
                onMinutesChanged: (v) =>
                    setState(() => attentionMinutes = safe(v)),
                soundEnabled: attentionSoundEnabled,
                onSoundChanged: (v) =>
                    setState(() => attentionSoundEnabled = v),
                flashEnabled: attentionFlashEnabled,
                onFlashChanged: (v) =>
                    setState(() => attentionFlashEnabled = v),
                notifyEnabled: attentionNotifyEnabled,
                onNotifyChanged: (v) =>
                    setState(() => attentionNotifyEnabled = v),
                bringToFrontEnabled: attentionBringToFrontEnabled,
                onBringToFrontChanged: (v) =>
                    setState(() => attentionBringToFrontEnabled = v),
              ),
              _ReminderStageCard(
                title: '75 min',
                minutes: reminderMinutes,
                onMinutesChanged: (v) =>
                    setState(() => reminderMinutes = safe(v)),
                soundEnabled: reminderSoundEnabled,
                onSoundChanged: (v) => setState(() => reminderSoundEnabled = v),
                flashEnabled: reminderFlashEnabled,
                onFlashChanged: (v) => setState(() => reminderFlashEnabled = v),
                notifyEnabled: reminderNotifyEnabled,
                onNotifyChanged: (v) =>
                    setState(() => reminderNotifyEnabled = v),
                bringToFrontEnabled: reminderBringToFrontEnabled,
                onBringToFrontChanged: (v) =>
                    setState(() => reminderBringToFrontEnabled = v),
              ),
              _ReminderStageCard(
                title: '90 min',
                minutes: urgentMinutes,
                onMinutesChanged: (v) =>
                    setState(() => urgentMinutes = safe(v)),
                soundEnabled: urgentSoundEnabled,
                onSoundChanged: (v) => setState(() => urgentSoundEnabled = v),
                flashEnabled: urgentFlashEnabled,
                onFlashChanged: (v) => setState(() => urgentFlashEnabled = v),
                notifyEnabled: urgentNotifyEnabled,
                onNotifyChanged: (v) => setState(() => urgentNotifyEnabled = v),
                bringToFrontEnabled: urgentBringToFrontEnabled,
                onBringToFrontChanged: (v) =>
                    setState(() => urgentBringToFrontEnabled = v),
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              SwitchListTile(
                value: swipeEnabled,
                title: const Text('swipe actions enabled'),
                subtitle: const Text(
                    'if disabled, swipe gestures on task rows are turned off.'),
                onChanged: (v) => setState(() => swipeEnabled = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: magnetEnabled,
                title: const Text('snap window to screen edges'),
                subtitle: const Text(
                    'when enabled, window will snap when within ~37px of an edge'),
                onChanged: (v) => setState(() => magnetEnabled = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: scheduledReminderSoundEnabled,
                title: const Text('play sound for scheduled reminders'),
                subtitle: const Text(
                    'play a sound for scheduled task reminders (15min and due)'),
                onChanged: (v) => setState(() => scheduledReminderSoundEnabled = v),
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'cloud sync (server)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: cloudServerUrl)
                  ..selection = TextSelection.collapsed(
                      offset: cloudServerUrl.length),
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://<simplepresent-cloud-server>',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => cloudServerUrl = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: cloudDeviceName)
                  ..selection = TextSelection.collapsed(
                      offset: cloudDeviceName.length),
                decoration: const InputDecoration(
                  labelText: 'Gerätename',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => cloudDeviceName = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: cloudPIN)
                  ..selection = TextSelection.collapsed(
                      offset: cloudPIN.length),
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'PIN (4-32 Zeichen)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => cloudPIN = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: cloudAccountId)
                  ..selection = TextSelection.collapsed(
                      offset: cloudAccountId.length),
                decoration: const InputDecoration(
                  labelText: 'Account ID',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => cloudAccountId = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: cloudWordPhrase)
                  ..selection = TextSelection.collapsed(
                      offset: cloudWordPhrase.length),
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '9-Wort-Phrase (lokal)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => cloudWordPhrase = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cloudBusy ? null : _suggestPhrase,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('9 Wörter vorschlagen'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cloudBusy ? null : _registerFirstDevice,
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Erstgerät registrieren'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cloudBusy ? null : _pairDevice,
                      icon: const Icon(Icons.link),
                      label: const Text('Gerät anbinden'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // QR-Code buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cloudBusy ? null : _showPairingQr,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('QR-Code anzeigen'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cloudBusy ? null : _scanPairingQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('QR-Code scannen'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cloudBusy ? null : _pastePairingLink,
                      icon: const Icon(Icons.content_paste),
                      label: const Text('Link einfügen'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                'Device ID: $cloudDeviceId\nToken: ${cloudToken.isEmpty ? '-' : cloudToken}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              SelectableText(
                'Client: $kClientVersion${_serverVersion.isNotEmpty ? ' | Server: $_serverVersion' : ' | Server: -'}',
                style: TextStyle(
                  fontSize: 11,
                  color: _versionWarning.isEmpty ? Colors.grey : Colors.orangeAccent,
                ),
              ),
              if (_versionWarning.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _versionWarning,
                  style: const TextStyle(fontSize: 11, color: Colors.orangeAccent),
                ),
              ],
              if (_cloudStatus.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _cloudStatus,
                  style: TextStyle(
                    color: _cloudStatus.contains('fehlgeschlagen')
                        ? Colors.redAccent
                        : Colors.greenAccent,
                  ),
                ),
              ],
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _ReminderStageCard extends StatelessWidget {
  const _ReminderStageCard({
    required this.title,
    required this.minutes,
    required this.onMinutesChanged,
    required this.soundEnabled,
    required this.onSoundChanged,
    required this.flashEnabled,
    required this.onFlashChanged,
    required this.notifyEnabled,
    required this.onNotifyChanged,
    required this.bringToFrontEnabled,
    required this.onBringToFrontChanged,
  });

  final String title;
  final int minutes;
  final ValueChanged<int> onMinutesChanged;
  final bool soundEnabled;
  final ValueChanged<bool> onSoundChanged;
  final bool flashEnabled;
  final ValueChanged<bool> onFlashChanged;
  final bool notifyEnabled;
  final ValueChanged<bool> onNotifyChanged;
  final bool bringToFrontEnabled;
  final ValueChanged<bool> onBringToFrontChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
                children: [
                const Text('minutes:'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextFormField(
                    initialValue: minutes.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    onChanged: (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null)
                        onMinutesChanged(parsed.clamp(1, 720));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                FilterChip(
                  label: const Text('sound'),
                  selected: soundEnabled,
                  onSelected: onSoundChanged,
                ),
                FilterChip(
                  label: const Text('flash'),
                  selected: flashEnabled,
                  onSelected: onFlashChanged,
                ),
                FilterChip(
                  label: const Text('notification'),
                  selected: notifyEnabled,
                  onSelected: onNotifyChanged,
                ),
                FilterChip(
                  label: const Text('bring to front'),
                  selected: bringToFrontEnabled,
                  onSelected: onBringToFrontChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsPageState extends State<StatsPage> {
  late DateTime _currentDate;

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime.now();
  }

  void _prevDay() {
    setState(() {
      _currentDate = _currentDate.subtract(const Duration(days: 1));
    });
  }

  void _nextDay() {
    setState(() {
      _currentDate = _currentDate.add(const Duration(days: 1));
    });
  }

  List<TaskItem> _tasksForDay(DateTime day) {
    return widget.doneList.where((t) {
      final c = t.completedAt;
      if (c == null) return false;
      return c.year == day.year && c.month == day.month && c.day == day.day;
    }).toList();
  }

  int _elapsedSecondsFor(TaskItem t) {
    var acc = t.stopwatchAccumulatedSeconds;
    if (t.stopwatchRunning && t.stopwatchStartedAt != null) {
      acc += DateTime.now().difference(t.stopwatchStartedAt!).inSeconds;
    }
    return acc;
  }

  int _minutesForTask(TaskItem t) {
    final secs = _elapsedSecondsFor(t);
    const blockSec = 15 * 60;
    final blocks = secs > 0 ? ((secs + blockSec - 1) ~/ blockSec) : 0;
    final stopwatchMinutes = blocks * 15;
    final manual = t.workMinutes ?? 0;
    return manual + stopwatchMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasksForDay(_currentDate);
    final totalMinutes = tasks.fold<int>(0, (s, t) => s + _minutesForTask(t));
    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEEE, dd.MM.yyyy').format(_currentDate)),
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
              icon: const Icon(Icons.arrow_left),
              tooltip: 'Previous day',
              onPressed: _prevDay),
          IconButton(
              icon: const Icon(Icons.arrow_right),
              tooltip: 'Next day',
              onPressed: _nextDay),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total completed: ${tasks.length}',
              style: TextStyle(
                fontSize: 16 * MediaQuery.textScaleFactorOf(context),
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Total time (minutes): $totalMinutes',
              style: TextStyle(fontSize: 16 * MediaQuery.textScaleFactorOf(context))),
            const SizedBox(height: 12),
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(_currentDate.day == DateTime.now().day
                          ? 'No tasks completed today'
                          : 'No tasks for this day'))
                  : ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (ctx, i) {
                        final t = tasks[i];
                        final minutes = _minutesForTask(t);
                        final completed = t.completedAt != null
                            ? DateFormat('HH:mm').format(t.completedAt!)
                            : '-';
                        return ListTile(
                          title: Text(t.text, style: TextStyle(fontSize: 14 * MediaQuery.textScaleFactorOf(context))),
                          subtitle: Text('completed: $completed', style: TextStyle(fontSize: 12 * MediaQuery.textScaleFactorOf(context))),
                          trailing: Text('$minutes min', style: TextStyle(fontSize: 12 * MediaQuery.textScaleFactorOf(context))),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen QR scanner page. Returns the scanned string or null.
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR-Code scannen'),
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              _handled = true;
              Navigator.of(context).pop(value);
              return;
            }
          }
        },
      ),
    );
  }
}
