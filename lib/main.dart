import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
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

class TaskItem {
  TaskItem({
    required this.text,
    this.done = false,
    this.important = false,
    this.inProgress = false,
    this.completedAt,
    this.inProgressAt,
    this.importantAt,
    this.createdAt,
  });

  final String text;
  final bool done;
  final bool important;
  final bool inProgress;
  final DateTime? completedAt; // timestamp when marked done
  final DateTime? inProgressAt; // timestamp when marked in progress
  final DateTime? importantAt; // timestamp when marked important
  final DateTime? createdAt; // timestamp when created

  TaskItem copyWith({
    String? text,
    bool? done,
    bool? important,
    bool? inProgress,
    DateTime? completedAt,
    DateTime? inProgressAt,
    DateTime? importantAt,
    DateTime? createdAt,
  }) {
    return TaskItem(
      text: text ?? this.text,
      done: done ?? this.done,
      important: important ?? this.important,
      inProgress: inProgress ?? this.inProgress,
      completedAt: completedAt ?? this.completedAt,
      inProgressAt: inProgressAt ?? this.inProgressAt,
      importantAt: importantAt ?? this.importantAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'done': done,
        'important': important,
        'inProgress': inProgress,
        // English field names
        'created_at': createdAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'in_progress_at': inProgressAt?.toIso8601String(),
        'important_at': importantAt?.toIso8601String(),
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
      return TaskItem(text: json, done: false);
    }
    final map = json as Map<String, dynamic>;
    return TaskItem(
      text: (map['text'] ?? '').toString(),
      done: map['done'] == true,
      important: map['important'] == true,
      inProgress: map['inProgress'] == true || map['in_arbeit'] == true,
      // support both new english keys and older german/variant keys
      createdAt: _parseDate(map['created_at'] ?? map['createdAt']),
      completedAt: _parseDate(map['completed_at'] ?? map['erledigt_am'] ?? map['done_at'] ?? map['doneAt']),
      inProgressAt: _parseDate(map['in_progress_at'] ?? map['in_arbeit_am'] ?? map['inArbeitAt'] ?? map['in_progress_at']),
      importantAt: _parseDate(map['important_at'] ?? map['wichtig_am'] ?? map['important_at']),
    );
  }
}

class _HomePageState extends State<HomePage> {
  final List<TaskItem> _today = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  late final Future<void> _initFuture = _loadToday();

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadList(String filename, List<TaskItem> target) async {
    try {
      final f = await _fileFor(filename);
      if (await f.exists()) {
        final text = await f.readAsString();
        final data = jsonDecode(text) as List<dynamic>;
        target.clear();
        target.addAll(data.map(TaskItem.fromJson));
      }
    } catch (_) {}
  }

  Future<void> _saveList(String filename, List<TaskItem> source) async {
    try {
      final f = await _fileFor(filename);
      final encoder = const JsonEncoder.withIndent('  ');
      await f.writeAsString(encoder.convert(source.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadToday() async {
    await _loadList('simplepresent_today.json', _today);
    setState(() {});
  }

  Future<void> _saveToday() async {
    await _saveList('simplepresent_today.json', _today);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _toastTimer?.cancel();
    _toastEntry?.remove();
    super.dispose();
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
      _today.insert(0, TaskItem(text: text.trim(), done: false, createdAt: DateTime.now()));
      _controller.clear();
    });
    _saveToday();
    _inputFocus.requestFocus();
  }

  void _setDone(int index, bool value) {
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
  }

  void _removeFromToday(int index) {
    setState(() {
      _today.removeAt(index);
    });
    _saveToday();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(DateTime.now());

    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        return Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _inputFocus.requestFocus(),
            child: Column(
              children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 22, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Today',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text: ', $dateLabel',
                              style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _today.isEmpty
                          ? const Center(child: Text('No tasks for today'))
                            : Builder(builder: (ctx) {
                                // Build grouped list preserving insertion order within groups
                                final bucketA = <MapEntry<int, TaskItem>>[]; // inProgress & important
                                final bucketB = <MapEntry<int, TaskItem>>[]; // inProgress
                                final bucketC = <MapEntry<int, TaskItem>>[]; // important
                                final bucketD = <MapEntry<int, TaskItem>>[]; // rest (insertion order)
                                final bucketDone = <MapEntry<int, TaskItem>>[]; // done tasks (always bottom)

                                final entries = _today.asMap().entries;
                                for (final e in entries) {
                                  final idx = e.key;
                                  final t = e.value;
                                  if (t.done) {
                                    bucketDone.add(e);
                                  } else if (t.inProgress && t.important) {
                                    bucketA.add(e);
                                  } else if (t.inProgress) {
                                    bucketB.add(e);
                                  } else if (t.important) {
                                    bucketC.add(e);
                                  } else {
                                    bucketD.add(e);
                                  }
                                }

                                final sorted = [...bucketA, ...bucketB, ...bucketC, ...bucketD, ...bucketDone];

                                return ListView.builder(
                                  itemCount: sorted.length,
                                  itemBuilder: (ctx, vi) {
                                    final originalIndex = sorted[vi].key;
                                    final task = sorted[vi].value;
                                    final i = originalIndex;
                                    return Dismissible(
                                      key: ValueKey('today_${i}_${task.text}_${task.done}'),
                                  background: Container(
                                    color: _today[i].inProgress ? Colors.green : Colors.green,
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    child: _today[i].inProgress
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
                                          ),
                                  ),
                                      secondaryBackground: Container(
                                        color: Colors.red,
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(right: 20),
                                        child: const Icon(Icons.delete, color: Colors.white),
                                      ),
                                      confirmDismiss: (direction) async {
                                        if (direction == DismissDirection.startToEnd) {
                                          final t = _today[i];
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
                                        final shouldDelete = await showDialog<bool>(
                                          context: context,
                                          builder: (dialogContext) => AlertDialog(
                                            title: const Text('Delete task?'),
                                            content: Text('Delete "${_today[i].text}"?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(dialogContext).pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.of(dialogContext).pop(true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        return shouldDelete == true;
                                      },
                                      direction: !task.done ? DismissDirection.horizontal : DismissDirection.endToStart,
                                      onDismissed: (_) => _removeFromToday(i),
                                      child: Card(
                                        color: task.inProgress ? Colors.green.withOpacity(0.10) : null,
                                        child: ListTile(
                                          leading: IconButton(
                                            tooltip: 'Done',
                                            icon: Icon(task.done ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                                            onPressed: () => _setDone(i, !task.done),
                                          ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  task.text,
                                                  style: TextStyle(
                                                    decoration: task.done ? TextDecoration.lineThrough : TextDecoration.none,
                                                    color: task.done
                                                        ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
                                                        : Theme.of(context).colorScheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // In-progress shovel icon
                                              if (task.inProgress && !task.done)
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6.0),
                                                  child: Icon(Icons.construction, color: Colors.greenAccent.shade200, size: 18),
                                                ),
                                              // Important star toggle
                                              IconButton(
                                                tooltip: 'Important',
                                                icon: Icon(
                                                    task.important ? Icons.star : Icons.star_border,
                                                    color: task.important ? Colors.amber : Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                onPressed: () {
                                                  final now = !_today[i].important ? DateTime.now() : _today[i].importantAt;
                                                  setState(() => _today[i] = _today[i].copyWith(important: !_today[i].important, importantAt: now));
                                                  _saveToday();
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
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
                            autofocus: true,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              hintText: 'New task for today',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: _addToToday,
                            onTapOutside: (_) => _inputFocus.requestFocus(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _addToToday(_controller.text),
                          child: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
