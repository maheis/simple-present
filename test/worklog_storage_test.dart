import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:simple_present/storage/sembast_storage.dart';
import 'package:simple_present/task_worklog_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('worklog captures status, time, content, moves and removals', () async {
    final directory = await Directory.systemTemp.createTemp('worklog-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    final storage = SembastStorage();
    await storage.init(debugMode: true);
    const today = 'simplepresent_today.json';
    const backlog = 'simplepresent_backlog.json';
    var task = <String, dynamic>{
      'id': 'task-1',
      'text': 'Initial title',
      'inProgress': false,
      'work_minutes': 0,
    };
    try {
      await storage.writeTaskList(today, [task]);
      await storage.writeTaskList(today, [task]);
      expect(await storage.readTaskWorklog('task-1'), hasLength(1));
      task = {...task, 'inProgress': true};
      await storage.writeTaskList(today, [task]);
      task = {...task, 'work_minutes': 60};
      await storage.writeTaskList(today, [task]);
      task = {...task, 'text': 'New title'};
      await storage.writeTaskList(today, [task]);
      await storage.writeTaskList(today, []);
      await storage.writeTaskList(backlog, [task]);
      final log = await storage.readTaskWorklog('task-1');
      expect(log.map((entry) => entry['action']),
          ['created', 'changed', 'changed', 'changed', 'removed', 'moved']);
      expect(log[1]['changes'], {
        'inProgress': {'before': false, 'after': true},
      });
      expect(log[2]['changes'], {
        'work_minutes': {'before': 0, 'after': 60},
      });
      expect(log[3]['changes'], {
        'text': {'before': 'Initial title', 'after': 'New title'},
      });
      expect(log.last['from_list'], today);
      expect(log.last['list'], backlog);
      expect(
          log.every((entry) => DateTime.tryParse(entry['timestamp']) != null),
          isTrue);
      await storage.writeTaskList(backlog, []);
      expect(
          (await storage.readTaskWorklog('task-1')).last['action'], 'removed');
      await storage.upsertTimeEntry(
        taskId: 'task-1',
        taskText: 'New title',
        date: '2026-10-20',
        taskDone: false,
        taskInProgress: true,
        stopwatchSeconds: 3600,
        workMinutes: 60,
      );
      final booked = (await storage.readTaskWorklog('task-1')).last;
      expect(booked['action'], 'time_booked');
      expect(booked['date'], '2026-10-20');
      final exported = await storage.exportWorklogs();
      final destinationDirectory =
          await Directory.systemTemp.createTemp('worklog-import-');
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => destinationDirectory.path,
      );
      final destination = SembastStorage();
      try {
        await destination.init(debugMode: true);
        await destination.importWorklogs(exported);
        expect(await destination.exportWorklogs(), exported);
      } finally {
        destination.dispose();
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
      }
      await storage.importWorklogs(exported);
      await storage.importWorklogs(exported);
      expect((await storage.readTaskWorklog('task-1')).length,
          (exported['task-1'] as List).length);
      await storage.refresh();
      expect((await storage.readTaskWorklog('task-1')).last['action'],
          'time_booked');

      task = {
        ...task,
        'done': true,
        'important': true,
        'subtasks': [
          {'id': 'step-1', 'text': 'Step', 'inProgress': true, 'done': false},
        ],
      };
      await storage.writeTaskList(backlog, [task]);
      final changed = (await storage.readTaskWorklog('task-1')).last;
      expect((changed['changes'] as Map).keys,
          containsAll(['done', 'important', 'subtasks']));
      final other = <String, dynamic>{'id': 'task-2', 'text': 'Other'};
      await storage.writeTaskList(backlog, [task, other]);
      await storage.writeTaskList(backlog, [other, task]);
      expect((await storage.readTaskWorklog('task-1')).last['action'],
          'reordered');
      await storage.writeTaskList(today, [task]);
      await storage.writeTaskList(backlog, [other]);
      final movedLog = await storage.readTaskWorklog('task-1');
      expect(movedLog.last['action'], 'moved');
      expect(movedLog.last['from_list'], backlog);
    } finally {
      storage.dispose();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
    }
  });

  test('existing task snapshots do not invent past creation events', () async {
    final directory = await Directory.systemTemp.createTemp('worklog-legacy-');
    final appDirectory = Directory('${directory.path}/simplepresent-debug');
    await appDirectory.create();
    final database = await databaseFactoryIo
        .openDatabase('${appDirectory.path}/simplepresent.db');
    final listStore = StoreRef<String, Object?>('lists');
    const task = {'id': 'old', 'text': 'Existing task', 'inProgress': false};
    await listStore.record('simplepresent_today.json').put(database, [task]);
    await database.close();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      await storage.writeTaskList('simplepresent_today.json', [task]);
      expect(await storage.readTaskWorklog('old'), isEmpty);
      await storage.writeTaskList('simplepresent_today.json', [
        {...task, 'inProgress': true},
      ]);
      expect(
          (await storage.readTaskWorklog('old')).single['action'], 'changed');
    } finally {
      storage.dispose();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
    }
  });

  testWidgets('worklog shows actions and expandable before/after values',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TaskWorklogPage(
        taskTitle: 'Example task',
        loadEntries: () async => [
          {
            'id': 'event-1',
            'timestamp': '2026-10-20T10:00:00',
            'action': 'changed',
            'task_text': 'Example task',
            'list': 'simplepresent_today.json',
            'changes': {
              'text': {'before': 'Original title', 'after': 'Example task'},
              'inProgress': {'before': false, 'after': true},
            },
          },
        ],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Title changed; Started work'), findsOneWidget);
    expect(find.textContaining('2026-10-20'), findsOneWidget);
    await tester.tap(find.text('Title changed; Started work'));
    await tester.pumpAndSettle();
    expect(find.text('Before: Original title'), findsOneWidget);
    expect(find.text('After: Example task'), findsOneWidget);
    expect(find.text('After: yes'), findsOneWidget);
  });
}
