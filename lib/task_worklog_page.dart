import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _fieldLabels = <String, String>{
  'text': 'Title',
  'notes': 'Notes',
  'done': 'Done',
  'inProgress': 'In progress',
  'important': 'Important',
  'work_minutes': 'Manual time (minutes)',
  'booked_work_minutes': 'Booked manual time (minutes)',
  'booked_stopwatch_seconds': 'Booked tracked time (seconds)',
  'stopwatch_seconds': 'Tracked time (seconds)',
  'stopwatch_running': 'Stopwatch running',
  'stopwatch_started_at': 'Stopwatch started',
  'in_progress_at': 'In progress since',
  'important_at': 'Important since',
  'completed_at': 'Completed',
  'scheduled_at': 'Scheduled',
  'created_at': 'Created',
  'recurrence': 'Repeat',
  'ask_repeat_date_on_recreation': 'Confirm repeat date',
  'subtasks': 'Subtasks',
};

String worklogListName(dynamic value) {
  return (value ?? '')
      .toString()
      .replaceFirst('simplepresent_', '')
      .replaceFirst('.json', '');
}

String taskWorklogSummary(Map<String, dynamic> entry) {
  final list = worklogListName(entry['list']);
  switch (entry['action']) {
    case 'created':
      return 'Created in $list';
    case 'moved':
      return 'Moved: ${worklogListName(entry['from_list'])} -> $list';
    case 'time_booked':
      return 'Time booked for ${entry['date']}';
    case 'removed':
      return 'Removed from $list';
    case 'restored':
      return 'Restored to $list';
    case 'reordered':
      return 'Reordered in $list';
    default:
      final changes = entry['changes'];
      if (changes is! Map || changes.isEmpty) return 'Changed';
      final labels = <String>[];
      for (final field in changes.keys) {
        final change = changes[field];
        final after = change is Map ? change['after'] : null;
        switch (field) {
          case 'inProgress':
            labels.add(after == true ? 'Started work' : 'Stopped work');
            break;
          case 'done':
            labels.add(after == true ? 'Completed' : 'Reopened');
            break;
          case 'stopwatch_running':
            labels
                .add(after == true ? 'Stopwatch started' : 'Stopwatch stopped');
            break;
          case 'work_minutes':
          case 'stopwatch_seconds':
            labels.add('Time updated');
            break;
          case 'in_progress_at':
          case 'completed_at':
          case 'important_at':
          case 'stopwatch_started_at':
            break;
          default:
            labels.add('${_fieldLabels[field] ?? field} changed');
        }
      }
      return labels.isEmpty ? 'Changed' : labels.toSet().join('; ');
  }
}

String _valueText(dynamic value) {
  if (value == null || value == '') return '(empty)';
  if (value is bool) return value ? 'yes' : 'no';
  if (value is List) {
    return value.map((item) {
      if (item is! Map || !item.containsKey('text')) return jsonEncode(item);
      final status = item['done'] == true
          ? 'done'
          : item['inProgress'] == true
              ? 'in progress'
              : 'open';
      return '${item['text']} [$status]';
    }).join('\n');
  }
  if (value is Map) return const JsonEncoder.withIndent('  ').convert(value);
  return value.toString();
}

class TaskWorklogPage extends StatefulWidget {
  const TaskWorklogPage({
    super.key,
    required this.taskTitle,
    required this.loadEntries,
  });

  final String taskTitle;
  final Future<List<Map<String, dynamic>>> Function() loadEntries;

  @override
  State<TaskWorklogPage> createState() => _TaskWorklogPageState();
}

class _TaskWorklogPageState extends State<TaskWorklogPage> {
  late Future<List<Map<String, dynamic>>> _entries = widget.loadEntries();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('worklog'),
        actions: [
          IconButton(
            tooltip: 'refresh worklog',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _entries = widget.loadEntries()),
          ),
        ],
      ),
      body: SelectionArea(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(widget.taskTitle,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _entries,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('could not load worklog'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = List<Map<String, dynamic>>.from(snapshot.data!)
                  ..sort((first, second) {
                    final firstTime = DateTime.tryParse(
                        (first['timestamp'] ?? '').toString());
                    final secondTime = DateTime.tryParse(
                        (second['timestamp'] ?? '').toString());
                    return (secondTime ??
                            DateTime.fromMillisecondsSinceEpoch(0))
                        .compareTo(firstTime ??
                            DateTime.fromMillisecondsSinceEpoch(0));
                  });
                if (entries.isEmpty) {
                  return const Center(child: Text('no worklog entries yet'));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final timestamp = DateTime.tryParse(
                        (entry['timestamp'] ?? '').toString());
                    final changes = entry['changes'] is Map
                        ? Map<String, dynamic>.from(entry['changes'])
                        : <String, dynamic>{};
                    return ExpansionTile(
                      key: PageStorageKey(entry['id'] ?? '$index'),
                      leading: const Icon(Icons.history),
                      title: Text(taskWorklogSummary(entry)),
                      subtitle: Text([
                        if (timestamp != null)
                          DateFormat('yyyy-MM-dd HH:mm:ss')
                              .format(timestamp.toLocal()),
                        worklogListName(entry['list']),
                      ].where((value) => value.isNotEmpty).join(' / ')),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (entry['task_text'] != null)
                          Text(entry['task_text'].toString()),
                        if (entry['position'] is Map)
                          Text('Position: ${entry['position']['before'] + 1}'
                              ' -> ${entry['position']['after'] + 1}'),
                        for (final change in changes.entries)
                          if (change.value is Map)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_fieldLabels[change.key] ?? change.key,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      'Before: ${_valueText(change.value['before'])}'),
                                  Text(
                                      'After: ${_valueText(change.value['after'])}'),
                                ],
                              ),
                            ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }
}
