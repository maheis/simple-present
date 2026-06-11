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
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
      ),
      home: const HomePage(),
    );
  }
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
      final genId = '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
      return TaskStep(id: genId, text: json, done: false);
    }
    final map = json as Map<String, dynamic>;
    final String id = (map['id'] ?? map['uid'] ?? '').toString();
    final String useId = id.isNotEmpty ? id : '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 32)}';
    return TaskStep(
      id: useId,
      text: (map['text'] ?? '').toString(),
      done: map['done'] == true,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
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

  TaskItem copyWith({
    String? id,
    String? text,
    bool? done,
    bool? important,
    bool? inProgress,
    DateTime? completedAt,
    DateTime? inProgressAt,
    DateTime? importantAt,
    DateTime? createdAt,
    DateTime? scheduledAt,
    String? notes,
    List<TaskStep>? subtasks,
  }) {
    return TaskItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      important: important ?? this.important,
      inProgress: inProgress ?? this.inProgress,
      completedAt: completedAt ?? this.completedAt,
      inProgressAt: inProgressAt ?? this.inProgressAt,
      importantAt: importantAt ?? this.importantAt,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      notes: notes ?? this.notes,
      subtasks: subtasks ?? this.subtasks,
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
      final genId = '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1<<32)}';
      return TaskItem(id: genId, text: json, done: false);
    }
    final map = json as Map<String, dynamic>;
    final String id = (map['id'] ?? map['uid'] ?? '').toString();
    final String useId = id.isNotEmpty ? id : '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1<<32)}';
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _idleTimer;
  Timer? _attentionTimer;
  final Duration _idleDuration = const Duration(minutes: 45);
  final Duration _attentionDuration = const Duration(minutes: 60);
  Timer? _reminderTimer;
  final Duration _reminderDuration = const Duration(minutes: 75);
  Timer? _urgentTimer;
  final Duration _urgentDuration = const Duration(minutes: 90);
  // Fired flags to ensure each reminder type fires only once per inactivity period
  bool _idleFired = false;
  bool _attentionFired = false;
  bool _reminderFired = false;
  bool _urgentFired = false;
  final MethodChannel _nativeWindowChannel =
      const MethodChannel('simple_present/window');
  Timer? _scheduledCheckTimer;
  Timer? _windowWatcherTimer;
  Map<String, int>? _lastSavedWindowGeom;
  final Set<String> _notified15 = <String>{};
  final Set<String> _notifiedDue = <String>{};
  final Set<int> _swiping = <int>{};

  // Zoom state: tile height and font scaling
  double _tileHeight = 52.0;
  final double _defaultTileHeight = 52.0;
  final double _minTileHeight = 1.0; // allow extremely thin tiles
  double _fontScale = 1.0;
  final double _minFontScale = 0.6;
  final double _baseFontSize = 16.0; // used when scaling text down
  double _tileHeightStart = 52.0;
  double _fontScaleStart = 1.0;
  bool _alwaysOnTop = false;
  final String _appTitle = 'SimplePresent';

  double _fontScaleForTileHeight(double tileHeight) {
    return tileHeight <= 1.0 ? _minFontScale : 1.0;
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
    _loadSettings();
    // Start watching window geometry after startup
    _startWindowWatcher();
    _startIdleTimer();
    _startAttentionTimer();
    _startReminderTimer();
    _startUrgentTimer();
    _startScheduledChecker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _inputFocus.requestFocus();
      }
    });
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
      final f = await _fileFor(filename);
      if (!await f.exists()) {
        await f.writeAsString('[]');
      }
    } catch (_) {}
  }

  Future<void> _ensureInitialFiles() async {
    await _ensureListFile('simplepresent_today.json');
    await _ensureListFile('simplepresent_done.json');
    await _ensureListFile('simplepresent_backlog.json');
  }

  Future<void> _initializeApp() async {
    await _ensureInitialFiles();

    // Ensure daily reset: when app is started the first time on a new day,
    // move all open (not done) tasks from Today into Backlog (bottom->top),
    // leave Done tasks in their file. Persist a lastRunDate in settings.
    try {
      final settingsFile = await _fileFor('simplepresent_settings.json');
      Map<String, dynamic> settings = {};
      if (await settingsFile.exists()) {
        try {
          settings = jsonDecode(await settingsFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {
          settings = {};
        }
      }
      final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final lastRun = settings['lastRunDate'] as String?;
      if (lastRun != todayKey) {
        // First run today -> migrate open tasks from today -> backlog
        final List<TaskItem> todayList = [];
        await _loadList('simplepresent_today.json', todayList);
        final List<TaskItem> movedToDone = [];
        int movedToBacklogCount = 0;
        if (todayList.isNotEmpty) {
          final List<TaskItem> backlogList = [];
          await _loadList('simplepresent_backlog.json', backlogList);
          final List<TaskItem> doneList = [];
          await _loadList('simplepresent_done.json', doneList);

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
          await _saveList('simplepresent_backlog.json', backlogList);
          if (movedToDone.isNotEmpty) {
            // append moved done tasks to existing done list (preserve existing order)
            doneList.addAll(movedToDone.reversed); // reverse to keep original top->bottom order
            await _saveList('simplepresent_done.json', doneList);
          }
          await _saveList('simplepresent_today.json', <TaskItem>[]);
        }
        settings['lastRunDate'] = todayKey;
        final enc = const JsonEncoder.withIndent('  ');
        try {
          await settingsFile.writeAsString(enc.convert(settings));
        } catch (_) {}
        // Show a short summary toast after first frame if any tasks were moved
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final movedDoneCount = movedToDone.length;
          if (movedToBacklogCount > 0 || movedDoneCount > 0) {
            final parts = <String>[];
            if (movedToBacklogCount > 0) parts.add('$movedToBacklogCount moved to Backlog');
            if (movedDoneCount > 0) parts.add('$movedDoneCount moved to Done');
            _showTopToast(parts.join(', '));
          }
        });
      }
    } catch (_) {}

    await _loadToday();
  }

  Future<void> _loadList(String filename, List<TaskItem> target) async {
    target.clear();
    try {
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
      await _loadList('simplepresent_done.json', existing);
      existing.addAll(items);
      await _saveList('simplepresent_done.json', existing);
    } catch (_) {}
  }

  Future<void> _saveList(String filename, List<TaskItem> source) async {
    try {
      final f = await _fileFor(filename);
      final encoder = const JsonEncoder.withIndent('  ');
      await f.writeAsString(
          encoder.convert(source.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadToday() async {
    await _loadList(_currentFile, _today);
    setState(() {});
  }

  Future<void> _saveToday() async {
    await _saveList(_currentFile, _today);
  }

  Future<void> _switchFile(bool showDone) async {
    _showingDone = showDone;
    _showingBacklog = false;
    _currentFile = showDone ? 'simplepresent_done.json' : 'simplepresent_today.json';
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
    _currentFile = 'simplepresent_backlog.json';
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
      final f = await _fileFor('simplepresent_settings.json');
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
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
      });
      if (data.containsKey('window')) {
        try {
          final w = data['window'];
          if (w is Map) {
            final wm = Map<String, int>.from(w.cast<String, dynamic>().map((k, v) => MapEntry(k, (v as num).toInt())));
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
        sw = (screen['width'] is int) ? screen['width'] as int : (screen['width'] is double ? (screen['width'] as double).toInt() : int.parse(screen['width'].toString()));
        sh = (screen['height'] is int) ? screen['height'] as int : (screen['height'] is double ? (screen['height'] as double).toInt() : int.parse(screen['height'].toString()));
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
        if (width <= 0 || height <= 0 || width > sw * 4 || height > sh * 4) valid = false;
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

      final payload = <String, dynamic>{'x': x, 'y': y, 'width': width, 'height': height, 'maximized': maximized, 'always_on_top': (_alwaysOnTop || (w['always_on_top'] == 1))};
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
      final f = await _fileFor('simplepresent_settings.json');
      final out = <String, dynamic>{'tileHeight': _tileHeight, 'fontScale': _fontScale};
      // Preserve lastRunDate if present in existing settings so daily-reset runs only once per day
      try {
        if (await f.exists()) {
          final existing = jsonDecode(await f.readAsString());
          if (existing is Map && existing.containsKey('lastRunDate')) {
            out['lastRunDate'] = existing['lastRunDate'];
          }
        }
      } catch (_) {}
      try {
        Map<String, dynamic>? useGeom;
        if (geom != null) {
          useGeom = geom.cast<String, dynamic>();
        } else {
          final g = await _nativeWindowChannel.invokeMethod('getWindowGeometry');
          if (g is Map) useGeom = Map<String, dynamic>.from(g.cast<String, dynamic>());
        }
        if (useGeom != null) out['window'] = useGeom;
      } catch (_) {}
      // Persist current notification flags as lists so restarts don't re-notify
      out['notified15'] = _notified15.toList();
      out['notifiedDue'] = _notifiedDue.toList();
      final encoder = const JsonEncoder.withIndent('  ');
      await f.writeAsString(encoder.convert(out));
    } catch (_) {}
  }

  @override
  void dispose() {
    _windowWatcherTimer?.cancel();
    _saveSettings();
    _controller.dispose();
    _inputFocus.dispose();
    _audioPlayer.dispose();
    _idleTimer?.cancel();
    _attentionTimer?.cancel();
    _reminderTimer?.cancel();
    _urgentTimer?.cancel();
    _scheduledCheckTimer?.cancel();
    for (final c in _editControllers.values) {
      c.dispose();
    }
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    for (final c in _subtaskInputControllers.values) {
      c.dispose();
    }
    _toastTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
  }

  String _taskNotifyKey(TaskItem t) {
    final sched = t.scheduledAt?.toIso8601String() ?? '';
    return '${t.id}|$sched';
  }

  void _startScheduledChecker() {
    _scheduledCheckTimer?.cancel();
    _scheduledCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      final now = DateTime.now();
      for (final t in _today) {
        // Do not remind for tasks without schedule or already completed
        if (t.scheduledAt == null) continue;
        if (t.done) continue;
        final diff = t.scheduledAt!.difference(now);
        final key = _taskNotifyKey(t);
        // 15-minute warning
          if (!diff.isNegative && diff.inMinutes <= 15 && !_notified15.contains(key)) {
          _notified15.add(key);
          try {
            await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('notify', <String, String>{
              'title': _appTitle,
              'body': 'Termin in 15 Minuten: ${t.text}',
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
            await _audioPlayer.play(AssetSource('sounds/pop.mp3'));
          } catch (_) {}
          try {
            await _nativeWindowChannel.invokeMethod('notify', <String, String>{
              'title': _appTitle,
              'body': 'Termin fällig: ${t.text}',
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

  void _startWindowWatcher() {
    _windowWatcherTimer?.cancel();
    _windowWatcherTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      try {
        final geom = await _nativeWindowChannel.invokeMethod('getWindowGeometry');
        if (geom is Map) {
          // normalize ints
          final norm = <String, int>{};
          for (final e in geom.entries) {
            final k = e.key.toString();
            final v = e.value;
            if (v is int) norm[k] = v;
            else if (v is double) norm[k] = v.toInt();
            else norm[k] = int.tryParse(v.toString()) ?? 0;
          }
          if (_lastSavedWindowGeom == null || !mapEquals(_lastSavedWindowGeom, norm)) {
            _lastSavedWindowGeom = Map<String, int>.from(norm);
            await _saveSettingsWithGeom(_lastSavedWindowGeom);
          }
        }
      } catch (_) {}
    });
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

  void _saveEditedTitle(int index) {
    final titleCtrl = _editControllers[index];
    final notesCtrl = _notesControllers[index];
    if (titleCtrl == null || notesCtrl == null) return;
    final newText = titleCtrl.text.trim();
    final newNotes = notesCtrl.text;
    if (newText.isEmpty) return;
    setState(() {
      _today[index] = _today[index].copyWith(text: newText, notes: newNotes);
    });
    _saveToday();
    _showTopToast('Task updated');
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
    _showTopToast('Termin gesetzt');
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
      await _loadList('simplepresent_today.json', todayList);
      todayList.insert(0, item.copyWith(done: false, inProgress: false));
      await _saveList('simplepresent_today.json', todayList);

      _showTopToast('Task moved to Today');
    } catch (_) {
      _showTopToast('Failed to move task to Today');
    }
    _registerActivity();
  }

  Future<void> _clearSchedule(int index) async {
    setState(() => _today[index] = _today[index].copyWith(scheduledAt: null));
    await _saveToday();
    _showTopToast('Termin entfernt');
    final idPrefix2 = '${_today[index].id}|';
    _notified15.removeWhere((k) => k.startsWith(idPrefix2));
    _notifiedDue.removeWhere((k) => k.startsWith(idPrefix2));
    _registerActivity();
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

  void _addToToday(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _today.insert(
          0,
          TaskItem(
              id: '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1<<32)}',
              text: text.trim(),
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

        _showTopToast('Task moved to Today');
      } catch (_) {
        _showTopToast('Failed to move task');
      }
      _registerActivity();
      return;
    }

    // If we're in the Backlog view and the user marks a task done, move it to Done list
    if (value && _currentFile == 'simplepresent_backlog.json') {
      try {
        final moved = original.copyWith(done: true, completedAt: DateTime.now());
        setState(() {
          _today.removeAt(index);
          _expanded.clear();
        });
        await _saveToday(); // persist removal from backlog
        await _appendDone([moved]);
        _showTopToast('Task moved to Done');
        _playDading();
      } catch (_) {
        _showTopToast('Failed to move task to Done');
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
    final removedId = _today[index].id;
    setState(() {
      _today.removeAt(index);
    });
    _saveToday();
    // Clear any pending notification flags for this task (use text match)
    final idPrefix = '${removedId}|';
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
      try {
        await _audioPlayer.play(AssetSource('sounds/there.mp3'));
      } catch (_) {
        SystemSound.play(SystemSoundType.alert);
      }
      _idleFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  void _startAttentionTimer() {
    _attentionTimer = Timer(_attentionDuration, () async {
      if (_attentionFired) return;
      try {
        await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        try {
          await _nativeWindowChannel.invokeMethod('flashTaskbar');
        } catch (_) {}
      } catch (_) {
        SystemSound.play(SystemSoundType.alert);
      }
      _attentionFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  void _startReminderTimer() {
    _reminderTimer = Timer(_reminderDuration, () async {
      if (_reminderFired) return;
      try {
        await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        try {
          await _nativeWindowChannel.invokeMethod('notify', <String, String>{
            'title': _appTitle,
            'body': 'You have been inactive for 75 minutes',
            'icon': 'assets/icons/icon.png',
          });
        } catch (_) {}
      } catch (_) {
        SystemSound.play(SystemSoundType.alert);
      }
      _reminderFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  void _startUrgentTimer() {
    _urgentTimer = Timer(_urgentDuration, () async {
      if (_urgentFired) return;
      try {
        await _audioPlayer.play(AssetSource('sounds/there.mp3'));
        try {
          await _nativeWindowChannel.invokeMethod('notify', <String, String>{
            'title': _appTitle,
            'body': 'You have been inactive for 90 minutes',
            'icon': 'assets/icons/icon.png',
          });
        } catch (_) {}
        try {
          await _nativeWindowChannel.invokeMethod('bringToFront');
        } catch (_) {}
      } catch (_) {
        SystemSound.play(SystemSoundType.alert);
      }
      _urgentFired = true;
      // do not auto-restart; wait for user activity to reset
    });
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(DateTime.now());

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        return Scaffold(
          body: Listener(
            onPointerSignal: (ps) {
              if (ps is PointerScrollEvent) {
                final ctrl = RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                    RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.controlRight);
                if (!ctrl) return;
                final delta = ps.scrollDelta.dy;
                final step = delta.abs() * 0.08;
                if (delta > 0) {
                  // zoom out
                  final candidate = (_tileHeight - step).clamp(_minTileHeight, _defaultTileHeight);
                  setState(() {
                    _tileHeight = candidate;
                    _fontScale = _fontScaleForTileHeight(_tileHeight);
                  });
                } else {
                  // zoom in
                  final candidate = (_tileHeight + step).clamp(_minTileHeight, _defaultTileHeight);
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
                final newHeight = (_tileHeightStart * d.scale).clamp(_minTileHeight, double.infinity);
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Left arrow moved to the far left of the header row
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios),
                              tooltip: 'Previous',
                              onPressed: () async {
                                await _cycleView(false);
                              },
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: _showingBacklog ? 'Backlog' : (_showingDone ? 'Done' : 'Today'),
                                        style: const TextStyle(
                                            fontSize: 24, fontWeight: FontWeight.w700),
                                      ),
                                      TextSpan(
                                        text: ', $dateLabel',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _alwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                                size: 20,
                              ),
                              tooltip: _alwaysOnTop ? 'Unpin window' : 'Pin window on top',
                              onPressed: () async {
                                final newVal = !_alwaysOnTop;
                                try {
                                  await _nativeWindowChannel.invokeMethod('setWindowGeometry', <String, dynamic>{'always_on_top': newVal});
                                  setState(() => _alwaysOnTop = newVal);
                                  await _saveSettings();
                                  _showTopToast(newVal ? 'Window pinned' : 'Window unpinned');
                                } catch (_) {}
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_forward_ios),
                              tooltip: 'Next',
                              onPressed: () async {
                                await _cycleView(true);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _today.isEmpty
                              ? Center(child: Text(_showingBacklog ? 'No backlog tasks' : (_showingDone ? 'No archived tasks' : 'No tasks for today')))
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
                                  final entries = _today.asMap().entries;
                                  for (final e in entries) {
                                    final t = e.value;
                                    if (t.done) {
                                      bucketDone.add(e);
                                      continue;
                                    }
                                    final hasSchedule = t.scheduledAt != null;
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
                                      if (newIndex > oldIndex) newIndex -= 1;
                                      final srcEntry = sorted[oldIndex];
                                      final dstEntry = sorted[newIndex];
                                      // Determine bucket membership for src and dst
                                      int bucketOf(MapEntry<int, TaskItem> e) {
                                        if (bucketOverdue.contains(e)) return 0;
                                        if (bucketImportantInProgress
                                            .contains(e)) return 1;
                                        if (bucketInProgress.contains(e))
                                          return 2;
                                        if (bucketImportant.contains(e))
                                          return 3;
                                        if (bucketDueIn1h.contains(e)) return 4;
                                        if (bucketRest.contains(e)) return 5;
                                        return 6; // done
                                      }

                                      final srcBucket = bucketOf(srcEntry);
                                      final dstBucket = bucketOf(dstEntry);
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

                                      final srcPos = targetBucket.indexWhere(
                                          (e) =>
                                              e.key == srcEntry.key &&
                                              e.value.text ==
                                                  srcEntry.value.text);
                                      if (srcPos == -1) return;

                                      // Compute destination position within the bucket by counting how many entries from start of sorted up to newIndex belong to this bucket
                                      int dstPos = 0;
                                      for (int i = 0; i < newIndex; i++) {
                                        if (bucketOf(sorted[i]) == srcBucket)
                                          dstPos++;
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
                                                List<MapEntry<int, TaskItem>>
                                                    b) =>
                                            newOrder
                                                .addAll(b.map((e) => e.value));
                                        appendBucket(bucketOverdue);
                                        appendBucket(bucketImportantInProgress);
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
                                    children:
                                        List.generate(sorted.length, (vi) {
                                      final originalIndex = sorted[vi].key;
                                      final task = sorted[vi].value;
                                      final i = originalIndex;
                                      return Dismissible(
                                          key: ValueKey(
                                              'today_${i}_${task.text}_${task.done}'),
                                          background: Container(
                                            color: Colors.green,
                                            alignment: Alignment.centerLeft,
                                            padding:
                                                const EdgeInsets.only(left: 20),
                                            child: (_showingBacklog || _currentFile == 'simplepresent_backlog.json')
                                                ? Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.arrow_forward, color: Colors.white),
                                                      const SizedBox(width: 8),
                                                      const Text('Moved to Today', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                                    ],
                                                  )
                                                : (_today[i].inProgress
                                                    ? Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.check_circle, color: Colors.white),
                                                          const SizedBox(width: 8),
                                                          const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                                        ],
                                                      )
                                                    : Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(Icons.construction, color: Colors.white, size: 18),
                                                          const SizedBox(width: 8),
                                                          const Text('In Progress', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                                        ],
                                                      )),
                                          ),
                                          secondaryBackground: Container(
                                            color: (_today[i].inProgress &&
                                                    !_today[i].done)
                                                ? Colors.transparent
                                                : Colors.red,
                                            alignment: Alignment.centerRight,
                                            // align delete icon where the star sits (far right)
                                            padding: const EdgeInsets.only(
                                                right: 12),
                                            child: (_today[i].inProgress &&
                                                    !_today[i].done)
                                                ? Text(
                                                    'open',
                                                    style: TextStyle(
                                                      decoration: TextDecoration
                                                          .lineThrough,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  )
                                                : const Icon(Icons.delete,
                                                    color: Colors.white),
                                          ),
                                          confirmDismiss: (direction) async {
                                            final t = _today[i];
                                            if (direction == DismissDirection.startToEnd) {
                                              // In Backlog view: Right swipe -> move to Today
                                              if (_currentFile == 'simplepresent_backlog.json' || _showingBacklog) {
                                                await _moveFromBacklog(i);
                                                return false;
                                              }
                                              // Right swipe (Today view): 1st -> set inProgress, 2nd -> set done
                                              if (!t.inProgress && !t.done) {
                                                setState(() => _today[i] = t.copyWith(inProgress: true, inProgressAt: DateTime.now()));
                                                _saveToday();
                                                _showTopToast('Task marked In Progress');
                                              } else if (t.inProgress && !t.done) {
                                                _setDone(i, true);
                                                _showTopToast('Task marked done');
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
                                                  'Task marked not In Progress');
                                              return false;
                                            }
                                            // Otherwise ask for delete confirmation
                                            final shouldDelete =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (dialogContext) =>
                                                  AlertDialog(
                                                title:
                                                    const Text('Delete task?'),
                                                content: Text(
                                                    'Delete "${_today[i].text}"?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                                dialogContext)
                                                            .pop(false),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                                dialogContext)
                                                            .pop(true),
                                                    child: const Text('Delete'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            return shouldDelete == true;
                                          },
                                          direction: !task.done
                                              ? DismissDirection.horizontal
                                              : DismissDirection.endToStart,
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
                                                    contentPadding: EdgeInsets.symmetric(
                                                        vertical: ((_tileHeight - _baseFontSize) / 2).clamp(0.0, 40.0),
                                                        horizontal: 12),
                                                    onTap: () =>
                                                        _toggleExpanded(i),
                                                    leading: IconButton(
                                                      tooltip: 'Done',
                                                      icon: Icon(task.done
                                                          ? Icons
                                                              .radio_button_checked
                                                          : Icons
                                                              .radio_button_unchecked),
                                                      onPressed: () => _setDone(
                                                          i, !task.done),
                                                    ),
                                                    title: Row(
                                                      children: [
                                                        Expanded(
                                                          child: _expanded.contains(i)
                                                                    ? const SizedBox.shrink()
                                                                    : Column(
                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                      children: [
                                                                        Text(
                                                                          task.text,
                                                                          style: TextStyle(
                                                                            fontSize: _fontScale < 1.0 ? _baseFontSize * _fontScale : null,
                                                                            decoration: task.done ? TextDecoration.lineThrough : TextDecoration.none,
                                                                            color: task.done
                                                                                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
                                                                                : Theme.of(context).colorScheme.onSurface,
                                                                          ),
                                                                        ),
                                                                        if (_showingDone && task.completedAt != null)
                                                                          Padding(
                                                                            padding: const EdgeInsets.only(top: 4.0),
                                                                            child: Text(
                                                                              'Completed: ${DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!)}',
                                                                              style: TextStyle(
                                                                                fontSize: 12,
                                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                      ],
                                                                    ),
                                                        ),
                                                        const SizedBox(
                                                          width: 4),
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
                                                                      .format(task
                                                                          .scheduledAt!),
                                                                  child:
                                                                      InkWell(
                                                                    onTap: () =>
                                                                        _pickSchedule(
                                                                            i),
                                                                    child: Row(
                                                                      mainAxisSize:
                                                                          MainAxisSize
                                                                              .min,
                                                                      children: [
                                                                        Icon(
                                                                            Icons
                                                                                .event,
                                                                            color:
                                                                                _scheduleIconColor(task.scheduledAt!),
                                                                            size: 16),
                                                                        const SizedBox(
                                                                            width:
                                                                                4),
                                                                        Text(
                                                                          DateFormat('HH:mm')
                                                                              .format(task.scheduledAt!),
                                                                          style: TextStyle(
                                                                              fontSize: 11,
                                                                              color: _scheduleIconColor(task.scheduledAt!)),
                                                                        ),
                                                                    ],
                                                                  ),
                                                                  ),
                                                                ),
                                                                Padding(
                                                                padding: const EdgeInsets
                                                                  .only(
                                                                    left:
                                                                      8.0,
                                                                    right:
                                                                      6.0),
                                                                child: IconButton(
                                                                  tooltip: task.inProgress && !task.done
                                                                    ? 'Remove In Progress'
                                                                    : 'Mark In Progress',
                                                                  icon: Icon(
                                                                    Icons
                                                                      .construction,
                                                                    color: (task.inProgress && !task.done)
                                                                      ? Colors.greenAccent.shade200
                                                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                                                    size: 18),
                                                                  onPressed: task.done
                                                                    ? null
                                                                    : () {
                                                                      final now = !_today[i].inProgress ? DateTime.now() : null;
                                                                      setState(() => _today[i] = _today[i].copyWith(inProgress: !_today[i].inProgress, inProgressAt: now));
                                                                      _saveToday();
                                                                      _registerActivity();
                                                                    },
                                                                ),
                                                                ),
                                                              if (_expanded
                                                                  .contains(i))
                                                                Builder(builder:
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
                                                                    onPressed: () =>
                                                                        _saveEditedTitle(
                                                                            i),
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
                                                                  color: task
                                                                      .important
                                                                    ? Colors
                                                                      .amber
                                                                    : Theme.of(context)
                                                                      .colorScheme
                                                                      .onSurfaceVariant),
                                                                onPressed: () {
                                                                  final now = !_today[
                                                                        i]
                                                                      .important
                                                                    ? DateTime
                                                                      .now()
                                                                    : _today[
                                                                        i]
                                                                      .importantAt;
                                                                  setState(() => _today[
                                                                    i] = _today[
                                                                      i]
                                                                    .copyWith(
                                                                      important: !_today[i]
                                                                        .important,
                                                                      importantAt:
                                                                        now));
                                                                  _saveToday();
                                                                },
                                                                ),
                                                                // Custom D&D handle (5px shifted to the right)
                                                                Padding(
                                                                padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                    left:
                                                                      5.0),
                                                                child: Opacity(
                                                                  opacity: _swiping
                                                                      .contains(
                                                                        i)
                                                                    ? 0.0
                                                                    : 1.0,
                                                                  child:
                                                                    ReorderableDragStartListener(
                                                                  index: vi,
                                                                  child: const Icon(
                                                                    Icons
                                                                      .drag_handle,
                                                                    size:
                                                                      18),
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
                                                                setState(() {});
                                                            });
                                                            return c;
                                                          }),
                                                          autofocus: true,
                                                          decoration:
                                                              const InputDecoration(
                                                            border: InputBorder
                                                                .none,
                                                            hintText: 'Titel',
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
                                                                    text:
                                                                        task.notes ??
                                                                            '');
                                                            n.addListener(() {
                                                              if (mounted)
                                                                setState(() {});
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
                                                            hintText: 'Notes',
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
                                                                controller: _subtaskInputControllers
                                                                    .putIfAbsent(
                                                                  task.id,
                                                                  () =>
                                                                      TextEditingController(),
                                                                ),
                                                                decoration:
                                                                    const InputDecoration(
                                                                  border:
                                                                      OutlineInputBorder(),
                                                                  hintText:
                                                                      'Unteraufgabe hinzufügen',
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
                                                              child: const Text(
                                                                  'Add'),
                                                            ),
                                                          ],
                                                        ),
                                                        if (task.subtasks.isNotEmpty)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                                      top: 12),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                for (final step in task.subtasks)
                                                                  Padding(
                                                                    padding: const EdgeInsets
                                                                        .only(
                                                                          bottom:
                                                                              6),
                                                                    child: Row(
                                                                      children: [
                                                                        Checkbox(
                                                                          value:
                                                                              step.done,
                                                                          onChanged: (value) => _updateSubtask(
                                                                              i,
                                                                              step.id,
                                                                              done: value ?? false),
                                                                        ),
                                                                        Expanded(
                                                                          child:
                                                                              TextFormField(
                                                                            key:
                                                                                ValueKey('subtask_${task.id}_${step.id}'),
                                                                            initialValue:
                                                                                step.text,
                                                                            decoration:
                                                                                const InputDecoration(
                                                                              border:
                                                                                  InputBorder.none,
                                                                              isDense:
                                                                                  true,
                                                                            ),
                                                                            onChanged:
                                                                                (value) => _updateSubtask(i, step.id, text: value),
                                                                          ),
                                                                        ),
                                                                        IconButton(
                                                                          tooltip:
                                                                              'Delete step',
                                                                          icon:
                                                                              const Icon(Icons.close),
                                                                          onPressed: () =>
                                                                              _removeSubtask(i, step.id),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                          ),
                                                        const SizedBox(
                                                            height: 10),
                                                        Text(
                                                            'Created: ${task.createdAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.createdAt!) : '-'}'),
                                                        const SizedBox(
                                                            height: 6),
                                                        Text(
                                                            'In Progress: ${task.inProgressAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.inProgressAt!) : '-'}'),
                                                        const SizedBox(
                                                            height: 6),
                                                        Text(
                                                            'Completed: ${task.completedAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.completedAt!) : '-'}'),
                                                        const SizedBox(
                                                            height: 6),
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                  'Scheduled: ${task.scheduledAt != null ? DateFormat('yyyy-MM-dd HH:mm').format(task.scheduledAt!) : '-'}'),
                                                            ),
                                                            IconButton(
                                                              tooltip:
                                                                  'Set schedule',
                                                              icon: const Icon(Icons
                                                                  .calendar_today),
                                                              onPressed: () =>
                                                                  _pickSchedule(
                                                                      i),
                                                            ),
                                                            if (task.scheduledAt !=
                                                                null)
                                                              IconButton(
                                                                tooltip:
                                                                    'Clear schedule',
                                                                icon: const Icon(
                                                                    Icons
                                                                        .clear),
                                                                onPressed: () =>
                                                                    _clearSchedule(
                                                                        i),
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
                SafeArea(
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
                              hintText: _showingDone ? 'Cannot add tasks in Done view' : 'New task for today',
                              border: const OutlineInputBorder(),
                            ),
                            onSubmitted: _showingDone ? null : _addToToday,
                            onTapOutside: (_) => _inputFocus.requestFocus(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _showingDone ? null : () => _addToToday(_controller.text),
                          child: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }
}
