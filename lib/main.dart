import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const SimplePresentApp());

class SimplePresentApp extends StatelessWidget {
  const SimplePresentApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SimplePresent',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _today = [];
  final List<String> _backlog = [];
  final TextEditingController _controller = TextEditingController();

  late final Future<void> _initFuture = _loadAll();

  Future<Directory> get _appDir async {
    final dir = await getApplicationDocumentsDirectory();
    return dir;
  }

  Future<File> _fileFor(String name) async {
    final dir = await _appDir;
    return File('${dir.path}/$name');
  }

  Future<void> _loadList(String filename, List<String> target) async {
    try {
      final f = await _fileFor(filename);
      if (await f.exists()) {
        final text = await f.readAsString();
        final data = jsonDecode(text) as List<dynamic>;
        target.clear();
        target.addAll(data.cast<String>());
      }
    } catch (_) {}
  }

  Future<void> _saveList(String filename, List<String> source) async {
    try {
      final f = await _fileFor(filename);
      await f.writeAsString(jsonEncode(source));
    } catch (_) {}
  }

  Future<void> _loadAll() async {
    await _loadList('tasks_today.json', _today);
    await _loadList('tasks_backlog.json', _backlog);
    setState(() {});
  }

  Future<void> _saveAll() async {
    await _saveList('tasks_today.json', _today);
    await _saveList('tasks_backlog.json', _backlog);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addToToday(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _today.insert(0, text.trim());
      _controller.clear();
    });
    _saveAll();
  }

  void _moveBacklogToToday(int index) {
    setState(() {
      final item = _backlog.removeAt(index);
      _today.insert(0, item);
    });
    _saveAll();
  }

  void _removeFromBacklog(int index) {
    setState(() {
      _backlog.removeAt(index);
    });
    _saveAll();
  }

  void _addToBacklog(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _backlog.insert(0, text.trim());
    });
    _saveAll();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snap) {
        return Scaffold(
          appBar: AppBar(title: const Text('SimplePresent')),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Heute', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: _today.isEmpty
                                ? const Center(child: Text('Keine Aufgaben für heute'))
                                : ListView.builder(
                                    itemCount: _today.length,
                                    itemBuilder: (ctx, i) => Card(
                                          child: ListTile(title: Text(_today[i])),
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
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'Neue Aufgabe (Enter: heute, + Backlog mit ⤴ long-press)',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: _addToToday,
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

              // Backlog sheet
              DraggableScrollableSheet(
                initialChildSize: 0.06,
                minChildSize: 0.06,
                maxChildSize: 1.0,
                builder: (context, controller) {
                  return LayoutBuilder(builder: (context, constraints) {
                    final isSmall = constraints.maxHeight < 120;
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      child: Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0, bottom: 4),
                            child: SizedBox(
                              width: 40,
                              height: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.all(Radius.circular(4))),
                              ),
                            ),
                          ),
                          if (!isSmall) const Text('Backlog', style: TextStyle(fontWeight: FontWeight.w600)),
                          if (!isSmall)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      onSubmitted: (v) => _addToBacklog(v),
                                      decoration: const InputDecoration(hintText: 'Neue Backlog-Aufgabe (Enter)'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: _backlog.isEmpty
                                ? const Center(child: Text('Backlog leer'))
                                : ListView.builder(
                                    controller: controller,
                                    itemCount: _backlog.length,
                                    itemBuilder: (ctx, i) => Dismissible(
                                          key: ValueKey('backlog_${i}_${_backlog[i]}'),
                                          background: Container(
                                            color: Colors.green,
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.only(left: 20),
                                            child: const Icon(Icons.arrow_upward, color: Colors.white),
                                          ),
                                          secondaryBackground: Container(
                                            color: Colors.red,
                                            alignment: Alignment.centerRight,
                                            padding: const EdgeInsets.only(right: 20),
                                            child: const Icon(Icons.delete, color: Colors.white),
                                          ),
                                          onDismissed: (dir) {
                                            if (dir == DismissDirection.startToEnd) {
                                              _moveBacklogToToday(i);
                                            } else {
                                              _removeFromBacklog(i);
                                            }
                                          },
                                          child: ListTile(
                                            title: Text(_backlog[i]),
                                            onTap: () => _moveBacklogToToday(i),
                                          ),
                                        ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
