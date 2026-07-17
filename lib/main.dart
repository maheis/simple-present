import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:simple_present/sync/cloud_sync_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:simple_present/storage/json_storage.dart';
import 'package:simple_present/storage/sembast_storage.dart';
import 'package:file_selector/file_selector.dart' as fs;

// sentinel to indicate "no change" in copyWith optional parameters
const _noChange = Object();

const String kClientVersion = '0.1.0';

String _suggestedCloudDeviceName() {
  if (Platform.isAndroid) return 'android';
  final host = Platform.localHostname.trim();
  if (host.isEmpty || host.toLowerCase() == 'localhost') {
    return 'desktop';
  }
  return host;
}

String _normalizeCloudDeviceName(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return _suggestedCloudDeviceName();
  if (Platform.isAndroid && value.toLowerCase() == 'localhost') {
    return 'android';
  }
  return value;
}

// Global mouse entropy buffer used across pages for phrase suggestion.
final List<int> _mouseEntropy = <int>[];

/// A snapshot of tracked time for one task on one day, read from the
/// `time_entries` Sembast store.
class TimeEntry {
  const TimeEntry({
    required this.taskId,
    required this.taskText,
    required this.date,
    required this.taskDone,
    required this.taskInProgress,
    required this.stopwatchSeconds,
    required this.workMinutes,
  });

  final String taskId;
  final String taskText;
  final String date; // YYYY-MM-DD
  final bool taskDone;
  final bool taskInProgress;
  final int stopwatchSeconds;
  final int workMinutes;

  /// Total rounded-up 15-min blocks from stopwatch + manual minutes.
  int get totalMinutes {
    const blockSec = 15 * 60;
    final blocks = stopwatchSeconds > 0
        ? ((stopwatchSeconds + blockSec - 1) ~/ blockSec)
        : 0;
    return blocks * 15 + workMinutes;
  }

  String get statusLabel {
    if (taskDone) return 'fertig';
    if (taskInProgress) return 'in Arbeit';
    return 'offen';
  }
}

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

// Top-level debug logger used by multiple widgets. It writes to
// `<Documents>/simplepresent/simplepresent_debug.log` (or the
// debug variant when in debug mode). This is intentionally simple so
// different widgets can call it without needing an instance.
Future<void> _debugLog(String msg) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final folderName = kDebugMode ? 'simplepresent-debug' : 'simplepresent';
    final sub = Directory('${dir.path}/$folderName');
    if (!await sub.exists()) await sub.create(recursive: true);
    final f = File('${sub.path}/simplepresent_debug.log');
    final stamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
    await f.writeAsString('[$stamp] $msg\n', mode: FileMode.append);
  } catch (_) {}
}

/// Export per-task JSON files for external widgets and trigger a refresh.
///
/// This is a minimal, safe implementation used by the desktop build when
/// storage is Sembast-based. It writes one JSON file per task into the
/// application documents directory under `simplepresent_widget/` and
/// invokes an Android platform method `refresh` if available.
Future<void> exportTodayAndRefresh(List<TaskItem> tasks) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/simplepresent_widget');
    if (!await folder.exists()) await folder.create(recursive: true);

    for (final t in tasks) {
      try {
        final f = File('${folder.path}/${t.id}.json');
        await f.writeAsString(jsonEncode(t.toJson()));
      } catch (_) {}
    }

    // Try to notify native layer on Android to refresh widgets.
    try {
      if (Platform.isAndroid) {
        const MethodChannel('simple_present/widget')
            .invokeMethod<void>('refresh');
      }
    } catch (_) {}
  } catch (_) {}
}

// Force-write debug log removed. Use _debugLog() instead (respects _debugWriteLog flag)

class SimplePresentApp extends StatelessWidget {
  const SimplePresentApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimplePresent',
      // Default to English for broader settings readability
      locale: const Locale('en', 'US'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        Locale('en', 'US'),
        Locale('en', 'GB'),
        Locale('de', 'DE'),
      ],
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
    final map = Map<String, dynamic>.from(json as Map);
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
    this.recurrence,
    this.askRepeatDateOnRecreation = false,
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
  // recurrence values: 'daily', 'weekly', 'monthly' or null
  final String? recurrence;
  // whether to ask user for repeat date when creating follow-up task
  final bool askRepeatDateOnRecreation;
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
    Object? recurrence = _noChange,
    bool? askRepeatDateOnRecreation,
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
      recurrence: identical(recurrence, _noChange)
          ? this.recurrence
          : (recurrence == null ? null : (recurrence as String)),
      askRepeatDateOnRecreation:
          askRepeatDateOnRecreation ?? this.askRepeatDateOnRecreation,
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
        'text': text, // Changed to ensure proper mapping
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
        'recurrence': recurrence,
        'ask_repeat_date_on_recreation': askRepeatDateOnRecreation,
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
    final map = Map<String, dynamic>.from(json as Map);
    final String id = (map['id'] ?? '').toString();
    final String useId = id.isNotEmpty
        ? id
        : '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    return TaskItem(
      id: useId,
      text: (map['text'] ?? '').toString(),
      done: map['done'] == true,
      important: map['important'] == true,
      inProgress: map['inProgress'] == true,
      createdAt: _parseDate(map['created_at']),
      scheduledAt: _parseDate(map['scheduled_at']),
      completedAt: _parseDate(map['completed_at']),
      inProgressAt: _parseDate(map['in_progress_at']),
      importantAt: _parseDate(map['important_at']),
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
      recurrence:
          (map['recurrence'] ?? map['repeat'] ?? '').toString().isNotEmpty
              ? (map['recurrence'] ?? map['repeat'] ?? '').toString()
              : null,
      askRepeatDateOnRecreation: map['ask_repeat_date_on_recreation'] == true,
    );
  }
}

class _LoadingGlowBlob extends StatelessWidget {
  const _LoadingGlowBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withAlpha((0.26 * 255).round()),
              color.withAlpha((0.06 * 255).round()),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final List<TaskItem> _today = [];
  final TextEditingController _controller = TextEditingController();
  // Controller and query for Done-list search
  final TextEditingController _doneSearchController = TextEditingController();
  String _doneSearchQuery = '';
  final FocusNode _inputFocus = FocusNode();
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;
  String? _lastToastMessage;
  DateTime? _lastToastAt;
  final Set<String> _expanded = <String>{};
  final Set<String> _busyTaskIds = <String>{};
  // Action queue to prevent concurrent edits to the same task
  final Map<String, List<Future<void> Function()>> _taskActionQueues = {};
  // Track which task is currently being processed
  final Set<String> _taskActionProcessing = <String>{};
  final Map<String, TextEditingController> _editControllers = {};
  final Map<String, TextEditingController> _notesControllers = {};
  final Map<String, FocusNode> _editFocusNodes = {};
  final Map<String, Timer?> _autosaveTimers = {};
  final Map<String, TextEditingController> _subtaskInputControllers = {};
  final Map<String, FocusNode> _subtaskFocusNodes = {};
  final Map<String, TextEditingController> _workControllers = {};

  void _requestInputFocusIfIdle() {
    try {
      for (final node in _editFocusNodes.values) {
        if (node.hasFocus) return; // don't steal focus while editing
      }
      if (!_inputFocus.hasFocus) _inputFocus.requestFocus();
    } catch (_) {}
  }

  // Staged important flag changes (apply when delayed reorder fires)
  final Map<String, bool> _stagedImportant = {};
  // Staged inProgress and done flag changes (apply when delayed reorder fires)
  final Map<String, bool> _stagedInProgress = {};
  final Map<String, bool> _stagedDone = {};
  // (removed) pending timers for delayed backlog->done moves
  // Staged scheduled date/time changes (apply when delayed reorder fires)
  final Map<String, DateTime?> _stagedScheduled = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  // Sembast-backed local storage.
  final _sembastStorage = SembastStorage();
  bool _useSembast = false;
  Timer? _idleTimer;
  Timer? _attentionTimer;
  // immediate reorder: no delay timer
  int _idleMinutes = 45;
  int _attentionMinutes = 60;
  Timer? _reminderTimer;
  int _reminderMinutes = 75;
  Timer? _urgentTimer;
  int _urgentMinutes = 90;
  bool _idleSoundEnabled = false;
  bool _attentionSoundEnabled = false;
  bool _attentionFlashEnabled = false;
  bool _reminderSoundEnabled = false;
  bool _reminderNotifyEnabled = false;
  bool _idleFlashEnabled = false;
  // play sound for scheduled task reminders (15min / due)
  bool _scheduledReminderSoundEnabled = false;
  bool _idleNotifyEnabled = false;
  bool _idleBringToFrontEnabled = false;
  bool _attentionNotifyEnabled = false;
  bool _attentionBringToFrontEnabled = false;
  bool _reminderFlashEnabled = false;
  bool _reminderBringToFrontEnabled = false;
  bool _urgentFlashEnabled = false;
  bool _urgentSoundEnabled = false;
  bool _urgentNotifyEnabled = false;
  bool _urgentBringToFrontEnabled = false;
  // Dynamic inactivity reminders: list of stages user can add/remove
  // Each stage: { 'minutes': int, 'sound': bool, 'flash': bool, 'notify': bool, 'bringToFront': bool }
  List<Map<String, dynamic>> _inactivityReminders = <Map<String, dynamic>>[];
  List<Timer?> _inactivityTimers = <Timer?>[];
  List<bool> _inactivityFired = <bool>[];
  bool _swipeEnabled = true;
  // Reminder window (HH:MM) — only remind within this time window when enabled
  String _reminderWindowFrom = '09:00';
  String _reminderWindowTo = '17:00';
  String _fontFamily = 'OpenDyslexic';
  // Fired flags to ensure each reminder type fires only once per inactivity period
  bool _idleFired = false;
  bool _attentionFired = false;
  bool _reminderFired = false;
  bool _urgentFired = false;
  final MethodChannel _nativeWindowChannel =
      const MethodChannel('simple_present/window');
  final MethodChannel _androidPermissionsChannel =
      const MethodChannel('simple_present/permissions');
  Timer? _scheduledCheckTimer;
  Timer? _windowWatcherTimer;
  Timer? _autoSwitchTimer;
  // Timestamp when the app started; used to avoid firing scheduled reminders
  // for tasks that became due before the app was started.
  final DateTime _appStartedAt = DateTime.now();
  final Duration _autoSwitchDuration = const Duration(minutes: 3);
  Timer? _stopwatchTicker;
  final Set<String> _notified15 = <String>{};
  final Set<String> _notifiedDue = <String>{};
  final Set<int> _swiping = <int>{};
  // Scroll controller for the main task list so we can bring expanded items into view
  final ScrollController _listScrollController = ScrollController();
  // Per-task keys to locate tiles in the list for scrolling
  final Map<String, GlobalKey> _tileKeys = {};
  // Minimal view removed.

  // Storage filenames are environment-independent. Debug/prod separation
  // happens via storage directory path, not via filename prefixes.
  String _storage(String name) => name;

  String _listDirBase(String filename) {
    var name = filename;
    if (name.startsWith('simplepresent_'))
      name = name.substring('simplepresent_'.length);
    if (name.endsWith('.json')) name = name.substring(0, name.length - 5);
    return name; // e.g. 'today', 'backlog', 'done', 'trash'
  }

  bool _isListDir(String filename) {
    final base = _listDirBase(filename);
    return base == 'today' ||
        base == 'backlog' ||
        base == 'done' ||
        base == 'trash';
  }

  // Zoom state: tile height and font scaling
  double _tileHeight = 16.0;
  // default/min tile height constants removed (unused)
  // min font scale removed (unused)
  final double _baseFontSize = 15.0; // used when scaling text down
  double _uiTextScaleFactor = 1.0;
  final double _minUiTextScaleFactor = 0.5;
  final double _maxUiTextScaleFactor = 1.6;
  // gesture scale start values removed (pinch zoom disabled)
  bool _alwaysOnTop = false;
  final String _appTitle = 'SimplePresent';
  String _cloudServerUrl = '';
  String _cloudAccountId = '';
  String _cloudDeviceId = '';
  String _cloudToken = '';
  String _cloudWordPhrase = '';
  String _cloudDeviceName = _suggestedCloudDeviceName();
  String _cloudPIN = '';
  bool _cloudAllowInsecureTls = false;
  // Auto-clean settings for Done list
  bool _autoPurgeDoneEnabled = false;
  int _doneRetentionDays = 30;
  // Color-scaling thresholds (configurable in settings)
  int _maxTasksToday = 25;
  int _maxTasksBacklog = 50;

  bool _versionWarningShown = false;
  bool _cloudSyncFailed = false;
  int _cloudLastSyncSuccessAt = 0;
  String _cloudSyncLastError = '';
  int _cloudArchiveLastWarnedDays = -1;
  Timer? _cloudPullTimer;
  bool _autoPromoteDueBacklogBusy = false;
  bool _cloudSyncBusy = false;
  bool _applyingCloudState = false;
  bool _suppressSyncToasts = false;
  bool _suppressCloudPushes = false;
  // Suppress toasts generated by automatic backups/exports
  bool _suppressBackupToasts = false;
  int _cloudStateVersion = 1;
  int _cloudLastSyncModifiedAt = 0;
  // Push queue: pending pushes are keyed by filename. Latest snapshot wins.
  // A dedicated drain loop processes them sequentially to prevent drops when
  // multiple lists change in the same operation (e.g. move today→backlog).
  final Map<String, List<TaskItem>> _pendingCloudPushes = {};
  bool _cloudPushDrainRunning = false;
  final Map<String, TaskItem> _cloudPendingTimeEntrySync = <String, TaskItem>{};
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

// removed task font-scale helper (unused after disabling task zoom)

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
  // Cached counts for lists shown in header
  int _countToday = 0;
  int _countBacklog = 0;
  int _countDone = 0;
  bool _initializationComplete = false;
  Future<void> _storageWriteChain = Future.value();

  // Optional override for storage path (set via settings 'storagePath')
  String? _storagePathOverride;
  // Enable debug write logging
  bool _debugWriteLog = false;
  final List<Map<String, String>> _pendingNotificationTaskActions =
      <Map<String, String>>[];
  final List<String> _pendingWidgetOpenTaskIds = <String>[];

  final Stream<int> _loadingTickStream =
      Stream<int>.periodic(const Duration(milliseconds: 220), (x) => x);

  // Automatic export (backup) settings
  bool _autoExportOnStart = false;
  int _autoExportIntervalMinutes = 0; // 0 = disabled
  bool _autoExportRunning = false;
  List<String> _autoExportTimes = <String>[]; // list of 'HH:MM' strings
  Timer? _autoExportIntervalTimer;
  final List<Timer> _autoExportTimeTimers = <Timer>[];
  String _lastAutoExportChecksum = '';
  int _autoExportMaxBackups = 14;

  late final Future<void> _initFuture = _initializeApp();

  // Snapshot of last persisted `_today` list used to detect local changes
  // and append them to the redo log. Maps task id -> JSON map.
  final Map<String, Map<String, dynamic>> _lastPersistedToday = {};
  // Staged edit snapshots captured when a task is opened for editing.
  // Key: task id -> JSON snapshot before edits. Written once when the
  // task is expanded and cleared when edits are finalized.
  final Map<String, Map<String, dynamic>> _stagedEditBefore = {};

  @override
  void initState() {
    super.initState();
    _nativeWindowChannel.setMethodCallHandler(_handleNativeWindowMethodCall);
    WidgetsBinding.instance.addObserver(this);
    // Do not watch or persist window geometry; OS chooses position.
    _startIdleTimer();
    _startAttentionTimer();
    _startReminderTimer();
    _startUrgentTimer();
    _startAutoSwitchTimer();
    _startScheduledChecker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (!Platform.isAndroid) _requestInputFocusIfIdle();
      }
    });

    // (maxTasks values loaded from settings elsewhere)
    // listen for any keyboard activity to reset idle timers
    try {
      HardwareKeyboard.instance.addHandler(_hardwareKeyHandler);
    } catch (_) {}
    // Start a short ticker to update stopwatch displays every second
    _stopwatchTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_initializationComplete) return;
      unawaited(_promoteDueBacklogToToday(showToast: false));
    }
  }

  bool _hardwareKeyHandler(KeyEvent ev) {
    _registerActivity();
    return false; // do not claim the event
  }

  // Collect simple mouse movement entropy for phrase generation.
  void _collectMouseEntropy(PointerEvent ev) {
    // store low-entropy deltas; keep list bounded to 256 bytes
    final x = ev.position.dx.toInt();
    final y = ev.position.dy.toInt();
    _mouseEntropy.add((x ^ y) & 0xff);
    if (_mouseEntropy.length > 256)
      _mouseEntropy.removeRange(0, _mouseEntropy.length - 256);
  }

  Future<Directory> get _appDir async {
    // If user specified an explicit storage path in settings, prefer it.
    if (_storagePathOverride != null && _storagePathOverride!.isNotEmpty) {
      final sub = Directory(_storagePathOverride!);
      try {
        if (!await sub.exists()) await sub.create(recursive: true);
      } catch (_) {}
      return sub;
    }
    final dir = await getApplicationDocumentsDirectory();
    final folderName = kDebugMode ? 'simplepresent-debug' : 'simplepresent';
    final sub = Directory('${dir.path}/$folderName');
    try {
      if (!await sub.exists()) await sub.create(recursive: true);
    } catch (_) {}
    return sub;
  }

  Future<File> _fileFor(String name) async {
    final dir = await _appDir;
    return File('${dir.path}/$name');
  }

  static const String _settingsFileName = 'simplepresent_settings.json';

  Map<String, dynamic> _asSettingsMap(dynamic raw) {
    if (raw is Map) {
      try {
        return Map<String, dynamic>.from(raw);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _readSettingsMap() async {
    try {
      final file = await _fileFor(_storage(_settingsFileName));
      if (!await file.exists()) return <String, dynamic>{};
      return _asSettingsMap(await file.readAsString());
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeSettingsMap(Map<String, dynamic> data) async {
    final file = await _fileFor(_storage(_settingsFileName));
    final encoded = const JsonEncoder.withIndent('  ').convert(data);
    await file.writeAsString(encoded);
  }

  Future<void> _appendRedoLog(String action,
      {String? taskId, Map<String, dynamic>? details}) async {
    try {
      final entry = <String, dynamic>{
        'timestamp': DateTime.now().toIso8601String(),
        'action': action,
        'task_id': taskId ?? '',
        'user_id': (_cloudDeviceId.trim().isNotEmpty
            ? _cloudDeviceId.trim()
            : Platform.localHostname),
        'details': details ?? {},
      };
      final line = '${jsonEncode(entry)}\n';
      await _appendRawLogEntry(_storage('simplepresent_redo.log'), line);
    } catch (_) {}
  }

  Future<void> _appendRawLogEntry(String name, String entry) async {
    try {
      final file = await _fileFor(name);
      await file.writeAsString(entry, mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _openNotes() async {
    try {
      String text = '';
      try {
        final file = await _fileFor(_storage('simplepresent_notes.txt'));
        if (await file.exists()) {
          try {
            text = await file.readAsString();
          } catch (_) {}
        }
      } catch (_) {
        text = '';
      }
      final controller = TextEditingController(text: text);
      final original = text;
      await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) {
        // ignore: deprecated_member_use
        return WillPopScope(
          onWillPop: () async {
            try {
              if (controller.text != original) {
                final file =
                    await _fileFor(_storage('simplepresent_notes.txt'));
                await file.writeAsString(controller.text);
                unawaited(_syncPushNotes(controller.text));
              }
            } catch (_) {}
            return true;
          },
          child: Scaffold(
            appBar: AppBar(
              leadingWidth: 40,
              titleSpacing: 0,
              toolbarHeight: 62,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Image.asset(
                        'assets/icons/color_transparent_notes.png',
                        width: 28,
                        height: 28),
                  ),
                  const SizedBox(width: 8),
                  Text('notes',
                      style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)
                          .copyWith(fontFamily: _fontFamily)),
                ],
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  expands: true,
                  decoration:
                      const InputDecoration.collapsed(hintText: 'Notes...'),
                ),
              ),
            ),
          ),
        );
      }));
    } catch (_) {}
  }

  Future<void> _debugLog(String msg) async {
    try {
      if (!_debugWriteLog) return;
      final f = await _fileFor(_storage('simplepresent_debug.log'));
      final stamp =
          DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      await f.writeAsString('[$stamp] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> _ensureListFile(String filename) async {
    try {
      if (_useSembast) {
        if (!_sembastStorage.taskListExists(filename)) {
          _sembastStorage
              .writeTaskList(filename, const <Map<String, dynamic>>[]);
        }
        return;
      }
      if (_isListDir(filename)) {
        final dir =
            Directory('${(await _appDir).path}/${_listDirBase(filename)}');
        if (!await dir.exists()) await dir.create(recursive: true);
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
    final initStartedAt = DateTime.now();
    const minLoadingDuration = Duration(milliseconds: 1800);
    // ensure current file respects debug mode
    _currentFile = _storage('simplepresent_today.json');
    _useSembast = true;
    try {
      await _sembastStorage.init(debugMode: kDebugMode);
    } catch (_) {}
    await _loadSettings();
    await _ensureInitialFiles();

    // Start auto-export timers and perform export on-start if configured
    try {
      _startAutoExportTimers();
      if (_autoExportOnStart) {
        unawaited(_performAutoExport());
      }
    } catch (_) {}

    // Do not rewrite all lists at startup.
    // Startup-wide resaves can cause excessive churn on list-dir storage.

    // Set a sensible default size on startup (width x height).
    // On Windows place the window at the top-right edge of the primary screen.
    try {
      if (Platform.isWindows) {
        try {
          final screen =
              await _nativeWindowChannel.invokeMethod('getScreenSize');
          int sw = 0;
          if (screen is Map) {
            final w = screen['width'];
            if (w is int)
              sw = w;
            else if (w is num)
              sw = w.toInt();
            else if (w is String) sw = int.tryParse(w) ?? 0;
          }
          final int width = 450;
          final int x = (sw > 0) ? math.max(0, sw - width) : 0;
          await _nativeWindowChannel
              .invokeMethod('setWindowGeometry', <String, dynamic>{
            'x': x,
            'y': 0,
            'width': width,
            'height': 700,
            'maximized': 0,
            'always_on_top': 0
          });
        } catch (_) {
          // fallback to center/normal sizing if screen query fails
          await _nativeWindowChannel.invokeMethod(
              'setWindowGeometry', <String, dynamic>{
            'width': 450,
            'height': 700,
            'maximized': 0,
            'always_on_top': 0
          });
        }
      } else {
        await _nativeWindowChannel.invokeMethod(
            'setWindowGeometry', <String, dynamic>{
          'width': 450,
          'height': 700,
          'maximized': 0,
          'always_on_top': 0
        });
      }
    } catch (_) {}

    // Start cloud pull in background so startup is never blocked by network.
    unawaited(_syncPullFromCloud());
    await _promoteDueBacklogToToday(showToast: true);
    await _loadToday();
    // Request Android 13+ notification permission on startup via native channel.
    unawaited(_requestAndroidNotificationPermission());
    // Run cleanup of old Done tasks if enabled
    unawaited(_purgeOldDoneTasksIfEnabled());
    unawaited(_fetchServerVersion());
    _startCloudPullTimer();
    // Start dynamic inactivity timers according to loaded settings
    _startInactivityTimers();

    final elapsed = DateTime.now().difference(initStartedAt);
    if (elapsed < minLoadingDuration) {
      await Future.delayed(minLoadingDuration - elapsed);
    }
    _initializationComplete = true;
    await _processPendingNotificationTaskActions();
    await _processPendingWidgetOpenTasks();
  }

  Future<void> _handleNativeWindowMethodCall(MethodCall call) async {
    if (call.method == 'notificationTaskAction') {
      final args = call.arguments;
      if (args is! Map) return;
      final taskId = (args['taskId'] ?? '').toString().trim();
      final action = (args['action'] ?? '').toString().trim();
      if (taskId.isEmpty || action.isEmpty) return;

      final payload = <String, String>{'taskId': taskId, 'action': action};
      if (!_initializationComplete) {
        _pendingNotificationTaskActions.add(payload);
        return;
      }
      await _applyNotificationTaskAction(taskId: taskId, action: action);
      return;
    }

    if (call.method == 'openTaskFromWidget') {
      final args = call.arguments;
      if (args is! Map) return;
      final taskId = (args['taskId'] ?? '').toString().trim();
      if (taskId.isEmpty) return;
      if (!_initializationComplete) {
        _pendingWidgetOpenTaskIds.add(taskId);
        return;
      }
      await _openTaskFromWidget(taskId);
      return;
    }
  }

  Future<void> _processPendingNotificationTaskActions() async {
    if (_pendingNotificationTaskActions.isEmpty) return;
    final pending =
        List<Map<String, String>>.from(_pendingNotificationTaskActions);
    _pendingNotificationTaskActions.clear();
    for (final entry in pending) {
      final taskId = (entry['taskId'] ?? '').trim();
      final action = (entry['action'] ?? '').trim();
      if (taskId.isEmpty || action.isEmpty) continue;
      await _applyNotificationTaskAction(taskId: taskId, action: action);
    }
  }

  Future<void> _processPendingWidgetOpenTasks() async {
    if (_pendingWidgetOpenTaskIds.isEmpty) return;
    final pending = List<String>.from(_pendingWidgetOpenTaskIds);
    _pendingWidgetOpenTaskIds.clear();
    for (final taskId in pending) {
      final id = taskId.trim();
      if (id.isEmpty) continue;
      await _openTaskFromWidget(id);
    }
  }

  Future<void> _openTaskFromWidget(String taskId) async {
    try {
      final todayFile = _storage('simplepresent_today.json');
      if (_currentFile != todayFile || _showingBacklog || _showingDone) {
        await _switchFile(false);
      } else {
        await _loadToday();
      }

      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx == -1) {
        unawaited(_debugLog(
            'widget open ignored: task not found in today ($taskId)'));
        return;
      }

      if (!mounted) return;
      setState(() {
        _expanded.clear();
        _expanded.add(taskId);
        _editControllers.putIfAbsent(taskId, () {
          final c = TextEditingController(text: _today[idx].text.trim());
          c.addListener(() {
            if (mounted) setState(() {});
            _scheduleAutoSave(taskId);
          });
          return c;
        });
        _notesControllers.putIfAbsent(taskId, () {
          final n = TextEditingController(text: _today[idx].notes ?? '');
          n.addListener(() {
            if (mounted) setState(() {});
            _scheduleAutoSave(taskId);
          });
          return n;
        });
      });

      try {
        _stagedEditBefore.putIfAbsent(taskId, () => _today[idx].toJson());
      } catch (_) {}

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final k = _tileKeys[taskId];
        if (k != null && k.currentContext != null) {
          try {
            Scrollable.ensureVisible(k.currentContext!,
                duration: const Duration(milliseconds: 300), alignment: 0.08);
          } catch (_) {}
        }
      });
    } catch (e) {
      unawaited(_debugLog('widget open failed: $taskId, $e'));
    }
  }

  Future<void> _applyNotificationTaskAction({
    required String taskId,
    required String action,
  }) async {
    try {
      final todayFile = _storage('simplepresent_today.json');
      final todayList = <TaskItem>[];
      await _loadList(todayFile, todayList);
      final idx = todayList.indexWhere((t) => t.id == taskId);
      if (idx == -1) {
        unawaited(_debugLog(
            'notification action ignored: task not found in today ($taskId, $action)'));
        return;
      }

      final now = DateTime.now();
      final current = todayList[idx];
      if (action == 'done') {
        todayList[idx] = current.copyWith(
          done: true,
          inProgress: false,
          completedAt: now,
          inProgressAt: null,
          stopwatchRunning: false,
          stopwatchStartedAt: null,
        );
      } else if (action == 'in_progress') {
        todayList[idx] = current.copyWith(
          done: false,
          inProgress: true,
          inProgressAt: current.inProgressAt ?? now,
          stopwatchRunning: true,
          stopwatchStartedAt: current.stopwatchStartedAt ?? now,
        );
      } else {
        return;
      }

      await _saveList(todayFile, todayList);
      final idPrefix = '$taskId|';
      _notified15.removeWhere((k) => k.startsWith(idPrefix));
      _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
      try {
        await _saveSettings();
      } catch (_) {}

      if (_currentFile == todayFile) {
        await _loadToday();
      } else {
        unawaited(_updateListCounts());
      }

      if (!mounted) return;
      if (action == 'done') {
        _showTopToast('task marked done (notification)');
      } else {
        _showTopToast('task marked in progress (notification)');
      }
    } catch (e) {
      unawaited(_debugLog('notification action failed: $taskId, $action, $e'));
    }
  }

  Future<void> _requestAndroidNotificationPermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _androidPermissionsChannel
          .invokeMethod<bool>('requestNotificationPermission');
    } catch (_) {}
  }

  Future<void> _refreshAndroidTodayWidget() async {
    if (!Platform.isAndroid) return;
    try {
      await _nativeWindowChannel.invokeMethod('refreshTodayWidget');
    } catch (_) {}
  }

  Future<void> _loadList(String filename, List<TaskItem> target) async {
    target.clear();
    try {
      if (_useSembast) {
        final rows = _sembastStorage.readTaskList(filename);
        for (var i = 0; i < rows.length; i++) {
          try {
            target.add(TaskItem.fromJson(rows[i]));
          } catch (e) {
            unawaited(_debugLog(
                'loadList parse error (sembast): file=$filename index=$i error=$e'));
          }
        }
        _dedupeTaskIdsInPlace(target, filename);
        return;
      }
      if (_isListDir(filename)) {
        final dir =
            Directory('${(await _appDir).path}/${_listDirBase(filename)}');
        if (await dir.exists()) {
          final files = dir.listSync().whereType<File>().toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          for (final f in files) {
            try {
              final text = await f.readAsString();
              final data = jsonDecode(text);
              target.add(TaskItem.fromJson(data));
            } catch (_) {}
          }
        }
        _dedupeTaskIdsInPlace(target, filename);
        return;
      }
      final f = await _fileFor(filename);
      if (await f.exists()) {
        final text = await f.readAsString();
        final data = jsonDecode(text) as List<dynamic>;
        for (var i = 0; i < data.length; i++) {
          try {
            target.add(TaskItem.fromJson(data[i]));
          } catch (e) {
            unawaited(_debugLog(
                'loadList parse error (file): file=$filename index=$i error=$e'));
          }
        }
      }
      _dedupeTaskIdsInPlace(target, filename);
    } catch (e) {
      unawaited(_debugLog('loadList failed: file=$filename error=$e'));
    }
  }

  void _dedupeTaskIdsInPlace(List<TaskItem> list, String sourceName) {
    try {
      final seen = <String>{};
      int replacedIds = 0;
      int reassignedDuplicates = 0;
      final normalized = <TaskItem>[];

      for (final t in list) {
        var id = t.id.trim();
        if (id.isEmpty) {
          id =
              '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
          replacedIds++;
        }
        if (seen.contains(id)) {
          // Keep the item but reassign ID instead of dropping data.
          id =
              '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
          while (seen.contains(id)) {
            id =
                '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
          }
          reassignedDuplicates++;
        }
        seen.add(id);
        normalized.add(id == t.id ? t : t.copyWith(id: id));
      }

      if (replacedIds > 0 || reassignedDuplicates > 0) {
        list
          ..clear()
          ..addAll(normalized);
        unawaited(_debugLog(
            'dedupe on load for $sourceName: replaced_empty_ids=$replacedIds, reassigned_duplicate_ids=$reassignedDuplicates'));
      }
    } catch (_) {}
  }

  Future<int> _promoteDueBacklogToToday({bool showToast = false}) async {
    if (_autoPromoteDueBacklogBusy) {
      unawaited(_debugLog('promote due backlog skipped: busy'));
      return 0;
    }
    _autoPromoteDueBacklogBusy = true;
    try {
      final backlogFile = _storage('simplepresent_backlog.json');
      final todayFile = _storage('simplepresent_today.json');
      final backlogList = <TaskItem>[];
      final todayList = <TaskItem>[];
      await Future.wait([
        _loadList(backlogFile, backlogList),
        _loadList(todayFile, todayList),
      ]);

      final now = DateTime.now();
      final todayDateStr = DateFormat('yyyy-MM-dd').format(now);
      final todayIds = todayList.map((t) => t.id).toSet();
      final promote = <TaskItem>[];
      var changed = false;

      backlogList.removeWhere((t) {
        if (t.scheduledAt == null || t.done) return false;
        // Promote if scheduled for today (any time) or earlier — compare date-only
        // so tasks set to "today at 23:59" are moved immediately, not after that time.
        final schedDateStr =
            DateFormat('yyyy-MM-dd').format(t.scheduledAt!.toLocal());
        final due = schedDateStr.compareTo(todayDateStr) <= 0;
        if (!due) return false;

        changed = true;
        if (!todayIds.contains(t.id)) {
          promote.add(t.copyWith(done: false, inProgress: false));
          todayIds.add(t.id);
        }
        return true;
      });

      if (!changed) {
        unawaited(_debugLog('promote due backlog: nothing to move'));
        return 0;
      }

      if (promote.isNotEmpty) {
        todayList.insertAll(0, promote);
      }

      // Persist per-task: remove from backlog and append to Today atomically
      for (final t in promote) {
        try {
          await _queueRemoveFromList(backlogFile, t.id);
        } catch (_) {}
        try {
          await _queueAppendToList(todayFile, t, insertTop: true);
        } catch (_) {}
      }

      if (mounted) {
        await _loadToday();
      }
      unawaited(_updateListCounts());

      if (showToast && promote.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTopToast(
              '${promote.length} task(s) moved from backlog to today');
        });
      }

      unawaited(_debugLog(
          'promote due backlog finished: moved=${promote.length}, backlog=${backlogList.length}, today=${todayList.length}'));

      return promote.length;
    } catch (_) {
      return 0;
    } finally {
      _autoPromoteDueBacklogBusy = false;
    }
  }

  Future<void> _updateListCounts() async {
    try {
      final List<TaskItem> tmp = [];
      await _loadList(_storage('simplepresent_today.json'), tmp);
      // Count only open (not done) tasks for Today
      _countToday = tmp.where((t) => !t.done).length;
      tmp.clear();
      await _loadList(_storage('simplepresent_backlog.json'), tmp);
      _countBacklog = tmp.length;
      tmp.clear();
      await _loadList(_storage('simplepresent_done.json'), tmp);
      _countDone = tmp.length;
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _purgeOldDoneTasksIfEnabled() async {
    if (!_autoPurgeDoneEnabled || _doneRetentionDays <= 0) return;
    await _purgeOldDoneTasks(_doneRetentionDays);
  }

  Future<void> _purgeOldDoneTasks(int days) async {
    try {
      final List<TaskItem> doneList = [];
      await _loadList(_storage('simplepresent_done.json'), doneList);
      if (doneList.isEmpty) return;
      final now = DateTime.now();
      final cutoff = now.subtract(Duration(days: days));
      final before = doneList.length;
      final remaining = doneList.where((t) {
        final c = t.completedAt;
        if (c == null) return true; // preserve items without timestamp
        return !c.isBefore(cutoff);
      }).toList();
      final removed = before - remaining.length;
      if (removed > 0) {
        // Remove each outdated task via per-task queue to ensure atomic removal
        final removedTasks = doneList.where((t) {
          final c = t.completedAt;
          if (c == null) return false; // preserved earlier
          return c.isBefore(cutoff);
        }).toList();
        for (final t in removedTasks) {
          await _queueRemoveFromList('simplepresent_done.json', t.id);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTopToast('removed $removed old done task(s)');
        });
      }
    } catch (_) {}
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatBacklogScheduleLabel(DateTime scheduledAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(scheduledAt.year, scheduledAt.month, scheduledAt.day);
    final dayDiff = day.difference(today).inDays.abs();

    if (_isSameDay(day, today.subtract(const Duration(days: 1)))) {
      return 'yesterday';
    }
    if (_isSameDay(day, today)) {
      return 'today';
    }
    if (dayDiff < 7) {
      return DateFormat('EEEE').format(scheduledAt);
    }
    return DateFormat('dd.MM.yyyy').format(scheduledAt);
  }

  Future<void> _appendDone(List<TaskItem> items) async {
    if (items.isEmpty) return;
    try {
      // Enqueue each item append under its own task queue to ensure
      // atomic, per-task processing across lists.
      for (final it in items) {
        await _queueAppendToList('simplepresent_done.json', it,
            insertTop: false);
      }
    } catch (_) {}
  }

  Future<void> _queueAppendToList(String filename, TaskItem item,
      {bool insertTop = true}) async {
    try {
      unawaited(
          _debugLog('queueAppend: scheduling append ${item.id} -> $filename'));
      await _queueTaskAction(item.id, () async {
        final List<TaskItem> list = [];
        await _loadList(filename, list);
        if (insertTop) {
          list.insert(0, item);
        } else {
          list.add(item);
        }
        await _saveList(filename, list);
      });
    } catch (_) {}
  }

  Future<void> _queueRemoveFromList(String filename, String taskId) async {
    try {
      unawaited(
          _debugLog('queueRemove: scheduling remove $taskId -> $filename'));
      await _queueTaskAction(taskId, () async {
        final List<TaskItem> list = [];
        await _loadList(filename, list);
        list.removeWhere((t) => t.id == taskId);
        await _saveList(filename, list);
      });
    } catch (_) {}
  }

  // Serialized file-op chaining to avoid concurrent read/write races on the
  // same list file. Operations for the same filename are executed sequentially.
  final Map<String, Future<void>> _fileWriteChains = {};

  Future<void> _serializedFileOp(
      String filename, Future<void> Function() op) async {
    final prev = _fileWriteChains[filename];
    final completer = Completer<void>();
    _fileWriteChains[filename] = completer.future;
    try {
      unawaited(_debugLog('serializedFileOp: start $filename'));
      if (prev != null) {
        try {
          await prev;
        } catch (_) {}
      }
      await op();
      unawaited(_debugLog('serializedFileOp: finished $filename'));
    } finally {
      completer.complete();
      if (_fileWriteChains[filename] == completer.future) {
        _fileWriteChains.remove(filename);
      }
    }
  }

  /// Replace the contents of [filename] with [items] using per-task queue
  /// operations, but serialized file operations to avoid races. This keeps
  /// sync semantics similar to a full replace while ensuring per-task
  /// operations are atomic and debuggable.
  Future<void> _queueReplaceList(String filename, List<TaskItem> items) async {
    try {
      // First, ensure each incoming item is upserted via its task queue.
      for (final it in items) {
        unawaited(
            _debugLog('queueReplace: scheduling upsert ${it.id} -> $filename'));
        await _queueTaskAction(it.id, () async {
          await _serializedFileOp(filename, () async {
            final List<TaskItem> cur = [];
            await _loadList(filename, cur);
            // Remove any existing entry with same id
            cur.removeWhere((t) => t.id == it.id);
            // Insert at top
            cur.insert(0, it);
            await _saveList(filename, cur);
          });
        });
      }

      // Then, remove any tasks that are not present in the new set.
      final newIds = items.map((e) => e.id).toSet();
      await _serializedFileOp(filename, () async {
        final List<TaskItem> cur = [];
        await _loadList(filename, cur);
        final toRemove = cur.where((t) => !newIds.contains(t.id)).toList();
        for (final r in toRemove) {
          unawaited(_debugLog(
              'queueReplace: scheduling remove ${r.id} from $filename'));
          await _queueTaskAction(r.id, () async {
            await _serializedFileOp(filename, () async {
              final List<TaskItem> now = [];
              await _loadList(filename, now);
              now.removeWhere((t) => t.id == r.id);
              await _saveList(filename, now);
            });
          });
        }
      });
    } catch (e, st) {
      unawaited(_debugLog('queueReplaceList failed for $filename: $e\n$st'));
    }
  }

  Future<void> _createNextRecurrenceIfNeeded(TaskItem task,
      {bool appendToDone = true}) async {
    try {
      if (appendToDone) {
        await _appendDone([task]);
      }
    } catch (_) {}
    try {
      final rec = task.recurrence;
      if (rec != null && rec.isNotEmpty) {
        final base = task.scheduledAt ?? DateTime.now();
        final next = _computeNextRecurrence(base, rec);
        if (next != null) {
          // Only ask user if askRepeatDateOnRecreation is enabled for this task
          DateTime chosen = next;
          if (task.askRepeatDateOnRecreation && mounted) {
            try {
              final pretty = DateFormat('yyyy-MM-dd HH:mm').format(next);
              final action = await showDialog<String?>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Create follow-up task'),
                  content: Text('Create next occurrence on $pretty?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop('skip'),
                        child: const Text('Skip')),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop('choose'),
                        child: const Text('Choose')),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop('create'),
                        child: const Text('Create')),
                  ],
                ),
              );
              if (action == 'skip' || action == null) {
                // user chose not to create
                return;
              }
              if (action == 'choose') {
                final date = await showDatePicker(
                  context: context,
                  initialDate: next,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (date == null) return;
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(next),
                );
                final t = time ?? TimeOfDay.fromDateTime(next);
                chosen =
                    DateTime(date.year, date.month, date.day, t.hour, t.minute);
              }
            } catch (_) {}
          }

          final newId =
              '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
          final newTask = task.copyWith(
            id: newId,
            createdAt: DateTime.now(),
            completedAt: null,
            done: false,
            inProgress: false,
            stopwatchAccumulatedSeconds: 0,
            stopwatchRunning: false,
            stopwatchStartedAt: null,
            scheduledAt: chosen,
            subtasks:
                task.subtasks.map((s) => s.copyWith(done: false)).toList(),
          );
          if (_isSameDay(chosen, DateTime.now())) {
            final filename = _storage('simplepresent_today.json');
            final List<TaskItem> todayList = [];
            await _loadList(filename, todayList);
            todayList.insert(0, newTask);
            await _saveList(filename, todayList);
            try {
              unawaited(_appendRedoLog('create',
                  taskId: newTask.id,
                  details: {'text': newTask.text, 'generated_from': task.id}));
            } catch (_) {}
            // If the UI currently shows Today, update the in-memory view immediately
            try {
              if (_currentFile == filename && mounted) {
                // Show spinner on the newly created task while we update UI
                unawaited(_queueTaskAction(newTask.id, () async {
                  if (!mounted) return;
                  setState(() {
                    _today.insert(0, newTask);
                  });
                  await _saveToday();
                  unawaited(_updateListCounts());
                }));
              }
            } catch (_) {}
            try {
              _showTopToast('follow up created');
            } catch (_) {}
          } else {
            final filename = _storage('simplepresent_backlog.json');
            final List<TaskItem> backlogList = [];
            await _loadList(filename, backlogList);
            backlogList.insert(0, newTask);
            await _saveList(filename, backlogList);
            try {
              unawaited(_appendRedoLog('create',
                  taskId: newTask.id,
                  details: {'text': newTask.text, 'generated_from': task.id}));
            } catch (_) {}
            // If the UI currently shows Backlog, update the in-memory view immediately
            // Only update _today if we're actually showing the backlog file
            try {
              if (_showingBacklog && _currentFile == filename && mounted) {
                unawaited(_queueTaskAction(newTask.id, () async {
                  if (!mounted) return;
                  setState(() {
                    _today.insert(0, newTask);
                  });
                  await _saveToday();
                  unawaited(_updateListCounts());
                }));
              }
            } catch (_) {}
            try {
              _showTopToast('follow up created');
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveList(String filename, List<TaskItem> source,
      {bool triggerCloudSync = true}) async {
    await (_storageWriteChain =
        _storageWriteChain.catchError((_) {}).then((_) async {
      try {
        unawaited(_debugLog(
            'saveList start: $filename count=${source.length} sembast=$_useSembast listdir=${_isListDir(filename)}'));
        final encoder = const JsonEncoder.withIndent('  ');
        if (_useSembast) {
          _sembastStorage.writeTaskList(
            filename,
            source.map((e) => e.toJson()).toList(),
          );
        } else if (_isListDir(filename)) {
          final dir =
              Directory('${(await _appDir).path}/${_listDirBase(filename)}');
          if (!await dir.exists()) await dir.create(recursive: true);
          // write each task as its own file with index prefix to preserve order
          final Set<String> keep = {};
          for (var i = 0; i < source.length; i++) {
            final t = source[i];
            final name = '${i.toString().padLeft(8, '0')}_${t.id}.json';
            final f = File('${dir.path}/$name');
            final tmp = File('${dir.path}/$name.tmp');
            final content = encoder.convert(t.toJson());
            try {
              await tmp.writeAsString(content);
              // Try to atomically rename the temp file to the final name.
              // Do NOT delete the destination beforehand — deleting triggers
              // explicit DELETE dispositions which OneDrive may react to.
              try {
                await tmp.rename(f.path);
                unawaited(_debugLog('wrote task file: ${f.path}'));
                // Small delay and verify the file exists; if not, attempt fallback
                try {
                  await Future.delayed(const Duration(milliseconds: 120));
                  if (!await f.exists()) {
                    unawaited(_debugLog(
                        'post-rename check: file missing ${f.path}; attempting fallback write'));
                    try {
                      await f.writeAsString(content);
                      unawaited(
                          _debugLog('fallback wrote task file: ${f.path}'));
                    } catch (_) {
                      unawaited(
                          _debugLog('fallback write failed for: ${f.path}'));
                    }
                    // directory snapshot for diagnostics
                    try {
                      final names = (await dir.list().toList())
                          .whereType<File>()
                          .map((e) => p.basename(p.normalize(e.path)))
                          .join(',');
                      unawaited(_debugLog(
                          'dir-snapshot after write: ${dir.path} -> $names'));
                    } catch (_) {}
                  }
                } catch (_) {}
              } catch (_) {
                // If rename fails (e.g. because the destination exists or
                // the platform doesn't allow overwrite), fall back to
                // overwriting the destination file in place to avoid a
                // separate delete event that OneDrive could act upon.
                try {
                  await f.writeAsString(content);
                  if (await tmp.exists()) await tmp.delete();
                  unawaited(
                      _debugLog('wrote task file by overwrite: ${f.path}'));
                } catch (_) {}
              }
            } catch (_) {
              // best-effort: attempt direct write
              try {
                await f.writeAsString(content);
                unawaited(_debugLog('direct wrote task file: ${f.path}'));
              } catch (_) {}
            }
            // Use filename (basename) only for matching to avoid differences
            // in absolute path representation (slashes, case, OneDrive prefixes).
            final fname = p.basename(p.normalize(f.path)).toLowerCase();
            keep.add(fname);
          }
          // remove orphaned files
          try {
            final existingFiles = dir.listSync().whereType<File>().toList();
            for (final fileObj in existingFiles) {
              final existingName =
                  p.basename(p.normalize(fileObj.path)).toLowerCase();
              if (!keep.contains(existingName)) {
                try {
                  await fileObj.delete();
                  unawaited(
                      _debugLog('deleted orphaned task file: ${fileObj.path}'));
                } catch (_) {}
              }
            }
          } catch (_) {}
        } else {
          final text = encoder.convert(source.map((e) => e.toJson()).toList());
          final f = await _fileFor(filename);
          // Write to a temporary file first and then rename to the final file
          // to avoid leaving a truncated/empty file if the process is killed
          // or the write is interrupted (observed on Windows clients).
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(text);
          try {
            // Avoid explicit delete before replace to reduce delete-churn
            // in synced folders.
            await tmp.rename(f.path);
            unawaited(_debugLog('wrote list file: ${f.path}'));
            try {
              await Future.delayed(const Duration(milliseconds: 120));
              if (!await f.exists()) {
                unawaited(_debugLog(
                    'post-rename check: list file missing ${f.path}; attempting fallback write'));
                try {
                  await f.writeAsString(text);
                  unawaited(_debugLog('fallback wrote list file: ${f.path}'));
                } catch (_) {
                  unawaited(_debugLog(
                      'fallback write failed for list file: ${f.path}'));
                }
                try {
                  final names = (await (f.parent).list().toList())
                      .whereType<File>()
                      .map((e) => p.basename(p.normalize(e.path)))
                      .join(',');
                  unawaited(_debugLog(
                      'dir-snapshot after list write: ${f.parent.path} -> $names'));
                } catch (_) {}
              }
            } catch (_) {}
          } catch (_) {
            // Best-effort fallback: attempt to copy contents and remove temp.
            try {
              await f.writeAsString(text);
              if (await tmp.exists()) await tmp.delete();
              unawaited(_debugLog('wrote list file by overwrite: ${f.path}'));
            } catch (_) {}
          }
        }
        if (triggerCloudSync) {
          // Use push queue to ensure sequential delivery.
          // This prevents the second push being silently dropped during move
          // operations (today + backlog both change in the same action).
          _enqueuePush(filename, source);
        }
        unawaited(_debugLog('saveList completed: $filename'));
        if (_listDirBase(filename) == 'today') {
          unawaited(_refreshAndroidTodayWidget());
        }
      } catch (e, st) {
        unawaited(_debugLog('saveList failed: $filename error=$e\n$st'));
      }
    }));
    await _storageWriteChain;
  }

  /// Export all lists (today, backlog, done, trash) to a single JSON file at [path].
  /// If the file exists it will be overwritten.
  Future<void> exportAllListsToJsonFile(String path) async {
    try {
      final List<TaskItem> todayList = [];
      final List<TaskItem> backlogList = [];
      final List<TaskItem> doneList = [];
      final List<TaskItem> trashList = [];

      await _loadList(_storage('simplepresent_today.json'), todayList);
      await _loadList(_storage('simplepresent_backlog.json'), backlogList);
      await _loadList(_storage('simplepresent_done.json'), doneList);
      await _loadList('simplepresent_trash.json', trashList);

      final Map<String, dynamic> exportData = {
        'exportedAt': DateTime.now().toIso8601String(),
        'today': todayList.map((t) => t.toJson()).toList(),
        'backlog': backlogList.map((t) => t.toJson()).toList(),
        'done': doneList.map((t) => t.toJson()).toList(),
        'trash': trashList.map((t) => t.toJson()).toList(),
      };

      final f = File(path);
      await f.create(recursive: true);
      await f.writeAsString(
          const JsonEncoder.withIndent('  ').convert(exportData));
      try {
        _showTopToast('exported to ${p.basename(path)}');
      } catch (_) {}
      unawaited(_debugLog('exportAllListsToJsonFile wrote $path'));
    } catch (e, st) {
      unawaited(_debugLog('exportAllListsToJsonFile failed: $e\n$st'));
      try {
        _showTopToast('export failed');
      } catch (_) {}
    }
  }

  /// Import lists from a JSON file at [path]. If [merge] is true, items will be
  /// merged by `id` into existing lists (no duplicates). If false, lists will be
  /// replaced by the imported content.
  Future<void> importAllListsFromJsonFile(String path,
      {bool merge = false}) async {
    try {
      final f = File(path);
      if (!await f.exists()) {
        try {
          _showTopToast('import file not found');
        } catch (_) {}
        return;
      }
      final text = await f.readAsString();
      final data = jsonDecode(text) as Map<String, dynamic>;

      final List<TaskItem> importedToday = (data['today'] is List)
          ? List<Map<String, dynamic>>.from(data['today'])
              .map(TaskItem.fromJson)
              .toList()
          : <TaskItem>[];
      final List<TaskItem> importedBacklog = (data['backlog'] is List)
          ? List<Map<String, dynamic>>.from(data['backlog'])
              .map(TaskItem.fromJson)
              .toList()
          : <TaskItem>[];
      final List<TaskItem> importedDone = (data['done'] is List)
          ? List<Map<String, dynamic>>.from(data['done'])
              .map(TaskItem.fromJson)
              .toList()
          : <TaskItem>[];
      final List<TaskItem> importedTrash = (data['trash'] is List)
          ? List<Map<String, dynamic>>.from(data['trash'])
              .map(TaskItem.fromJson)
              .toList()
          : <TaskItem>[];

      // Helper to merge or replace a target filename
      Future<void> applyListImport(
          String filename, List<TaskItem> imported) async {
        if (!merge) {
          await _saveList(filename, imported);
          return;
        }
        // merge: load existing, append items with new ids
        final List<TaskItem> existing = [];
        await _loadList(filename, existing);
        final existingIds = existing.map((e) => e.id).toSet();
        final toAdd =
            imported.where((e) => !existingIds.contains(e.id)).toList();
        if (toAdd.isNotEmpty) {
          for (final it in toAdd) {
            await _queueAppendToList(filename, it, insertTop: true);
          }
        }
      }

      await applyListImport(
          _storage('simplepresent_today.json'), importedToday);
      await applyListImport(
          _storage('simplepresent_backlog.json'), importedBacklog);
      await applyListImport(_storage('simplepresent_done.json'), importedDone);
      await applyListImport('simplepresent_trash.json', importedTrash);

      // reload current view and counts
      try {
        await _loadToday();
      } catch (_) {}
      unawaited(_updateListCounts());
      try {
        _showTopToast('imported ${p.basename(path)}');
      } catch (_) {}
      unawaited(
          _debugLog('importAllListsFromJsonFile applied $path merge=$merge'));
    } catch (e, st) {
      unawaited(_debugLog('importAllListsFromJsonFile failed: $e\n$st'));
      try {
        _showTopToast('import failed');
      } catch (_) {}
    }
  }

  Future<void> _exportViaChooser() async {
    try {
      final now = DateTime.now();
      final suggestedName =
          'simplepresent-export-${DateFormat('yyyyMMdd-HHmmss').format(now)}.json';

      final dir = await _appDir;
      final home = Platform.environment['HOME'] ?? dir.path;
      final downloads = '$home/Downloads';
      final options = <String>[];
      options.add(dir.path);
      if (Directory(downloads).existsSync()) options.add(downloads);
      if (home.isNotEmpty && home != dir.path) options.add(home);

      String chosenDir = dir.path;
      String fileName = suggestedName;

      final res = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Export as JSON'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: const InputDecoration(labelText: 'Filename'),
                    controller: TextEditingController(text: fileName),
                    onChanged: (v) => fileName = v,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<String>(
                          value: chosenDir,
                          items: options
                              .map((o) =>
                                  DropdownMenuItem(value: o, child: Text(o)))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => chosenDir = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          try {
                            final picked = await fs.getDirectoryPath();
                            if (picked != null && picked.isNotEmpty) {
                              setState(() => chosenDir = picked);
                            }
                          } catch (_) {}
                        },
                        child: const Text('Choose folder...'),
                      ),
                    ],
                  )
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Save')),
              ],
            );
          });
        },
      );

      if (res != true) return;
      final exportPath = p.join(chosenDir, fileName);
      await exportAllListsToJsonFile(exportPath);
    } catch (e, st) {
      unawaited(_debugLog('exportViaChooser failed: $e\n$st'));
      try {
        _showTopToast('export failed');
      } catch (_) {}
    }
  }

  Future<void> _importViaChooser() async {
    try {
      final typeGroup = fs.XTypeGroup(label: 'json', extensions: ['json']);
      final xfile = await fs.openFile(acceptedTypeGroups: [typeGroup]);
      if (xfile == null) return;
      // Ask user whether to merge or replace imported lists
      final choice = await showDialog<String?>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('import mode'),
          content: const Text(
              'import as merge (keep existing) or replace (overwrite all)?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop('cancel'),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop('merge'),
                child: const Text('Merge')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop('replace'),
                child: const Text('Replace')),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      final doMerge = choice == 'merge';

      // Show a blocking loading dialog during import
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: const Text('importing'),
            content: Row(
              children: [
                SizedBox(
                    width: 24, height: 24, child: CircularProgressIndicator()),
                const SizedBox(width: 16),
                const Expanded(child: Text('file...')),
              ],
            ),
          ),
        ),
      );

      try {
        await importAllListsFromJsonFile(xfile.path, merge: doMerge);
      } finally {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
    } catch (e, st) {
      unawaited(_debugLog('importViaChooser failed: $e\n$st'));
      try {
        _showTopToast('import failed');
      } catch (_) {}
    }
  }

  Future<void> _loadToday() async {
    await _loadList(_currentFile, _today);
    // If today is unexpectedly empty but a backup exists, restore it.
    try {
      if ((_today.isEmpty)) {
        final backupFile = await _fileFor('simplepresent_today.backup.json');
        if (await backupFile.exists()) {
          try {
            final text = await backupFile.readAsString();
            final data = jsonDecode(text) as List<dynamic>;
            if (data.isNotEmpty) {
              _today.clear();
              _today.addAll(data.map(TaskItem.fromJson));
              unawaited(_debugLog('restored today list from backup'));
              // Persist restored state to main today file.
              await _saveList(_storage('simplepresent_today.json'), _today);
              // Remove backup after successful restore.
              await backupFile.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    // Apply list-specific ordering only for display when opening a list.
    try {
      if (_currentFile == _storage('simplepresent_backlog.json')) {
        // Backlog: sort by scheduled date/time (earliest first).
        // Tasks without a schedule stay after scheduled tasks.
        // For equal keys, preserve original order to avoid visual jumping.
        final indexed = <MapEntry<int, TaskItem>>[];
        for (var i = 0; i < _today.length; i++) {
          indexed.add(MapEntry(i, _today[i]));
        }

        indexed.sort((a, b) {
          final aSched = a.value.scheduledAt;
          final bSched = b.value.scheduledAt;
          if (aSched != null && bSched != null) {
            final byDate = aSched.compareTo(bSched);
            if (byDate != 0) return byDate;
            return a.key.compareTo(b.key);
          }
          if (aSched != null) return -1;
          if (bSched != null) return 1;
          return a.key.compareTo(b.key);
        });

        _today
          ..clear()
          ..addAll(indexed.map((e) => e.value));
      } else if (_currentFile == _storage('simplepresent_done.json')) {
        // Sort done list by completion timestamp (newest first). Tasks without
        // `completedAt` are placed at the end, preserving relative order where
        // timestamps are equal.
        try {
          _today.sort((a, b) {
            final da = a.completedAt;
            final db = b.completedAt;
            if (da == null && db == null) return 0;
            if (da == null) return 1; // a after b
            if (db == null) return -1; // a before b
            return db.compareTo(da); // newest first
          });
        } catch (_) {}
      }
    } catch (_) {}
    setState(() {});
    // Ensure header counters are up to date
    unawaited(_updateListCounts());
    try {
      _lastPersistedToday.clear();
      for (final t in _today) {
        _lastPersistedToday[t.id] = t.toJson();
      }
    } catch (_) {}
  }

  Future<void> _saveToday() async {
    try {
      // Persist the currently loaded list (`_today` holds the in-memory
      // representation of whatever view is active). Use `_currentFile` so
      // saving operations write back to the correct file (today/backlog/done).
      await _saveList(_currentFile, _today);
      unawaited(_updateListCounts());

      // Update the snapshot after a successful save to keep last persisted
      // map in sync. Individual edit/create/delete actions are logged when
      // finalized elsewhere.
      try {
        _lastPersistedToday.clear();
        for (final t in _today) _lastPersistedToday[t.id] = t.toJson();
      } catch (_) {}
    } catch (_) {}
  }

  bool get _cloudSyncConfigured {
    return _cloudServerUrl.trim().isNotEmpty &&
        _cloudAccountId.trim().isNotEmpty &&
        _cloudDeviceId.trim().isNotEmpty &&
        _cloudToken.trim().isNotEmpty &&
        _cloudWordPhrase.trim().isNotEmpty;
  }

  void _queueCloudTimeEntrySync(TaskItem task) {
    if (!_cloudSyncConfigured || _applyingCloudState) return;

    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _cloudPendingTimeEntrySync['$date:${task.id}'] = task;
    _flushPendingCloudTimeEntrySync();
  }

  void _flushPendingCloudTimeEntrySync() {
    if (!_cloudSyncConfigured || _cloudSyncBusy || _applyingCloudState) return;
    if (_cloudPendingTimeEntrySync.isEmpty) return;
    unawaited(_runPendingCloudTimeEntrySync());
  }

  Future<void> _runPendingCloudTimeEntrySync() async {
    while (_cloudPendingTimeEntrySync.isNotEmpty &&
        _cloudSyncConfigured &&
        !_cloudSyncBusy &&
        !_applyingCloudState) {
      final entry = _cloudPendingTimeEntrySync.entries.first;
      _cloudPendingTimeEntrySync.remove(entry.key);
      final ok = await _syncPushTimeEntryToCloud(entry.value);
      if (!ok) {
        _cloudPendingTimeEntrySync[entry.key] = entry.value;
        break;
      }
    }
  }

  Future<bool> _syncPushTimeEntryToCloud(TaskItem task) async {
    if (!_cloudSyncConfigured ||
        _cloudSyncBusy ||
        _applyingCloudState ||
        _suppressCloudPushes) return false;
    _suppressSyncToasts = true;
    _cloudSyncBusy = true;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
        allowInsecureCertificates: _cloudAllowInsecureTls,
      );
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final modifiedAt = DateTime.now().millisecondsSinceEpoch;
      _cloudStateVersion += 1;

      final encryptedPayload = await CloudSyncClient.encryptStatePayload(
        payload: <String, dynamic>{
          'kind': 'time_entry',
          'date': date,
          'entry': <String, dynamic>{
            'task_id': task.id,
            'task_text': task.text,
            'task_done': task.done,
            'task_in_progress': task.inProgress,
            'stopwatch_seconds': task.stopwatchAccumulatedSeconds,
            'work_minutes': task.workMinutes,
            'recorded_at': modifiedAt,
          },
        },
        phrase: _cloudWordPhrase,
      );

      await client.pushItems(
        accountId: _cloudAccountId.trim(),
        token: _cloudToken.trim(),
        items: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'time:$date:${task.id}',
            'payload': encryptedPayload,
            'modified_at': modifiedAt,
            'tombstone': false,
            'origin_device_id': _cloudDeviceId.trim(),
            'version': _cloudStateVersion,
          }
        ],
      );

      // Note: do NOT update _cloudLastSyncModifiedAt here (see _syncPushToCloud).
      await _saveSettings();
      _onCloudSyncSuccess();
      return true;
    } catch (e) {
      _onCloudSyncError(e);
      return false;
    } finally {
      _cloudSyncBusy = false;
      _flushPendingCloudTimeEntrySync();
    }
  }

  // --- Push queue --------------------------------------------------------
  // Enqueues a cloud push for [filename] with [source] as the payload.
  // The latest snapshot for a given filename replaces any pending one
  // (last-write-wins per list), so rapid successive saves are collapsed.
  // A sequential drain loop then sends each pending list to the server
  // one at a time to avoid races.
  void _enqueuePush(String filename, List<TaskItem> source) {
    if (!_cloudSyncConfigured || _applyingCloudState || _suppressCloudPushes)
      return;
    if (_cloudListNameForFilename(filename) == null) return;
    _pendingCloudPushes[filename] = List<TaskItem>.from(source);
    if (!_cloudPushDrainRunning) {
      unawaited(_drainPushQueue());
    }
  }

  Future<void> _drainPushQueue() async {
    if (_cloudPushDrainRunning) return;
    _cloudPushDrainRunning = true;
    try {
      while (_pendingCloudPushes.isNotEmpty) {
        if (!mounted || !_cloudSyncConfigured) break;

        // Wait if a pull (or another sync) is in progress (max ~15 s).
        int waited = 0;
        while ((_cloudSyncBusy || _applyingCloudState) && waited < 15000) {
          await Future.delayed(const Duration(milliseconds: 400));
          waited += 400;
        }
        if (_cloudSyncBusy || _applyingCloudState) {
          // Still busy after timeout — give up for now, will retry next save.
          break;
        }

        final entry = _pendingCloudPushes.entries.first;
        _pendingCloudPushes.remove(entry.key);
        await _syncPushToCloud(entry.key, entry.value);
      }
    } catch (e) {
      await _debugLog('_drainPushQueue error: $e');
    } finally {
      _cloudPushDrainRunning = false;
      // Restart drain if new items arrived while we were finishing.
      if (_pendingCloudPushes.isNotEmpty && mounted && _cloudSyncConfigured) {
        unawaited(_drainPushQueue());
      }
    }
  }
  // -----------------------------------------------------------------------

  Future<void> _syncPushToCloud(String filename, List<TaskItem> source) async {
    if (!_cloudSyncConfigured ||
        _cloudSyncBusy ||
        _applyingCloudState ||
        _suppressCloudPushes) return;
    final listName = _cloudListNameForFilename(filename);
    if (listName == null) return;
    // Suppress toasts originating from sync operations.
    _suppressSyncToasts = true;
    _cloudSyncBusy = true;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
        allowInsecureCertificates: _cloudAllowInsecureTls,
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
        // Only send a tombstone if the task does NOT exist in any other list.
        //
        // Without this check, a move operation (e.g. backlog → today) would:
        //   1. Push today  → server stores task:X with list=today
        //   2. Push backlog → sees X missing from backlog, sends tombstone for
        //      task:X, which OVERWRITES the today entry → X appears deleted!
        //
        // We detect "moved, not deleted" by checking:
        //   a) _cloudKnownXxxIds for the other lists (already updated by
        //      earlier pushes in the same drain pass), and
        //   b) any pending push snapshots (for lists not yet pushed in this pass).
        final existsInOtherList = _allListNamesExcept(listName).any((other) {
          // Already-pushed list: check its known ID set.
          if (_knownIdSetForList(other).contains(removed)) return true;
          // Not yet pushed: check the pending snapshot if available.
          for (final pendingEntry in _pendingCloudPushes.entries) {
            if (_cloudListNameForFilename(pendingEntry.key) == other) {
              if (pendingEntry.value.any((t) => t.id == removed)) return true;
            }
          }
          return false;
        });
        if (existsInOtherList) continue; // Task was moved, not deleted.

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
      // Note: do NOT update _cloudLastSyncModifiedAt here.
      // Only _syncPullFromCloud advances this cursor so we never accidentally
      // skip changes from other devices that happened before our push.
      await _saveSettings();
      _onCloudSyncSuccess();
    } catch (e) {
      _onCloudSyncError(e);
    } finally {
      _cloudSyncBusy = false;
      _suppressSyncToasts = false;
      _flushPendingCloudTimeEntrySync();
    }
  }

  String? _cloudListNameForFilename(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('simplepresent_today') || lower.contains('/today'))
      return 'today';
    if (lower.contains('simplepresent_backlog') || lower.contains('/backlog'))
      return 'backlog';
    if (lower.contains('simplepresent_done') || lower.contains('/done'))
      return 'done';
    return null;
  }

  Set<String> _knownIdSetForList(String listName) {
    switch (listName) {
      case 'today':
        return _cloudKnownTodayIds;
      case 'backlog':
        return _cloudKnownBacklogIds;
      case 'done':
        return _cloudKnownDoneIds;
      default:
        return <String>{};
    }
  }

  /// Returns all known list names except [listName].
  List<String> _allListNamesExcept(String listName) {
    return ['today', 'backlog', 'done'].where((n) => n != listName).toList();
  }

  // Cloud syncing of redo-log entries has been removed.

  Future<bool> _syncPushNotes(String text) async {
    if (!_cloudSyncConfigured ||
        _cloudSyncBusy ||
        _applyingCloudState ||
        _suppressCloudPushes) return false;

    _cloudSyncBusy = true;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
        allowInsecureCertificates: _cloudAllowInsecureTls,
      );
      final modifiedAt = DateTime.now().millisecondsSinceEpoch;
      _cloudStateVersion += 1;

      final encryptedPayload = await CloudSyncClient.encryptStatePayload(
        payload: <String, dynamic>{
          'kind': 'notes',
          'text': text,
        },
        phrase: _cloudWordPhrase,
      );

      await client.pushItems(
        accountId: _cloudAccountId.trim(),
        token: _cloudToken.trim(),
        items: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'notes',
            'payload': encryptedPayload,
            'modified_at': modifiedAt,
            'tombstone': false,
            'origin_device_id': _cloudDeviceId.trim(),
            'version': _cloudStateVersion,
          }
        ],
      );

      // Note: do NOT update _cloudLastSyncModifiedAt here (see _syncPushToCloud).
      await _saveSettings();
      _onCloudSyncSuccess();
      return true;
    } catch (e) {
      _onCloudSyncError(e);
      return false;
    } finally {
      _cloudSyncBusy = false;
      _suppressSyncToasts = false;
    }
  }

  void _onCloudSyncSuccess() {
    _cloudLastSyncSuccessAt = DateTime.now().millisecondsSinceEpoch;
    _cloudSyncLastError = '';
    if (_cloudSyncFailed && mounted) {
      _cloudSyncFailed = false;
      _showTopToast('☁ Sync wiederhergestellt.');
    }
  }

  void _onCloudSyncError(Object e) {
    final msg = e.toString();
    final short = msg.contains('SocketException') ||
            msg.contains('Connection refused') ||
            msg.contains('Failed host lookup')
        ? 'Server nicht erreichbar.'
        : msg.contains('HandshakeException') ||
                msg.contains('CERTIFICATE_VERIFY_FAILED')
            ? 'TLS-Handshake fehlgeschlagen. Zertifikat/CA pruefen (oder unsichere Zertifikate erlauben).'
            : msg.contains('missing bearer token')
                ? 'Sync: Authentifizierung fehlgeschlagen (Authorization-Header fehlt, Proxy-Konfiguration pruefen).'
                : msg.contains('401') || msg.contains('403')
                    ? 'Sync: Authentifizierung fehlgeschlagen.'
                    : msg.contains('Server error')
                        ? 'Sync: Server-Fehler.'
                        : 'Sync fehlgeschlagen.';
    _cloudSyncLastError = short;
    if (!_cloudSyncFailed && mounted) {
      _cloudSyncFailed = true;
      _showTopToast('☁ $short');
    }
  }

  String _cloudSyncStatusTooltip() {
    if (!_cloudSyncConfigured) {
      return 'cloud-sync is not configured';
    }
    if (_cloudSyncBusy) {
      return 'synchronization in progress...';
    }
    final lastSuccess = _cloudLastSyncSuccessAt > 0
        ? DateFormat('yyyy-MM-dd HH:mm:ss').format(
            DateTime.fromMillisecondsSinceEpoch(_cloudLastSyncSuccessAt),
          )
        : null;
    if (_cloudSyncFailed) {
      final reason = _cloudSyncLastError.isNotEmpty
          ? _cloudSyncLastError
          : 'unknown error';
      if (lastSuccess != null) {
        return 'synchronization failed\n$reason\nlast successful: $lastSuccess';
      }
      return 'synchronization failed\n$reason';
    }
    if (lastSuccess != null) {
      return 'synchronization ok\nlast synchronized: $lastSuccess';
    }
    return 'not yet synchronized.';
  }

  Color _cloudSyncStatusColor(ColorScheme scheme) {
    if (!_cloudSyncConfigured) return scheme.outline;
    if (_cloudSyncBusy) return Colors.amberAccent;
    if (_cloudSyncFailed) return Colors.redAccent;
    if (_cloudLastSyncSuccessAt > 0) return Colors.lightGreenAccent;
    return scheme.outline;
  }

  Future<void> _manualSyncNow() async {
    if (!_cloudSyncConfigured) {
      _showTopToast('cloud-sync is not configured');
      return;
    }
    if (_cloudSyncBusy) {
      _showTopToast('synchronization in progress...');
      return;
    }

    // Cancel any pending debounced auto-pushes – we're doing a full sync now.
    _pendingCloudPushes.clear();

    // Finalize any open edits so they get logged as a single entry.
    try {
      await _finalizeAllEdits();
    } catch (_) {}

    _suppressSyncToasts = true;
    try {
      _showTopToast('synchronizing...');

      // Step 1: Load all local lists and notes from disk.
      final todayFile = _storage('simplepresent_today.json');
      final backlogFile = _storage('simplepresent_backlog.json');
      final doneFile = _storage('simplepresent_done.json');
      final notesFile = await _fileFor(_storage('simplepresent_notes.txt'));

      final todayList = <TaskItem>[];
      final backlogList = <TaskItem>[];
      final doneList = <TaskItem>[];

      await Future.wait([
        _loadList(todayFile, todayList),
        _loadList(backlogFile, backlogList),
        _loadList(doneFile, doneList),
      ]);

      String notesText = '';
      try {
        if (await notesFile.exists()) {
          notesText = await notesFile.readAsString();
        }
      } catch (_) {}

      // Step 2: Push all 3 lists SEQUENTIALLY.
      // Parallel pushes are broken because _cloudSyncBusy blocks the 2nd + 3rd.
      await _syncPushToCloud(todayFile, todayList);
      await _syncPushToCloud(backlogFile, backlogList);
      await _syncPushToCloud(doneFile, doneList);

      // Step 3: Push notes if non-empty.
      if (notesText.isNotEmpty) {
        await _syncPushNotes(notesText);
      }

      // Step 4: Push all pending time-entries (drain the queue completely).
      while (_cloudPendingTimeEntrySync.isNotEmpty) {
        final entry = _cloudPendingTimeEntrySync.entries.first;
        _cloudPendingTimeEntrySync.remove(entry.key);
        try {
          await _syncPushTimeEntryToCloud(entry.value);
        } catch (_) {
          // Re-enqueue on failure, will retry on next manual sync.
          _cloudPendingTimeEntrySync[entry.key] = entry.value;
          break;
        }
      }

      // Step 5: Pull full remote state (since=0 ensures we never miss changes
      // from other devices that were pushed before our push timestamp).
      _cloudLastSyncModifiedAt = 0;
      await _syncPullFromCloud();

      // Step 6: Fetch server version
      await _fetchServerVersion();

      // Step 7: Reload current view
      await _loadToday();

      _showTopToast('synchronization completed');
    } catch (e) {
      _showTopToast('synchronization failed');
    } finally {
      _suppressSyncToasts = false;
    }
  }

  Future<void> _fetchServerVersion() async {
    if (_cloudServerUrl.trim().isEmpty) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
        allowInsecureCertificates: _cloudAllowInsecureTls,
      );
      final health = await client.getHealth();
      if (health != null && mounted) {
        final isOutdated = _isClientOlderThanServer(kClientVersion, health);
        if (isOutdated && !_versionWarningShown) {
          _versionWarningShown = true;
          _showTopToast(
              'warning: client-version $kClientVersion is older than server-version $health.');
        }
      }
    } catch (_) {
      // Fehler beim Abrufen der Version ignorieren
    }
  }

  Future<void> _refreshCloudAccountStatus({
    bool showToastIfWarning = false,
  }) async {
    if (!_cloudSyncConfigured) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
        allowInsecureCertificates: _cloudAllowInsecureTls,
      );
      final status = await client.getAccountStatus(token: _cloudToken.trim());
      final days = status.daysUntilArchive;

      if (showToastIfWarning &&
          status.warning &&
          days >= 0 &&
          _cloudArchiveLastWarnedDays != days) {
        _cloudArchiveLastWarnedDays = days;
        _showTopToast(
            'cloud notice: archiving in $days days without activity.');
      }
      if (showToastIfWarning && status.archived) {
        _showTopToast('cloud account is archived.');
      }
    } catch (_) {
      // Optionaler Status-Endpunkt, Fehler hier sollen normalen Sync nicht blockieren.
    }
  }

  Future<void> _syncPullFromCloud() async {
    if (!_cloudSyncConfigured) {
      unawaited(_debugLog('syncPullFromCloud: skip - not configured'));
      return;
    }
    if (_cloudSyncBusy) {
      unawaited(_debugLog('syncPullFromCloud: skip - already busy'));
      return;
    }
    unawaited(_debugLog('syncPullFromCloud: start'));
    final sw = Stopwatch()..start();
    // Finalize any open edits before applying remote state
    try {
      await _finalizeAllEdits();
    } catch (_) {}
    // Suppress toasts triggered by cloud sync actions while applying state.
    _suppressSyncToasts = true;
    _cloudSyncBusy = true;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _cloudServerUrl.trim(),
        allowInsecureCertificates: _cloudAllowInsecureTls,
      );
      final pulledItems = await client.pullChangedItems(
        token: _cloudToken.trim(),
        since: _cloudLastSyncModifiedAt,
        idPrefix: '',
      );
      await _refreshCloudAccountStatus(showToastIfWarning: true);
      if (pulledItems.isEmpty) {
        // Nothing new from server — still counts as a successful contact.
        _onCloudSyncSuccess();
        return;
      }

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
      try {
        for (final item in pulledItems) {
          if (item.modifiedAt > maxModifiedAt) maxModifiedAt = item.modifiedAt;
          if (item.version > _cloudStateVersion)
            _cloudStateVersion = item.version;

          final taskId =
              item.id.startsWith('task:') ? item.id.substring(5) : item.id;
          if (taskId.isEmpty) continue;

          if (item.tombstone) {
            if (item.id.startsWith('task:')) {
              for (final list in listMap.values) {
                list.removeWhere((t) => t.id == taskId);
              }
              _cloudKnownTodayIds.remove(taskId);
              _cloudKnownBacklogIds.remove(taskId);
              _cloudKnownDoneIds.remove(taskId);
            }
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

          final kind = (payload['kind'] ?? '').toString();
          if (kind == 'notes') {
            final incomingText = (payload['text'] ?? '').toString();
            try {
              final notesFile =
                  await _fileFor(_storage('simplepresent_notes.txt'));
              final localModified = await (await notesFile.exists())
                  ? (await notesFile.lastModified()).millisecondsSinceEpoch
                  : 0;
              if (item.modifiedAt > localModified ||
                  (localModified == 0 && incomingText.isNotEmpty)) {
                try {
                  await notesFile.writeAsString(incomingText);
                  if (mounted) _showTopToast('notes updated from cloud');
                } catch (_) {}
              }
            } catch (_) {}
            continue;
          }
          if (item.id.startsWith('time:') || kind == 'time_entry') {
            final entryRaw = payload['entry'];
            final entry =
                entryRaw is Map ? Map<String, dynamic>.from(entryRaw) : payload;
            final date = (payload['date'] ?? entry['date'] ?? '').toString();
            final entryTaskId = (entry['task_id'] ?? '').toString();
            final entryTaskText = (entry['task_text'] ?? '').toString();
            if (date.isEmpty || entryTaskId.isEmpty) continue;
            _sembastStorage.upsertTimeEntry(
              taskId: entryTaskId,
              taskText: entryTaskText,
              date: date,
              taskDone: entry['task_done'] == true || entry['task_done'] == 1,
              taskInProgress: entry['task_in_progress'] == true ||
                  entry['task_in_progress'] == 1,
              stopwatchSeconds: (entry['stopwatch_seconds'] is num)
                  ? (entry['stopwatch_seconds'] as num).toInt()
                  : int.tryParse(
                          entry['stopwatch_seconds']?.toString() ?? '') ??
                      0,
              workMinutes: (entry['work_minutes'] is num)
                  ? (entry['work_minutes'] as num).toInt()
                  : int.tryParse(entry['work_minutes']?.toString() ?? '') ?? 0,
              recordedAt: (entry['recorded_at'] is num)
                  ? (entry['recorded_at'] as num).toInt()
                  : int.tryParse(entry['recorded_at']?.toString() ?? ''),
            );
            continue;
          }

          final taskRaw = payload['task'];
          final listName = (payload['list'] ?? '').toString();
          final position = (payload['position'] is num)
              ? (payload['position'] as num).toInt()
              : int.tryParse(payload['position']?.toString() ?? '') ?? 0;
          if (taskRaw is! Map || !listMap.containsKey(listName)) continue;

          final task = TaskItem.fromJson(Map<String, dynamic>.from(taskRaw));

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

        await _queueReplaceList(_storage('simplepresent_today.json'), today);
        await _queueReplaceList(
            _storage('simplepresent_backlog.json'), backlog);
        await _queueReplaceList(_storage('simplepresent_done.json'), done);
        await _loadToday();
        _cloudKnownTodayIds
          ..clear()
          ..addAll(today.map((t) => t.id));
        _cloudKnownBacklogIds
          ..clear()
          ..addAll(backlog.map((t) => t.id));
        _cloudKnownDoneIds
          ..clear()
          ..addAll(done.map((t) => t.id));
        try {
          await _saveSettings();
        } catch (_) {}
      } finally {
        _applyingCloudState = false;
      }

      _cloudLastSyncModifiedAt = maxModifiedAt;
      await _saveSettings();
      _onCloudSyncSuccess();
    } catch (e, st) {
      unawaited(_debugLog('syncPullFromCloud: error $e\n$st'));
      _onCloudSyncError(e);
    } finally {
      _cloudSyncBusy = false;
      _suppressSyncToasts = false;
      _flushPendingCloudTimeEntrySync();
      // Restart drain queue for any pushes that were waiting for the pull.
      if (_pendingCloudPushes.isNotEmpty &&
          !_cloudPushDrainRunning &&
          mounted) {
        unawaited(_drainPushQueue());
      }
      sw.stop();
      unawaited(_debugLog(
          'syncPullFromCloud: finished in ${sw.elapsedMilliseconds}ms'));
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
    for (final id in _editControllers.keys) {
      try {
        _autosaveTimers[id]?.cancel();
      } catch (_) {}
    }
    _autosaveTimers.clear();
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
    for (final id in _editControllers.keys) {
      try {
        _autosaveTimers[id]?.cancel();
      } catch (_) {}
    }
    _autosaveTimers.clear();
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
    // Order: 0 = today, 1 = backlog (Done is not part of the carousel)
    final idx =
        _showingBacklog ? 1 : 0; // treat _showingDone as today for cycling
    final next = (idx + 1) % 2; // toggle between 0 and 1
    if (next == 0) {
      await _switchFile(false);
    } else {
      await _switchToBacklog();
    }
  }

  Future<void> _loadSettings() async {
    try {
      final data = await _readSettingsMap();
      if (data.isEmpty) return;

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
          // Respect persisted value but cap to a small maximum so tiles stay minimal
          setState(() => _tileHeight = math.min(v.toDouble(), 16.0));
        }
      }
      if (data.containsKey('fontScale')) {
        // persisted fontScale ignored (task zoom disabled)
      }
      setState(() {
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
        _scheduledReminderSoundEnabled = readBool(
            'scheduledReminderSoundEnabled', _scheduledReminderSoundEnabled);
        _urgentSoundEnabled =
            readBool('urgentSoundEnabled', _urgentSoundEnabled);
        _urgentNotifyEnabled =
            readBool('urgentNotifyEnabled', _urgentNotifyEnabled);
        _urgentFlashEnabled =
            readBool('urgentFlashEnabled', _urgentFlashEnabled);
        _urgentBringToFrontEnabled =
            readBool('urgentBringToFrontEnabled', _urgentBringToFrontEnabled);
        _swipeEnabled = readBool('swipeEnabled', _swipeEnabled);
        _autoPurgeDoneEnabled =
            readBool('autoPurgeDoneEnabled', _autoPurgeDoneEnabled);
        // Automatic export (backups)
        _autoExportOnStart = readBool('autoExportOnStart', _autoExportOnStart);
        _autoExportIntervalMinutes =
            readInt('autoExportIntervalMinutes', _autoExportIntervalMinutes);
        final aet = data['autoExportTimes'];
        if (aet is List) {
          _autoExportTimes = aet.map((e) => e.toString()).toList();
        }
        final lastChk = data['lastAutoExportChecksum'];
        if (lastChk is String) _lastAutoExportChecksum = lastChk;
        _autoExportMaxBackups =
            readInt('autoExportMaxBackups', _autoExportMaxBackups);
        _doneRetentionDays = readInt('doneRetentionDays', _doneRetentionDays);
        // Restore persisted UI text scale factor if present
        _uiTextScaleFactor = _clampUiTextScaleFactor(
            readDouble('uiTextScaleFactor', _uiTextScaleFactor));
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
        if (deviceName is String) {
          _cloudDeviceName = _normalizeCloudDeviceName(deviceName);
        }
        final cloudPin = data['cloudPIN'];
        if (cloudPin is String) {
          _cloudPIN = cloudPin;
        }
        _cloudAllowInsecureTls =
            readBool('cloudAllowInsecureTls', _cloudAllowInsecureTls);
        final cloudVersion = data['cloudStateVersion'];
        if (cloudVersion is num) {
          _cloudStateVersion = cloudVersion.toInt();
        }
        final cloudModifiedAt = data['cloudLastSyncModifiedAt'];
        if (cloudModifiedAt is num) {
          _cloudLastSyncModifiedAt = cloudModifiedAt.toInt();
        }
        final cloudLastSuccessAt = data['cloudLastSyncSuccessAt'];
        if (cloudLastSuccessAt is num) {
          _cloudLastSyncSuccessAt = cloudLastSuccessAt.toInt();
        }
        _cloudSyncFailed = readBool('cloudSyncFailed', _cloudSyncFailed);
        final cloudSyncLastError = data['cloudSyncLastError'];
        if (cloudSyncLastError is String) {
          _cloudSyncLastError = cloudSyncLastError;
        }
        final knownToday = data['cloudKnownTodayIds'];
        if (knownToday is List) {
          _cloudKnownTodayIds = knownToday.map((e) => e.toString()).toSet();
        }
        final knownBacklog = data['cloudKnownBacklogIds'];
        if (knownBacklog is List) {
          _cloudKnownBacklogIds = knownBacklog.map((e) => e.toString()).toSet();
        }
        final knownDone = data['cloudKnownDoneIds'];
        if (knownDone is List) {
          _cloudKnownDoneIds = knownDone.map((e) => e.toString()).toSet();
        }
        // Optional storage path override
        final storagePath = data['storagePath'];
        if (storagePath is String && storagePath.isNotEmpty) {
          _storagePathOverride = storagePath;
        }
        // Optional debug write logging
        _debugWriteLog = readBool('debugWriteLog', _debugWriteLog);
        // If debug logging is enabled in settings, create an initial entry
        // so the logfile appears immediately for debugging verification.
        try {
          if (_debugWriteLog) unawaited(_debugLog('debugWriteLog enabled'));
        } catch (_) {}
        final rwFrom = data['reminderWindowFrom'];
        if (rwFrom is String && rwFrom.isNotEmpty) {
          _reminderWindowFrom = rwFrom;
        }
        final rwTo = data['reminderWindowTo'];
        if (rwTo is String && rwTo.isNotEmpty) {
          _reminderWindowTo = rwTo;
        }
        // Load dynamic inactivity reminders if present; otherwise default to empty
        if (data.containsKey('inactivityReminders')) {
          final list = data['inactivityReminders'];
          if (list is List) {
            _inactivityReminders = list.map((e) {
              if (e is Map) return Map<String, dynamic>.from(e);
              return <String, dynamic>{};
            }).toList();
          }
        }
      });
      // Do not restore persisted window geometry or position; OS/window manager
      // determines position. Size is set once on startup elsewhere.
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
          // load optional counters thresholds
          final mt = data['maxTasksToday'];
          if (mt is num) _maxTasksToday = mt.toInt();
          final mb = data['maxTasksBacklog'];
          if (mb is num) _maxTasksBacklog = mb.toInt();
        }
      } catch (_) {}
    } catch (_) {}
  }

  // Window geometry restoration removed — position and persisted geometry
  // handling is disabled.

  Future<void> _saveSettings() async {
    await _saveSettingsWithGeom(null);
  }

  Future<void> _saveSettingsWithGeom(Map<String, dynamic>? geom) async {
    try {
      final out = <String, dynamic>{
        'tileHeight': _tileHeight,
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
        'uiTextScaleFactor': _uiTextScaleFactor,
        'fontFamily': _fontFamily,
        'cloudServerUrl': _cloudServerUrl,
        'cloudAccountId': _cloudAccountId,
        'cloudDeviceId': _cloudDeviceId,
        'cloudToken': _cloudToken,
        'cloudWordPhrase': _cloudWordPhrase,
        'cloudDeviceName': _cloudDeviceName,
        'cloudPIN': _cloudPIN,
        'cloudAllowInsecureTls': _cloudAllowInsecureTls,
        'cloudStateVersion': _cloudStateVersion,
        'cloudLastSyncModifiedAt': _cloudLastSyncModifiedAt,
        'cloudLastSyncSuccessAt': _cloudLastSyncSuccessAt,
        'cloudSyncFailed': _cloudSyncFailed,
        'cloudSyncLastError': _cloudSyncLastError,
        'cloudKnownTodayIds': _cloudKnownTodayIds.toList(),
        'cloudKnownBacklogIds': _cloudKnownBacklogIds.toList(),
        'cloudKnownDoneIds': _cloudKnownDoneIds.toList(),
        'scheduledReminderSoundEnabled': _scheduledReminderSoundEnabled,
        'reminderWindowFrom': _reminderWindowFrom,
        'reminderWindowTo': _reminderWindowTo,
        'inactivityReminders': _inactivityReminders,
        'autoPurgeDoneEnabled': _autoPurgeDoneEnabled,
        'doneRetentionDays': _doneRetentionDays,
        'maxTasksToday': _maxTasksToday,
        'maxTasksBacklog': _maxTasksBacklog,
        // Optional override for storage location
        'storagePath': _storagePathOverride ?? '',
        // Enable debug logging of write operations
        'debugWriteLog': _debugWriteLog,
        // Automatic export (backups)
        'autoExportOnStart': _autoExportOnStart,
        'autoExportIntervalMinutes': _autoExportIntervalMinutes,
        'autoExportTimes': _autoExportTimes,
        'autoExportMaxBackups': _autoExportMaxBackups,
        'lastAutoExportChecksum': _lastAutoExportChecksum,
      };

      // Do not capture or persist window geometry or position.
      // Persist current notification flags as lists so restarts don't re-notify
      out['notified15'] = _notified15.toList();
      out['notifiedDue'] = _notifiedDue.toList();
      await _writeSettingsMap(out);
      await _refreshAndroidTodayWidget();
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    // Try to finalize any pending edits before dispose (best-effort)
    try {
      unawaited(_finalizeAllEdits());
    } catch (_) {}
    try {
      HardwareKeyboard.instance.removeHandler(_hardwareKeyHandler);
    } catch (_) {}
    _windowWatcherTimer?.cancel();
    _saveSettings();
    _controller.dispose();
    try {
      _doneSearchController.dispose();
    } catch (_) {}
    _inputFocus.dispose();
    _audioPlayer.dispose();
    _idleTimer?.cancel();
    _attentionTimer?.cancel();
    _reminderTimer?.cancel();
    _urgentTimer?.cancel();
    for (final t in _inactivityTimers) {
      try {
        t?.cancel();
      } catch (_) {}
    }
    try {
      _autoExportIntervalTimer?.cancel();
    } catch (_) {}
    for (final t in _autoExportTimeTimers) {
      try {
        t.cancel();
      } catch (_) {}
    }
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
    try {
      _listScrollController.dispose();
    } catch (_) {}
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _stopwatchTicker?.cancel();
    _sembastStorage.dispose();
    super.dispose();
  }

  // Minimal view mode removed: `_minimalViewMode` is fixed to `false`.

  String _taskNotifyKey(TaskItem t) {
    final sched = t.scheduledAt?.toIso8601String() ?? '';
    return '${t.id}|$sched';
  }

  void _startScheduledChecker() {
    _scheduledCheckTimer?.cancel();
    _scheduledCheckTimer =
        Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_initializationComplete) return;
      await _promoteDueBacklogToToday(showToast: false);
      final now = DateTime.now();
      for (final t in _today) {
        // Do not remind for tasks without schedule or already completed
        if (t.scheduledAt == null) continue;
        if (t.done) continue;
        final diff = t.scheduledAt!.difference(now);
        final key = _taskNotifyKey(t);
        // 15-minute warning removed per user request
        // At due time or overdue (first time)
        // Do not fire reminders for tasks that were already due before the
        // application was started (avoid popping reminders on app start).
        if (t.scheduledAt!.isBefore(_appStartedAt)) continue;

        if (diff.inSeconds <= 0 && !_notifiedDue.contains(key)) {
          _notifiedDue.add(key);
          try {
            if (_scheduledReminderSoundEnabled) {
              await _playShortSound('sounds/pop.mp3', alert: false);
            }
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('notify', <String, String>{
              //'title': _appTitle,
              'title': '',
              'body': '${t.text}',
              'icon': 'assets/icons/color_transparent_icon.png',
              'taskId': t.id,
            });
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('bringToFront');
          } catch (_) {}
          // Persist notified flags so restart doesn't re-notify
          try {
            await _saveSettings();
          } catch (_) {}
        }
      }
    });
  }

  bool _isWithinReminderWindow(DateTime now) {
    try {
      int parseMin(String s) {
        final p = s.split(':');
        final h = int.tryParse(p[0]) ?? 0;
        final m = int.tryParse(p[1]) ?? 0;
        return h * 60 + m;
      }

      final from = parseMin(_reminderWindowFrom);
      final to = parseMin(_reminderWindowTo);
      final nowMin = now.hour * 60 + now.minute;
      if (from <= to) {
        return nowMin >= from && nowMin <= to;
      }
      // overnight window (e.g. 22:00 - 06:00)
      return nowMin >= from || nowMin <= to;
    } catch (_) {
      return true; // on parse error, default to allow
    }
  }

  Duration _durationUntilNextWindowStart(DateTime now) {
    try {
      final pFrom = _reminderWindowFrom.split(':');
      final fh = int.tryParse(pFrom[0]) ?? 9;
      final fm = int.tryParse(pFrom[1]) ?? 0;
      final start = DateTime(now.year, now.month, now.day, fh, fm);
      if (now.isBefore(start)) return start.difference(now);
      final next = start.add(const Duration(days: 1));
      return next.difference(now);
    } catch (_) {
      return const Duration(minutes: 1);
    }
  }

  Future<void> _performAutoExport() async {
    if (_autoExportRunning) return;
    _autoExportRunning = true;
    try {
      // Build deterministic export JSON (no timestamp) and skip if unchanged
      final exportJsonDet = await _buildExportJsonString();
      final chk = _computeFnv1a64(exportJsonDet);
      if (chk == _lastAutoExportChecksum) {
        unawaited(_debugLog('autoExport skipped: no changes'));
        return;
      }
      final dir = await _appDir;
      final exportDir = Directory('${dir.path}/simplepresent-exports');
      if (!await exportDir.exists()) await exportDir.create(recursive: true);
      final now = DateTime.now();
      final fileName =
          'simplepresent-backup-${DateFormat('yyyyMMdd-HHmmss').format(now)}.json';
      final path = p.join(exportDir.path, fileName);
      final f = File(path);
      await f.create(recursive: true);
      // Add a timestamp only to the written file (do not include it in checksum)
      try {
        final Map<String, dynamic> out = jsonDecode(exportJsonDet);
        out['exportedAt'] = DateTime.now().toIso8601String();
        final finalJson = const JsonEncoder.withIndent('  ').convert(out);
        await f.writeAsString(finalJson);
      } catch (_) {
        // fallback to writing the deterministic export if something goes wrong
        await f.writeAsString(exportJsonDet);
      }
      // enforce max backups retention
      try {
        if (_autoExportMaxBackups > 0) {
          final files = await exportDir
              .list()
              .where((e) =>
                  e is File &&
                  p.basename(e.path).startsWith('simplepresent-backup-') &&
                  e.path.endsWith('.json'))
              .cast<File>()
              .toList();
          files.sort((a, b) => a.path.compareTo(b.path));
          final excess = files.length - _autoExportMaxBackups;
          if (excess > 0) {
            for (var i = 0; i < excess; i++) {
              try {
                await files[i].delete();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
      // Intentionally do not show a toast for automatic backups.
      // update stored checksum
      _lastAutoExportChecksum = chk;
      unawaited(_saveSettings());
    } catch (e, st) {
      unawaited(_debugLog('autoExport failed: $e\n$st'));
    } finally {
      _autoExportRunning = false;
    }
  }

  void _startAutoExportTimers() {
    // cancel existing
    try {
      _autoExportIntervalTimer?.cancel();
    } catch (_) {}
    for (final t in _autoExportTimeTimers) {
      try {
        t.cancel();
      } catch (_) {}
    }
    _autoExportTimeTimers.clear();

    if (_autoExportIntervalMinutes > 0) {
      _autoExportIntervalTimer = Timer.periodic(
          Duration(minutes: _autoExportIntervalMinutes), (_) async {
        if (!_initializationComplete) return;
        await _performAutoExport();
      });
    }

    for (final hhmm in _autoExportTimes) {
      try {
        final parts = hhmm.split(':');
        if (parts.length != 2) continue;
        final h = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        final now = DateTime.now();
        var scheduled = DateTime(now.year, now.month, now.day, h, m);
        if (!scheduled.isAfter(now))
          scheduled = scheduled.add(const Duration(days: 1));
        final delay = scheduled.difference(now);
        final timer = Timer(delay, () async {
          if (_initializationComplete) await _performAutoExport();
          // reschedule for next day
          try {
            final next =
                DateTime(scheduled.year, scheduled.month, scheduled.day, h, m)
                    .add(const Duration(days: 1));
            final nextDelay = next.difference(DateTime.now());
            final t2 = Timer(nextDelay, () async {
              if (_initializationComplete) await _performAutoExport();
              _startAutoExportTimers();
            });
            _autoExportTimeTimers.add(t2);
          } catch (_) {}
        });
        _autoExportTimeTimers.add(timer);
      } catch (_) {}
    }
  }

  Future<String> _buildExportJsonString() async {
    final List<TaskItem> todayList = [];
    final List<TaskItem> backlogList = [];
    final List<TaskItem> doneList = [];
    final List<TaskItem> trashList = [];
    await _loadList(_storage('simplepresent_today.json'), todayList);
    await _loadList(_storage('simplepresent_backlog.json'), backlogList);
    await _loadList(_storage('simplepresent_done.json'), doneList);
    await _loadList('simplepresent_trash.json', trashList);
    final Map<String, dynamic> exportData = {
      'today': todayList.map((t) => t.toJson()).toList(),
      'backlog': backlogList.map((t) => t.toJson()).toList(),
      'done': doneList.map((t) => t.toJson()).toList(),
      'trash': trashList.map((t) => t.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  String _computeFnv1a64(String s) {
    // simple FNV-1a 64-bit implementation returning hex string.
    final bytes = utf8.encode(s);
    const int fnvOffset = 0xcbf29ce484222325;
    const int fnvPrime = 0x100000001b3;
    var hash = fnvOffset;
    for (final b in bytes) {
      hash ^= b;
      // Dart int is arbitrary precision; mask to 64-bit
      hash = (hash * fnvPrime) & 0xffffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0');
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
    final id = _today[index].id;
    return _queueTaskAction(id, () async {
      final idx = _today.indexWhere((t) => t.id == id);
      if (idx == -1) return;
      final t = _today[idx];
      if (t.stopwatchRunning) return;
      final now = DateTime.now();
      // Enforce `inProgress` flag when stopwatch is running or inProgressAt exists.
      for (var i = 0; i < _today.length; i++) {
        final tt = _today[i];
        if ((tt.stopwatchRunning || tt.inProgressAt != null) &&
            !tt.inProgress &&
            !tt.done) {
          final inferredAt = tt.inProgressAt ?? tt.stopwatchStartedAt ?? now;
          try {
            unawaited(_queueTaskAction(tt.id, () async {
              final j = _today.indexWhere((t) => t.id == tt.id);
              if (j == -1) return;
              setState(() => _today[j] = _today[j]
                  .copyWith(inProgress: true, inProgressAt: inferredAt));
              await _saveToday();
            }));
          } catch (_) {}
        }
      }
      final before = _today[idx];
      final after = before.copyWith(
          stopwatchRunning: true,
          stopwatchStartedAt: now,
          inProgress: true,
          inProgressAt: now);
      setState(() => _today[idx] = after);
      unawaited(_appendRedoLog('stopwatch_start',
          taskId: before.id,
          details: {'before': before.toJson(), 'after': after.toJson()}));
      // Clear any staged toggle for this task since we applied it directly
      _stagedInProgress.remove(t.id);
      await _saveToday();
      _scheduleDelayedReorder();
      _registerActivity();
    });
  }

  Future<void> _stopStopwatch(int index) async {
    final id = _today[index].id;
    return _queueTaskAction(id, () async {
      final idx = _today.indexWhere((t) => t.id == id);
      if (idx == -1) return;
      final t = _today[idx];
      if (!t.stopwatchRunning) return;
      final started = t.stopwatchStartedAt ?? DateTime.now();
      final added = DateTime.now().difference(started).inSeconds;
      final newAccum = t.stopwatchAccumulatedSeconds + added;
      final before = _today[idx];
      final after = before.copyWith(
          stopwatchRunning: false,
          stopwatchStartedAt: null,
          stopwatchAccumulatedSeconds: newAccum);
      setState(() => _today[idx] = after);
      unawaited(_appendRedoLog('stopwatch_stop',
          taskId: before.id,
          details: {'before': before.toJson(), 'after': after.toJson()}));
      await _saveToday();
      _scheduleDelayedReorder();
      _upsertTimeEntry(_today[idx]);
    });
  }

  Future<void> _resetStopwatch(int index) async {
    final id = _today[index].id;
    return _queueTaskAction(id, () async {
      final idx = _today.indexWhere((t) => t.id == id);
      if (idx == -1) return;
      final t = _today[idx];
      final before = t;
      final after = t.copyWith(
          stopwatchRunning: false,
          stopwatchStartedAt: null,
          stopwatchAccumulatedSeconds: 0);
      setState(() => _today[idx] = after);
      unawaited(_appendRedoLog('stopwatch_reset',
          taskId: before.id,
          details: {'before': before.toJson(), 'after': after.toJson()}));
      await _saveToday();
    });
  }

  // Window watcher and magnet/snapping behavior removed.

  Future<void> _openStats() async {
    final List<TaskItem> doneList = [];
    await _loadList(_storage('simplepresent_done.json'), doneList);

    // Normalize: tasks marked done but missing completedAt are considered completed now
    final normalized = doneList.map((t) {
      if (t.done && t.completedAt == null) {
        return t.copyWith(completedAt: DateTime.now());
      }
      return t;
    }).toList();

    // Load all time entries from DB for all known dates, so the stats page
    // can show historical data regardless of where the task currently lives.
    List<TimeEntry> allTimeEntries = [];
    if (_useSembast) {
      try {
        final dates = _sembastStorage.getTimeEntryDates();
        for (final date in dates) {
          final rows = _sembastStorage.getTimeEntriesForDate(date);
          for (final row in rows) {
            allTimeEntries.add(TimeEntry(
              taskId: row['task_id'] as String,
              taskText: row['task_text'] as String,
              date: date,
              taskDone: (row['task_done'] as int?) == 1,
              taskInProgress: (row['task_in_progress'] as int?) == 1,
              stopwatchSeconds: (row['stopwatch_seconds'] as int?) ?? 0,
              workMinutes: (row['work_minutes'] as int?) ?? 0,
            ));
          }
        }
      } catch (_) {}
    }

    // Also include in-memory tasks with tracked time for today that may not
    // have been written to the DB yet (e.g. running stopwatch).
    if (!_useSembast) {
      final List<TaskItem> todayList = [];
      final List<TaskItem> backlogList = [];
      await _loadList(_storage('simplepresent_today.json'), todayList);
      await _loadList(_storage('simplepresent_backlog.json'), backlogList);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      for (final t in [...todayList, ...backlogList]) {
        final hasTime = t.stopwatchAccumulatedSeconds > 0 || t.workMinutes > 0;
        if (!hasTime) continue;
        allTimeEntries.add(TimeEntry(
          taskId: t.id,
          taskText: t.text,
          date: today,
          taskDone: t.done,
          taskInProgress: t.inProgress,
          stopwatchSeconds: t.stopwatchAccumulatedSeconds,
          workMinutes: t.workMinutes,
        ));
      }
    }

    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => StatsPage(
              doneList: normalized,
              timeEntries: allTimeEntries,
              textScale: _uiTextScaleFactor,
            )));
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
            'uiTextScaleFactor': _uiTextScaleFactor,
            'fontFamily': _fontFamily,
            'cloudServerUrl': _cloudServerUrl,
            'cloudAccountId': _cloudAccountId,
            'cloudDeviceId': _cloudDeviceId,
            'cloudToken': _cloudToken,
            'cloudWordPhrase': _cloudWordPhrase,
            'cloudDeviceName': _cloudDeviceName,
            'cloudPIN': _cloudPIN,
            'cloudAllowInsecureTls': _cloudAllowInsecureTls,
            'cloudLastSyncSuccessAt': _cloudLastSyncSuccessAt,
            'cloudSyncFailed': _cloudSyncFailed,
            'cloudSyncLastError': _cloudSyncLastError,
            'scheduledReminderSoundEnabled': _scheduledReminderSoundEnabled,
            'reminderWindowFrom': _reminderWindowFrom,
            'reminderWindowTo': _reminderWindowTo,
            'autoPurgeDoneEnabled': _autoPurgeDoneEnabled,
            'doneRetentionDays': _doneRetentionDays,
            'maxTasksToday': _maxTasksToday,
            'maxTasksBacklog': _maxTasksBacklog,
          },
          onCloudDeviceRegistered: (Map<String, dynamic> registeredData) {
            // Sync cloud registration data back to home state immediately
            if (mounted) {
              setState(() {
                if (registeredData.containsKey('cloudAccountId')) {
                  _cloudAccountId = registeredData['cloudAccountId'] as String;
                }
                if (registeredData.containsKey('cloudDeviceId')) {
                  _cloudDeviceId = registeredData['cloudDeviceId'] as String;
                }
                if (registeredData.containsKey('cloudToken')) {
                  _cloudToken = registeredData['cloudToken'] as String;
                }
              });
              // Save settings immediately so token persists
              _saveSettings();
            }
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
      _scheduledReminderSoundEnabled =
          result['scheduledReminderSoundEnabled'] == true;
      _urgentSoundEnabled = result['urgentSoundEnabled'] == true;
      _urgentFlashEnabled = result['urgentFlashEnabled'] == true;
      _urgentNotifyEnabled = result['urgentNotifyEnabled'] == true;
      _urgentBringToFrontEnabled = result['urgentBringToFrontEnabled'] == true;
      _swipeEnabled = result['swipeEnabled'] == true;
      _autoPurgeDoneEnabled = result['autoPurgeDoneEnabled'] == true;
      _doneRetentionDays =
          clampMin(result['doneRetentionDays'], _doneRetentionDays);
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
      if (result['reminderWindowFrom'] is String) {
        _reminderWindowFrom = result['reminderWindowFrom'] as String;
      }
      if (result['reminderWindowTo'] is String) {
        _reminderWindowTo = result['reminderWindowTo'] as String;
      }
      if (result['cloudDeviceName'] is String) {
        final nameStr = result['cloudDeviceName'] as String;
        if (nameStr.isNotEmpty) _cloudDeviceName = nameStr;
      }
      if (result['cloudPIN'] is String) {
        _cloudPIN = result['cloudPIN'] as String;
      }
      _cloudAllowInsecureTls = result['cloudAllowInsecureTls'] == true;
      if (result['inactivityReminders'] is List) {
        try {
          final rawList = result['inactivityReminders'];
          final list = (rawList is List)
              ? rawList
                  .map((e) => (e is Map)
                      ? Map<String, dynamic>.from(e)
                      : <String, dynamic>{})
                  .toList()
              : <Map<String, dynamic>>[];
          _inactivityReminders = list;
        } catch (_) {
          _inactivityReminders = <Map<String, dynamic>>[];
        }
        // Apply automatic export settings
        _autoExportOnStart = result['autoExportOnStart'] == true;
        _autoExportIntervalMinutes = clampMin(
            result['autoExportIntervalMinutes'], _autoExportIntervalMinutes);
        if (result['autoExportTimes'] is List) {
          try {
            final raw = result['autoExportTimes'];
            _autoExportTimes = (raw as List).map((e) => e.toString()).toList();
          } catch (_) {}
        } else if (result['autoExportTimes'] is String) {
          final s = result['autoExportTimes'] as String;
          _autoExportTimes = s
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
        if (result['autoExportMaxBackups'] is int ||
            result['autoExportMaxBackups'] is String) {
          try {
            final v = (result['autoExportMaxBackups'] is int)
                ? result['autoExportMaxBackups'] as int
                : int.tryParse(result['autoExportMaxBackups'].toString()) ??
                    _autoExportMaxBackups;
            _autoExportMaxBackups = v.clamp(0, 9999);
          } catch (_) {}
        }
      }
    });

    _registerActivity();
    // Restart inactivity timers if they were updated in settings
    try {
      _startInactivityTimers();
    } catch (_) {}
    await _saveSettings();
    unawaited(_purgeOldDoneTasksIfEnabled());
    _startCloudPullTimer();
    unawaited(_syncPullFromCloud());
    unawaited(_fetchServerVersion());
    _showTopToast('settings saved');
  }

  void _toggleExpanded(int index) {
    final taskId = _today[index].id;
    if (_expanded.contains(taskId)) {
      // collapsing: save edited title/notes before collapsing
      _saveEditedTitle(index);
      setState(() {
        _expanded.remove(taskId);
      });
    } else {
      // When opening a task, ensure any other expanded task is closed
      // and its edits are saved.
      final currentlyOpen = _expanded.toList();
      for (final openId in currentlyOpen) {
        final openIdx = _today.indexWhere((t) => t.id == openId);
        if (openIdx != -1) {
          _saveEditedTitle(openIdx);
        }
      }
      setState(() {
        _expanded.clear();
        _expanded.add(taskId);
        _editControllers.putIfAbsent(taskId, () {
          final c = TextEditingController(text: _today[index].text.trim());
          c.addListener(() {
            if (mounted) setState(() {});
            _scheduleAutoSave(taskId);
          });
          return c;
        });
        _notesControllers.putIfAbsent(taskId, () {
          final n = TextEditingController(text: _today[index].notes ?? '');
          n.addListener(() {
            if (mounted) setState(() {});
            _scheduleAutoSave(taskId);
          });
          return n;
        });
      });
      // Capture staged-before snapshot for finalizing edits later.
      try {
        _stagedEditBefore.putIfAbsent(taskId, () => _today[index].toJson());
      } catch (_) {}
      // After the frame is rendered, ensure the newly expanded tile is visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final k = _tileKeys[taskId];
        if (k != null && k.currentContext != null) {
          try {
            Scrollable.ensureVisible(k.currentContext!,
                duration: const Duration(milliseconds: 300), alignment: 0.08);
          } catch (_) {}
        }
      });
    }
    _registerActivity();
  }

  /// Finalize any open edits by saving and logging them. This should be
  /// called before navigation or header actions so that edits are recorded
  /// as a single consolidated redo-log entry.
  Future<void> _finalizeAllEdits() async {
    // Only finalize the currently focused edit to avoid bulk-saving
    // entire lists. This prevents accidental overwrites when multiple
    // tasks are expanded but the user intended to edit a single task.
    try {
      String? focusedTaskId;
      for (final e in _editFocusNodes.entries) {
        if (e.value.hasFocus) {
          focusedTaskId = e.key;
          break;
        }
      }
      if (focusedTaskId == null) return;
      final idx = _today.indexWhere((t) => t.id == focusedTaskId);
      if (idx == -1) return;
      await _saveEditedTitle(idx);
    } catch (_) {
      // best-effort: swallow errors to avoid throwing during dispose
    }
  }

  Future<void> _saveEditedTitle(int index) async {
    if (index < 0 || index >= _today.length) return;
    final taskId = _today[index].id;
    final titleCtrl = _editControllers[taskId];
    final notesCtrl = _notesControllers[taskId];
    if (titleCtrl == null || notesCtrl == null) return;
    final newText = titleCtrl.text.trim();
    final newNotes = notesCtrl.text;
    if (newText.isEmpty) return;
    // Apply edits and finalize a single consolidated log entry for this task.
    Map<String, dynamic>? beforeSnapshot;
    try {
      beforeSnapshot =
          _stagedEditBefore.remove(taskId) ?? _lastPersistedToday[taskId];
    } catch (_) {
      beforeSnapshot = _lastPersistedToday[taskId];
    }
    await _queueTaskAction(taskId, () async {
      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx == -1) return;
      setState(() {
        var updated = _today[idx].copyWith(text: newText, notes: newNotes);
        final workCtrl = _workControllers[updated.id];
        if (workCtrl != null) {
          final parsed = int.tryParse(workCtrl.text.trim());
          if (parsed != null) {
            updated = updated.copyWith(workMinutes: parsed);
          }
        }
        _today[idx] = updated;
      });

      // Persist changes first (so _saveList writes the full state)
      await _saveToday();
      try {
        if (_today[idx].done) unawaited(_cancelTaskNotification(taskId));
      } catch (_) {}
      _scheduleDelayedReorder();
      _upsertTimeEntry(_today[idx]);

      // Now append a single log entry for this consolidated change if something changed
      try {
        final afterSnapshot = _today[idx].toJson();
        if (beforeSnapshot == null) {
          // treat as create if no prior snapshot known
          unawaited(_appendRedoLog('create',
              taskId: taskId, details: {'after': afterSnapshot}));
        } else if (jsonEncode(beforeSnapshot) != jsonEncode(afterSnapshot)) {
          unawaited(_appendRedoLog('edit',
              taskId: taskId,
              details: {'before': beforeSnapshot, 'after': afterSnapshot}));
        }
        // update last persisted snapshot for this task
        _lastPersistedToday[taskId] = afterSnapshot;
      } catch (_) {}
    });

    final scheduled = _today[index].scheduledAt;
    if (scheduled != null) {
      final scheduledKey = DateFormat('yyyy-MM-dd').format(scheduled.toLocal());
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (scheduledKey.compareTo(todayKey) > 0) {
        // only move to backlog if scheduled strictly in the future
        await _moveToBacklogByIndex(index);
        return;
      }
    }

    _registerActivity();
  }

  void _scheduleAutoSave(String taskId) {
    try {
      _autosaveTimers[taskId]?.cancel();
    } catch (_) {}
    _autosaveTimers[taskId] = Timer(const Duration(milliseconds: 800), () {
      _autosaveTimers.remove(taskId);
      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx != -1) _saveEditedTitle(idx);
    });
  }

  /// Write (or overwrite) the time-entry row for [task] on today's date.
  /// Only runs when Sembast is available; silently skipped otherwise.
  void _upsertTimeEntry(TaskItem task) {
    if (!_useSembast) return;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      _sembastStorage.upsertTimeEntry(
        taskId: task.id,
        taskText: task.text,
        date: date,
        taskDone: task.done,
        taskInProgress: task.inProgress,
        stopwatchSeconds: task.stopwatchAccumulatedSeconds,
        workMinutes: task.workMinutes,
      );
      _queueCloudTimeEntrySync(task);
    } catch (_) {}
  }

  // If the task has a scheduled date and it's not today, move it to backlog.
  // (handled inside _saveEditedTitle below)

  Future<void> _addSubtask(
      int taskIndex, TextEditingController controller) async {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    if (taskIndex < 0 || taskIndex >= _today.length) return;
    final taskId = _today[taskIndex].id;
    final step = TaskStep(
      id: '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}',
      text: text,
    );

    await _queueTaskAction(taskId, () async {
      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx == -1) return;
      final task = _today[idx];
      setState(() {
        _today[idx] = task.copyWith(subtasks: [...task.subtasks, step]);
      });
      controller.clear();
      // Return focus to the subtask input so the user can add another subtask quickly
      try {
        _subtaskFocusNodes[task.id]?.requestFocus();
      } catch (_) {}
      await _saveToday();
      try {
        if (!_stagedEditBefore.containsKey(task.id))
          unawaited(_appendRedoLog('subtask_add',
              taskId: task.id, details: {'subtask': step.toJson()}));
      } catch (_) {}
      _scheduleDelayedReorder();
      _registerActivity();
    });
  }

  Future<void> _updateSubtask(
    int taskIndex,
    String subtaskId, {
    String? text,
    bool? done,
  }) {
    if (taskIndex < 0 || taskIndex >= _today.length) return Future.value();
    final taskId = _today[taskIndex].id;
    return _queueTaskAction(taskId, () async {
      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx == -1) return;
      final task = _today[idx];
      TaskStep? beforeStep;
      final updated = task.subtasks.map((step) {
        if (step.id != subtaskId) return step;
        beforeStep = step;
        return step.copyWith(
          text: text,
          done: done,
        );
      }).toList();
      setState(() {
        _today[idx] = task.copyWith(subtasks: updated);
      });
      await _saveToday();
      try {
        if (beforeStep != null && !_stagedEditBefore.containsKey(task.id))
          unawaited(_appendRedoLog('subtask_edit', taskId: task.id, details: {
            'subtaskId': subtaskId,
            'before': beforeStep!.toJson(),
            'after': updated.firstWhere((s) => s.id == subtaskId).toJson()
          }));
      } catch (_) {}
      _scheduleDelayedReorder();
      _registerActivity();
    });
  }

  void _scheduleDelayedReorder() {
    if (kDebugMode)
      print(
          '_scheduleDelayedReorder: immediate run stagedKeys=${_stagedScheduled.keys.toList()}');
    unawaited(_performDelayedReorder());
  }

  Future<void> _performDelayedReorder() async {
    // Apply any staged important flag changes before computing new order.
    if (_stagedImportant.isNotEmpty) {
      final stagedImportant = Map<String, bool>.from(_stagedImportant);
      _stagedImportant.clear();
      for (final entry in stagedImportant.entries) {
        final id = entry.key;
        final val = entry.value;
        final now = val ? DateTime.now() : null;
        try {
          unawaited(_queueTaskAction(id, () async {
            final idx = _today.indexWhere((t) => t.id == id);
            if (idx == -1) return;
            setState(() => _today[idx] =
                _today[idx].copyWith(important: val, importantAt: now));
            await _saveToday();
          }));
        } catch (_) {}
      }
    }
    // Apply staged inProgress changes and automatically start/stop stopwatch
    if (_stagedInProgress.isNotEmpty) {
      final stagedInProgress = Map<String, bool>.from(_stagedInProgress);
      _stagedInProgress.clear();
      for (final entry in stagedInProgress.entries) {
        final id = entry.key;
        final val = entry.value;
        final idx = _today.indexWhere((t) => t.id == id);
        if (idx != -1) {
          if (val == true) {
            try {
              await _startStopwatch(idx);
            } catch (_) {}
          } else {
            try {
              await _stopStopwatch(idx);
            } catch (_) {}
            // ensure inProgress flag is cleared via per-task queue
            try {
              final taskId = _today[idx].id;
              unawaited(_queueTaskAction(taskId, () async {
                final j = _today.indexWhere((t) => t.id == taskId);
                if (j == -1) return;
                setState(() => _today[j] =
                    _today[j].copyWith(inProgress: false, inProgressAt: null));
                await _saveToday();
              }));
            } catch (_) {}
          }
        }
      }
    }
    // Apply staged done changes
    if (_stagedDone.isNotEmpty) {
      final stagedDone = Map<String, bool>.from(_stagedDone);
      _stagedDone.clear();
      for (final entry in stagedDone.entries) {
        final id = entry.key;
        final val = entry.value;
        final idx = _today.indexWhere((t) => t.id == id);
        if (idx != -1) {
          final taskId = id;
          // determine a sensible before-snapshot
          Map<String, dynamic>? beforeSnapshot;
          try {
            beforeSnapshot =
                _stagedEditBefore.remove(taskId) ?? _lastPersistedToday[taskId];
          } catch (_) {
            beforeSnapshot = _lastPersistedToday[taskId];
          }
          // apply the done/undone change to the task
          final now = val == true ? DateTime.now() : null;
          if (val == true) {
            // stop any running stopwatch to avoid further time accumulation
            try {
              await _stopStopwatch(idx);
            } catch (_) {}
            // ensure inProgress is cleared when marking done — perform via queue so spinner shows
            unawaited(_queueTaskAction(taskId, () async {
              final idx2 = _today.indexWhere((t) => t.id == taskId);
              if (idx2 == -1) return;
              setState(() => _today[idx2] = _today[idx2].copyWith(
                  done: true,
                  completedAt: now,
                  inProgress: false,
                  inProgressAt: null,
                  stopwatchRunning: false,
                  stopwatchStartedAt: null));
              await _saveToday();
              try {
                unawaited(_cancelTaskNotification(taskId));
              } catch (_) {}
            }));
          } else {
            unawaited(_queueTaskAction(taskId, () async {
              final idx2 = _today.indexWhere((t) => t.id == taskId);
              if (idx2 == -1) return;
              setState(() => _today[idx2] =
                  _today[idx2].copyWith(done: false, completedAt: null));
              await _saveToday();
            }));
          }
          final afterSnapshot = _today[idx].toJson();
          // Handle subtask-level diffs separately so the consolidated `edit` entry
          // does not contain large JSON blobs for subtasks.
          try {
            final beforeSubs = (beforeSnapshot != null &&
                    beforeSnapshot['subtasks'] is List)
                ? List<Map<String, dynamic>>.from(beforeSnapshot['subtasks'])
                : <Map<String, dynamic>>[];
            final afterSubs = (afterSnapshot['subtasks'] is List)
                ? List<Map<String, dynamic>>.from(afterSnapshot['subtasks'])
                : <Map<String, dynamic>>[];

            final beforeById = {
              for (var s in beforeSubs)
                (s['id'] ?? s['uid'] ?? '').toString(): s
            };
            final afterById = {
              for (var s in afterSubs) (s['id'] ?? s['uid'] ?? '').toString(): s
            };

            // Adds
            for (final s in afterSubs) {
              final id = (s['id'] ?? s['uid'] ?? '').toString();
              if (id.isEmpty) continue;
              if (!beforeById.containsKey(id)) {
                unawaited(_appendRedoLog('subtask_add',
                    taskId: taskId, details: {'subtask': s}));
              }
            }
            // Removes
            for (final s in beforeSubs) {
              final id = (s['id'] ?? s['uid'] ?? '').toString();
              if (id.isEmpty) continue;
              if (!afterById.containsKey(id)) {
                unawaited(_appendRedoLog('subtask_remove',
                    taskId: taskId, details: {'subtask': s}));
              }
            }
            // Edits and done-toggle
            for (final id in beforeById.keys) {
              if (!afterById.containsKey(id)) continue;
              final b = beforeById[id]!;
              final a = afterById[id]!;
              if (jsonEncode(b) != jsonEncode(a)) {
                // detect done toggle
                final bDone = (b['done'] == true || b['completed'] == true);
                final aDone = (a['done'] == true || a['completed'] == true);
                if (bDone != aDone) {
                  unawaited(_appendRedoLog(
                      aDone ? 'subtask_done' : 'subtask_undone',
                      taskId: taskId,
                      details: {'subtaskId': id, 'before': b, 'after': a}));
                } else {
                  unawaited(_appendRedoLog('subtask_edit',
                      taskId: taskId,
                      details: {'subtaskId': id, 'before': b, 'after': a}));
                }
              }
            }
            // Reorder: compare id order
            final beforeOrder = beforeSubs
                .map((s) => (s['id'] ?? s['uid'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .toList();
            final afterOrder = afterSubs
                .map((s) => (s['id'] ?? s['uid'] ?? '').toString())
                .where((s) => s.isNotEmpty)
                .toList();
            if (beforeOrder.isNotEmpty &&
                afterOrder.isNotEmpty &&
                jsonEncode(beforeOrder) != jsonEncode(afterOrder)) {
              unawaited(_appendRedoLog('subtask_reorder',
                  taskId: taskId,
                  details: {'before': beforeOrder, 'after': afterOrder}));
            }
          } catch (_) {}

          // Record explicit done/reopen actions when the done flag changed.
          try {
            final beforeDone = beforeSnapshot != null &&
                (beforeSnapshot['done'] == true ||
                    beforeSnapshot['completed_at'] != null ||
                    beforeSnapshot['completedAt'] == true);
            final afterDone = afterSnapshot['done'] == true ||
                afterSnapshot['completed_at'] != null ||
                afterSnapshot['completedAt'] == true;
            if (beforeSnapshot != null && beforeDone != afterDone) {
              // use 'done' for marking done, 'reopen' for undoing done
              unawaited(_appendRedoLog(afterDone ? 'done' : 'reopen',
                  taskId: taskId, details: {'text': _today[idx].text}));
              if (afterDone) {
                try {
                  unawaited(_playDading());
                } catch (_) {}
              } else {
                try {
                  unawaited(_playThere());
                } catch (_) {}
              }
            }
          } catch (_) {}
          // If the task was marked done, move it to the Done list and
          // create the next recurrence occurrence if applicable. This
          // applies regardless of which view the change originated from.
          try {
            if (val == true) {
              // Only move the task into Done (and create the next recurrence)
              // when the task was in Backlog. Tasks completed while viewing
              // Today should remain in Today.
              if (_showingBacklog ||
                  _currentFile == _storage('simplepresent_backlog.json')) {
                // movedTask is current _today[idx] (we set done above)
                final movedTask = _today[idx];
                // remove from current in-memory list and persist via per-task queue
                unawaited(_queueTaskAction(movedTask.id, () async {
                  if (!mounted) return;
                  setState(() {
                    _today.removeAt(idx);
                    _expanded.clear();
                  });
                  await _saveToday();
                }));
                await _createNextRecurrenceIfNeeded(movedTask,
                    appendToDone: true);
              } else {
                // Stay in Today: just persist the updated Today list
                await _saveToday();
                // Ensure recurrence entries are created even when task remains in Today
                try {
                  await _createNextRecurrenceIfNeeded(_today[idx],
                      appendToDone: false);
                } catch (_) {}
              }
            }
          } catch (_) {}

          // Now append the consolidated edit entry but with subtasks removed to avoid JSON noise.
          final beforeCopy = beforeSnapshot != null
              ? Map<String, dynamic>.from(beforeSnapshot)
              : null;
          final afterCopy = Map<String, dynamic>.from(afterSnapshot);
          if (beforeCopy != null) beforeCopy.remove('subtasks');
          afterCopy.remove('subtasks');

          if (beforeSnapshot == null) {
            // treat as create if no prior snapshot known
            unawaited(_appendRedoLog('create',
                taskId: taskId, details: {'after': afterSnapshot}));
          } else if (jsonEncode(beforeCopy) != jsonEncode(afterCopy)) {
            unawaited(_appendRedoLog('edit',
                taskId: taskId,
                details: {'before': beforeCopy, 'after': afterCopy}));
          }
        }
      }
      _stagedDone.clear();
    }
    // Apply staged scheduled changes
    final idsToMoveToBacklog = <String>[];
    final hadBacklogScheduleChange =
        _showingBacklog && _stagedScheduled.isNotEmpty;
    if (_stagedScheduled.isNotEmpty) {
      for (final entry in _stagedScheduled.entries) {
        final id = entry.key;
        final val = entry.value; // DateTime? or null
        final idx = _today.indexWhere((t) => t.id == id);
        if (idx != -1) {
          // Apply scheduled change via per-task queue so spinner appears
          if (val == null) {
            await _queueTaskAction(id, () async {
              final j = _today.indexWhere((t) => t.id == id);
              if (j == -1) return;
              setState(() => _today[j] = _today[j].copyWith(scheduledAt: null));
              await _saveToday();
            });
          } else {
            // apply the scheduledAt change
            await _queueTaskAction(id, () async {
              final j = _today.indexWhere((t) => t.id == id);
              if (j == -1) return;
              setState(() => _today[j] = _today[j].copyWith(scheduledAt: val));
              await _saveToday();
            });
            // Only move to backlog when the scheduled date is strictly in the future.
            // Tasks scheduled for today or in the past should remain in Today
            // when edited.
            final scheduledKey = DateFormat('yyyy-MM-dd').format(val.toLocal());
            final todayKeyLocal =
                DateFormat('yyyy-MM-dd').format(DateTime.now());
            if (scheduledKey.compareTo(todayKeyLocal) > 0) {
              if (kDebugMode)
                print(
                    '_performDelayedReorder: staging move id=$id scheduled=$scheduledKey today=$todayKeyLocal');
              // Only schedule a move to backlog when we're currently showing Today
              // (don't move tasks that are being edited while viewing Backlog or Done)
              if (!_showingBacklog && !_showingDone) {
                idsToMoveToBacklog.add(id);
              }
            } else {
              if (kDebugMode)
                print(
                    '_performDelayedReorder: skip staging id=$id scheduled=$scheduledKey today=$todayKeyLocal');
            }
          }
        }
      }
      _stagedScheduled.clear();
    }
    final now = DateTime.now();
    final bucketImportantInProgress = <TaskItem>[];
    final bucketInProgressScheduledPast = <TaskItem>[];
    final bucketInProgressNoSchedule = <TaskItem>[];
    final bucketInProgressScheduledFuture = <TaskItem>[];
    final bucketImportant = <TaskItem>[];
    final bucketScheduledPast = <TaskItem>[];
    final bucketDueIn1h = <TaskItem>[];
    final bucketRest = <TaskItem>[];
    final bucketScheduledFuture = <TaskItem>[];
    final bucketDone = <TaskItem>[];

    for (final t in _today) {
      final hasSchedule = t.scheduledAt != null;
      final diff = hasSchedule ? t.scheduledAt!.difference(now) : null;
      final isOverdue = hasSchedule && diff!.isNegative;
      final dueWithin1h =
          hasSchedule && !diff!.isNegative && diff.inMinutes <= 60;
      final isScheduledFuture = hasSchedule && !isOverdue && !dueWithin1h;

      if (t.done) {
        bucketDone.add(t);
        continue;
      }

      // In-progress handling (split into important + scheduling buckets)
      if (t.inProgress) {
        if (t.important) {
          bucketImportantInProgress.add(t);
        } else if (isOverdue) {
          bucketInProgressScheduledPast.add(t);
        } else if (isScheduledFuture) {
          bucketInProgressScheduledFuture.add(t);
        } else {
          // no schedule or dueWithin1h counts as no-schedule here
          bucketInProgressNoSchedule.add(t);
        }
        continue;
      }

      // Non in-progress items
      if (t.important) {
        bucketImportant.add(t);
        continue;
      }
      if (isOverdue) {
        bucketScheduledPast.add(t);
        continue;
      }
      if (dueWithin1h) {
        bucketDueIn1h.add(t);
        continue;
      }
      if (isScheduledFuture) {
        bucketScheduledFuture.add(t);
        continue;
      }
      bucketRest.add(t);
    }

    // Sort in-progress buckets by most-recently started first
    int _cmpInProgressStart(TaskItem a, TaskItem b) {
      final da = a.inProgressAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = b.inProgressAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    }

    bucketImportantInProgress.sort(_cmpInProgressStart);
    bucketInProgressScheduledPast.sort(_cmpInProgressStart);
    bucketInProgressNoSchedule.sort(_cmpInProgressStart);
    bucketInProgressScheduledFuture.sort(_cmpInProgressStart);

    // Sort scheduled buckets chronologically: past newest first, dueWithin1h ascending, future ascending
    bucketScheduledPast.sort((a, b) => (b.scheduledAt ??
            DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    bucketDueIn1h.sort((a, b) => (a.scheduledAt ??
            DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(b.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0)));
    bucketScheduledFuture.sort((a, b) => (a.scheduledAt ??
            DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(b.scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0)));

    // Compose final order per requested sequence
    final newOrder = <TaskItem>[];
    newOrder.addAll(bucketImportantInProgress); // in arbeit - wichtig
    newOrder.addAll(
        bucketInProgressScheduledPast); // in arbeit - uhrzeit in vergangenheit
    newOrder.addAll(bucketInProgressNoSchedule); // in arbeit
    newOrder.addAll(
        bucketInProgressScheduledFuture); // in arbeit - uhrzeit in der zukunft
    newOrder.addAll(bucketImportant); // wichtig
    newOrder.addAll(bucketScheduledPast); // uhrzeit in vergangenheit
    newOrder.addAll(bucketDueIn1h); // uhrzeit in naher zukunft
    newOrder.addAll(bucketRest); // rest
    newOrder.addAll(bucketScheduledFuture); // uhrzeit in der zukunft rest
    newOrder.addAll(bucketDone);

    // As a safety net, ensure any tasks currently marked inProgress are
    // placed before non-inProgress tasks (preserve relative ordering).
    final inProgressFirst =
        newOrder.where((t) => t.inProgress && !t.done).toList();
    final restFinal =
        newOrder.where((t) => !(t.inProgress && !t.done)).toList();
    final finalOrder = <TaskItem>[]
      ..addAll(inProgressFirst)
      ..addAll(restFinal);

    // Debug: print classification & ordering to console in debug builds.
    if (kDebugMode) {
      final buf = StringBuffer();
      buf.writeln('--- _performDelayedReorder debug ---');
      buf.writeln('Now: $now');
      for (var i = 0; i < finalOrder.length; i++) {
        final t = finalOrder[i];
        buf.writeln(
            '#$i: "${t.text}" id=${t.id} done=${t.done} inProgress=${t.inProgress} important=${t.important} scheduled=${t.scheduledAt} inProgressAt=${t.inProgressAt}');
      }
      buf.writeln('--- end debug ---');
      // Print asynchronously to avoid blocking UI
      unawaited(Future(() => print(buf.toString())));
    }

    setState(() {
      _today
        ..clear()
        ..addAll(finalOrder);
    });
    _saveToday();

    // If a backlog task's date was changed to today or earlier, promote it now.
    if (hadBacklogScheduleChange) {
      unawaited(_promoteDueBacklogToToday(showToast: true));
    }

    // After reordering, move any tasks with scheduled dates strictly in the future
    // into backlog. Double-check the item's scheduled date at move-time to
    // avoid races where the staged value differs from the current item.
    if (idsToMoveToBacklog.isNotEmpty) {
      // If the user switched to Backlog/Done view since staging, skip moves.
      if (_showingBacklog || _showingDone) {
        if (kDebugMode)
          print(
              '_performDelayedReorder: skipping moves because view is backlog/done');
      } else {
        final todayKeyCheck = DateFormat('yyyy-MM-dd').format(DateTime.now());
        for (final id in idsToMoveToBacklog) {
          if (kDebugMode)
            print(
                '_performDelayedReorder: considering move id=$id (runtime check)');
          // find current index for id
          final idx = _today.indexWhere((t) => t.id == id);
          if (idx != -1) {
            final current = _today[idx];
            final sched = current.scheduledAt;
            if (sched != null) {
              final scheduledKey =
                  DateFormat('yyyy-MM-dd').format(sched.toLocal());
              if (kDebugMode)
                print(
                    '_performDelayedReorder: runtime compare id=$id scheduled=$scheduledKey today=$todayKeyCheck');
              if (scheduledKey.compareTo(todayKeyCheck) > 0) {
                // await the move to ensure it completes and the backlog is updated
                await _moveToBacklogByIndex(idx);
              }
            }
          }
        }
      }
    }
  }

  Future<void> _removeSubtask(int taskIndex, String subtaskId) async {
    if (taskIndex < 0 || taskIndex >= _today.length) return;
    final taskId = _today[taskIndex].id;
    await _queueTaskAction(taskId, () async {
      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx == -1) return;
      final task = _today[idx];
      TaskStep? removed;
      final list = task.subtasks.where((step) => step.id != subtaskId).toList();
      try {
        removed = task.subtasks.firstWhere((s) => s.id == subtaskId,
            orElse: () => TaskStep(id: '', text: '', done: false));
      } catch (_) {}
      setState(() {
        _today[idx] = task.copyWith(subtasks: list);
      });
      await _saveToday();
      try {
        if (removed != null &&
            removed.id.isNotEmpty &&
            !_stagedEditBefore.containsKey(task.id))
          unawaited(_appendRedoLog('subtask_remove',
              taskId: task.id, details: {'subtask': removed.toJson()}));
      } catch (_) {}
      _registerActivity();
    });
  }

  Future<void> _reorderSubtasks(
      int taskIndex, int oldIndex, int newIndex) async {
    if (taskIndex < 0 || taskIndex >= _today.length) return;
    final taskId = _today[taskIndex].id;
    await _queueTaskAction(taskId, () async {
      final idx = _today.indexWhere((t) => t.id == taskId);
      if (idx == -1) return;
      final task = _today[idx];
      final list = List<TaskStep>.from(task.subtasks);
      final beforeOrder = list.map((s) => s.id).toList();
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      final afterOrder = list.map((s) => s.id).toList();
      setState(() {
        _today[idx] = task.copyWith(subtasks: list);
      });
      await _saveToday();
      try {
        if (!_stagedEditBefore.containsKey(task.id))
          unawaited(_appendRedoLog('subtask_reorder',
              taskId: task.id,
              details: {'before': beforeOrder, 'after': afterOrder}));
      } catch (_) {}
      _registerActivity();
    });
  }

  Future<void> _pickSchedule(int index) async {
    final now = DateTime.now();
    final initial = _today[index].scheduledAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      // Use English (UK) so labels stay English and week starts on Monday
      locale: const Locale('en', 'GB'),
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
    // apply scheduled time via per-task queue so spinner shows during mutation
    final taskId = _today[index].id;
    final beforeSched = _today[index].scheduledAt;
    await _queueTaskAction(taskId, () async {
      final j = _today.indexWhere((t) => t.id == taskId);
      if (j == -1) return;
      setState(() => _today[j] = _today[j].copyWith(scheduledAt: scheduled));
      await _saveToday();
      // Stage this scheduled change for delayed reorder handling
      setState(() => _stagedScheduled[_today[j].id] = scheduled);
      if (kDebugMode)
        print(
            '_pickSchedule: staged id=${_today[j].id} scheduled=${DateFormat('yyyy-MM-dd HH:mm').format(scheduled)}');
      _scheduleDelayedReorder();

      try {
        if (!_stagedEditBefore.containsKey(_today[j].id))
          unawaited(_appendRedoLog('schedule_set',
              taskId: _today[j].id,
              details: {
                'before': beforeSched?.toIso8601String(),
                'after': scheduled.toIso8601String()
              }));
      } catch (_) {}
      _showTopToast('schedule set');
      // clear any prior notifications for this task so reminders can be re-scheduled
      final idPrefix = '${_today[j].id}|';
      _notified15.removeWhere((k) => k.startsWith(idPrefix));
      _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
      _registerActivity();
      try {
        await _saveSettings();
      } catch (_) {}
    });
  }

  Future<void> _showRecurrenceDialog(int index) async {
    final task = _today[index];
    String baseRec = task.recurrence ?? '';
    String selected = baseRec.startsWith('daily:') ? 'daily' : baseRec;
    // weekdays selection: 1=Mon .. 7=Sun
    final weekSelected = List<bool>.filled(7, true);
    // weekly/monthly helper values
    int weeklyInterval = 1;
    int yearlyInterval = 1;
    String monthlyMode = 'dom'; // 'dom' or 'weekday'
    int dom = DateTime.now().day;
    String weekdayMode = 'first'; // 'first' or 'last'
    int weekday = DateTime.now().weekday; // 1-7
    bool askRepeatDateOnRecreation = task.askRepeatDateOnRecreation;

    if (baseRec.startsWith('daily:')) {
      final parts = baseRec.split(':');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        // explicit mask provided -> reset and apply
        for (var i = 0; i < 7; i++) weekSelected[i] = false;
        for (final p in parts[1].split(',')) {
          final n = int.tryParse(p.trim());
          if (n != null && n >= 1 && n <= 7) weekSelected[n - 1] = true;
        }
      }
    }

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Recurrence'),
          content: StatefulBuilder(builder: (ctx2, setState2) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('None'),
                  onTap: () => setState2(() => selected = ''),
                  trailing: Icon(
                    (selected == '')
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: (selected == '')
                        ? Theme.of(ctx2).colorScheme.primary
                        : null,
                  ),
                ),
                ListTile(
                  title: const Text('Daily'),
                  onTap: () => setState2(() => selected = 'daily'),
                  trailing: Icon(
                    (selected == 'daily')
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: (selected == 'daily')
                        ? Theme.of(ctx2).colorScheme.primary
                        : null,
                  ),
                ),
                if (selected == 'daily')
                  Column(
                    children: List.generate(7, (i) {
                      const names = [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun'
                      ];
                      return CheckboxListTile(
                        title: Text(names[i]),
                        value: weekSelected[i],
                        onChanged: (v) =>
                            setState2(() => weekSelected[i] = v ?? false),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    }),
                  ),
                ListTile(
                  title: const Text('Weekly'),
                  onTap: () => setState2(() => selected = 'weekly'),
                  trailing: Icon(
                    (selected == 'weekly')
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: (selected == 'weekly')
                        ? Theme.of(ctx2).colorScheme.primary
                        : null,
                  ),
                ),
                if (selected == 'weekly')
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, right: 12.0),
                    child: Row(
                      children: [
                        const Text('Interval (weeks):'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: weeklyInterval,
                          items: List.generate(12, (i) => i + 1)
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')))
                              .toList(),
                          onChanged: (v) =>
                              setState2(() => weeklyInterval = v ?? 1),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  title: const Text('Monthly'),
                  onTap: () => setState2(() => selected = 'monthly'),
                  trailing: Icon(
                    (selected == 'monthly')
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: (selected == 'monthly')
                        ? Theme.of(ctx2).colorScheme.primary
                        : null,
                  ),
                ),
                if (selected == 'monthly')
                  Column(
                    children: [
                      Row(
                        children: [
                          Radio<String>(
                              value: 'dom',
                              groupValue: monthlyMode,
                              onChanged: (v) =>
                                  setState2(() => monthlyMode = v ?? 'dom')),
                          const SizedBox(width: 6),
                          const Text('Day of month'),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              initialValue: '$dom',
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(isDense: true),
                              onChanged: (val) => setState2(
                                  () => dom = int.tryParse(val) ?? dom),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Radio<String>(
                              value: 'weekday',
                              groupValue: monthlyMode,
                              onChanged: (v) => setState2(
                                  () => monthlyMode = v ?? 'weekday')),
                          const SizedBox(width: 6),
                          const Text('Weekday rule'),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                              value: weekdayMode,
                              items: const [
                                DropdownMenuItem(
                                    value: 'first', child: Text('first')),
                                DropdownMenuItem(
                                    value: 'last', child: Text('last'))
                              ],
                              onChanged: (v) =>
                                  setState2(() => weekdayMode = v ?? 'first')),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                              value: weekday,
                              items: List.generate(7, (i) => i + 1)
                                  .map((d) => DropdownMenuItem(
                                      value: d,
                                      child: Text([
                                        'Mon',
                                        'Tue',
                                        'Wed',
                                        'Thu',
                                        'Fri',
                                        'Sat',
                                        'Sun'
                                      ][d - 1])))
                                  .toList(),
                              onChanged: (v) => setState2(
                                  () => weekday = v ?? DateTime.now().weekday)),
                        ],
                      ),
                    ],
                  ),
                ListTile(
                  title: const Text('Yearly'),
                  onTap: () => setState2(() => selected = 'yearly'),
                  trailing: Icon(
                    (selected == 'yearly')
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: (selected == 'yearly')
                        ? Theme.of(ctx2).colorScheme.primary
                        : null,
                  ),
                ),
                if (selected == 'yearly')
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0, right: 12.0),
                    child: Row(
                      children: [
                        const Text('Interval (years):'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: yearlyInterval,
                          items: List.generate(5, (i) => i + 1)
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')))
                              .toList(),
                          onChanged: (v) =>
                              setState2(() => yearlyInterval = v ?? 1),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('ask date on follow up creation'),
                  value: askRepeatDateOnRecreation,
                  onChanged: (v) =>
                      setState2(() => askRepeatDateOnRecreation = v ?? false),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            );
          }),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        );
      },
    );

    if (res != true) return;

    String newRec;
    if (selected == 'daily') {
      final picked = <String>[];
      for (var i = 0; i < 7; i++) {
        if (weekSelected[i]) picked.add('${i + 1}');
      }
      if (picked.length >= 7 || picked.isEmpty) {
        // treat all-selected or none-selected as plain daily
        newRec = 'daily';
      } else {
        newRec = 'daily:${picked.join(',')}';
      }
    } else if (selected == 'weekly') {
      // weekly with interval
      newRec = 'weekly:$weeklyInterval';
    } else if (selected == 'monthly') {
      if (monthlyMode == 'dom') {
        final safeDom = dom.clamp(1, 31);
        newRec = 'monthly:day=$safeDom';
      } else {
        // weekday rule like monthly:weekday=first:1
        newRec = 'monthly:weekday=$weekdayMode:$weekday';
      }
    } else if (selected == 'yearly') {
      newRec = yearlyInterval <= 1 ? 'yearly' : 'yearly:$yearlyInterval';
    } else if (selected.isEmpty) {
      newRec = '';
    } else {
      newRec = selected;
    }

    // Apply recurrence change via per-task queue so spinner shows during mutation
    final _recTaskId = _today[index].id;
    await _queueTaskAction(_recTaskId, () async {
      final j = _today.indexWhere((t) => t.id == _recTaskId);
      if (j == -1) return;
      setState(() {
        _today[j] = _today[j].copyWith(
          recurrence: newRec.isEmpty ? null : newRec,
          askRepeatDateOnRecreation: askRepeatDateOnRecreation,
        );
      });
      await _saveToday();
    });
  }

  Future<void> _moveFromBacklog(int index) async {
    try {
      // Load backlog file and remove the item there (index refers to backlog list)
      final backlogFile = _storage('simplepresent_backlog.json');
      final List<TaskItem> backlogList = [];
      await _loadList(backlogFile, backlogList);
      if (index < 0 || index >= backlogList.length) {
        _showTopToast('failed to move task to today');
        return;
      }
      final item = backlogList.removeAt(index);

      // Prepare today list and item to move.
      // Do not use `_today` here because in backlog view `_today` holds backlog data.
      final todayFile = _storage('simplepresent_today.json');
      final List<TaskItem> todayList = [];
      await _loadList(todayFile, todayList);
      final movedItem = item.copyWith(done: false, inProgress: false);
      todayList.insert(0, movedItem);

      // Perform both saves in parallel (they operate on different files)
      await Future.wait([
        _saveList(backlogFile, backlogList, triggerCloudSync: false),
        _saveList(todayFile, todayList, triggerCloudSync: false),
      ]);

      // Update visible list without reloading from disk.
      // In backlog view, remove the moved item from the currently shown backlog list.
      unawaited(_queueTaskAction(movedItem.id, () async {
        if (!mounted) return;
        setState(() {
          if (_showingBacklog || _currentFile == backlogFile) {
            if (index >= 0 && index < _today.length) {
              _today.removeAt(index);
            }
          } else {
            _today.insert(0, movedItem);
          }
        });
        await _saveToday();
      }));

      _showTopToast('task moved to today');

      // Log move from backlog to today
      unawaited(_appendRedoLog('move_to_today',
          taskId: item.id, details: {'from': 'backlog', 'to': 'today'}));

      // Update header counts
      unawaited(_updateListCounts());

      // Push both lists to cloud after local state is stable (run in background)
      try {
        unawaited(_syncPushToCloud(backlogFile, backlogList));
        unawaited(_syncPushToCloud(todayFile, todayList));
      } catch (_) {}
    } catch (_) {
      _showTopToast('failed to move task to today');
    }
    _registerActivity();
  }

  Future<void> _moveToBacklogByIndex(int index) async {
    // If we're already showing the backlog (or the current file is the
    // backlog file), a move-to-backlog would be a no-op and may silently
    // reorder items inside the backlog. Skip in that case to avoid
    // performing intra-backlog moves triggered by edits.
    if (_showingBacklog ||
        _currentFile == _storage('simplepresent_backlog.json')) {
      if (kDebugMode)
        print('_moveToBacklogByIndex: skip because showing backlog');
      return;
    }

    try {
      final item = _today[index];
      // Remove via per-task queue so spinner appears on the task while removing
      await _queueTaskAction(item.id, () async {
        if (!mounted) return;
        setState(() {
          _today.removeAt(index);
          _expanded.clear();
        });
        await _saveToday(); // persist removal from today
      });
      // If stopwatch was running, stop it and record the accumulated seconds
      TaskItem toStore = item;
      if (item.stopwatchRunning) {
        final started = item.stopwatchStartedAt ?? DateTime.now();
        final added = DateTime.now().difference(started).inSeconds;
        final newAccum = item.stopwatchAccumulatedSeconds + added;
        toStore = item.copyWith(
            stopwatchRunning: false,
            stopwatchStartedAt: null,
            stopwatchAccumulatedSeconds: newAccum,
            inProgress: false);
      } else {
        toStore = item.copyWith(done: false, inProgress: false);
      }

      // insert at top so task appears first in backlog via queued helper
      await _queueAppendToList('simplepresent_backlog.json', toStore,
          insertTop: true);
      // Log move to backlog
      unawaited(_appendRedoLog('move_to_backlog',
          taskId: toStore.id, details: {'from': 'today', 'to': 'backlog'}));
      // Also log reopen (task marked not done)
      try {
        unawaited(_appendRedoLog('reopen',
            taskId: toStore.id, details: {'text': toStore.text}));
      } catch (_) {}
      try {
        unawaited(_playThere());
      } catch (_) {}
      // Persist time entry for this task (if using Sembast this appends a row)
      _upsertTimeEntry(toStore);
      // If we're currently showing backlog, reload to reflect the new top item
      if (_showingBacklog ||
          _currentFile == _storage('simplepresent_backlog.json')) {
        await _loadToday();
      }
      _showTopToast('task moved to backlog');
    } catch (_) {
      _showTopToast('failed to move task to backlog');
    }
    _registerActivity();
  }

  Future<void> _moveToBacklog(int index) async {
    // Skip moving into backlog if we're already viewing backlog to avoid
    // re-inserting the item into the same list (which looks like an
    // unnecessary intra-backlog move).
    if (_showingBacklog ||
        _currentFile == _storage('simplepresent_backlog.json')) {
      if (kDebugMode) print('_moveToBacklog: skip because showing backlog');
      return;
    }

    try {
      final item = _today[index];
      // Remove via per-task queue so spinner appears on the task while removing
      await _queueTaskAction(item.id, () async {
        if (!mounted) return;
        setState(() {
          _today.removeAt(index);
          _expanded.clear();
        });
        await _saveToday(); // persist removal from today
      });
      // Stop running stopwatch and persist time if necessary
      TaskItem toStore = item;
      if (item.stopwatchRunning) {
        final started = item.stopwatchStartedAt ?? DateTime.now();
        final added = DateTime.now().difference(started).inSeconds;
        final newAccum = item.stopwatchAccumulatedSeconds + added;
        toStore = item.copyWith(
            stopwatchRunning: false,
            stopwatchStartedAt: null,
            stopwatchAccumulatedSeconds: newAccum,
            inProgress: false);
      } else {
        toStore = item.copyWith(done: false, inProgress: false);
      }

      // insert at top so task appears first in backlog via queued helper
      await _queueAppendToList('simplepresent_backlog.json', toStore,
          insertTop: true);
      unawaited(_appendRedoLog('move_to_backlog',
          taskId: toStore.id, details: {'from': 'today', 'to': 'backlog'}));
      try {
        unawaited(_appendRedoLog('reopen',
            taskId: toStore.id, details: {'text': toStore.text}));
      } catch (_) {}
      _upsertTimeEntry(toStore);
      // If we're currently showing backlog, reload to reflect the new top item
      if (_showingBacklog ||
          _currentFile == _storage('simplepresent_backlog.json')) {
        await _loadToday();
      }

      _showTopToast('task moved to backlog');
    } catch (_) {
      _showTopToast('failed to move task to backlog');
    }
    _registerActivity();
  }

  Future<void> _duplicateTask(int index) async {
    try {
      final item = _today[index];
      final newId =
          '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
      final newItem = item.copyWith(
        id: newId,
        createdAt: DateTime.now(),
        done: false,
        completedAt: null,
        inProgress: false,
        inProgressAt: null,
        stopwatchAccumulatedSeconds: 0,
        stopwatchRunning: false,
        stopwatchStartedAt: null,
      );

      // Insert into the same logical list where we're currently viewing, default to backlog for Done view
      String targetFile;
      if (_currentFile == _storage('simplepresent_backlog.json')) {
        targetFile = _storage('simplepresent_backlog.json');
        await _queueAppendToList(targetFile, newItem, insertTop: true);
        _upsertTimeEntry(newItem);
      } else if (_currentFile == _storage('simplepresent_done.json')) {
        // when duplicating from Done, put the copy in Backlog and switch view to Backlog
        targetFile = _storage('simplepresent_backlog.json');
        await _queueAppendToList(targetFile, newItem, insertTop: true);
        _upsertTimeEntry(newItem);
      } else {
        targetFile = _storage('simplepresent_today.json');
        await _queueAppendToList(targetFile, newItem, insertTop: true);
        _upsertTimeEntry(newItem);
      }

      // Ensure the UI shows the target list and expand the new item for editing
      final switchToTarget = _currentFile != targetFile;
      if (switchToTarget) {
        _currentFile = targetFile;
      }
      await _loadToday();
      // Log duplication
      unawaited(_appendRedoLog('duplicate',
          taskId: newId, details: {'source': item.id, 'target': targetFile}));
      setState(() {
        _expanded.clear();
        _expanded.add(newId);
        _editControllers.putIfAbsent(newId, () {
          final c = TextEditingController(text: newItem.text);
          c.addListener(() {
            if (mounted) setState(() {});
            _scheduleAutoSave(newId);
          });
          return c;
        });
        _notesControllers.putIfAbsent(newId, () {
          final n = TextEditingController(text: newItem.notes ?? '');
          n.addListener(() {
            if (mounted) setState(() {});
            _scheduleAutoSave(newId);
          });
          return n;
        });
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final k = _tileKeys[newId];
        if (k != null && k.currentContext != null) {
          try {
            Scrollable.ensureVisible(k.currentContext!,
                duration: const Duration(milliseconds: 300), alignment: 0.08);
          } catch (_) {}
        }
      });
      // Ensure the title field has focus
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (!Platform.isAndroid)
            _editFocusNodes
                .putIfAbsent(newId, () => FocusNode())
                .requestFocus();
        } catch (_) {}
      });
      _showTopToast('task duplicated');
    } catch (_) {
      _showTopToast('failed to duplicate task');
    }
    _registerActivity();
  }

  Future<void> _clearSchedule(int index) async {
    if (index < 0 || index >= _today.length) return;
    final id = _today[index].id;
    await _queueTaskAction(id, () async {
      final idx = _today.indexWhere((t) => t.id == id);
      if (idx == -1) return;
      final beforeSched = _today[idx].scheduledAt;
      // clear in-memory and save current view
      setState(() => _today[idx] = _today[idx].copyWith(scheduledAt: null));
      await _saveToday();
      try {
        if (!_stagedEditBefore.containsKey(id))
          unawaited(_appendRedoLog('schedule_clear',
              taskId: id, details: {'before': beforeSched?.toIso8601String()}));
      } catch (_) {}
      _showTopToast('schedule cleared');
      final idPrefix2 = '$id|';
      _notified15.removeWhere((k) => k.startsWith(idPrefix2));
      _notifiedDue.removeWhere((k) => k.startsWith(idPrefix2));
      _registerActivity();
    });

    // Ensure persisted lists also have the schedule cleared for this task id
    try {
      final files = [
        _storage('simplepresent_today.json'),
        _storage('simplepresent_backlog.json'),
        _storage('simplepresent_done.json')
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
            if (_useSembast) {
              try {
                final rows = _sembastStorage.readTaskList(f);
                savedText = const JsonEncoder.withIndent('  ').convert(rows);
              } catch (_) {
                savedText = null;
              }
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
              final now2 = DateTime.now().toIso8601String();
              final entry2 =
                  '$now2 | post-save snippet for $f id=$id | snippet=${snippet.replaceAll("\n", " ")}\n';
              await _appendRawLogEntry(
                  'simplepresent_clear_schedule.log', entry2);
            }
          } catch (_) {}
        }
      }
      // reload view so UI reflects persisted changes
      await _loadToday();

      // write a debug log in app dir to help diagnose persistence mismatches
      try {
        final now = DateTime.now().toIso8601String();
        final entry =
            '$now | cleared schedule for id=$id | changed=${changedFiles.join(',')}' +
                '\n';
        await _appendRawLogEntry('simplepresent_clear_schedule.log', entry);
      } catch (_) {}
    } catch (_) {}
    try {
      await _saveSettings();
    } catch (_) {}
  }

  void _showTopToast(String message) {
    // Don't show toasts caused by applying cloud state, sync, or backups.
    if (_suppressSyncToasts || _applyingCloudState || _suppressBackupToasts)
      return;
    // Dedupe identical messages shown recently and throttle brief bursts
    final now = DateTime.now();
    if (_lastToastMessage != null && _lastToastMessage == message) {
      if (_lastToastAt != null && now.difference(_lastToastAt!).inSeconds < 3) {
        return; // suppress duplicate within 3s
      }
    }
    if (_lastToastAt != null &&
        now.difference(_lastToastAt!).inMilliseconds < 700) {
      return; // throttle too-frequent toasts
    }
    _lastToastMessage = message;
    _lastToastAt = now;

    _toastTimer?.cancel();
    _toastEntry?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);

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
      for (final id in _editControllers.keys) {
        try {
          _autosaveTimers[id]?.cancel();
        } catch (_) {}
      }
      _autosaveTimers.clear();
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
    final newId =
        '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    final newItem = TaskItem(
        id: newId,
        text: input,
        done: false,
        createdAt: DateTime.now(),
        notes: '');

    // Run creation through the per-task queue so the spinner appears on the new task
    unawaited(_queueTaskAction(newId, () async {
      setState(() {
        _today.insert(0, newItem);
        _controller.clear();
      });
      await _saveToday();
      // Log creation for redo/undo purposes
      try {
        unawaited(
            _appendRedoLog('create', taskId: newId, details: {'text': input}));
      } catch (_) {}
      if (!Platform.isAndroid) _requestInputFocusIfIdle();
      _registerActivity();
    }));
  }

  Future<void> _setDone(int index, bool value) async {
    // If we're in the Done view and the user unchecks done, move the task to Backlog
    final original = _today[index];
    if (!value &&
        (_showingDone || _currentFile == _storage('simplepresent_done.json'))) {
      try {
        final restored = original.copyWith(done: false, completedAt: null);
        // Remove via per-task queue so spinner appears while task is moved
        await _queueTaskAction(restored.id, () async {
          if (!mounted) return;
          setState(() {
            _today.removeAt(index);
            _expanded.clear();
          });
          await _saveToday(); // persist removal from done file
        });

        // Append to backlog via per-task queue to ensure atomicity across lists
        await _queueAppendToList('simplepresent_backlog.json', restored,
            insertTop: true);

        _showTopToast('task moved to backlog');
        try {
          unawaited(_appendRedoLog('reopen',
              taskId: restored.id, details: {'text': restored.text}));
        } catch (_) {}
        try {
          unawaited(_playThere());
        } catch (_) {}
        try {
          unawaited(_cancelTaskNotification(restored.id));
        } catch (_) {}
      } catch (_) {
        _showTopToast('failed to move task');
      }
      _registerActivity();
      return;
    }

    // If we're in the Backlog view and the user marks a task done, move it to Done list
    if (value &&
        (_showingBacklog ||
            _currentFile == _storage('simplepresent_backlog.json'))) {
      try {
        // stop running stopwatch for this task before moving to Done
        await _stopStopwatch(index);
        final finalTask = _today[index];
        final moved =
            finalTask.copyWith(done: true, completedAt: DateTime.now());
        // Remove via per-task queue so spinner appears on the task while removing
        await _queueTaskAction(moved.id, () async {
          if (!mounted) return;
          setState(() {
            _today.removeAt(index);
            _expanded.clear();
          });
          await _saveToday(); // persist removal from backlog
        });
        try {
          unawaited(_appendRedoLog('done',
              taskId: moved.id, details: {'text': finalTask.text}));
        } catch (_) {}
        try {
          unawaited(_cancelTaskNotification(moved.id));
        } catch (_) {}
        // Note: Do NOT create recurrence entries here - this is a pure list move without user "done" interaction
        _showTopToast('task moved to done');
        _playDading();
      } catch (_) {
        _showTopToast('failed to move task to done');
      }
      _registerActivity();
      return;
    }

    // Stage done change to avoid immediate reordering; persist when delayed reorder runs.
    final t = _today[index];
    setState(() => _stagedDone[t.id] = value);
    // When the user stages a task as done, cancel any existing notification
    // so Android notifications for this task disappear immediately.
    if (value == true) {
      try {
        unawaited(_cancelTaskNotification(t.id));
      } catch (_) {}
    }
    // If marking done, ensure any staged inProgress is cleared
    if (value == true) {
      _stagedInProgress.remove(t.id);
    }
    _scheduleDelayedReorder();
    // If marked done, still stop the stopwatch now to avoid counting further time
    if (value == true) {
      try {
        await _stopStopwatch(index);
      } catch (_) {}
    }
    // clear notification flags for this task (by id)
    final idPrefix = '${t.id}|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
    // Play a friendly sound when a task is marked done
    if (value == true) {
      _playDading();
    }
    _registerActivity();
    try {
      await _saveSettings();
    } catch (_) {}
  }

  Future<void> _playDading() async {
    await _playShortSound('sounds/ding.mp3', alert: false);
  }

  Future<void> _cancelTaskNotification(String taskId) async {
    try {
      await _nativeWindowChannel.invokeMethod(
          'cancelNotification', <String, String>{'taskId': taskId});
    } catch (_) {}
    try {
      await _nativeWindowChannel.invokeMethod(
          'removeNotification', <String, String>{'taskId': taskId});
    } catch (_) {}
    try {
      await _nativeWindowChannel.invokeMethod(
          'clearNotification', <String, String>{'taskId': taskId});
    } catch (_) {}
  }

  Future<void> _playThere() async {
    await _playShortSound('sounds/there.mp3', alert: true);
  }

  Future<void> _playShortSound(String asset, {bool alert = false}) async {
    try {
      await _debugLog(
          '_playShortSound: starting playback of $asset (alert=$alert)');
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.play(AssetSource(asset));
      await _debugLog('_playShortSound: playback started successfully');
    } catch (e) {
      await _debugLog('_playShortSound: failed - $e');
    }
  }

  void _performSwipeAction(String taskId, String action) {
    // Schedule the action to run after snap-back animation (~340ms).
    // The actual execution will be queued and show loading indicator.
    Future.delayed(const Duration(milliseconds: 340), () async {
      if (!mounted) return;

      switch (action) {
        case 'moveFromBacklog':
          await _queueMoveFromBacklogByTaskId(taskId);
          break;
        case 'setInProgress':
          await _queueTaskAction(taskId, () async {
            final idx = _today.indexWhere((x) => x.id == taskId);
            if (idx == -1) return;
            _showTopToast('task marked in progress');
            _registerActivity();
            await _startStopwatch(idx);
            final cur = _today.indexWhere((x) => x.id == taskId);
            if (cur != -1) {
              setState(() {
                _today[cur] = _today[cur].copyWith(
                  inProgress: true,
                  inProgressAt: _today[cur].inProgressAt ?? DateTime.now(),
                );
              });
            }
            await _saveToday();
          });
          break;
        case 'setDone':
          await _queueTaskAction(taskId, () async {
            final idx = _today.indexWhere((x) => x.id == taskId);
            if (idx == -1) return;
            try {
              await _stopStopwatch(idx);
            } catch (_) {}
            try {
              final now = DateTime.now();
              final original = _today[idx];
              setState(() {
                _today[idx] = original.copyWith(
                  done: true,
                  inProgress: false,
                  completedAt: now,
                );
              });
            } catch (_) {}
            // Log marking done
            try {
              final title = _today[idx].text;
              unawaited(_appendRedoLog(
                'done',
                taskId: _today[idx].id,
                details: {'text': title},
              ));
            } catch (_) {}
            // Clear notification flags
            try {
              final idPrefix = '${_today[idx].id}|';
              _notified15.removeWhere((k) => k.startsWith(idPrefix));
              _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
            } catch (_) {}
            try {
              _upsertTimeEntry(_today[idx]);
            } catch (_) {}
            try {
              await _playDading();
            } catch (_) {}
            try {
              await _saveToday();
            } catch (_) {}
            try {
              await _createNextRecurrenceIfNeeded(_today[idx],
                  appendToDone: false);
            } catch (_) {}
            _registerActivity();
            _showTopToast('task marked done');
          });
          break;
        case 'unsetInProgress':
          await _queueTaskAction(taskId, () async {
            final idx = _today.indexWhere((x) => x.id == taskId);
            if (idx == -1) return;
            try {
              await _stopStopwatch(idx);
            } catch (_) {}
            try {
              unawaited(_queueTaskAction(_today[idx].id, () async {
                final id2 = _today[idx].id;
                final idx2 = _today.indexWhere((t) => t.id == id2);
                if (idx2 == -1) return;
                setState(() {
                  _today[idx2] = _today[idx2].copyWith(
                    inProgress: false,
                    inProgressAt: null,
                  );
                });
                await _saveToday();
              }));
            } catch (_) {}
            await _saveToday();
            _registerActivity();
            _showTopToast('task marked not in progress');
          });
          break;
      }
    });
  }

  Future<void> _queueTaskAction(
      String taskId, Future<void> Function() action) async {
    // Add action to the queue for this task
    _taskActionQueues.putIfAbsent(taskId, () => []).add(action);

    // Show loading spinner
    if (!_busyTaskIds.contains(taskId) && mounted) {
      try {
        unawaited(_debugLog('queue show: $taskId'));
      } catch (_) {}
      setState(() => _busyTaskIds.add(taskId));
    }

    // Start processing if not already processing
    if (_taskActionProcessing.contains(taskId)) {
      return; // Already processing, will be handled by the queue
    }

    _taskActionProcessing.add(taskId);

    while (_taskActionQueues[taskId]?.isNotEmpty ?? false) {
      if (!mounted) break;

      try {
        final nextAction = _taskActionQueues[taskId]!.removeAt(0);
        await nextAction();
      } catch (e) {
        await _debugLog('_queueTaskAction error: $e');
      }
    }

    _taskActionProcessing.remove(taskId);
    _taskActionQueues.remove(taskId);

    // Hide loading spinner
    if (mounted) {
      try {
        unawaited(_debugLog('queue hide: $taskId'));
      } catch (_) {}
      setState(() => _busyTaskIds.remove(taskId));
    }
  }

  // Wrapper to queue _setDone by task ID instead of index
  Future<void> _queueSetDoneByTaskId(String taskId, bool value) async {
    final idx = _today.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    await _queueTaskAction(taskId, () => _setDone(idx, value));
  }

  // Wrapper to queue _moveToBacklog by task ID instead of index
  Future<void> _queueMoveToBacklogByTaskId(String taskId) async {
    final idx = _today.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    await _queueTaskAction(taskId, () => _moveToBacklog(idx));
  }

  // Wrapper to queue _moveFromBacklog by task ID instead of index
  Future<void> _queueMoveFromBacklogByTaskId(String taskId) async {
    final idx = _today.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    await _queueTaskAction(taskId, () => _moveFromBacklog(idx));
  }

  Future<void> _removeFromToday(int index) async {
    final removed = _today[index];
    // Remove via per-task queue so spinner shows while deleting
    await _queueTaskAction(removed.id, () async {
      if (!mounted) return;
      setState(() {
        _today.removeAt(index);
      });
      await _saveToday();
    });
    // Move the removed task into the trash file instead of permanent delete
    try {
      await _queueAppendToList('simplepresent_trash.json', removed,
          insertTop: false);
    } catch (_) {}
    try {
      unawaited(_cancelTaskNotification(removed.id));
    } catch (_) {}
    // Clear any pending notification flags for this task (use text match)
    final idPrefix = '${removed.id}|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix));
    _registerActivity();
    try {
      await _saveSettings();
    } catch (_) {}
  }

  void _registerActivity() {
    // Reset idle timer on user activity
    try {
      _idleTimer?.cancel();
      _attentionTimer?.cancel();
      _reminderTimer?.cancel();
      // cancel any dynamic inactivity timers
      for (final t in _inactivityTimers) {
        try {
          t?.cancel();
        } catch (_) {}
      }
    } catch (_) {}
    // Reset fired flags so reminders can fire again after activity
    _idleFired = false;
    _attentionFired = false;
    _reminderFired = false;
    _urgentFired = false;
    // reset dynamic fired flags
    _inactivityFired =
        List<bool>.generate(_inactivityReminders.length, (_) => false);
    // Start the built-in inactivity timers and the dynamic reminder timers.
    _startIdleTimer();
    _startAttentionTimer();
    _startReminderTimer();
    _startUrgentTimer();
    _startInactivityTimers();
    _startAutoSwitchTimer();
    if (_initializationComplete) {
      unawaited(_promoteDueBacklogToToday(showToast: false));
    }
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
      final now = DateTime.now();
      if (!_isWithinReminderWindow(now)) {
        final delay = _durationUntilNextWindowStart(now);
        _idleTimer = Timer(delay, () async {
          if (_idleFired) return;
          if (_idleSoundEnabled) {
            try {
              await _playShortSound('sounds/there.mp3', alert: true);
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
              await _nativeWindowChannel
                  .invokeMethod('notify', <String, String>{
                'title': _appTitle,
                'body': 'You have been inactive for $_idleMinutes minutes',
                'icon': 'assets/icons/color_transparent_icon.png',
              });
            } catch (_) {}
          }
          if (_idleBringToFrontEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('bringToFront');
            } catch (_) {}
          }
          _idleFired = true;
        });
        return;
      }
      if (_idleSoundEnabled) {
        try {
          await _playShortSound('sounds/there.mp3', alert: true);
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
            'icon': 'assets/icons/color_transparent_icon.png',
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

  DateTime? _computeNextRecurrence(DateTime base, String recurrence) {
    try {
      final s = recurrence.trim();
      if (s.isEmpty) return null;

      // DAILY variants
      if (s.startsWith('daily')) {
        // daily or daily:1,2,3 (weekday filter)
        if (s == 'daily') {
          return DateTime(base.year, base.month, base.day + 1, base.hour,
              base.minute, base.second);
        }
        final parts = s.split(':');
        if (parts.length > 1) {
          final daysPart = parts[1];
          final allowed = <int>{};
          for (final p in daysPart.split(',')) {
            final n = int.tryParse(p.trim());
            if (n != null && n >= 1 && n <= 7) allowed.add(n);
          }
          if (allowed.isEmpty)
            return DateTime(base.year, base.month, base.day + 1, base.hour,
                base.minute, base.second);
          for (int i = 1; i <= 30; i++) {
            final cand = base.add(Duration(days: i));
            if (allowed.contains(cand.weekday))
              return DateTime(cand.year, cand.month, cand.day, base.hour,
                  base.minute, base.second);
          }
          return null;
        }
      }

      // WEEKLY variants: 'weekly' or 'weekly:N' where N is interval weeks
      if (s.startsWith('weekly')) {
        final parts = s.split(':');
        if (parts.length == 1) return base.add(const Duration(days: 7));
        final n = int.tryParse(parts[1]);
        if (n != null && n > 0) return base.add(Duration(days: 7 * n));
        return base.add(const Duration(days: 7));
      }

      // MONTHLY variants: 'monthly' or 'monthly:day=15' or 'monthly:weekday=first:1' / 'monthly:weekday=last:1'
      if (s.startsWith('monthly')) {
        final after = s.contains(':') ? s.split(':').sublist(1).join(':') : '';
        if (after.isEmpty || after == '') {
          // simple monthly: add one month preserving day (clamped)
          int y = base.year;
          int m = base.month + 1;
          if (m > 12) {
            m = 1;
            y += 1;
          }
          final lastDay = DateTime(y, m + 1, 0).day;
          final d = base.day <= lastDay ? base.day : lastDay;
          return DateTime(y, m, d, base.hour, base.minute, base.second);
        }
        // parse key=value or weekday spec
        try {
          // day=15
          if (after.startsWith('day=')) {
            final v = int.tryParse(after.substring(4));
            if (v != null && v >= 1 && v <= 31) {
              // find next month where day exists and date > base
              for (int add = 1; add <= 24; add++) {
                int y = base.year + ((base.month - 1 + add) ~/ 12);
                int m = ((base.month - 1 + add) % 12) + 1;
                final lastDay = DateTime(y, m + 1, 0).day;
                final day = v <= lastDay ? v : lastDay;
                final cand =
                    DateTime(y, m, day, base.hour, base.minute, base.second);
                if (cand.isAfter(base)) return cand;
              }
              return null;
            }
          }
          if (after.startsWith('weekday=')) {
            // weekday=first:1 or weekday=last:1 -> rest = 'first:1'
            final rest = after.substring('weekday='.length);
            final parts2 = rest.split(':');
            if (parts2.length >= 2) {
              final which = parts2[0];
              final wd = int.tryParse(parts2[1]);
              if (wd != null && wd >= 1 && wd <= 7) {
                for (int add = 1; add <= 24; add++) {
                  int y = base.year + ((base.month - 1 + add) ~/ 12);
                  int m = ((base.month - 1 + add) % 12) + 1;
                  DateTime cand;
                  if (which == 'first') {
                    // find first weekday wd in month m
                    final firstOfMonth = DateTime(y, m, 1);
                    int offset = (wd - firstOfMonth.weekday) % 7;
                    if (offset < 0) offset += 7;
                    cand = firstOfMonth.add(Duration(days: offset));
                  } else {
                    // last
                    final lastDayDate = DateTime(y, m + 1, 0);
                    int offset = (lastDayDate.weekday - wd) % 7;
                    if (offset < 0) offset += 7;
                    cand = lastDayDate.subtract(Duration(days: offset));
                  }
                  cand = DateTime(cand.year, cand.month, cand.day, base.hour,
                      base.minute, base.second);
                  if (cand.isAfter(base)) return cand;
                }
              }
            }
          }
        } catch (_) {}
        return null;
      }

      // YEARLY
      if (s.startsWith('yearly')) {
        // simple yearly: add one year, clamping feb29
        try {
          final y = base.year + 1;
          final m = base.month;
          final lastDay = DateTime(y, m + 1, 0).day;
          final d = base.day <= lastDay ? base.day : lastDay;
          return DateTime(y, m, d, base.hour, base.minute, base.second);
        } catch (_) {
          return null;
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  // Public wrapper for tests and external callers
  DateTime? computeNextRecurrence(DateTime base, String recurrence) =>
      _computeNextRecurrence(base, recurrence);

  void _startAttentionTimer() {
    _attentionTimer = Timer(_attentionDuration, () async {
      if (_attentionFired) return;
      final now = DateTime.now();
      if (!_isWithinReminderWindow(now)) {
        final delay = _durationUntilNextWindowStart(now);
        _attentionTimer = Timer(delay, () async {
          if (_attentionFired) return;
          if (_attentionSoundEnabled) {
            try {
              await _playShortSound('sounds/there.mp3', alert: true);
            } catch (_) {}
          }
          if (_attentionFlashEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('flashTaskbar');
            } catch (_) {}
          }
          if (_attentionNotifyEnabled) {
            try {
              await _nativeWindowChannel
                  .invokeMethod('notify', <String, String>{
                'title': _appTitle,
                'body': 'You have been inactive for $_attentionMinutes minutes',
                'icon': 'assets/icons/color_transparent_icon.png',
              });
            } catch (_) {}
          }
          if (_attentionBringToFrontEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('bringToFront');
            } catch (_) {}
          }
          _attentionFired = true;
        });
        return;
      }
      if (_attentionSoundEnabled) {
        try {
          await _playShortSound('sounds/there.mp3', alert: true);
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
            'icon': 'assets/icons/color_transparent_icon.png',
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
      final now = DateTime.now();
      if (!_isWithinReminderWindow(now)) {
        final delay = _durationUntilNextWindowStart(now);
        _reminderTimer = Timer(delay, () async {
          if (_reminderFired) return;
          if (_reminderSoundEnabled) {
            try {
              await _playShortSound('sounds/there.mp3', alert: true);
            } catch (_) {}
          }
          if (_reminderFlashEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('flashTaskbar');
            } catch (_) {}
          }
          if (_reminderNotifyEnabled) {
            try {
              await _nativeWindowChannel
                  .invokeMethod('notify', <String, String>{
                'title': _appTitle,
                'body': 'You have been inactive for $_reminderMinutes minutes',
                'icon': 'assets/icons/color_transparent_icon.png',
              });
            } catch (_) {}
          }
          if (_reminderBringToFrontEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('bringToFront');
            } catch (_) {}
          }
          _reminderFired = true;
        });
        return;
      }
      if (_reminderSoundEnabled) {
        try {
          await _playShortSound('sounds/there.mp3', alert: true);
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
            'icon': 'assets/icons/color_transparent_icon.png',
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
      final now = DateTime.now();
      if (!_isWithinReminderWindow(now)) {
        final delay = _durationUntilNextWindowStart(now);
        _urgentTimer = Timer(delay, () async {
          if (_urgentFired) return;
          if (_urgentSoundEnabled) {
            try {
              await _playShortSound('sounds/there.mp3', alert: true);
            } catch (_) {}
          }
          if (_urgentFlashEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('flashTaskbar');
            } catch (_) {}
          }
          if (_urgentNotifyEnabled) {
            try {
              await _nativeWindowChannel
                  .invokeMethod('notify', <String, String>{
                'title': _appTitle,
                'body': 'You have been inactive for $_urgentMinutes minutes',
                'icon': 'assets/icons/color_transparent_icon.png',
              });
            } catch (_) {}
          }
          if (_urgentBringToFrontEnabled) {
            try {
              await _nativeWindowChannel.invokeMethod('bringToFront');
            } catch (_) {}
          }
          _urgentFired = true;
        });
        return;
      }
      if (_urgentSoundEnabled) {
        try {
          await _playShortSound('sounds/there.mp3', alert: true);
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
            'icon': 'assets/icons/color_transparent_icon.png',
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

  void _startInactivityTimers() {
    // cancel existing
    for (final t in _inactivityTimers) {
      try {
        t?.cancel();
      } catch (_) {}
    }
    _inactivityTimers =
        List<Timer?>.filled(_inactivityReminders.length, null, growable: true);
    _inactivityFired =
        List<bool>.filled(_inactivityReminders.length, false, growable: true);
    for (var i = 0; i < _inactivityReminders.length; i++) {
      final stage = _inactivityReminders[i];
      final minutes = (stage['minutes'] is int)
          ? stage['minutes'] as int
          : int.tryParse(stage['minutes']?.toString() ?? '') ?? 0;
      final duration = Duration(minutes: minutes.clamp(1, 720));
      _inactivityTimers[i] = Timer(duration, () async {
        if (_inactivityFired.length > i && _inactivityFired[i]) return;
        final now = DateTime.now();
        if (!_isWithinReminderWindow(now)) {
          final delay = _durationUntilNextWindowStart(now);
          _inactivityTimers[i] = Timer(delay, () async {
            if (_inactivityFired.length > i && _inactivityFired[i]) return;
            await _fireInactivityStage(i);
          });
          return;
        }
        await _fireInactivityStage(i);
      });
    }
  }

  Future<void> _fireInactivityStage(int i) async {
    if (i < 0 || i >= _inactivityReminders.length) return;
    final stage = _inactivityReminders[i];
    final minutes = stage['minutes']?.toString() ?? '';
    final sound = stage['sound'] == true;
    final flash = stage['flash'] == true;
    final notify = stage['notify'] == true;
    final bring = stage['bringToFront'] == true;
    if (sound) {
      try {
        await _playShortSound('sounds/there.mp3', alert: true);
      } catch (_) {
        SystemSound.play(SystemSoundType.alert);
      }
    }
    if (flash) {
      try {
        await _nativeWindowChannel.invokeMethod('flashTaskbar');
      } catch (_) {}
    }
    if (notify) {
      try {
        await _nativeWindowChannel.invokeMethod('notify', <String, String>{
          'title': _appTitle,
          'body': 'You have been inactive for $minutes minutes',
          'icon': 'assets/icons/color_transparent_icon.png',
        });
      } catch (_) {}
    }
    if (bring) {
      try {
        await _nativeWindowChannel.invokeMethod('bringToFront');
      } catch (_) {}
    }
    if (_inactivityFired.length > i) _inactivityFired[i] = true;
  }

  Widget _buildFancyLoadingScreen(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<int>(
          stream: _loadingTickStream,
          initialData: 0,
          builder: (context, snap) {
            final tick = (snap.data ?? 0).toDouble();
            final blend = 0.5 + 0.5 * math.sin(tick * 0.12);
            final primaryGlow =
                Color.lerp(cs.primaryContainer, cs.tertiaryContainer, blend)!;
            final secondaryGlow =
                Color.lerp(cs.tertiaryContainer, cs.primaryContainer, blend)!;

            double pulse(int phase) {
              return 0.55 +
                  0.45 * (0.5 + 0.5 * math.sin((tick + phase * 1.3) * 0.9));
            }

            final mqSize = MediaQuery.of(context).size;
            if (mqSize.width <= 24 || mqSize.height <= 24) {
              return const SizedBox.shrink();
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.surface,
                          Color.lerp(cs.surface, cs.secondaryContainer, 0.22)!,
                          Color.lerp(cs.surface, cs.primaryContainer, 0.28)!,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 40 + 8 * math.sin(tick * 0.25),
                  left: 20,
                  child: _LoadingGlowBlob(color: primaryGlow, size: 160),
                ),
                Positioned(
                  right: 16,
                  bottom: 30 + 12 * math.cos(tick * 0.21),
                  child: _LoadingGlowBlob(color: secondaryGlow, size: 140),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 140 + 10 * math.sin(tick * 0.18),
                  child: Center(
                    child: _LoadingGlowBlob(
                      color: Color.lerp(primaryGlow, secondaryGlow, 0.5)!,
                      size: 120,
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.asset(
                              'assets/icons/color_transparent_icon.png',
                              width: 28,
                              height: 28,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'simplepresent',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: _fontFamily,
                                  color: cs.onSurface
                                      .withAlpha((0.78 * 255).round()),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (i) {
                            final p = pulse(i);
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              width: 10 + (p * 6),
                              height: 10 + (p * 6),
                              decoration: BoxDecoration(
                                color: Color.lerp(cs.primary, cs.tertiary, p),
                                shape: BoxShape.circle,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'loading tasks...',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: _fontFamily,
                            color: cs.onSurface.withAlpha((0.86 * 255).round()),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'syncing, repairing and preparing your workspace',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: _fontFamily,
                            color: cs.onSurfaceVariant
                                .withAlpha((0.84 * 255).round()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
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
            // Show loading screen while initializing and syncing lists.
            if (snap.connectionState == ConnectionState.waiting) {
              return _buildFancyLoadingScreen(context);
            }

            return Scaffold(
              body: Stack(
                children: [
                  Listener(
                    onPointerDown: (_) => _registerActivity(),
                    onPointerMove: _collectMouseEntropy,
                    // Task zoom via pointer signals disabled
                    onPointerSignal: (_) {},
                    child: GestureDetector(
                      // Pinch-to-zoom disabled for tasks
                      onScaleStart: (_) {},
                      onScaleUpdate: (_) {},
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        if (!Platform.isAndroid) _requestInputFocusIfIdle();
                        _registerActivity();
                      },
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            height: Platform.isAndroid
                                ? MediaQuery.of(context).padding.top
                                : 0.0,
                          ),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.fromLTRB(12, 22, 6, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    child: Row(
                                      key: const ValueKey('header_visible'),
                                      children: [
                                        // Left arrow moved to the far left of the header row
                                        IconButton(
                                          icon: Icon(_showingDone
                                              ? Icons.arrow_back
                                              : Icons.arrow_back_ios),
                                          tooltip: _showingDone
                                              ? 'Back'
                                              : 'Previous',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                              minWidth: 28, minHeight: 28),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () async {
                                            if (_showingDone) {
                                              await _switchFile(false);
                                            } else {
                                              await _cycleView(false);
                                            }
                                          },
                                        ),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 0),
                                                child: Image.asset(
                                                  _showingBacklog
                                                      ? 'assets/icons/color_transparent_backlog.png'
                                                      : (_showingDone
                                                          ? 'assets/icons/color_transparent_done.png'
                                                          : 'assets/icons/color_transparent_today.png'),
                                                  width: 28,
                                                  height: 28,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _showingDone
                                                    ? SizedBox(
                                                        height: 44,
                                                        child: TextField(
                                                          controller:
                                                              _doneSearchController,
                                                          onChanged: (v) =>
                                                              setState(() {
                                                            _doneSearchQuery =
                                                                v.trim();
                                                          }),
                                                          decoration:
                                                              InputDecoration(
                                                            hintText:
                                                                'Search done',
                                                            isDense: true,
                                                            contentPadding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    vertical:
                                                                        10,
                                                                    horizontal:
                                                                        12),
                                                            suffixIcon:
                                                                _doneSearchQuery
                                                                        .isNotEmpty
                                                                    ? IconButton(
                                                                        icon: const Icon(
                                                                            Icons.clear),
                                                                        onPressed:
                                                                            () {
                                                                          _doneSearchController
                                                                              .clear();
                                                                          setState(
                                                                              () {
                                                                            _doneSearchQuery =
                                                                                '';
                                                                          });
                                                                        },
                                                                      )
                                                                    : null,
                                                          ),
                                                        ),
                                                      )
                                                    : Text(
                                                        _showingBacklog
                                                            ? 'backlog'
                                                            : 'today',
                                                        style: const TextStyle(
                                                                fontSize: 24,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)
                                                            .copyWith(
                                                                fontFamily:
                                                                    _fontFamily),
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                              ),
                                              const SizedBox(width: 8.0),
                                              Text(
                                                (_showingBacklog
                                                        ? _countBacklog
                                                        : (_showingDone
                                                            ? _countDone
                                                            : _countToday))
                                                    .toString(),
                                                style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w400),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            PopupMenuButton<String>(
                                              icon: Icon(Icons.more_vert,
                                                  color: Theme.of(context)
                                                      .iconTheme
                                                      .color),
                                              onSelected: (v) async {
                                                await _finalizeAllEdits();
                                                if (v == 'stats')
                                                  await _openStats();
                                                else if (v == 'settings')
                                                  await _openSettings();
                                                else if (v == 'notes')
                                                  await _openNotes();
                                                else if (v == 'export')
                                                  await _exportViaChooser();
                                                else if (v == 'import')
                                                  await _importViaChooser();
                                                else if (v == 'redo') {
                                                  final res = await Navigator
                                                          .of(context)
                                                      .push(MaterialPageRoute(
                                                          builder: (ctx) =>
                                                              const RedoLogPage()));
                                                  if (res is Map &&
                                                      res['undo'] == true &&
                                                      res['entry'] is Map<
                                                          String, dynamic>) {
                                                    try {
                                                      await _loadToday();
                                                    } catch (_) {}
                                                    try {
                                                      _showTopToast(
                                                          'undo applied');
                                                    } catch (_) {}
                                                  } else if (res == true) {
                                                    try {
                                                      await _loadToday();
                                                    } catch (_) {}
                                                    try {
                                                      _showTopToast(
                                                          'undo applied');
                                                    } catch (_) {}
                                                  }
                                                } else if (v == 'done') {
                                                  await _switchFile(true);
                                                }
                                              },
                                              itemBuilder: (ctx) {
                                                final items =
                                                    <PopupMenuEntry<String>>[];
                                                items.add(PopupMenuItem(
                                                    value: 'stats',
                                                    child: Row(children: [
                                                      Image.asset(
                                                          'assets/icons/white_transparent_statistic.png',
                                                          width: 18,
                                                          height: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('statistics')
                                                    ])));
                                                items.add(PopupMenuItem(
                                                    value: 'settings',
                                                    child: Row(children: [
                                                      Image.asset(
                                                          'assets/icons/white_transparent_settings.png',
                                                          width: 18,
                                                          height: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('settings')
                                                    ])));
                                                items.add(PopupMenuItem(
                                                    value: 'notes',
                                                    child: Row(children: [
                                                      Image.asset(
                                                          'assets/icons/white_transparent_notes.png',
                                                          width: 18,
                                                          height: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('notes')
                                                    ])));
                                                items.add(PopupMenuItem(
                                                    value: 'redo',
                                                    child: Row(children: [
                                                      Image.asset(
                                                          'assets/icons/white_transparent_redo.png',
                                                          width: 18,
                                                          height: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('redo log')
                                                    ])));
                                                items.add(PopupMenuItem(
                                                    value: 'export',
                                                    child: Row(children: [
                                                      Icon(
                                                          Icons
                                                              .download_rounded,
                                                          size: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('export')
                                                    ])));
                                                items.add(PopupMenuItem(
                                                    value: 'import',
                                                    child: Row(children: [
                                                      Icon(Icons.upload_rounded,
                                                          size: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('import')
                                                    ])));
                                                items.add(PopupMenuItem(
                                                    value: 'done',
                                                    child: Row(children: [
                                                      Image.asset(
                                                          'assets/icons/white_transparent_done.png',
                                                          width: 18,
                                                          height: 18),
                                                      const SizedBox(width: 8),
                                                      const Text('done')
                                                    ])));
                                                // 'Next' removed by request
                                                return items;
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
                                    height: 8.0,
                                  ),
                                  Expanded(
                                    child: _today.isEmpty
                                        ? Center(
                                            child: Text(_showingBacklog
                                                ? 'no backlog tasks'
                                                : (_showingDone
                                                    ? 'no archived tasks'
                                                    : 'no tasks for today')))
                                        : Builder(builder: (ctx) {
                                            // Build grouped list preserving insertion order within groups.
                                            // Order must match _performDelayedReorder schema.
                                            final bucketImportantInProgress =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketInProgressScheduledPast =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketInProgressNoSchedule =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketInProgressScheduledFuture =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketImportant =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketScheduledPast =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketDueIn1h =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketRest =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketScheduledFuture =
                                                <MapEntry<int, TaskItem>>[];
                                            final bucketDone =
                                                <MapEntry<int, TaskItem>>[];

                                            final now = DateTime.now();
                                            final entries =
                                                _today.asMap().entries;
                                            // If viewing Done and a search query is present,
                                            // filter entries so only matching tasks are processed.
                                            Iterable<MapEntry<int, TaskItem>>
                                                entriesFiltered = entries;
                                            if (_showingDone &&
                                                _doneSearchQuery.isNotEmpty) {
                                              final q = _doneSearchQuery
                                                  .toLowerCase();
                                              entriesFiltered =
                                                  entries.where((e) {
                                                final t = e.value;
                                                final txt =
                                                    t.text.toLowerCase();
                                                final notes = (t.notes ?? '')
                                                    .toLowerCase();
                                                return txt.contains(q) ||
                                                    notes.contains(q);
                                              });
                                            }
                                            for (final e in entriesFiltered) {
                                              final t = e.value;
                                              if (t.done) {
                                                bucketDone.add(e);
                                                continue;
                                              }
                                              final hasSchedule =
                                                  t.scheduledAt != null;
                                              final diff = hasSchedule
                                                  ? t.scheduledAt!
                                                      .difference(now)
                                                  : null;
                                              final isOverdue = hasSchedule &&
                                                  diff!.isNegative;
                                              final dueWithin1h = hasSchedule &&
                                                  !diff!.isNegative &&
                                                  diff.inMinutes <= 60;

                                              final isScheduledFuture =
                                                  hasSchedule &&
                                                      !isOverdue &&
                                                      !dueWithin1h;

                                              if (t.inProgress && t.important) {
                                                bucketImportantInProgress
                                                    .add(e);
                                                continue;
                                              }
                                              if (t.inProgress) {
                                                if (isOverdue) {
                                                  bucketInProgressScheduledPast
                                                      .add(e);
                                                } else if (isScheduledFuture) {
                                                  bucketInProgressScheduledFuture
                                                      .add(e);
                                                } else {
                                                  bucketInProgressNoSchedule
                                                      .add(e);
                                                }
                                                continue;
                                              }
                                              if (t.important) {
                                                bucketImportant.add(e);
                                                continue;
                                              }
                                              if (isOverdue) {
                                                bucketScheduledPast.add(e);
                                                continue;
                                              }
                                              if (dueWithin1h) {
                                                bucketDueIn1h.add(e);
                                                continue;
                                              }
                                              if (isScheduledFuture) {
                                                bucketScheduledFuture.add(e);
                                                continue;
                                              }
                                              bucketRest.add(e);
                                            }

                                            final sorted = [
                                              ...bucketImportantInProgress,
                                              ...bucketInProgressScheduledPast,
                                              ...bucketInProgressNoSchedule,
                                              ...bucketInProgressScheduledFuture,
                                              ...bucketImportant,
                                              ...bucketScheduledPast,
                                              ...bucketDueIn1h,
                                              ...bucketRest,
                                              ...bucketScheduledFuture,
                                              ...bucketDone,
                                            ];

                                            return ReorderableListView(
                                              scrollController:
                                                  _listScrollController,
                                              buildDefaultDragHandles: false,
                                              onReorderItem:
                                                  (oldIndex, newIndex) {
                                                if (oldIndex < 0 ||
                                                    oldIndex >= sorted.length) {
                                                  return;
                                                }
                                                final srcEntry =
                                                    sorted[oldIndex];
                                                // Determine bucket membership for src and dst
                                                int bucketOf(
                                                    MapEntry<int, TaskItem> e) {
                                                  if (bucketImportantInProgress
                                                      .contains(e)) return 0;
                                                  if (bucketInProgressScheduledPast
                                                      .contains(e)) return 1;
                                                  if (bucketInProgressNoSchedule
                                                      .contains(e)) return 2;
                                                  if (bucketInProgressScheduledFuture
                                                      .contains(e)) return 3;
                                                  if (bucketImportant
                                                      .contains(e)) return 4;
                                                  if (bucketScheduledPast
                                                      .contains(e)) return 5;
                                                  if (bucketDueIn1h.contains(e))
                                                    return 6;
                                                  if (bucketRest.contains(e))
                                                    return 7;
                                                  if (bucketScheduledFuture
                                                      .contains(e)) return 8;
                                                  return 9; // done
                                                }

                                                final srcBucket =
                                                    bucketOf(srcEntry);
                                                final safeNewIndex = newIndex
                                                    .clamp(0, sorted.length);
                                                final probeIndex =
                                                    safeNewIndex >=
                                                            sorted.length
                                                        ? sorted.length - 1
                                                        : safeNewIndex;
                                                final dstBucket = bucketOf(
                                                    sorted[probeIndex]);
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
                                                    targetBucket =
                                                        bucketImportantInProgress;
                                                    break;
                                                  case 1:
                                                    targetBucket =
                                                        bucketInProgressScheduledPast;
                                                    break;
                                                  case 2:
                                                    targetBucket =
                                                        bucketInProgressNoSchedule;
                                                    break;
                                                  case 3:
                                                    targetBucket =
                                                        bucketInProgressScheduledFuture;
                                                    break;
                                                  case 4:
                                                    targetBucket =
                                                        bucketImportant;
                                                    break;
                                                  case 5:
                                                    targetBucket =
                                                        bucketScheduledPast;
                                                    break;
                                                  case 6:
                                                    targetBucket =
                                                        bucketDueIn1h;
                                                    break;
                                                  case 7:
                                                    targetBucket = bucketRest;
                                                    break;
                                                  case 8:
                                                    targetBucket =
                                                        bucketScheduledFuture;
                                                    break;
                                                  default:
                                                    targetBucket = bucketDone;
                                                }

                                                // onReorderItem already gives
                                                // a post-removal newIndex.
                                                final adjustedNewIndex =
                                                    safeNewIndex;
                                                if (adjustedNewIndex ==
                                                    oldIndex) {
                                                  return;
                                                }

                                                final reordered = List<
                                                    MapEntry<int,
                                                        TaskItem>>.from(sorted);
                                                final moved = reordered
                                                    .removeAt(oldIndex);
                                                reordered.insert(
                                                    adjustedNewIndex, moved);

                                                final reorderedBucket =
                                                    reordered
                                                        .where((e) =>
                                                            bucketOf(e) ==
                                                            srcBucket)
                                                        .toList();

                                                setState(() {
                                                  targetBucket
                                                    ..clear()
                                                    ..addAll(reorderedBucket);

                                                  // rebuild _today preserving bucket concatenation order
                                                  final newOrder = <TaskItem>[];
                                                  void appendBucket(
                                                          List<
                                                                  MapEntry<int,
                                                                      TaskItem>>
                                                              b) =>
                                                      newOrder.addAll(b
                                                          .map((e) => e.value));
                                                  appendBucket(
                                                      bucketImportantInProgress);
                                                  appendBucket(
                                                      bucketInProgressScheduledPast);
                                                  appendBucket(
                                                      bucketInProgressNoSchedule);
                                                  appendBucket(
                                                      bucketInProgressScheduledFuture);
                                                  appendBucket(bucketImportant);
                                                  appendBucket(
                                                      bucketScheduledPast);
                                                  appendBucket(bucketDueIn1h);
                                                  appendBucket(bucketRest);
                                                  appendBucket(
                                                      bucketScheduledFuture);
                                                  appendBucket(bucketDone);
                                                  _today.clear();
                                                  _today.addAll(newOrder);
                                                  _saveToday();
                                                });
                                              },
                                              children: List.generate(
                                                  sorted.length, (vi) {
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
                                                // Minimal-mode removed: always render the full task Dismissible below.
                                                final containerKey =
                                                    _tileKeys.putIfAbsent(
                                                        task.id,
                                                        () => GlobalKey());
                                                final firstIndexForId =
                                                    _today.indexWhere(
                                                        (t) => t.id == task.id);
                                                final tileBodyKey =
                                                    firstIndexForId == i
                                                        ? containerKey
                                                        : ValueKey(
                                                            'dup-${task.id}-$i');
                                                final bool _isDimmed =
                                                    _stagedDone[task.id] ??
                                                        task.done;
                                                final Color _iconColor =
                                                    _isDimmed
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withAlpha(
                                                                (0.30 * 255)
                                                                    .round())
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface;
                                                final Color _primaryTextColor =
                                                    _isDimmed
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurface
                                                            .withAlpha(
                                                                (0.30 * 255)
                                                                    .round())
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurface;
                                                final Color _variantColor =
                                                    _isDimmed
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant
                                                            .withAlpha(
                                                                (0.30 * 255)
                                                                    .round())
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant;
                                                return Dismissible(
                                                  key:
                                                      ValueKey('${task.id}-$i'),
                                                  background: Container(
                                                    color: Colors.green,
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    padding:
                                                        const EdgeInsets.only(
                                                            left: 20),
                                                    child: (_showingBacklog ||
                                                            _currentFile ==
                                                                _storage(
                                                                    'simplepresent_backlog.json'))
                                                        ? Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              const Icon(
                                                                  Icons
                                                                      .arrow_circle_left,
                                                                  color: Colors
                                                                      .white,
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
                                                                  const Text(
                                                                      'done',
                                                                      style: TextStyle(
                                                                          color: Colors
                                                                              .white,
                                                                          fontWeight:
                                                                              FontWeight.w600)),
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
                                                                              FontWeight.w600)),
                                                                ],
                                                              )),
                                                  ),
                                                  secondaryBackground:
                                                      Container(
                                                    color:
                                                        (_today[i].inProgress &&
                                                                !_today[i].done)
                                                            ? Colors.transparent
                                                            : Colors.red,
                                                    alignment:
                                                        Alignment.centerRight,
                                                    // align delete icon where the star sits (far right)
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 12),
                                                    child: (_today[i]
                                                                .inProgress &&
                                                            !_today[i].done)
                                                        ? Text(
                                                            'open',
                                                            style: TextStyle(
                                                              decoration:
                                                                  TextDecoration
                                                                      .none,
                                                              color: Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .onSurface,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          )
                                                        : const Icon(
                                                            Icons.delete,
                                                            color:
                                                                Colors.white),
                                                  ),
                                                  confirmDismiss:
                                                      (direction) async {
                                                    final t = _today[i];
                                                    final taskId = t.id;
                                                    // Prevent swipe actions when the task is expanded/open
                                                    if (_expanded.contains(
                                                        taskId)) return false;

                                                    if (direction ==
                                                        DismissDirection
                                                            .startToEnd) {
                                                      // Right swipe: queue action, return immediately to snap back
                                                      if (_currentFile ==
                                                              _storage(
                                                                  'simplepresent_backlog.json') ||
                                                          _showingBacklog) {
                                                        // Backlog view: move to Today
                                                        _performSwipeAction(
                                                            taskId,
                                                            'moveFromBacklog');
                                                        return false;
                                                      }
                                                      if (!t.inProgress &&
                                                          !t.done) {
                                                        // Today view: set in progress
                                                        _performSwipeAction(
                                                            taskId,
                                                            'setInProgress');
                                                        return false;
                                                      }
                                                      if (t.inProgress &&
                                                          !t.done) {
                                                        // Today view: set done
                                                        _performSwipeAction(
                                                            taskId, 'setDone');
                                                        return false;
                                                      }
                                                      return false;
                                                    }

                                                    if (direction ==
                                                        DismissDirection
                                                            .endToStart) {
                                                      // Left swipe: if inProgress, unset it; otherwise delete
                                                      if (t.inProgress &&
                                                          !t.done) {
                                                        _performSwipeAction(
                                                            taskId,
                                                            'unsetInProgress');
                                                        return false;
                                                      }

                                                      // Otherwise ask for delete confirmation
                                                      final shouldDelete =
                                                          await showDialog<
                                                              bool>(
                                                        context: context,
                                                        builder:
                                                            (dialogContext) =>
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
                                                                      .pop(
                                                                          false),
                                                              child: const Text(
                                                                  'cancel'),
                                                            ),
                                                            FilledButton(
                                                              autofocus: true,
                                                              onPressed: () =>
                                                                  Navigator.of(
                                                                          dialogContext)
                                                                      .pop(
                                                                          true),
                                                              child: const Text(
                                                                  'delete'),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      return shouldDelete ==
                                                          true;
                                                    }

                                                    return false;
                                                  },
                                                  direction: (!_expanded
                                                              .contains(
                                                                  task.id) &&
                                                          _swipeEnabled)
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
                                                        key: tileBodyKey,
                                                        color: (task.inProgress
                                                            ? Colors.green
                                                                .withAlpha(
                                                                    (0.10 * 255)
                                                                        .round())
                                                            : null),
                                                        child: ListTile(
                                                          contentPadding: EdgeInsets
                                                              .symmetric(
                                                                  vertical: ((_tileHeight -
                                                                              _baseFontSize) /
                                                                          2)
                                                                      .clamp(
                                                                          0.0,
                                                                          40.0),
                                                                  horizontal:
                                                                      12),
                                                          onTap: () =>
                                                              _toggleExpanded(
                                                                  i),
                                                          leading: _busyTaskIds
                                                                  .contains(
                                                                      task.id)
                                                              ? const SizedBox(
                                                                  width: 48,
                                                                  height: 48,
                                                                  child: Center(
                                                                    child:
                                                                        SizedBox(
                                                                      width: 20,
                                                                      height:
                                                                          20,
                                                                      child: CircularProgressIndicator(
                                                                          strokeWidth:
                                                                              2),
                                                                    ),
                                                                  ),
                                                                )
                                                              : IconButton(
                                                                  tooltip:
                                                                      'done',
                                                                  icon: Icon(
                                                                      (_stagedDone[task.id] ??
                                                                              task
                                                                                  .done)
                                                                          ? Icons
                                                                              .radio_button_checked
                                                                          : Icons
                                                                              .radio_button_unchecked,
                                                                      color: ((task.important &&
                                                                              !task.done)
                                                                          ? Colors.amber
                                                                          : _iconColor),
                                                                      size: 18),
                                                                  onPressed:
                                                                      () async {
                                                                    final current =
                                                                        _stagedDone[task.id] ??
                                                                            task.done;
                                                                    final newVal =
                                                                        !current;
                                                                    // If we're in Done view and unchecking, perform immediate move back to Today
                                                                    if (!newVal &&
                                                                        _currentFile ==
                                                                            _storage('simplepresent_done.json') &&
                                                                        task.done) {
                                                                      await _queueSetDoneByTaskId(
                                                                          task.id,
                                                                          newVal);
                                                                      return;
                                                                    }
                                                                    // If we're in Backlog view and marking done, mirror Today behavior:
                                                                    // set the radio button immediately (via _stagedDone) and start a short timer
                                                                    if (_currentFile ==
                                                                            _storage(
                                                                                'simplepresent_backlog.json') &&
                                                                        !task
                                                                            .done) {
                                                                      if (newVal) {
                                                                        // set visual state immediately
                                                                        setState(() =>
                                                                            _stagedDone[task.id] =
                                                                                true);
                                                                        // perform done immediately
                                                                        try {
                                                                          await _queueSetDoneByTaskId(
                                                                              task.id,
                                                                              true);
                                                                        } catch (_) {}
                                                                        return;
                                                                      } else {
                                                                        // user unchecked before timer fired: cancel timer and clear staged state
                                                                        setState(() =>
                                                                            _stagedDone.remove(task.id));
                                                                        return;
                                                                      }
                                                                    }
                                                                    // Stage the change and schedule delayed reorder
                                                                    setState(() =>
                                                                        _stagedDone[task.id] =
                                                                            newVal);
                                                                    _scheduleDelayedReorder();
                                                                  },
                                                                ),
                                                          title: Row(
                                                            children: [
                                                              Expanded(
                                                                child: _expanded
                                                                        .contains(task
                                                                            .id)
                                                                    ? const SizedBox
                                                                        .shrink()
                                                                    : Column(
                                                                        crossAxisAlignment:
                                                                            CrossAxisAlignment.start,
                                                                        children: [
                                                                          Text(
                                                                            task.text,
                                                                            style:
                                                                                _fontTextStyle(
                                                                              TextStyle(
                                                                                fontSize: _baseFontSize,
                                                                                fontWeight: FontWeight.normal,
                                                                                decoration: TextDecoration.none,
                                                                                color: task.done ? _primaryTextColor.withAlpha((0.6 * 255).round()) : (task.important ? Colors.amber : _primaryTextColor),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                          if (totalSubtasks >
                                                                              0)
                                                                            Padding(
                                                                              padding: const EdgeInsets.only(top: 2.0),
                                                                              child: Text(
                                                                                '$completedSubtasks/$totalSubtasks',
                                                                                style: TextStyle(
                                                                                  fontSize: 12,
                                                                                  color: _variantColor,
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          if (task.done &&
                                                                              task.completedAt != null)
                                                                            Padding(
                                                                              padding: const EdgeInsets.only(top: 4.0),
                                                                              child: Text(
                                                                                'completed: ${DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!)}',
                                                                                style: TextStyle(
                                                                                  fontSize: 12,
                                                                                  color: _variantColor,
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
                                                                              final manual = task.workMinutes;
                                                                              final totalMinutes = manual + accumulatedMinutes;
                                                                              if (totalMinutes <= 0)
                                                                                return const SizedBox.shrink();
                                                                              final hours = totalMinutes ~/ 60;
                                                                              final mins = totalMinutes % 60;
                                                                              final label = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
                                                                              return Padding(
                                                                                padding: const EdgeInsets.only(top: 4.0),
                                                                                child: Text(
                                                                                  'spent: $label',
                                                                                  style: TextStyle(
                                                                                    fontSize: 12,
                                                                                    color: _variantColor,
                                                                                  ),
                                                                                ),
                                                                              );
                                                                            }),
                                                                        ],
                                                                      ),
                                                              ),
                                                              const SizedBox(
                                                                  width: 2),
                                                              // Right aligned icons: scheduled+time, in-progress, save (when expanded), star (far right)
                                                              Opacity(
                                                                opacity: _swiping
                                                                        .contains(
                                                                            i)
                                                                    ? 0.0
                                                                    : 1.0,
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    // Calendar button with time below it (date shown in backlog)
                                                                    if (!(_stagedDone[
                                                                            task.id] ??
                                                                        task.done))
                                                                      Padding(
                                                                        padding: const EdgeInsets
                                                                            .only(
                                                                            left:
                                                                                4.0,
                                                                            right:
                                                                                2.0),
                                                                        child:
                                                                            Column(
                                                                          mainAxisSize:
                                                                              MainAxisSize.min,
                                                                          children: [
                                                                            IconButton(
                                                                              padding: const EdgeInsets.all(4),
                                                                              constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                                                              tooltip: task.scheduledAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.scheduledAt!) : 'set schedule',
                                                                              icon: Icon(Icons.calendar_today, size: 18, color: task.scheduledAt != null ? _scheduleIconColor(task.scheduledAt!) : _iconColor),
                                                                              onPressed: () => _pickSchedule(i),
                                                                            ),
                                                                            if (task.scheduledAt !=
                                                                                null)
                                                                              Padding(
                                                                                padding: const EdgeInsets.only(top: 2.0),
                                                                                child: Column(
                                                                                  mainAxisSize: MainAxisSize.min,
                                                                                  children: [
                                                                                    Text(
                                                                                      DateFormat('HH:mm').format(task.scheduledAt!),
                                                                                      style: TextStyle(fontSize: 11, color: _scheduleIconColor(task.scheduledAt!)),
                                                                                    ),
                                                                                    // Show full date in Backlog, or in Today when the scheduled date is not today and is in the past
                                                                                    if (_showingBacklog || _currentFile == _storage('simplepresent_backlog.json') || (task.scheduledAt != null && !_isSameDay(task.scheduledAt!, DateTime.now()) && task.scheduledAt!.isBefore(DateTime.now())))
                                                                                      Text(
                                                                                        (_showingBacklog || _currentFile == _storage('simplepresent_backlog.json')) ? _formatBacklogScheduleLabel(task.scheduledAt!) : (_isSameDay(task.scheduledAt!, DateTime.now().subtract(const Duration(days: 1))) ? 'yesterday' : DateFormat('EEEE').format(task.scheduledAt!)),
                                                                                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                                                      ),
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    if (_currentFile ==
                                                                            _storage('simplepresent_backlog.json') ||
                                                                        _showingBacklog)
                                                                      Padding(
                                                                        padding: const EdgeInsets
                                                                            .only(
                                                                            left:
                                                                                4.0,
                                                                            right:
                                                                                2.0),
                                                                        child:
                                                                            IconButton(
                                                                          padding: const EdgeInsets
                                                                              .all(
                                                                              4),
                                                                          constraints: const BoxConstraints(
                                                                              minWidth: 0,
                                                                              minHeight: 0),
                                                                          tooltip:
                                                                              'move to today',
                                                                          icon: Icon(
                                                                              Icons.arrow_circle_left,
                                                                              size: 20,
                                                                              color: _iconColor),
                                                                          onPressed:
                                                                              () async {
                                                                            await _queueMoveFromBacklogByTaskId(task.id);
                                                                          },
                                                                        ),
                                                                      ),

                                                                    // Important button: moved into expanded editor
                                                                    // Custom D&D handle (reduced left padding)
                                                                    Padding(
                                                                      padding: const EdgeInsets
                                                                          .only(
                                                                          left:
                                                                              2.0),
                                                                      child:
                                                                          Opacity(
                                                                        opacity: _swiping.contains(i)
                                                                            ? 0.0
                                                                            : 1.0,
                                                                        child:
                                                                            ReorderableDragStartListener(
                                                                          index:
                                                                              i,
                                                                          child: Icon(
                                                                              Icons.drag_handle,
                                                                              size: 18,
                                                                              color: _iconColor),
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
                                                      if (_expanded
                                                          .contains(task.id))
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      14.0,
                                                                  vertical:
                                                                      8.0),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              // Editable title in expanded area
                                                              TextField(
                                                                controller: _editControllers
                                                                    .putIfAbsent(
                                                                        task.id,
                                                                        () {
                                                                  final c = TextEditingController(
                                                                      text: task
                                                                          .text);
                                                                  c.addListener(
                                                                      () {
                                                                    if (mounted)
                                                                      setState(
                                                                          () {});
                                                                    _scheduleAutoSave(
                                                                        task.id);
                                                                  });
                                                                  return c;
                                                                }),
                                                                focusNode: _editFocusNodes
                                                                    .putIfAbsent(
                                                                        task.id,
                                                                        () =>
                                                                            FocusNode()),
                                                                autofocus: true,
                                                                decoration:
                                                                    const InputDecoration(
                                                                  border:
                                                                      InputBorder
                                                                          .none,
                                                                  hintText:
                                                                      'title',
                                                                ),
                                                                onSubmitted: (_) =>
                                                                    _saveEditedTitle(
                                                                        i),
                                                              ),
                                                              // (Important button moved to recurrence row)
                                                              const SizedBox(
                                                                  height: 8),
                                                              // Notes field (moved above timestamps)
                                                              TextField(
                                                                controller: _notesControllers
                                                                    .putIfAbsent(
                                                                        task.id,
                                                                        () {
                                                                  final n = TextEditingController(
                                                                      text: task
                                                                              .notes ??
                                                                          '');
                                                                  n.addListener(
                                                                      () {
                                                                    if (mounted)
                                                                      setState(
                                                                          () {});
                                                                    _scheduleAutoSave(
                                                                        task.id);
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
                                                                  hintText:
                                                                      'notes',
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
                                                                      focusNode: _subtaskFocusNodes.putIfAbsent(
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
                                                                              _subtaskInputControllers[task.id]!),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  FilledButton(
                                                                    onPressed: () =>
                                                                        _addSubtask(
                                                                            i,
                                                                            _subtaskInputControllers[task.id]!),
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
                                                                          top:
                                                                              12),
                                                                  child:
                                                                      SizedBox(
                                                                    // let the ReorderableListView size to its children
                                                                    child:
                                                                        ReorderableListView(
                                                                      buildDefaultDragHandles:
                                                                          false,
                                                                      shrinkWrap:
                                                                          true,
                                                                      physics:
                                                                          const NeverScrollableScrollPhysics(),
                                                                      onReorderItem: (oldIndex,
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
                                                                              key: ValueKey('subtask_${task.id}_${step.id}'),
                                                                              child: ListTile(
                                                                                dense: true,
                                                                                leading: Checkbox(
                                                                                  value: step.done,
                                                                                  onChanged: (value) => _updateSubtask(i, step.id, done: value ?? false),
                                                                                ),
                                                                                title: step.done
                                                                                    ? Text(
                                                                                        step.text,
                                                                                        style: TextStyle(
                                                                                          decoration: TextDecoration.none,
                                                                                          color: Theme.of(context).colorScheme.onSurface.withAlpha((0.6 * 255).round()),
                                                                                        ),
                                                                                      )
                                                                                    : TextFormField(
                                                                                        initialValue: step.text,
                                                                                        decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                                                                                        onChanged: (value) => _updateSubtask(i, step.id, text: value),
                                                                                      ),
                                                                                trailing: Row(
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
                                                                      final mm = ((s % 3600) ~/
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
                                                                        width:
                                                                            8),
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
                                                                              _startStopwatch(i),
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
                                                                              _stopStopwatch(i)
                                                                          : null,
                                                                    ),
                                                                    IconButton(
                                                                      tooltip:
                                                                          'reset',
                                                                      icon: const Icon(
                                                                          Icons
                                                                              .restart_alt),
                                                                      onPressed: (task.stopwatchAccumulatedSeconds > 0 ||
                                                                              task
                                                                                  .stopwatchRunning)
                                                                          ? () =>
                                                                              _resetStopwatch(i)
                                                                          : null,
                                                                    ),
                                                                    const SizedBox(
                                                                        width:
                                                                            12),
                                                                    // Manual time entry (time spent) shown to the right of the stopwatch buttons
                                                                    Flexible(
                                                                      child:
                                                                          ConstrainedBox(
                                                                        constraints:
                                                                            const BoxConstraints(maxWidth: 220),
                                                                        child:
                                                                            TextField(
                                                                          controller: _workControllers.putIfAbsent(
                                                                              task.id,
                                                                              () {
                                                                            final initial = task.workMinutes > 0
                                                                                ? task.workMinutes.toString()
                                                                                : '';
                                                                            final c =
                                                                                TextEditingController(text: initial);
                                                                            c.addListener(() {
                                                                              if (mounted)
                                                                                setState(() {});
                                                                            });
                                                                            return c;
                                                                          }),
                                                                          keyboardType:
                                                                              TextInputType.number,
                                                                          decoration: const InputDecoration(
                                                                              border: OutlineInputBorder(),
                                                                              hintText: 'time spent'),
                                                                          onTap:
                                                                              () {
                                                                            // Manual entry only: do not auto-suggest stopwatch time here.
                                                                          },
                                                                          onSubmitted:
                                                                              (value) {
                                                                            final parsed =
                                                                                int.tryParse(value.trim());
                                                                            if (parsed ==
                                                                                null)
                                                                              return;
                                                                            try {
                                                                              unawaited(_queueTaskAction(task.id, () async {
                                                                                final idx = _today.indexWhere((t) => t.id == task.id);
                                                                                if (idx == -1) return;
                                                                                setState(() {
                                                                                  _today[idx] = _today[idx].copyWith(workMinutes: parsed);
                                                                                });
                                                                                await _saveToday();
                                                                                try {
                                                                                  _upsertTimeEntry(_today[idx]);
                                                                                } catch (_) {}
                                                                              }));
                                                                            } catch (_) {}
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
                                                                      onPressed:
                                                                          () =>
                                                                              _clearSchedule(i),
                                                                    ),
                                                                  if (!_showingBacklog &&
                                                                      !_showingDone &&
                                                                      !task
                                                                          .done)
                                                                    IconButton(
                                                                      tooltip:
                                                                          'move to backlog',
                                                                      icon: const Icon(
                                                                          Icons
                                                                              .arrow_circle_right),
                                                                      onPressed:
                                                                          () async {
                                                                        await _queueMoveToBacklogByTaskId(
                                                                            task.id);
                                                                      },
                                                                    ),
                                                                ],
                                                              ),
                                                              const SizedBox(
                                                                  height: 12),
                                                              // Recurrence selector (moved below scheduled)
                                                              Row(
                                                                children: [
                                                                  const Text(
                                                                      'repeat:'),
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  // Open a dialog for recurrence options (supports weekday masks)
                                                                  TextButton(
                                                                    onPressed: () =>
                                                                        _showRecurrenceDialog(
                                                                            i),
                                                                    child: Text(task.recurrence ==
                                                                                null ||
                                                                            task
                                                                                .recurrence!.isEmpty
                                                                        ? 'none'
                                                                        : task
                                                                            .recurrence!),
                                                                  ),
                                                                  const Spacer(),
                                                                  IconButton(
                                                                    tooltip:
                                                                        'Duplicate',
                                                                    icon: Icon(
                                                                        Icons
                                                                            .copy,
                                                                        color: Theme.of(context)
                                                                            .colorScheme
                                                                            .onSurfaceVariant),
                                                                    onPressed:
                                                                        () async {
                                                                      await _duplicateTask(
                                                                          i);
                                                                    },
                                                                  ),
                                                                  IconButton(
                                                                    tooltip: task.inProgress &&
                                                                            !task.done
                                                                        ? 'remove in progress'
                                                                        : 'mark in progress',
                                                                    icon: Icon(
                                                                      Icons
                                                                          .construction,
                                                                      color: ((_stagedInProgress[task.id] ?? task.inProgress) && !(_stagedDone[task.id] ?? task.done))
                                                                          ? Colors
                                                                              .greenAccent
                                                                              .shade200
                                                                          : Theme.of(context)
                                                                              .colorScheme
                                                                              .onSurfaceVariant,
                                                                    ),
                                                                    onPressed:
                                                                        () async {
                                                                      final was =
                                                                          _stagedInProgress[task.id] ??
                                                                              task.inProgress;
                                                                      if (!was) {
                                                                        try {
                                                                          await _startStopwatch(
                                                                              i);
                                                                        } catch (_) {}
                                                                      } else {
                                                                        try {
                                                                          await _stopStopwatch(
                                                                              i);
                                                                        } catch (_) {}
                                                                        // Clear the inProgress flag via the per-task queue so the spinner shows
                                                                        unawaited(_queueTaskAction(
                                                                            task.id,
                                                                            () async {
                                                                          final idx = _today.indexWhere((t) =>
                                                                              t.id ==
                                                                              task.id);
                                                                          if (idx ==
                                                                              -1)
                                                                            return;
                                                                          setState(() => _today[idx] = _today[idx].copyWith(
                                                                              inProgress: false,
                                                                              inProgressAt: null));
                                                                          await _saveToday();
                                                                        }));
                                                                      }
                                                                      _registerActivity();
                                                                    },
                                                                  ),
                                                                  IconButton(
                                                                    tooltip:
                                                                        'Important',
                                                                    icon: Icon(
                                                                        (_stagedImportant[task.id] ?? task.important)
                                                                            ? Icons
                                                                                .star
                                                                            : Icons
                                                                                .star_border,
                                                                        color: (_stagedImportant[task.id] ??
                                                                                task.important)
                                                                            ? Colors.amber
                                                                            : Theme.of(context).colorScheme.onSurfaceVariant),
                                                                    onPressed:
                                                                        () {
                                                                      final newVal =
                                                                          !(_stagedImportant[task.id] ??
                                                                              task.important);
                                                                      setState(() =>
                                                                          _stagedImportant[task.id] =
                                                                              newVal);
                                                                      _scheduleDelayedReorder();
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
                            child: SafeArea(
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
                                        autofocus: !_showingDone &&
                                            !Platform.isAndroid,
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
                                        onTapOutside: (_) {
                                          if (!Platform.isAndroid)
                                            _requestInputFocusIfIdle();
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ElevatedButton(
                                          onPressed: _showingDone
                                              ? null
                                              : () =>
                                                  _addToToday(_controller.text),
                                          child: const Icon(Icons.add),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Tooltip(
                                              message:
                                                  _cloudSyncStatusTooltip(),
                                              child: Container(
                                                width: 10,
                                                height: 10,
                                                decoration: BoxDecoration(
                                                  color: _cloudSyncStatusColor(
                                                      Theme.of(context)
                                                          .colorScheme),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Tooltip(
                                              message: 'synchronize',
                                              child: InkWell(
                                                onTap: _cloudSyncBusy
                                                    ? null
                                                    : _manualSyncNow,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  child: Icon(
                                                    Icons.sync,
                                                    size: 18,
                                                    color: _cloudSyncBusy
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .outline
                                                        : Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
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
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                          scale: animation,
                          child:
                              FadeTransition(opacity: animation, child: child),
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
                                  await _nativeWindowChannel.invokeMethod(
                                      'setWindowGeometry', <String, dynamic>{
                                    'always_on_top': newVal
                                  });
                                  setState(() => _alwaysOnTop = newVal);
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
                  // Minimal-mode toggle removed
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
  const StatsPage({
    super.key,
    required this.doneList,
    this.timeEntries = const [],
    required this.textScale,
  });
  final List<TaskItem> doneList;

  /// All time entries from the DB (across all dates). Filtered by date in the page.
  final List<TimeEntry> timeEntries;
  final double textScale;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initial,
    this.onCloudDeviceRegistered,
  });

  final Map<String, dynamic> initial;
  final Function(Map<String, dynamic>)? onCloudDeviceRegistered;

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
  late bool scheduledReminderSoundEnabled;
  late String reminderWindowFrom;
  late String reminderWindowTo;
  late double textScaleFactor;
  late String fontFamily;
  late String cloudServerUrl;
  late String cloudAccountId;
  late String cloudDeviceId;
  late String cloudToken;
  late String cloudWordPhrase;
  late String cloudDeviceName;
  late String cloudPIN;
  late bool cloudAllowInsecureTls;
  late int cloudLastSyncSuccessAt;
  late bool cloudSyncFailed;
  late String cloudSyncLastError;
  late bool autoPurgeDoneEnabled;
  late bool autoExportOnStart;
  late int autoExportIntervalMinutes;
  late String autoExportTimesCsv;
  late int autoExportMaxBackups;
  // local toast state for SettingsPage
  OverlayEntry? _toastEntryLocal;
  Timer? _toastTimerLocal;
  String? _lastToastMessageLocal;
  DateTime? _lastToastAtLocal;
  // controllers for inputs that must preserve cursor position
  late TextEditingController _cloudServerUrlController;
  // local cache for devices shown in settings
  List<Map<String, dynamic>> _settingsCloudDevices = <Map<String, dynamic>>[];

  Future<void> _fetchCloudDevicesSettings() async {
    if (cloudServerUrl.trim().isEmpty || cloudToken.trim().isEmpty) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _normalizedServerUrl(),
        allowInsecureCertificates: cloudAllowInsecureTls,
      );
      final devices = await client.listDevices(token: cloudToken.trim());
      if (mounted) setState(() => _settingsCloudDevices = devices);
    } catch (e) {
      // ignore here, show little status elsewhere
    }
  }

  Future<void> _revokeCloudDeviceSettings(String deviceId) async {
    if (cloudServerUrl.trim().isEmpty || cloudToken.trim().isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('revoke device'),
        content: const Text(
            'revoke this device? it will no longer be able to sync.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('revoke')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: _normalizedServerUrl(),
        allowInsecureCertificates: cloudAllowInsecureTls,
      );
      await client.revokeDevice(token: cloudToken.trim(), deviceId: deviceId);
      if (mounted) {
        _showTopToastLocal('device revoked');
        await _fetchCloudDevicesSettings();
      }
    } catch (_) {}
  }

  void _showTopToastLocal(String message) {
    final now = DateTime.now();
    if (_lastToastMessageLocal != null && _lastToastMessageLocal == message) {
      if (_lastToastAtLocal != null &&
          now.difference(_lastToastAtLocal!).inSeconds < 3) return;
    }
    if (_lastToastAtLocal != null &&
        now.difference(_lastToastAtLocal!).inMilliseconds < 700) return;
    _lastToastMessageLocal = message;
    _lastToastAtLocal = now;

    _toastTimerLocal?.cancel();
    _toastEntryLocal?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    _toastEntryLocal = OverlayEntry(
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
                  child: Text(message,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
              ),
              builder: (context, offset, child) {
                return Transform.translate(
                    offset: Offset(0, offset.dy * 60), child: child);
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(_toastEntryLocal!);
    _toastTimerLocal = Timer(const Duration(milliseconds: 1650), () {
      _toastEntryLocal?.remove();
      _toastEntryLocal = null;
    });
  }

  Future<void> _showDevicesDialogSettings() async {
    await _fetchCloudDevicesSettings();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('registered devices'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: _settingsCloudDevices.isEmpty
              ? const Center(child: Text('no devices found'))
              : ListView.builder(
                  itemCount: _settingsCloudDevices.length,
                  itemBuilder: (c, i) {
                    final d = _settingsCloudDevices[i];
                    final revoked = d['revoked'] == true;
                    return ListTile(
                      title: Text(
                          d['name']?.toString() ?? d['id']?.toString() ?? ''),
                      subtitle:
                          Text('id: ${d['id']}\ncreated: ${d['created_at']}'),
                      isThreeLine: true,
                      trailing: revoked
                          ? const Text('revoked',
                              style: TextStyle(color: Colors.redAccent))
                          : TextButton(
                              onPressed: () => _revokeCloudDeviceSettings(
                                  d['id']?.toString() ?? ''),
                              child: const Text('revoke'),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('close'))
        ],
      ),
    );
  }

  late int doneRetentionDays;
  late int maxTasksToday;
  late int maxTasksBacklog;
  String _cloudStatus = '';
  String _settingsServerVersion = '';
  String _versionWarning = '';
  String _cloudArchiveInfo = '';
  bool _cloudArchiveWarning = false;
  int _cloudArchiveLastWarnedDays = -1;
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
  late bool _initialScheduledReminderSoundEnabled;
  late String _initialReminderWindowFrom;
  late String _initialReminderWindowTo;
  late double _initialTextScaleFactor;
  late String _initialFontFamily;
  late String _initialCloudServerUrl;
  late String _initialCloudAccountId;
  late String _initialCloudDeviceId;
  late String _initialCloudToken;
  late String _initialCloudWordPhrase;
  late String _initialCloudDeviceName;
  late String _initialCloudPIN;
  late bool _initialCloudAllowInsecureTls;
  late bool _initialAutoPurgeDoneEnabled;
  late int _initialDoneRetentionDays;
  late int _initialMaxTasksToday;
  late int _initialMaxTasksBacklog;
  late bool _initialAutoExportOnStart;
  late int _initialAutoExportIntervalMinutes;
  late String _initialAutoExportTimesCsv;
  late List<Map<String, dynamic>> _inactivityRemindersLocal;

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
    scheduledReminderSoundEnabled =
        readBool('scheduledReminderSoundEnabled', true);
    reminderWindowFrom = readString('reminderWindowFrom', '09:00');
    reminderWindowTo = readString('reminderWindowTo', '17:00');
    textScaleFactor = readDouble('uiTextScaleFactor', 1.0).clamp(0.5, 1.6);
    fontFamily = readString('fontFamily', 'OpenDyslexic');
    cloudServerUrl = readString('cloudServerUrl', '');
    _cloudServerUrlController = TextEditingController(text: cloudServerUrl);
    cloudAccountId = readString('cloudAccountId', '');
    cloudDeviceId = readString('cloudDeviceId', '');
    cloudToken = readString('cloudToken', '');
    cloudWordPhrase = readString('cloudWordPhrase', '');
    cloudDeviceName = _normalizeCloudDeviceName(
      readString('cloudDeviceName', _suggestedCloudDeviceName()),
    );
    cloudPIN = readString('cloudPIN', '');
    cloudAllowInsecureTls = readBool('cloudAllowInsecureTls', false);
    autoPurgeDoneEnabled = readBool('autoPurgeDoneEnabled', false);
    autoExportOnStart = readBool('autoExportOnStart', false);
    autoExportIntervalMinutes = readInt('autoExportIntervalMinutes', 0);
    final aet = widget.initial['autoExportTimes'];
    if (aet is List) {
      autoExportTimesCsv = aet.map((e) => e.toString()).join(',');
    } else {
      autoExportTimesCsv = readString('autoExportTimesCsv', '');
    }
    autoExportMaxBackups = readInt('autoExportMaxBackups', 14);
    doneRetentionDays = readInt('doneRetentionDays', 30).clamp(1, 365);
    maxTasksToday = readInt('maxTasksToday', 25).clamp(1, 9999);
    maxTasksBacklog = readInt('maxTasksBacklog', 50).clamp(1, 9999);
    cloudLastSyncSuccessAt = readInt('cloudLastSyncSuccessAt', 0);
    cloudSyncFailed = readBool('cloudSyncFailed', false);
    cloudSyncLastError = readString('cloudSyncLastError', '');
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
    _initialScheduledReminderSoundEnabled = scheduledReminderSoundEnabled;
    _initialReminderWindowFrom = reminderWindowFrom;
    _initialReminderWindowTo = reminderWindowTo;
    _initialTextScaleFactor = textScaleFactor;
    _initialFontFamily = fontFamily;
    _initialCloudServerUrl = cloudServerUrl;
    _initialCloudAccountId = cloudAccountId;
    _initialCloudDeviceId = cloudDeviceId;
    _initialCloudToken = cloudToken;
    _initialCloudWordPhrase = cloudWordPhrase;
    _initialCloudDeviceName = cloudDeviceName;
    _initialCloudPIN = cloudPIN;
    _initialCloudAllowInsecureTls = cloudAllowInsecureTls;
    _initialAutoPurgeDoneEnabled = autoPurgeDoneEnabled;
    _initialDoneRetentionDays = doneRetentionDays;
    _initialMaxTasksToday = maxTasksToday;
    _initialMaxTasksBacklog = maxTasksBacklog;
    _initialAutoExportOnStart = autoExportOnStart;
    _initialAutoExportIntervalMinutes = autoExportIntervalMinutes;
    _initialAutoExportTimesCsv = autoExportTimesCsv;
    _fetchServerVersionInSettings();
    unawaited(_refreshCloudAccountStatus());
    // Initialize local inactivity reminders from parent-provided initial map
    final ir = widget.initial['inactivityReminders'];
    if (ir is List) {
      _inactivityRemindersLocal = ir.map((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return <String, dynamic>{};
      }).toList();
    } else {
      _inactivityRemindersLocal = <Map<String, dynamic>>[];
    }
  }

  @override
  void dispose() {
    _toastTimerLocal?.cancel();
    _toastEntryLocal?.remove();
    _cloudServerUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchServerVersionInSettings() async {
    if (cloudServerUrl.trim().isEmpty) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: cloudServerUrl.trim(),
        allowInsecureCertificates: cloudAllowInsecureTls,
      );
      final version = await client.getHealth();
      if (version != null && mounted) {
        setState(() {
          _settingsServerVersion = version;
          _versionWarning = _isClientOlderThanServer(kClientVersion, version)
              ? 'warning: client is older than server. please update client.'
              : '';
        });
      }
    } catch (_) {
      // Ignore version fetch errors
    }
  }

  Future<void> _refreshCloudAccountStatus({
    bool showToastIfWarning = false,
  }) async {
    if (cloudServerUrl.trim().isEmpty || cloudToken.trim().isEmpty) return;
    try {
      final client = CloudSyncClient(
        serverBaseUrl: cloudServerUrl.trim(),
        allowInsecureCertificates: cloudAllowInsecureTls,
      );
      final status = await client.getAccountStatus(token: cloudToken.trim());
      final days = status.daysUntilArchive;
      final warningText = status.archived
          ? 'cloud account archived. please re-register or contact admin.'
          : (status.warning && days >= 0
              ? 'warning: cloud account will be archived in $days days without activity.'
              : '');

      if (!mounted) return;
      setState(() {
        _cloudArchiveWarning = status.warning;
        _cloudArchiveInfo = warningText;
      });

      if (showToastIfWarning &&
          status.warning &&
          days >= 0 &&
          _cloudArchiveLastWarnedDays != days) {
        _cloudArchiveLastWarnedDays = days;
        setState(() {
          _cloudStatus =
              'cloud notice: archive in $days days without activity.';
        });
      }
      if (showToastIfWarning && status.archived) {
        setState(() {
          _cloudStatus = 'cloud account is archived.';
        });
      }
    } catch (_) {
      // Optional endpoint, ignore temporary failures.
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges()) {
      return true;
    }
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('changes not saved'),
        content: const Text('there are unsaved settings. really leave?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () {
              // Close the dialog and return the current settings map to the parent
              Navigator.of(ctx).pop(false);
              Navigator.of(context).pop(<String, dynamic>{
                'idleMinutes': idleMinutes,
                'attentionMinutes': attentionMinutes,
                'reminderMinutes': reminderMinutes,
                'urgentMinutes': urgentMinutes,
                'idleSoundEnabled': idleSoundEnabled,
                'idleFlashEnabled': idleFlashEnabled,
                'idleNotifyEnabled': idleNotifyEnabled,
                'idleBringToFrontEnabled': idleBringToFrontEnabled,
                'attentionSoundEnabled': attentionSoundEnabled,
                'attentionFlashEnabled': attentionFlashEnabled,
                'attentionNotifyEnabled': attentionNotifyEnabled,
                'attentionBringToFrontEnabled': attentionBringToFrontEnabled,
                'reminderSoundEnabled': reminderSoundEnabled,
                'reminderNotifyEnabled': reminderNotifyEnabled,
                'reminderFlashEnabled': reminderFlashEnabled,
                'reminderBringToFrontEnabled': reminderBringToFrontEnabled,
                'urgentSoundEnabled': urgentSoundEnabled,
                'urgentFlashEnabled': urgentFlashEnabled,
                'urgentNotifyEnabled': urgentNotifyEnabled,
                'urgentBringToFrontEnabled': urgentBringToFrontEnabled,
                'swipeEnabled': swipeEnabled,
                'uiTextScaleFactor': textScaleFactor,
                'fontFamily': fontFamily,
                'cloudServerUrl': cloudServerUrl,
                'cloudAccountId': cloudAccountId,
                'cloudDeviceId': cloudDeviceId,
                'cloudToken': cloudToken,
                'cloudWordPhrase': cloudWordPhrase,
                'cloudDeviceName': cloudDeviceName,
                'cloudPIN': cloudPIN,
                'cloudAllowInsecureTls': cloudAllowInsecureTls,
                'cloudLastSyncSuccessAt': null,
                'cloudSyncFailed': false,
                'cloudSyncLastError': null,
                'scheduledReminderSoundEnabled': scheduledReminderSoundEnabled,
                'reminderWindowFrom': reminderWindowFrom,
                'reminderWindowTo': reminderWindowTo,
                'autoPurgeDoneEnabled': false,
                'doneRetentionDays': 30,
                'inactivityReminders': _inactivityRemindersLocal,
                'maxTasksToday': maxTasksToday,
                'maxTasksBacklog': maxTasksBacklog,
                // Automatic export settings
                'autoExportOnStart': autoExportOnStart,
                'autoExportIntervalMinutes': autoExportIntervalMinutes,
                'autoExportTimes': autoExportTimesCsv
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
                'autoExportMaxBackups': autoExportMaxBackups,
              });
            },
            child: const Text('save'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('discard'),
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
        scheduledReminderSoundEnabled !=
            _initialScheduledReminderSoundEnabled ||
        urgentFlashEnabled != _initialUrgentFlashEnabled ||
        urgentNotifyEnabled != _initialUrgentNotifyEnabled ||
        urgentBringToFrontEnabled != _initialUrgentBringToFrontEnabled ||
        swipeEnabled != _initialSwipeEnabled ||
        textScaleFactor != _initialTextScaleFactor ||
        fontFamily != _initialFontFamily ||
        cloudServerUrl != _initialCloudServerUrl ||
        cloudAccountId != _initialCloudAccountId ||
        cloudDeviceId != _initialCloudDeviceId ||
        cloudToken != _initialCloudToken ||
        cloudWordPhrase != _initialCloudWordPhrase ||
        cloudDeviceName != _initialCloudDeviceName ||
        cloudPIN != _initialCloudPIN ||
        cloudAllowInsecureTls != _initialCloudAllowInsecureTls ||
        autoPurgeDoneEnabled != _initialAutoPurgeDoneEnabled ||
        doneRetentionDays != _initialDoneRetentionDays ||
        maxTasksToday != _initialMaxTasksToday ||
        maxTasksBacklog != _initialMaxTasksBacklog ||
        reminderWindowFrom != _initialReminderWindowFrom ||
        reminderWindowTo != _initialReminderWindowTo ||
        autoExportOnStart != _initialAutoExportOnStart ||
        autoExportIntervalMinutes != _initialAutoExportIntervalMinutes ||
        autoExportTimesCsv != _initialAutoExportTimesCsv;
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
      // Use alphanumeric group phrase by default for stronger randomness.
      final extra = List<int>.from(_mouseEntropy);
      cloudWordPhrase = CloudSyncClient.suggestWordPhrase(
          alphaNumeric: true, groupLen: 6, extraEntropy: extra);
      _mouseEntropy.clear();
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
                    'pair another device',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'scan this qr code on the new device to transfer server url and account id. the 9-word phrase will also be transferred.',
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
                            _cloudStatus = 'pairing link copied to clipboard.';
                          });
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('copy link'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('close'),
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
  Future<void> _applyPairingUri(String raw,
      {required String sourceLabel}) async {
    try {
      // if we already have a paired device, warn before importing pairing info
      if (cloudDeviceId.trim().isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('replace existing pairing?'),
            content: const Text(
                'warning: importing pairing info will replace the previously registered device on the server. continue?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('cancel')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('replace')),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _cloudStatus = 'import cancelled');
          return;
        }
      }
      final uri = Uri.parse(raw);
      if (uri.scheme != 'simplepresent' || uri.host != 'pair') {
        setState(() => _cloudStatus = 'invalid pairing link ($sourceLabel).');
        return;
      }
      final server = uri.queryParameters['server'] ?? '';
      final account = uri.queryParameters['account'] ?? '';
      final phrase = uri.queryParameters['phrase'] ?? '';
      if (server.isEmpty || account.isEmpty || phrase.isEmpty) {
        setState(
            () => _cloudStatus = 'pairing link incomplete ($sourceLabel).');
        return;
      }
      setState(() {
        cloudServerUrl = server;
        cloudAccountId = account;
        cloudWordPhrase = phrase;
        _cloudStatus =
            'server url, account id and 9-word phrase imported ($sourceLabel). now tap "pair device".';
      });
    } catch (_) {
      setState(() =>
          _cloudStatus = 'pairing link could not be read ($sourceLabel).');
    }
  }

  Future<void> _scanPairingQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const _QrScannerPage(),
      ),
    );
    if (result == null || !mounted) return;
    await _applyPairingUri(result, sourceLabel: 'QR-Code');
  }

  Future<void> _pastePairingLink() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _cloudStatus = 'clipboard is empty.');
      return;
    }
    await _applyPairingUri(text, sourceLabel: 'Zwischenablage');
  }

  Future<void> _registerFirstDevice() async {
    try {
      setState(() {
        _cloudBusy = true;
        _cloudStatus = '';
      });
      if (cloudPIN.isEmpty || cloudPIN.length < 4) {
        setState(() {
          _cloudStatus = 'pin must be at least 4 characters.';
          _cloudBusy = false;
        });
        return;
      }
      // warn if a device id already exists: registering will replace existing pairing
      if (cloudDeviceId.trim().isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('replace existing pairing?'),
            content: const Text(
                'warning: creating a new registration will replace the previously registered device on the server. continue?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('cancel')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('replace')),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _cloudBusy = false);
          return;
        }
      }
      final client = CloudSyncClient(
        serverBaseUrl: _normalizedServerUrl(),
        allowInsecureCertificates: cloudAllowInsecureTls,
      );
      final result = await client.registerFirstClient(
        deviceName: _normalizeCloudDeviceName(cloudDeviceName),
        phrase: cloudWordPhrase,
        pin: cloudPIN,
      );
      setState(() {
        cloudAccountId = result.accountId;
        cloudDeviceId = result.deviceId;
        cloudToken = result.token;
        _cloudStatus = result.notice == null || result.notice!.isEmpty
            ? 'first device registered.'
            : 'first device registered. ${result.notice!}';
      });
      // Notify parent to sync settings
      if (widget.onCloudDeviceRegistered != null) {
        widget.onCloudDeviceRegistered!({
          'cloudAccountId': cloudAccountId,
          'cloudDeviceId': cloudDeviceId,
          'cloudToken': cloudToken,
        });
      }
      await _refreshCloudAccountStatus(showToastIfWarning: true);
    } catch (e) {
      setState(() {
        _cloudStatus = 'register failed: $e';
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
          _cloudStatus = 'pin required for pairing.';
          _cloudBusy = false;
        });
        return;
      }
      // If we already have a device id, warn the user that pairing will replace it.
      if (cloudDeviceId.trim().isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('replace existing pairing?'),
            content: const Text(
                'warning: creating a new pairing will replace the previously registered device on the server. continue?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('cancel')),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('replace')),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _cloudBusy = false);
          return;
        }
      }
      final client = CloudSyncClient(
        serverBaseUrl: _normalizedServerUrl(),
        allowInsecureCertificates: cloudAllowInsecureTls,
      );
      final result = await client.pairClient(
        accountId: cloudAccountId.trim(),
        deviceName: _normalizeCloudDeviceName(cloudDeviceName),
        phrase: cloudWordPhrase,
        pin: cloudPIN,
      );
      setState(() {
        cloudDeviceId = result.deviceId;
        cloudToken = result.token;
        _cloudStatus = 'device paired successfully.';
      });
      // Notify parent to sync settings
      if (widget.onCloudDeviceRegistered != null) {
        widget.onCloudDeviceRegistered!({
          'cloudDeviceId': cloudDeviceId,
          'cloudToken': cloudToken,
        });
      }
      await _refreshCloudAccountStatus(showToastIfWarning: true);
    } catch (e) {
      setState(() {
        _cloudStatus = 'pairing failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cloudBusy = false;
        });
      }
    }
  }

  Future<void> _confirmAndRemovePeering() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('remove peering?'),
        content: const Text(
            'This will clear the cloud server, account and device registration from this client. Continue?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('remove')),
        ],
      ),
    );
    if (proceed != true) return;

    // Return a partial result with cleared cloud fields. _openSettings will apply and persist.
    final result = <String, dynamic>{
      'cloudServerUrl': '',
      'cloudAccountId': '',
      'cloudDeviceId': '',
      'cloudToken': '',
      'cloudWordPhrase': '',
      'cloudDeviceName': _suggestedCloudDeviceName(),
      'cloudPIN': '',
      'cloudAllowInsecureTls': false,
    };
    if (mounted) Navigator.of(context).pop(result);
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
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final shouldLeave = await _onWillPop();
            if (shouldLeave && mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leadingWidth: 40,
              titleSpacing: 0,
              toolbarHeight: 62,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Image.asset(
                        'assets/icons/color_transparent_settings.png',
                        width: 28,
                        height: 28),
                  ),
                  const SizedBox(width: 8),
                  Text('settings',
                      style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700)
                          .copyWith(fontFamily: fontFamily)),
                ],
              ),
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
                      'reminderBringToFrontEnabled':
                          reminderBringToFrontEnabled,
                      'urgentSoundEnabled': urgentSoundEnabled,
                      'urgentFlashEnabled': urgentFlashEnabled,
                      'urgentNotifyEnabled': urgentNotifyEnabled,
                      'urgentBringToFrontEnabled': urgentBringToFrontEnabled,
                      'swipeEnabled': swipeEnabled,
                      'uiTextScaleFactor': textScaleFactor,
                      'scheduledReminderSoundEnabled':
                          scheduledReminderSoundEnabled,
                      'fontFamily': fontFamily,
                      'cloudServerUrl': cloudServerUrl,
                      'cloudAccountId': cloudAccountId,
                      'cloudDeviceId': cloudDeviceId,
                      'cloudToken': cloudToken,
                      'cloudWordPhrase': cloudWordPhrase,
                      'cloudDeviceName': cloudDeviceName,
                      'cloudPIN': cloudPIN,
                      'cloudAllowInsecureTls': cloudAllowInsecureTls,
                      'inactivityReminders': _inactivityRemindersLocal,
                      'autoPurgeDoneEnabled': autoPurgeDoneEnabled,
                      'doneRetentionDays': doneRetentionDays,
                      'maxTasksToday': maxTasksToday,
                      'maxTasksBacklog': maxTasksBacklog,
                      // Automatic export settings
                      'autoExportOnStart': autoExportOnStart,
                      'autoExportIntervalMinutes': autoExportIntervalMinutes,
                      'autoExportTimes': autoExportTimesCsv
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList(),
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
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('font:'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: fontFamily,
                        items: const [
                          DropdownMenuItem(
                              value: 'OpenDyslexic',
                              child: Text('OpenDyslexic')),
                          DropdownMenuItem(
                              value: 'NotoSans', child: Text('NotoSans')),
                          DropdownMenuItem(
                              value: 'CourierPrime',
                              child: Text('CourierPrime')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => fontFamily = value);
                          }
                        },
                      ),
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
                const Divider(thickness: 1),
                const SizedBox(height: 8),
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('counters',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text(
                            'configure maximum task counts for color scaling (green→red).'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('today max:'),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: maxTasksToday.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder()),
                                onChanged: (v) {
                                  final parsed = int.tryParse(v);
                                  if (parsed != null)
                                    setState(() =>
                                        maxTasksToday = parsed.clamp(1, 9999));
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('backlog max:'),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                initialValue: maxTasksBacklog.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder()),
                                onChanged: (v) {
                                  final parsed = int.tryParse(v);
                                  if (parsed != null)
                                    setState(() => maxTasksBacklog =
                                        parsed.clamp(1, 9999));
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                const Text('inactivity reminders',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Dynamic list of user-defined inactivity reminder stages
                for (var i = 0; i < _inactivityRemindersLocal.length; i++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _ReminderStageCard(
                          title:
                              '${_inactivityRemindersLocal[i]['minutes'] ?? 'min'} min',
                          minutes: (_inactivityRemindersLocal[i]['minutes']
                                  is int)
                              ? _inactivityRemindersLocal[i]['minutes'] as int
                              : int.tryParse(_inactivityRemindersLocal[i]
                                              ['minutes']
                                          ?.toString() ??
                                      '') ??
                                  0,
                          onMinutesChanged: (v) => setState(() {
                            _inactivityRemindersLocal[i]['minutes'] =
                                v.clamp(1, 720);
                          }),
                          soundEnabled:
                              _inactivityRemindersLocal[i]['sound'] == true,
                          onSoundChanged: (v) => setState(() {
                            _inactivityRemindersLocal[i]['sound'] = v;
                          }),
                          flashEnabled:
                              _inactivityRemindersLocal[i]['flash'] == true,
                          onFlashChanged: (v) => setState(() {
                            _inactivityRemindersLocal[i]['flash'] = v;
                          }),
                          notifyEnabled:
                              _inactivityRemindersLocal[i]['notify'] == true,
                          onNotifyChanged: (v) => setState(() {
                            _inactivityRemindersLocal[i]['notify'] = v;
                          }),
                          bringToFrontEnabled: _inactivityRemindersLocal[i]
                                  ['bringToFront'] ==
                              true,
                          onBringToFrontChanged: (v) => setState(() {
                            _inactivityRemindersLocal[i]['bringToFront'] = v;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'remove',
                          onPressed: () => setState(() {
                            _inactivityRemindersLocal.removeAt(i);
                          }),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => setState(() {
                        // Add a new default stage (user will configure it)
                        _inactivityRemindersLocal.add({
                          'minutes': 30,
                          'sound': false,
                          'flash': false,
                          'notify': true,
                          'bringToFront': false,
                        });
                      }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add reminder'),
                    ),
                    const SizedBox(width: 12)
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('reminder time window',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text(
                            'only fire inactivity reminders within this time window.'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('from:'),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final parts = reminderWindowFrom.split(':');
                                final initial = TimeOfDay(
                                    hour: int.tryParse(parts[0]) ?? 9,
                                    minute: int.tryParse(parts[1]) ?? 0);
                                final picked = await showTimePicker(
                                    context: context, initialTime: initial);
                                if (picked != null) {
                                  setState(() => reminderWindowFrom =
                                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                                }
                              },
                              child: Text(reminderWindowFrom),
                            ),
                            const SizedBox(width: 16),
                            const Text('to:'),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final parts = reminderWindowTo.split(':');
                                final initial = TimeOfDay(
                                    hour: int.tryParse(parts[0]) ?? 17,
                                    minute: int.tryParse(parts[1]) ?? 0);
                                final picked = await showTimePicker(
                                    context: context, initialTime: initial);
                                if (picked != null) {
                                  setState(() => reminderWindowTo =
                                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
                                }
                              },
                              child: Text(reminderWindowTo),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                  value: scheduledReminderSoundEnabled,
                  title: const Text('play sound for scheduled reminders'),
                  subtitle: const Text(
                      'play a sound for scheduled task reminders (15min and due)'),
                  onChanged: (v) =>
                      setState(() => scheduledReminderSoundEnabled = v),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'cloud sync',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'note: cloud accounts must be used actively. inactive accounts are automatically archived after 30 days.',
                  style: TextStyle(fontSize: 11, color: Colors.orangeAccent),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _cloudServerUrlController,
                  decoration: const InputDecoration(
                    labelText: 'server url',
                    hintText: 'https://<simplepresent-cloud-server>',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => cloudServerUrl = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: cloudDeviceName)
                    ..selection =
                        TextSelection.collapsed(offset: cloudDeviceName.length),
                  decoration: const InputDecoration(
                    labelText: 'device name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => cloudDeviceName = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: cloudPIN)
                    ..selection =
                        TextSelection.collapsed(offset: cloudPIN.length),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'pin (4-32 chars)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => cloudPIN = value),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: cloudAllowInsecureTls,
                  title: const Text('accept insecure certificates'),
                  subtitle: const Text(
                      'only enable this for trusted self-signed/private ca setups.'),
                  onChanged: (v) => setState(() => cloudAllowInsecureTls = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: cloudAccountId)
                    ..selection =
                        TextSelection.collapsed(offset: cloudAccountId.length),
                  decoration: const InputDecoration(
                    labelText: 'account id',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => cloudAccountId = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(text: cloudWordPhrase)
                    ..selection =
                        TextSelection.collapsed(offset: cloudWordPhrase.length),
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '9-word phrase (local)',
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
                        label: const Text('suggest 9 words'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cloudBusy
                            ? null
                            : (cloudAccountId.trim().isEmpty
                                ? _registerFirstDevice
                                : _pairDevice),
                        icon: Icon(cloudAccountId.trim().isEmpty
                            ? Icons.person_add_alt_1
                            : Icons.link),
                        label: const Text('pair device'),
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
                        label: const Text('show qr code'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cloudBusy ? null : _scanPairingQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('scan qr code'),
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
                        label: const Text('paste link'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _cloudBusy ? null : _showDevicesDialogSettings,
                        icon: const Icon(Icons.devices),
                        label: const Text('manage devices'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Remove peering / clear cloud configuration
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                        onPressed: _cloudBusy
                            ? null
                            : () => _confirmAndRemovePeering(),
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.redAccent),
                        label: const Text('remove peering (clear cloud config)',
                            style: TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'device id: $cloudDeviceId\ntoken: ${cloudToken.isEmpty ? '-' : cloudToken}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'Client: $kClientVersion${_settingsServerVersion.isNotEmpty ? ' | Server: $_settingsServerVersion' : ' | Server: -'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: _versionWarning.isEmpty
                        ? Colors.grey
                        : Colors.orangeAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cloudSyncFailed
                      ? 'sync status: failed'
                      : (cloudLastSyncSuccessAt > 0
                          ? 'sync status: ok'
                          : 'sync status: not synchronized'),
                  style: TextStyle(
                    fontSize: 11,
                    color: cloudSyncFailed ? Colors.redAccent : Colors.grey,
                  ),
                ),
                if (cloudLastSyncSuccessAt > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'last sync: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(cloudLastSyncSuccessAt))}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
                if (cloudSyncFailed && cloudSyncLastError.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    cloudSyncLastError,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.redAccent),
                  ),
                ],
                if (_cloudArchiveInfo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _cloudArchiveInfo,
                    style: TextStyle(
                      fontSize: 11,
                      color: _cloudArchiveWarning
                          ? Colors.orangeAccent
                          : Colors.grey,
                    ),
                  ),
                ],
                if (_versionWarning.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _versionWarning,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.orangeAccent),
                  ),
                ],
                if (_cloudStatus.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    _cloudStatus,
                    style: TextStyle(
                      color: _cloudStatus.contains('failed')
                          ? Colors.redAccent
                          : Colors.greenAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('automatic backups',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        const Text(
                            'Automatically export task lists as JSON backups.'),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('export on start:'),
                          const SizedBox(width: 12),
                          Switch(
                              value: autoExportOnStart,
                              onChanged: (v) =>
                                  setState(() => autoExportOnStart = v))
                        ]),
                        const SizedBox(height: 4),
                        const Text('0 = unlimited',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('interval (min, 0=off):'),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue:
                                  autoExportIntervalMinutes.toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  isDense: true, border: OutlineInputBorder()),
                              onChanged: (v) {
                                final parsed = int.tryParse(v) ?? 0;
                                setState(() => autoExportIntervalMinutes =
                                    parsed.clamp(0, 60 * 24));
                              },
                            ),
                          )
                        ]),
                        const SizedBox(height: 8),
                        const Text('times (HH:MM comma-separated):'),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue: autoExportTimesCsv,
                          decoration: const InputDecoration(
                              border: OutlineInputBorder(), isDense: true),
                          onChanged: (v) =>
                              setState(() => autoExportTimesCsv = v),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Text('max backups:'),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue: autoExportMaxBackups.toString(),
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  isDense: true, border: OutlineInputBorder()),
                              onChanged: (v) {
                                final parsed = int.tryParse(v) ?? 0;
                                setState(() => autoExportMaxBackups =
                                    parsed.clamp(0, 9999));
                              },
                            ),
                          )
                        ]),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'cleanup',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: autoPurgeDoneEnabled,
                  title: const Text('auto-delete old done tasks'),
                  subtitle: const Text('delete done tasks older than x days.'),
                  onChanged: (v) => setState(() => autoPurgeDoneEnabled = v),
                ),
                if (autoPurgeDoneEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('days:'),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: TextFormField(
                          initialValue: doneRetentionDays.toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              isDense: true, border: OutlineInputBorder()),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null)
                              setState(() =>
                                  doneRetentionDays = parsed.clamp(1, 365));
                          },
                        ),
                      ),
                    ],
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

  /// All time-entry rows for [day] from the persistent DB entries.
  List<TimeEntry> _timeEntriesForDay(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    // Aggregate multiple recorded windows for the same task/date by summing
    // stopwatch seconds and manual work minutes so the stats reflect the
    // total time for that day only.
    final rows = widget.timeEntries
        .where((e) => e.date == dateStr && e.totalMinutes > 0);
    final Map<String, TimeEntry> agg = {};
    for (final e in rows) {
      final existing = agg[e.taskId];
      if (existing == null) {
        agg[e.taskId] = e;
      } else {
        final summed = TimeEntry(
          taskId: existing.taskId,
          taskText: existing.taskText,
          date: existing.date,
          taskDone: existing.taskDone || e.taskDone,
          taskInProgress: existing.taskInProgress || e.taskInProgress,
          stopwatchSeconds: existing.stopwatchSeconds + e.stopwatchSeconds,
          workMinutes: existing.workMinutes + e.workMinutes,
        );
        agg[existing.taskId] = summed;
      }
    }
    return agg.values.toList();
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
    return blocks * 15 + t.workMinutes;
  }

  _StatRow _rowFromEntry(TimeEntry e) {
    return _StatRow(
      taskText: e.taskText,
      minutes: e.totalMinutes,
      isDone: e.taskDone,
      completedAt: null,
      statusLabel: e.statusLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.textScale;
    final doneTasks = _tasksForDay(_currentDate);
    final timeEntries = _timeEntriesForDay(_currentDate);

    // Build unified row list: one row per task.
    // Prefer DB time for minutes; fall back to task payload for done tasks.
    final doneRows = <_StatRow>[];
    final openRows = <_StatRow>[];

    // 1. Status-driven rows from persistent time entries.
    final doneEntryIds = <String>{};
    for (final t in doneTasks) {
      final entry = timeEntries.where((e) => e.taskId == t.id).firstOrNull;
      final isDone = entry?.taskDone ?? true;
      final row = _StatRow(
        taskText: t.text,
        minutes: entry?.totalMinutes ?? _minutesForTask(t),
        isDone: isDone,
        completedAt: t.completedAt,
        statusLabel: isDone ? 'fertig' : (entry?.statusLabel ?? 'offen'),
      );
      if (row.isDone) {
        doneRows.add(row);
      } else {
        openRows.add(row);
      }
      if (entry != null) doneEntryIds.add(entry.taskId);
    }

    // 2. Remaining time entries for tasks not represented in doneTasks.
    for (final e in timeEntries) {
      if (doneEntryIds.contains(e.taskId)) continue;
      final row = _rowFromEntry(e);
      if (row.isDone) {
        doneRows.add(row);
      } else {
        openRows.add(row);
      }
    }

    final totalMinutes = doneRows.fold<int>(0, (s, r) => s + r.minutes) +
        openRows.fold<int>(0, (s, r) => s + r.minutes);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 40,
        titleSpacing: 0,
        toolbarHeight: 62,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Image.asset('assets/icons/color_transparent_statistic.png',
                  width: 28, height: 28),
            ),
            const SizedBox(width: 8),
            Text(
              DateFormat('EEE, dd.MM.yyyy').format(_currentDate),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        centerTitle: false,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
              icon: const Icon(Icons.arrow_left),
              tooltip: 'Vorheriger Tag',
              onPressed: _prevDay),
          IconButton(
              icon: const Icon(Icons.arrow_right),
              tooltip: 'Nächster Tag',
              onPressed: _nextDay),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Erledigt: ${doneRows.where((r) => r.isDone).length}  |  Gesamt Zeit: $totalMinutes min',
                style: TextStyle(
                    fontSize: 16 * scale, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Expanded(
              child: (doneRows.isEmpty && openRows.isEmpty)
                  ? Center(
                      child: Text(_currentDate.day == DateTime.now().day
                          ? 'Heute noch keine Zeiterfassung'
                          : 'Keine Einträge für diesen Tag'))
                  : ListView(
                      children: [
                        if (doneRows.isNotEmpty) ...[
                          Text('Erledigt',
                              style: TextStyle(
                                  fontSize: 13 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.greenAccent)),
                          const SizedBox(height: 4),
                          for (final r in doneRows)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.task_alt,
                                  size: 18, color: Colors.greenAccent),
                              title: Text(r.taskText,
                                  style: TextStyle(fontSize: 14 * scale)),
                              subtitle: Text(
                                'Status: ${r.statusLabel}${r.completedAt != null ? ' | erledigt: ${DateFormat('HH:mm').format(r.completedAt!)}' : ''}',
                                style: TextStyle(fontSize: 11 * scale),
                              ),
                              trailing: r.minutes > 0
                                  ? Text('${r.minutes} min',
                                      style: TextStyle(fontSize: 12 * scale))
                                  : null,
                            ),
                        ],
                        if (openRows.isNotEmpty) ...[
                          if (doneRows.isNotEmpty) const Divider(),
                          Text('Laufend (nicht abgeschlossen)',
                              style: TextStyle(
                                  fontSize: 13 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orangeAccent)),
                          const SizedBox(height: 4),
                          for (final r in openRows)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                r.statusLabel == 'in Arbeit'
                                    ? Icons.timelapse
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: Colors.orangeAccent,
                              ),
                              title: Text(r.taskText,
                                  style: TextStyle(fontSize: 14 * scale)),
                              subtitle: Text(
                                'Status: ${r.statusLabel}',
                                style: TextStyle(fontSize: 11 * scale),
                              ),
                              trailing: Text('${r.minutes} min',
                                  style: TextStyle(fontSize: 12 * scale)),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/* Top-level redo log page (moved here to avoid nested class declarations) */
class RedoLogPage extends StatefulWidget {
  const RedoLogPage({super.key});
  @override
  State<RedoLogPage> createState() => _RedoLogPageState();
}

class _RedoLogPageState extends State<RedoLogPage> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  bool _storageReady = false;
  final _sembastStorage = SembastStorage();
  late final ScrollController _hScrollController;
  late final ScrollController _vScrollController;
  OverlayEntry? _toastEntryLocal;
  Timer? _toastTimerLocal;
  String? _lastToastMessageLocal;
  DateTime? _lastToastAtLocal;

  @override
  void initState() {
    super.initState();
    unawaited(_initStorageAndLoad());
    _hScrollController = ScrollController();
    _vScrollController = ScrollController();
  }

  Future<void> _initStorageAndLoad() async {
    try {
      await _sembastStorage.init(debugMode: kDebugMode);
      _storageReady = true;
    } catch (_) {
      _storageReady = false;
    }
    await _loadEntries();
  }

  @override
  void dispose() {
    try {
      _hScrollController.dispose();
    } catch (_) {}
    try {
      _vScrollController.dispose();
    } catch (_) {}
    try {
      _sembastStorage.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _appendRawLogEntry(String name, String entry) async {
    try {
      if (_storageReady) {
        final f = await _fileForName(name);
        await f.writeAsString(entry, mode: FileMode.append);
      } else {
        final f = await _fileForName(name);
        await f.writeAsString(entry, mode: FileMode.append);
      }
    } catch (_) {}
  }

  Future<File> _fileForName(String name) async {
    // Resolve the application documents directory and ensure we use
    // the same `simplepresent` subfolder as the rest of the app.
    final dir = await getApplicationDocumentsDirectory();
    final folderName = kDebugMode ? 'simplepresent-debug' : 'simplepresent';
    final sub = Directory('${dir.path}/$folderName');
    try {
      if (!await sub.exists()) await sub.create(recursive: true);
    } catch (_) {}
    return File('${sub.path}/$name');
  }

  String _storageName(String name) => kDebugMode ? 'debug_$name' : name;

  Future<void> _loadEntries() async {
    setState(() {
      _loading = true;
    });
    try {
      final lines = <String>[];
      final f = await _fileForName(_storageName('simplepresent_redo.log'));
      if (!await f.exists()) {
        setState(() {
          _entries = [];
          _loading = false;
        });
        return;
      }
      final fileLines = await f.readAsLines();
      lines.addAll(fileLines);
      final recent =
          lines.length > 500 ? lines.sublist(lines.length - 500) : lines;
      final parsed = <Map<String, dynamic>>[];
      for (final l in recent.reversed) {
        try {
          final m = jsonDecode(l);
          if (m is Map<String, dynamic>)
            parsed.add(m);
          else
            parsed.add({'raw': l});
        } catch (_) {
          parsed.add({'raw': l});
        }
      }
      setState(() {
        _entries = parsed;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _entries = [];
        _loading = false;
      });
    }
  }

  String _shortDetails(Map<String, dynamic> e) {
    final d = e['details'];
    final action = (e['action'] ?? '').toString();
    if (d == null) {
      // fallback to raw line
      final raw = e['raw']?.toString() ?? '';
      return raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
    }
    try {
      if (d is Map<String, dynamic>) {
        // If this is an explicit undo entry, summarize the inner undone entry
        if (action == 'undo' && d['undone_entry'] is Map) {
          try {
            final inner = Map<String, dynamic>.from(d['undone_entry']);
            final innerAction = (inner['action'] ?? '')?.toString() ?? '';
            final innerTask =
                (inner['task_id'] ?? inner['taskId'] ?? '')?.toString() ?? '';
            String innerSummary = '';
            try {
              innerSummary = _shortDetails(
                  {'action': innerAction, 'details': inner['details']});
            } catch (_) {
              innerSummary = innerAction;
            }
            if (innerTask.isNotEmpty)
              return 'undo: $innerAction for ${_shortVal(innerTask)}';
            if (innerSummary.isNotEmpty) return 'undo: $innerSummary';
            return 'undo: $innerAction';
          } catch (_) {}
        }
        // Special-case subtask actions for friendlier display
        if (action == 'subtask_add' && d['subtask'] is Map) {
          final s = Map<String, dynamic>.from(d['subtask']);
          final txt =
              _shortVal(s['text'] ?? s['title'] ?? s['name'] ?? s['id']);
          return 'subtask added: $txt';
        }
        if (action == 'subtask_remove' && d['subtask'] is Map) {
          final s = Map<String, dynamic>.from(d['subtask']);
          final txt =
              _shortVal(s['text'] ?? s['title'] ?? s['name'] ?? s['id']);
          return 'subtask removed: $txt';
        }
        if (action == 'subtask_edit') {
          // Show concise diff for the subtask fields
          if (d['before'] is Map || d['after'] is Map) {
            final before = d['before'] is Map
                ? Map<String, dynamic>.from(d['before'])
                : <String, dynamic>{};
            final after = d['after'] is Map
                ? Map<String, dynamic>.from(d['after'])
                : <String, dynamic>{};
            final keys = <String>{}
              ..addAll(before.keys.map((k) => k.toString()))
              ..addAll(after.keys.map((k) => k.toString()));
            final parts = <String>[];
            for (final k in keys) {
              final b = before[k];
              final a = after[k];
              if (jsonEncode(b) != jsonEncode(a)) {
                parts.add('$k: "${_shortVal(b)}" → "${_shortVal(a)}"');
              }
            }
            if (parts.isNotEmpty) return 'subtask edit: ' + parts.join('; ');
          }
        }
        if (action == 'subtask_reorder' && d['before'] is List) {
          final before =
              List.from(d['before']).map((x) => x.toString()).toList();
          return 'subtask order: ${before.join(", ")}';
        }
        // If details only contains a `text` field, show the text itself
        if (d.length == 1 && d.containsKey('text')) {
          final txt = _shortVal(d['text']);
          return txt;
        }
        // before/after snapshot diff
        final before = d['before'] is Map
            ? Map<String, dynamic>.from(d['before'])
            : <String, dynamic>{};
        final after = d['after'] is Map
            ? Map<String, dynamic>.from(d['after'])
            : <String, dynamic>{};
        if (before.isNotEmpty || after.isNotEmpty) {
          final keys = <String>{}
            ..addAll(before.keys.map((k) => k.toString()))
            ..addAll(after.keys.map((k) => k.toString()));
          final parts = <String>[];
          for (final k in keys) {
            final b = before[k];
            final a = after[k];
            if (jsonEncode(b) != jsonEncode(a)) {
              final bs = _shortVal(b);
              final as = _shortVal(a);
              parts.add('$k: "$bs" -> "$as"');
            }
          }
          if (parts.isNotEmpty) return parts.join('; ');
        }
        // simple map (e.g., move details)
        if (d.containsKey('from') && d.containsKey('to')) {
          return 'moved: ${d['from']} → ${d['to']}';
        }
        final s = jsonEncode(d);
        return s.length > 80 ? '${s.substring(0, 80)}…' : s;
      }
      final s = d.toString();
      return s.length > 80 ? '${s.substring(0, 80)}…' : s;
    } catch (_) {
      final s = e['raw']?.toString() ?? d.toString();
      return s.length > 80 ? '${s.substring(0, 80)}…' : s;
    }
  }

  String _shortVal(dynamic v) {
    if (v == null) return 'null';
    try {
      if (v is String) {
        final dt = DateTime.tryParse(v);
        if (dt != null)
          return DateFormat('yyyy-MM-dd HH:mm').format(dt.toLocal());
        return v.length > 50 ? '${v.substring(0, 50)}…' : v;
      }
      final s = jsonEncode(v);
      return s.length > 50 ? '${s.substring(0, 50)}…' : s;
    } catch (_) {
      final s = v.toString();
      return s.length > 50 ? '${s.substring(0, 50)}…' : s;
    }
  }

  Future<void> _copyAll() async {
    try {
      String text = '';
      final f = await _fileForName(_storageName('simplepresent_redo.log'));
      if (!await f.exists()) return;
      text = await f.readAsString();
      if (text.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) _showTopToastLocal('Copied redo log to clipboard');
    } catch (_) {}
  }

  void _showDetails(Map<String, dynamic> e) {
    final pretty = () {
      try {
        if (e.containsKey('raw')) return e['raw'].toString();
        // Helpers to render subtask(s) tersely
        String renderSubtask(Map s) {
          final id = (s['id'] ?? s['uid'] ?? '')?.toString() ?? '';
          final txt =
              (s['text'] ?? s['title'] ?? s['name'] ?? '')?.toString() ?? '';
          final done =
              (s['done'] == true || s['completed'] == true) ? ' (done)' : '';
          if (id.isNotEmpty && txt.isNotEmpty)
            return '$id: ${_shortVal(txt)}$done';
          if (txt.isNotEmpty) return _shortVal(txt) + done;
          if (id.isNotEmpty) return id + done;
          return jsonEncode(s);
        }

        String renderSubtaskList(List lst) {
          final lines = <String>[];
          for (var i = 0; i < lst.length; i++) {
            final item = lst[i];
            if (item is Map) {
              lines.add(
                  '${i + 1}. ${renderSubtask(Map<String, dynamic>.from(item))}');
            } else {
              lines.add('${i + 1}. ${_shortVal(item)}');
            }
          }
          return lines.join('\n');
        }

        final action = (e['action'] ?? '').toString();
        final d = e['details'];

        // If this is an undo entry, pretty-print the inner undone entry more cleanly
        if (action == 'undo' && d is Map && d['undone_entry'] is Map) {
          final inner = Map<String, dynamic>.from(d['undone_entry']);
          final header = 'Undo performed: ${e['timestamp'] ?? e['time'] ?? ''}';
          final innerDetails = inner['details'];
          if (innerDetails is Map) {
            if (innerDetails['subtask'] is Map) {
              return header +
                  '\n' +
                  'Undone: ' +
                  renderSubtask(
                      Map<String, dynamic>.from(innerDetails['subtask']));
            }
            if (innerDetails['subtasks'] is List) {
              return header +
                  '\n' +
                  'Undone subtasks:\n' +
                  renderSubtaskList(List.from(innerDetails['subtasks']));
            }
          }
          return header +
              '\n' +
              const JsonEncoder.withIndent('  ').convert(inner);
        }

        // If details directly include subtask(s), render them nicely
        if (d is Map) {
          if (d['subtask'] is Map) {
            return 'subtask: ' +
                renderSubtask(Map<String, dynamic>.from(d['subtask']));
          }
          if (d['subtasks'] is List) {
            return 'subtasks:\n' + renderSubtaskList(List.from(d['subtasks']));
          }
          // also handle before/after containing subtasks
          if (d['before'] is Map && d['before']['subtasks'] is List) {
            return 'before subtasks:\n' +
                renderSubtaskList(List.from(d['before']['subtasks']));
          }
          if (d['after'] is Map && d['after']['subtasks'] is List) {
            return 'after subtasks:\n' +
                renderSubtaskList(List.from(d['after']['subtasks']));
          }
        }

        return const JsonEncoder.withIndent('  ').convert(e);
      } catch (_) {
        return e.toString();
      }
    }();
    showModalBottomSheet<void>(
        context: context,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      child:
                          SingleChildScrollView(child: SelectableText(pretty))),
                  Row(children: [
                    TextButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: pretty));
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Copy')),
                    const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Close')),
                  ])
                ],
              ),
            ),
          );
        });
  }

  Future<List<Map<String, dynamic>>> _readListFile(String name) async {
    try {
      if (_storageReady) {
        try {
          final rows = _sembastStorage.readTaskList(_storageName(name));
          return rows.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {
          return [];
        }
      }
      final f = await _fileForName(_storageName(name));
      if (!await f.exists()) return [];
      final s = await f.readAsString();
      final v = jsonDecode(s);
      if (v is List)
        return v
            .map((e) => e is Map<String, dynamic>
                ? Map<String, dynamic>.from(e)
                : <String, dynamic>{})
            .toList();
    } catch (_) {}
    return [];
  }

  Future<void> _writeListFile(
      String name, List<Map<String, dynamic>> list) async {
    try {
      final encoder = const JsonEncoder.withIndent('  ');
      final content = encoder.convert(list);
      if (_storageReady) {
        _sembastStorage.writeTaskList(_storageName(name), list);
        // When using Sembast, also export per-task JSON files for the
        // Android widget if we just wrote the `today` list.
        try {
          if (name == _storageName('simplepresent_today.json')) {
            final tasks = list
                .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
                .where((t) => !t.done)
                .toList();
            unawaited(exportTodayAndRefresh(tasks));
          }
        } catch (_) {}
        return;
      }
      final f = await _fileForName(_storageName(name));
      try {
        await _debugLog('write list file tmp for: ${f.path}');
      } catch (_) {}
      // write atomically via temp file in the same dir
      final tmp = File('${f.path}.tmp');
      try {
        await tmp.writeAsString(content);
        try {
          await tmp.rename(f.path);
          await _debugLog('wrote list file: ${f.path}');
        } catch (_) {
          await f.writeAsString(content);
          if (await tmp.exists()) await tmp.delete();
          await _debugLog('wrote list file by overwrite: ${f.path}');
        }
      } catch (e) {
        try {
          await f.writeAsString(content);
          await _debugLog('direct wrote list file: ${f.path}');
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _undoEntry(Map<String, dynamic> e) async {
    try {
      final action = (e['action'] ?? '')?.toString() ?? '';
      final taskId =
          (e['task_id'] ?? e['taskId'] ?? e['taskId'] ?? '')?.toString() ?? '';
      // Load lists
      final today = await _readListFile('simplepresent_today.json');
      final backlog = await _readListFile('simplepresent_backlog.json');
      final done = await _readListFile('simplepresent_done.json');

      bool changed = false;

      Map<String, dynamic>? removeById(
          List<Map<String, dynamic>> list, String id) {
        final idx = list
            .indexWhere((m) => (m['id'] ?? m['uid'] ?? '').toString() == id);
        if (idx == -1) return null;
        return list.removeAt(idx);
      }

      if (action == 'create') {
        // undo create -> remove created item from any list
        final removed = removeById(today, taskId) ??
            removeById(backlog, taskId) ??
            removeById(done, taskId);
        if (removed != null) changed = true;
      } else if (action == 'done') {
        // undo done -> move from done back to today
        final removed = removeById(done, taskId);
        if (removed != null) {
          removed['done'] = false;
          removed.remove('completedAt');
          today.insert(0, removed);
          changed = true;
        }
      } else if (action == 'reopen') {
        // undo reopen -> mark as done (move to done)
        final removed =
            removeById(today, taskId) ?? removeById(backlog, taskId);
        if (removed != null) {
          removed['done'] = true;
          removed['completedAt'] = DateTime.now().toIso8601String();
          done.insert(0, removed);
          changed = true;
        }
      } else if (action == 'move_to_backlog') {
        // undo move to backlog -> move from backlog to today
        final removed = removeById(backlog, taskId);
        if (removed != null) {
          today.insert(0, removed);
          changed = true;
        }
      } else if (action == 'move_to_today') {
        final removed = removeById(today, taskId);
        if (removed != null) {
          backlog.insert(0, removed);
          changed = true;
        }
      } else if (action == 'duplicate') {
        // details.source/target? remove target id if present
        final details = e['details'];
        final target =
            details is Map ? (details['target'] ?? '')?.toString() ?? '' : '';
        if (target.isNotEmpty) {
          final removed = removeById(today, target) ??
              removeById(backlog, target) ??
              removeById(done, target);
          if (removed != null) changed = true;
        }
      } else if (action == 'edit') {
        // restore before snapshot if available
        final details = e['details'];
        if (details is Map && details['before'] is Map) {
          final before = Map<String, dynamic>.from(details['before']);
          // find task in lists and replace fields
          for (final list in [today, backlog, done]) {
            final idx = list.indexWhere(
                (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
            if (idx != -1) {
              final cur = list[idx];
              before.forEach((k, v) {
                cur[k] = v;
              });
              list[idx] = cur;
              changed = true;
              break;
            }
          }
        }
      } else if (action == 'subtask_add') {
        // details.subtask -> remove that subtask from the task
        final details = e['details'];
        if (details is Map && details['subtask'] is Map) {
          final sid = (details['subtask']['id'] ?? '')?.toString() ?? '';
          if (sid.isNotEmpty) {
            for (final list in [today, backlog, done]) {
              final idx = list.indexWhere(
                  (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
              if (idx != -1) {
                final subt = (list[idx]['subtasks'] is List)
                    ? List<Map<String, dynamic>>.from(list[idx]['subtasks'])
                    : <Map<String, dynamic>>[];
                final beforeLen = subt.length;
                subt.removeWhere((s) => (s['id'] ?? '')?.toString() == sid);
                if (subt.length != beforeLen) {
                  list[idx]['subtasks'] = subt;
                  changed = true;
                  break;
                }
              }
            }
          }
        }
      } else if (action == 'subtask_remove') {
        // details.subtask -> add that subtask back to the task (append)
        final details = e['details'];
        if (details is Map && details['subtask'] is Map) {
          final sub = Map<String, dynamic>.from(details['subtask']);
          for (final list in [today, backlog, done]) {
            final idx = list.indexWhere(
                (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
            if (idx != -1) {
              final subt = (list[idx]['subtasks'] is List)
                  ? List<Map<String, dynamic>>.from(list[idx]['subtasks'])
                  : <Map<String, dynamic>>[];
              subt.add(sub);
              list[idx]['subtasks'] = subt;
              changed = true;
              break;
            }
          }
        }
      } else if (action == 'subtask_edit') {
        final details = e['details'];
        if (details is Map &&
            details['subtaskId'] != null &&
            details['before'] is Map) {
          final sid = details['subtaskId'].toString();
          final before = Map<String, dynamic>.from(details['before']);
          for (final list in [today, backlog, done]) {
            final idx = list.indexWhere(
                (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
            if (idx != -1) {
              final subt = (list[idx]['subtasks'] is List)
                  ? List<Map<String, dynamic>>.from(list[idx]['subtasks'])
                  : <Map<String, dynamic>>[];
              for (var si = 0; si < subt.length; si++) {
                if ((subt[si]['id'] ?? '')?.toString() == sid) {
                  subt[si] = before;
                  list[idx]['subtasks'] = subt;
                  changed = true;
                  break;
                }
              }
              if (changed) break;
            }
          }
        }
      } else if (action == 'subtask_reorder') {
        final details = e['details'];
        if (details is Map && details['before'] is List) {
          final beforeOrder =
              List<String>.from(details['before'].map((x) => x.toString()));
          for (final list in [today, backlog, done]) {
            final idx = list.indexWhere(
                (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
            if (idx != -1) {
              final subt = (list[idx]['subtasks'] is List)
                  ? List<Map<String, dynamic>>.from(list[idx]['subtasks'])
                  : <Map<String, dynamic>>[];
              final mapById = {
                for (var s in subt) (s['id'] ?? '').toString(): s
              };
              final newList = <Map<String, dynamic>>[];
              for (final id in beforeOrder) {
                if (mapById.containsKey(id)) newList.add(mapById[id]!);
              }
              // append any missing ones
              for (final s in subt)
                if (!beforeOrder.contains((s['id'] ?? '').toString()))
                  newList.add(s);
              list[idx]['subtasks'] = newList;
              changed = true;
              break;
            }
          }
        }
      } else if (action == 'schedule_set' || action == 'schedule_clear') {
        final details = e['details'];
        if (details is Map) {
          final before = details['before'];
          DateTime? beforeDt;
          if (before is String && before.isNotEmpty)
            beforeDt = DateTime.tryParse(before);
          // find task and set scheduledAt
          for (final list in [today, backlog, done]) {
            final idx = list.indexWhere(
                (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
            if (idx != -1) {
              list[idx]['scheduled_at'] = beforeDt?.toIso8601String();
              list[idx]['scheduledAt'] = beforeDt?.toIso8601String();
              changed = true;
              break;
            }
          }
          // If task currently lives in backlog but before schedule implies it should be in today, move it back.
          if (!changed) {
            // try to find in backlog and move to today if appropriate
            final bidx = backlog.indexWhere(
                (m) => (m['id'] ?? m['uid'] ?? '').toString() == taskId);
            if (bidx != -1) {
              final now = DateTime.now();
              final shouldBeToday = beforeDt == null ||
                  (beforeDt.year == now.year &&
                      beforeDt.month == now.month &&
                      beforeDt.day == now.day);
              if (shouldBeToday) {
                final item = backlog.removeAt(bidx);
                today.insert(0, item..remove('scheduled_at'));
                changed = true;
              }
            }
          }
        }
      }

      if (changed) {
        // persist changes
        await _writeListFile('simplepresent_today.json', today);
        await _writeListFile('simplepresent_backlog.json', backlog);
        await _writeListFile('simplepresent_done.json', done);

        // Append an explicit undo entry to the redo log file
        final undoEntry = {
          'timestamp': DateTime.now().toIso8601String(),
          'action': 'undo',
          'task_id': taskId,
          'details': {'undone_entry': e},
        };
        try {
          await _appendRawLogEntry(_storageName('simplepresent_redo.log'),
              '${jsonEncode(undoEntry)}\n');
        } catch (_) {}
        // Also try to push this undo entry to the cloud as an encrypted 'redo' item
        // Hand off cloud push to the caller (HomePage) by returning the undo entry.

        // feedback will be shown by the caller after the page pops
        await _loadEntries();
        // Return the undo entry to the caller so HomePage can push it to cloud
        try {
          Navigator.of(context).pop({'undo': true, 'entry': undoEntry});
        } catch (_) {}
      } else {
        if (mounted) _showTopToastLocal('Nothing to undo');
      }
    } catch (err) {
      if (mounted) _showTopToastLocal('Undo failed: $err');
    }
  }

  void _showTopToastLocal(String message) {
    final now = DateTime.now();
    if (_lastToastMessageLocal != null && _lastToastMessageLocal == message) {
      if (_lastToastAtLocal != null &&
          now.difference(_lastToastAtLocal!).inSeconds < 3) return;
    }
    if (_lastToastAtLocal != null &&
        now.difference(_lastToastAtLocal!).inMilliseconds < 700) return;
    _lastToastMessageLocal = message;
    _lastToastAtLocal = now;

    _toastTimerLocal?.cancel();
    _toastEntryLocal?.remove();

    final overlay = Overlay.of(context, rootOverlay: true);
    _toastEntryLocal = OverlayEntry(
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
                    offset: Offset(0, offset.dy * 60), child: child);
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(_toastEntryLocal!);
    _toastTimerLocal = Timer(const Duration(milliseconds: 1650), () {
      _toastEntryLocal?.remove();
      _toastEntryLocal = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 40,
        titleSpacing: 0,
        toolbarHeight: 62,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Image.asset('assets/icons/color_transparent_redo.png',
                  width: 28, height: 28),
            ),
            const SizedBox(width: 8),
            Text('Redo Log',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loadEntries),
          IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Copy all',
              onPressed: _copyAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: _entries.isEmpty
                  ? const Center(child: Text('No redo log entries'))
                  : LayoutBuilder(builder: (ctx, constraints) {
                      final width = constraints.maxWidth;
                      final cross = width > 1000 ? 3 : (width > 600 ? 2 : 1);
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cross,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 3,
                        ),
                        itemCount: _entries.length,
                        itemBuilder: (ctx2, i) {
                          final e = _entries[i];
                          final rawTs = e['timestamp'] ?? e['time'] ?? '';
                          String formattedTs = '';
                          if (rawTs != null && rawTs.toString().isNotEmpty) {
                            final dt = DateTime.tryParse(rawTs.toString());
                            if (dt != null) {
                              formattedTs = DateFormat('yyyy-MM-dd HH:mm:ss')
                                  .format(dt.toLocal());
                            } else {
                              formattedTs = rawTs.toString();
                            }
                          }
                          final action = (e['action'] ?? '')?.toString() ?? '';
                          final detailShort = _shortDetails(e);
                          return Card(
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(formattedTs,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                      Text(action,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Text(detailShort,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 4),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                            icon: const Icon(Icons.copy),
                                            tooltip: 'Copy entry',
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                  ClipboardData(
                                                      text: jsonEncode(e)));
                                              if (mounted)
                                                _showTopToastLocal(
                                                    'Copied entry');
                                            }),
                                        IconButton(
                                            icon: const Icon(Icons.open_in_new),
                                            tooltip: 'View details',
                                            onPressed: () => _showDetails(e)),
                                        IconButton(
                                            icon: const Icon(Icons.undo),
                                            tooltip: 'Undo action',
                                            onPressed: () async {
                                              final confirm = await showDialog<
                                                      bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                          title: const Text(
                                                              'Undo action?'),
                                                          content: Text(
                                                              'Undo "${e['action']}" for ${_shortDetails(e)}?'),
                                                          actions: [
                                                            TextButton(
                                                                onPressed: () =>
                                                                    Navigator.of(
                                                                            ctx)
                                                                        .pop(
                                                                            false),
                                                                child: const Text(
                                                                    'Cancel')),
                                                            FilledButton(
                                                                onPressed: () =>
                                                                    Navigator.of(
                                                                            ctx)
                                                                        .pop(
                                                                            true),
                                                                child:
                                                                    const Text(
                                                                        'Undo'))
                                                          ]));
                                              if (confirm == true) {
                                                await _undoEntry(e);
                                              }
                                            }),
                                      ]),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }),
            ),
    );
  }
}

class _StatRow {
  const _StatRow({
    required this.taskText,
    required this.minutes,
    required this.isDone,
    required this.completedAt,
    required this.statusLabel,
  });
  final String taskText;
  final int minutes;
  final bool isDone;
  final DateTime? completedAt;
  final String statusLabel;
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
        leadingWidth: 40,
        titleSpacing: 0,
        toolbarHeight: 62,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Icon(Icons.qr_code, size: 28),
            ),
            const SizedBox(width: 8),
            Text('scan qr code',
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          ],
        ),
        centerTitle: false,
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
