import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  TaskItem({required this.text, this.done = false});

  final String text;
  final bool done;

  TaskItem copyWith({String? text, bool? done}) {
    return TaskItem(text: text ?? this.text, done: done ?? this.done);
  }

  Map<String, dynamic> toJson() => {'text': text, 'done': done};

  static TaskItem fromJson(dynamic json) {
    // Backward compatible with old string-only storage.
    if (json is String) {
      return TaskItem(text: json, done: false);
    }
    final map = json as Map<String, dynamic>;
    return TaskItem(text: (map['text'] ?? '').toString(), done: map['done'] == true);
  }
}

class _HomePageState extends State<HomePage> {
  final List<TaskItem> _today = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

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
      await f.writeAsString(jsonEncode(source.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadToday() async {
    await _loadList('tasks_today.json', _today);
    setState(() {});
  }

  Future<void> _saveToday() async {
    await _saveList('tasks_today.json', _today);
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _addToToday(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _today.insert(0, TaskItem(text: text.trim(), done: false));
      _controller.clear();
    });
    _saveToday();
    _inputFocus.requestFocus();
  }

  void _setDone(int index, bool value) {
    setState(() {
      final t = _today[index];
      _today[index] = t.copyWith(done: value);
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
                              text: 'heute',
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
                            ? const Center(child: Text('Keine Aufgaben für heute'))
                            : ListView.builder(
                                itemCount: _today.length,
                                itemBuilder: (ctx, i) => Dismissible(
                                  key: ValueKey('today_${i}_${_today[i].text}_${_today[i].done}'),
                                  background: Container(
                                    color: Colors.green,
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.only(left: 20),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text('Fertig', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
                                      _setDone(i, true);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Aufgabe als fertig markiert')),
                                        );
                                      }
                                      return false;
                                    }
                                    final shouldDelete = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('Aufgabe löschen?'),
                                        content: Text('"${_today[i].text}" wirklich löschen?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(dialogContext).pop(false),
                                            child: const Text('Abbrechen'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.of(dialogContext).pop(true),
                                            child: const Text('Löschen'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return shouldDelete == true;
                                  },
                                  direction: DismissDirection.horizontal,
                                  onDismissed: (_) => _removeFromToday(i),
                                  child: Card(
                                    child: ListTile(
                                      leading: IconButton(
                                        tooltip: 'Fertig',
                                        icon: Icon(_today[i].done ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                                        onPressed: () => _setDone(i, !_today[i].done),
                                      ),
                                      title: Text(
                                        _today[i].text,
                                        style: TextStyle(
                                          decoration: _today[i].done ? TextDecoration.lineThrough : TextDecoration.none,
                                          color: _today[i].done
                                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65)
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                              hintText: 'Neue Aufgabe für heute',
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
