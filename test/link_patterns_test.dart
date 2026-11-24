import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:simple_present/main.dart' as app;
import 'package:simple_present/link_patterns.dart';
import 'package:simple_present/task_links.dart';

void main() {
  test('matches configured ticket pattern and substitutes the actual key', () {
    final matches = findTaskLinks('Fix PLS-1017 and PLS-42', const [
      LinkPattern(
          pattern: r'PLS-\d+', urlTemplate: 'https://work.example/jira/%PID%'),
    ]);
    expect(matches.map((match) => match.text), ['PLS-1017', 'PLS-42']);
    expect(matches.first.uri.toString(), 'https://work.example/jira/PLS-1017');
  });

  test('rejects invalid patterns, templates and non-http links', () {
    expect(
        const LinkPattern(
                pattern: '[', urlTemplate: 'https://example.com/%PID%')
            .validate(),
        isNotNull);
    expect(
        const LinkPattern(pattern: 'ABC', urlTemplate: 'https://example.com/')
            .validate(),
        isNotNull);
    expect(
        const LinkPattern(pattern: 'ABC', urlTemplate: 'file:///tmp/%PID%')
            .validate(),
        isNotNull);
    expect(
        findTaskLinks('ABC', const [
          LinkPattern(pattern: '[', urlTemplate: 'https://example.com/%PID%'),
          LinkPattern(pattern: r'^', urlTemplate: 'https://example.com/%PID%'),
        ]),
        isEmpty);
  });

  test('encodes matches and resolves overlaps without duplicate links', () {
    final matches = findTaskLinks('ID 12/34', const [
      LinkPattern(pattern: r'12/34', urlTemplate: 'https://example.com/%PID%'),
      LinkPattern(pattern: r'12', urlTemplate: 'https://other.example/%PID%'),
    ]);
    expect(matches, hasLength(1));
    expect(matches.single.uri.toString(), 'https://example.com/12%2F34');
    final sameMatch = findTaskLinks('PLS-1', const [
      LinkPattern(
          pattern: r'PLS-\d+', urlTemplate: 'https://first.example/%PID%'),
      LinkPattern(
          pattern: r'PLS-\d+', urlTemplate: 'https://second.example/%PID%'),
    ]);
    expect(sameMatch.single.uri.host, 'first.example');
  });

  testWidgets('ticket links open from task title, notes and subtasks',
      (tester) async {
    final opened = <Uri>[];
    var titleTapped = false;
    Future<bool> open(Uri uri) async {
      opened.add(uri);
      return true;
    }

    const rules = [
      LinkPattern(
          pattern: r'PLS-\d+', urlTemplate: 'https://work.example/jira/%PID%'),
    ];
    final notes = TextEditingController(text: 'Notes PLS-2');
    final subtask = TextEditingController(text: 'Step PLS-3');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          GestureDetector(
            onTap: () => titleTapped = true,
            child:
                TaskLinkText(text: 'Title PLS-1', rules: rules, openLink: open),
          ),
          TaskLinkActions(controller: notes, rules: rules, openLink: open),
          TaskLinkActions(controller: subtask, rules: rules, openLink: open),
        ]),
      ),
    ));
    final title = tester.widget<Text>(find.descendant(
      of: find.byType(TaskLinkText),
      matching: find.byType(Text),
    ));
    final span = title.textSpan as TextSpan;
    final link = span.children!
        .whereType<TextSpan>()
        .firstWhere((child) => child.text == 'PLS-1');
    expect(link.recognizer, isNotNull);
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
      of: find.byType(TaskLinkText),
      matching: find.byType(RichText),
    ));
    final box = paragraph
        .getBoxesForSelection(
          const TextSelection(baseOffset: 6, extentOffset: 11),
        )
        .first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await tester.pump();
    expect(titleTapped, isFalse);
    await tester.tap(find.text('PLS-2'));
    await tester.tap(find.text('PLS-3'));
    await tester.pump();
    expect(opened.map((uri) => uri.toString()), [
      'https://work.example/jira/PLS-1',
      'https://work.example/jira/PLS-2',
      'https://work.example/jira/PLS-3',
    ]);
    notes.text = 'Updated PLS-42';
    await tester.pump();
    expect(find.text('PLS-2'), findsNothing);
    expect(find.text('PLS-42'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    notes.dispose();
    subtask.dispose();
  });

  testWidgets('long task links fit a narrow subtask field', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 110,
          child: TaskLinkActions(
            text: 'PLS-12345678901234567890',
            rules: const [
              LinkPattern(
                  pattern: r'PLS-\d+',
                  urlTemplate: 'https://work.example/%PID%'),
            ],
            openLink: (_) async => true,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('failed browser launch shows feedback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskLinkActions(
          text: 'PLS-1',
          rules: const [
            LinkPattern(
                pattern: r'PLS-\d+', urlTemplate: 'https://work.example/%PID%'),
          ],
          openLink: (_) async => false,
        ),
      ),
    ));
    await tester.tap(find.text('PLS-1'));
    await tester.pump();
    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('settings validate, save and reload link rules', (tester) async {
    var settings = <String, dynamic>{};
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final result =
                        await Navigator.of(context).push<Map<String, dynamic>>(
                      MaterialPageRoute(
                          builder: (_) => app.SettingsPage(initial: settings)),
                    );
                    if (result != null) settings = result;
                  },
                  child: const Text('open settings'),
                ),
              )),
    ));
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('new link rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '[');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'https://work.example/jira/%PID%');
    await tester.tap(find.widgetWithText(FilledButton, 'save'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid regular expression'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), r'PLS-\d+');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'file:///tmp/%PID%');
    await tester.tap(find.widgetWithText(FilledButton, 'save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid http or https URL'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).at(1), 'https://work.example/jira/%PID%');
    await tester.tap(find.widgetWithText(FilledButton, 'save'));
    await tester.pumpAndSettle();
    expect(find.text(r'PLS-\d+'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'save'));
    await tester.pumpAndSettle();
    expect(settings['linkPatterns'], [
      {'pattern': r'PLS-\d+', 'url': 'https://work.example/jira/%PID%'},
    ]);
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    expect(find.text(r'PLS-\d+'), findsOneWidget);
    await tester.tap(find.byTooltip('edit link rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), r'OPS-\d+');
    await tester.tap(find.widgetWithText(FilledButton, 'save'));
    await tester.pumpAndSettle();
    expect(find.text(r'OPS-\d+'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('changes not saved'), findsOneWidget);
    await tester.tap(find.text('save').last);
    await tester.pumpAndSettle();
    expect((settings['linkPatterns'] as List).single['pattern'], r'OPS-\d+');
    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('delete link rule'));
    await tester.tap(find.widgetWithText(TextButton, 'save'));
    await tester.pumpAndSettle();
    expect(settings['linkPatterns'], isEmpty);
  });

  testWidgets('task window loads link rules for title notes and subtasks',
      (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('task-links-');
      final appDirectory = Directory('${directory.path}/simplepresent-debug');
      await appDirectory.create();
      await File('${appDirectory.path}/simplepresent_settings.json')
          .writeAsString(
        jsonEncode({
          'linkPatterns': [
            {'pattern': r'PLS-\d+', 'url': 'https://work.example/jira/%PID%'},
          ],
        }),
      );
      final database = await databaseFactoryIo
          .openDatabase('${appDirectory.path}/simplepresent.db');
      await StoreRef<String, Object?>('lists')
          .record('simplepresent_today.json')
          .put(database, [
        {
          'id': 'task',
          'text': 'Title PLS-1',
          'notes': 'Notes PLS-2',
          'subtasks': [
            {'id': 'step', 'text': 'Step PLS-3', 'done': false},
          ],
        },
      ]);
      await database.close();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final audioDisposed = Completer<void>();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path);
      messenger.setMockMethodCallHandler(
          const MethodChannel('simple_present/window'), (_) async => true);
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (_) async => null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global/events'),
          (_) async => null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'), (call) async {
        if (call.method == 'create') {
          final playerId = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$playerId'),
            (_) async => null,
          );
        }
        if (call.method == 'dispose' && !audioDisposed.isCompleted) {
          audioDisposed.complete();
        }
        return null;
      });
      try {
        await tester.pumpWidget(
            const MaterialApp(home: app.TaskWindowPage(taskId: 'task')));
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.text('PLS-1').evaluate().isNotEmpty &&
              find.text('PLS-2').evaluate().isNotEmpty &&
              find.text('PLS-3').evaluate().isNotEmpty) break;
        }
        expect(find.text('PLS-1'), findsOneWidget);
        expect(find.text('PLS-2'), findsOneWidget);
        expect(find.text('PLS-3'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await audioDisposed.future.timeout(const Duration(seconds: 10));
        messenger.setMockMethodCallHandler(
            const MethodChannel('simple_present/window'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global/events'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'), null);
      }
    });
  });

  testWidgets('main task view loads links for titles notes and subtasks',
      (tester) async {
    await tester.runAsync(() async {
      final directory =
          await Directory.systemTemp.createTemp('main-task-links-');
      final appDirectory = Directory('${directory.path}/simplepresent-debug');
      await appDirectory.create();
      await File('${appDirectory.path}/simplepresent_settings.json')
          .writeAsString(
        jsonEncode({
          'lastRunDate': DateTime.now().toIso8601String().substring(0, 10),
          'linkPatterns': [
            {'pattern': r'PLS-\d+', 'url': 'https://work.example/jira/%PID%'},
          ],
        }),
      );
      final database = await databaseFactoryIo
          .openDatabase('${appDirectory.path}/simplepresent.db');
      await StoreRef<String, Object?>('lists')
          .record('simplepresent_today.json')
          .put(database, [
        {
          'id': 'task',
          'text': 'Title PLS-1',
          'notes': 'Notes PLS-2',
          'subtasks': [
            {'id': 'step', 'text': 'Step PLS-3', 'done': false},
          ],
        },
      ]);
      await database.close();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final audioDisposed = Completer<void>();
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path);
      messenger.setMockMethodCallHandler(
          const MethodChannel('simple_present/window'), (_) async => true);
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global'),
          (_) async => null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers.global/events'),
          (_) async => null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'), (call) async {
        if (call.method == 'create') {
          final playerId = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$playerId'),
              (_) async => null);
        }
        if (call.method == 'dispose' && !audioDisposed.isCompleted) {
          audioDisposed.complete();
        }
        return null;
      });
      try {
        await tester.pumpWidget(const app.SimplePresentApp());
        for (var attempt = 0; attempt < 200; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byType(TaskLinkText).evaluate().isNotEmpty) break;
        }
        expect(find.byType(TaskLinkText), findsOneWidget);
        final title = tester.widget<Text>(find.descendant(
            of: find.byType(TaskLinkText), matching: find.byType(Text)));
        expect(
            (title.textSpan as TextSpan)
                .children!
                .whereType<TextSpan>()
                .any((span) => span.text == 'PLS-1' && span.recognizer != null),
            isTrue);
        final tile = find
            .ancestor(
                of: find.byType(TaskLinkText), matching: find.byType(ListTile))
            .first;
        tester.widget<ListTile>(tile).onTap!();
        await tester.pump();
        expect(find.text('PLS-1'), findsOneWidget);
        expect(find.text('PLS-2'), findsOneWidget);
        expect(find.text('PLS-3'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await audioDisposed.future.timeout(const Duration(seconds: 10));
        messenger.setMockMethodCallHandler(
            const MethodChannel('simple_present/window'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers.global/events'), null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('xyz.luan/audioplayers'), null);
      }
    });
  });
}
