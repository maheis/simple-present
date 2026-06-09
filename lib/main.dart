import 'package:flutter/material.dart';

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
  final List<String> _tasks = ['Erste Aufgabe', 'Zweite Aufgabe'];
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTask() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _tasks.add(text);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('SimplePresent — Demo')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'Neue Aufgabe'),
                  ),
                ),
                IconButton(icon: const Icon(Icons.add), onPressed: _addTask),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _tasks.length,
                itemBuilder: (ctx, i) => ListTile(title: Text(_tasks[i])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
