// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sembast/sembast_io.dart';

import 'package:simple_present/main.dart';

void main() {
  testWidgets('Adds a task to today list', (WidgetTester tester) async {
    await initializeDateFormatting('de_DE');
    await tester.pumpWidget(const SimplePresentApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Milch kaufen');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('Milch kaufen'), findsOneWidget);
  });

  for (final (source, action) in [
    ('today', 'open'),
    ('today', 'use here'),
    ('backlog', 'move to today'),
    ('done', 'reactivate'),
  ]) {
    testWidgets('new task input clears when selecting $source via $action',
        (tester) async {
      await tester.runAsync(() async {
        final directory =
            await Directory.systemTemp.createTemp('new-task-search-');
        final appDirectory = Directory('${directory.path}/simplepresent-debug');
        await appDirectory.create();
        await File('${appDirectory.path}/simplepresent_settings.json')
            .writeAsString(
          jsonEncode({
            'lastRunDate': DateTime.now().toIso8601String().substring(0, 10)
          }),
        );
        final database = await databaseFactoryIo
            .openDatabase('${appDirectory.path}/simplepresent.db');
        await StoreRef<String, Object?>('lists')
            .record('simplepresent_$source.json')
            .put(database, [
          {
            'id': 'existing-task',
            'text': 'Existing candidate',
            'done': source == 'done',
            if (source == 'done')
              'completed_at': DateTime.now().toIso8601String(),
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
          if (call.method == 'dispose' && !audioDisposed.isCompleted)
            audioDisposed.complete();
          return null;
        });
        try {
          await tester.pumpWidget(const SimplePresentApp());
          final input = find.byWidgetPredicate((widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'new task for today');
          for (var attempt = 0; attempt < 200; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (input.evaluate().isNotEmpty) break;
          }
          expect(input, findsOneWidget);
          final controller = tester.widget<TextField>(input).controller!;
          await tester.enterText(input, 'Existing candidate');
          final actionLabel = action == 'open' ? 'use here' : action;
          for (var attempt = 0; attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
            if (find.text(actionLabel).evaluate().isNotEmpty) break;
          }
          expect(find.text(actionLabel), findsOneWidget);
          if (action == 'open') {
            final result = find
                .ancestor(
                    of: find.text(actionLabel), matching: find.byType(ListTile))
                .first;
            tester.widget<ListTile>(result).onTap!();
          } else {
            await tester.tap(find.text(actionLabel));
          }
          await tester.pump();
          expect(controller.text, isEmpty);
          for (var attempt = 0; attempt < 50; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
          await tester.pump(const Duration(milliseconds: 500));
          expect(controller.text, isEmpty);
          expect(find.text(actionLabel), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await audioDisposed.future.timeout(const Duration(seconds: 10));
          for (final channel in const [
            'plugins.flutter.io/path_provider',
            'simple_present/window',
            'xyz.luan/audioplayers.global',
            'xyz.luan/audioplayers.global/events',
            'xyz.luan/audioplayers',
          ]) {
            messenger.setMockMethodCallHandler(MethodChannel(channel), null);
          }
        }
      });
    });
  }
}
