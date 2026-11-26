import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:simple_present/main.dart' as app;
import 'package:simple_present/storage/sembast_storage.dart';
import 'package:simple_present/task_time_controls.dart';
import 'package:simple_present/time_booking.dart';
import 'package:simple_present/time_bookings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tracked time is split at midnight', () {
    final bookings = splitTrackedTime(
      sessionId: 'session',
      taskId: 'task',
      taskText: 'Example',
      startedAt: DateTime(2026, 4, 3, 23, 50),
      endedAt: DateTime(2026, 4, 4, 0, 15),
    );
    expect(bookings.map((booking) => booking.bookingDate),
        ['2026-04-03', '2026-04-04']);
    expect(bookings.map((booking) => booking.trackedSeconds), [600, 900]);
    expect(bookings.every((booking) => booking.source == 'stopwatch'), isTrue);
  });

  test('older bookings retain identifiable origin', () {
    expect(TimeBooking.fromJson({'id': 'manual', 'booked_minutes': 30}).source,
        'manual');
    expect(TimeBooking.fromJson({'id': 'timer', 'tracked_seconds': 60}).source,
        'stopwatch');
    expect(
        TimeBooking.fromJson({'id': 'legacy-day-task', 'booked_minutes': 30})
            .source,
        'legacy');
  });

  Future<Directory> mockDocumentsDirectory(String prefix) async {
    final directory = await Directory.systemTemp.createTemp(prefix);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    return directory;
  }

  test('timer sessions book only the time on each day', () async {
    final directory = await mockDocumentsDirectory('time-booking-timer-');
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      await storage.startTaskTimer(
          taskId: 'task', taskText: 'Example', now: DateTime(2026, 4, 3, 10));
      await storage.stopTaskTimer('task', now: DateTime(2026, 4, 3, 18, 15));
      await storage.startTaskTimer(
          taskId: 'task', taskText: 'Example', now: DateTime(2026, 4, 4, 9));
      await storage.stopTaskTimer('task', now: DateTime(2026, 4, 4, 9, 15));
      await storage.stopTaskTimer('task', now: DateTime(2026, 4, 4, 9, 30));
      final bookings = await storage.readTimeBookings();
      expect(bookings, hasLength(2));
      expect(bookings[0].bookingDate, '2026-04-04');
      expect(bookings[0].trackedSeconds, 15 * 60);
      expect(bookings[1].bookingDate, '2026-04-03');
      expect(bookings[1].trackedSeconds, 495 * 60);
      final backup = await storage.exportTimeBookings();
      await storage.importTimeBookings(backup);
      expect(
          (await storage.readTimeBookings())
              .map((entry) => entry.trackedSeconds),
          [15 * 60, 495 * 60]);
      await storage.saveTimeBooking(const TimeBooking(
          id: 'manual',
          bookingDate: '2026-04-04',
          bookingTime: '10:00',
          bookedMinutes: 30,
          taskId: 'task',
          taskText: 'Example'));
      await storage.resetTaskTimer('task');
      final remaining = await storage.readTimeBookings();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, 'manual');
      await storage.startTaskTimer(
          taskId: 'live',
          taskText: 'Running',
          now: DateTime.now().subtract(const Duration(minutes: 15)));
      final liveBackup = await storage.exportTimeBookings();
      expect(
          liveBackup.where((entry) => entry['task_id'] == 'live'), isNotEmpty);
      await storage.importTimeBookings(liveBackup);
      final live = (await storage.readTimeBookings(includeRunning: true))
          .where((entry) => entry.taskId == 'live')
          .toList();
      expect(live.map((entry) => entry.id).toSet().length, live.length);
      await storage.stopTaskTimer('live');
      final stopped = (await storage.readTimeBookings())
          .where((entry) => entry.taskId == 'live')
          .toList();
      expect(stopped.length, live.length);
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  test('interrupted timers stop at the last app checkpoint', () async {
    final directory = await mockDocumentsDirectory('timer-checkpoint-');
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      await storage.startTaskTimer(
          taskId: 'task',
          taskText: 'Example',
          now: DateTime(2026, 4, 3, 23, 50));
      await storage.checkpointActiveTimers(now: DateTime(2026, 4, 4, 0, 15));
      await storage.recoverInterruptedTimers();
      await storage.recoverInterruptedTimers();
      final bookings = await storage.readTimeBookings(includeRunning: true);
      expect(bookings, hasLength(2));
      expect(bookings.map((entry) => entry.trackedSeconds), [900, 600]);
      expect(await storage.readTaskTimer('task'), isNull);
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  test('recovery does not shorten a saved timer snapshot', () async {
    final directory = await mockDocumentsDirectory('timer-snapshot-');
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      final start = DateTime(2026, 4, 3, 10);
      await storage.startTaskTimer(
          taskId: 'task', taskText: 'Example', now: start);
      await storage.checkpointActiveTimers(now: DateTime(2026, 4, 3, 10, 15));
      await storage.saveTimeBooking(TimeBooking(
        id: '${start.microsecondsSinceEpoch}-task-2026-04-03',
        bookingDate: '2026-04-03',
        bookingTime: '10:00',
        bookedMinutes: 0,
        trackedSeconds: 20 * 60,
        source: 'stopwatch',
        taskId: 'task',
        taskText: 'Example',
      ));
      await storage.recoverInterruptedTimers();
      expect((await storage.readTimeBookings()).single.trackedSeconds, 20 * 60);
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  test('restarting the app closes timers at shutdown, not restart', () async {
    final directory = await mockDocumentsDirectory('timer-runtime-');
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      await storage.startTimeTrackingRuntime();
      await storage.startTaskTimer(
          taskId: 'task', taskText: 'Example', now: DateTime(2026, 4, 3, 10));
      await Future.wait([
        storage.stopTimeTrackingRuntime(now: DateTime(2026, 4, 3, 10, 15)),
        storage.stopTimeTrackingRuntime(now: DateTime(2026, 4, 3, 10, 15)),
      ]);
      expect(await storage.readTaskTimer('task'), isNotNull);
      expect(
          (await storage.readTimeBookings(includeRunning: true))
              .single
              .trackedSeconds,
          15 * 60);
      await expectLater(storage.stopTaskTimer('task'), throwsStateError);
      await storage.startTimeTrackingRuntime();
      final booking = (await storage.readTimeBookings()).single;
      expect(booking.bookingDate, '2026-04-03');
      expect(booking.trackedSeconds, 15 * 60);
      expect(await storage.readTaskTimer('task'), isNull);
      await storage.stopTimeTrackingRuntime();
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  test('legacy running timers without checkpoints do not count offline time',
      () async {
    final directory = await mockDocumentsDirectory('timer-legacy-runtime-');
    final appDirectory = Directory('${directory.path}/simplepresent-debug');
    await appDirectory.create();
    final database = await databaseFactoryIo
        .openDatabase('${appDirectory.path}/simplepresent.db');
    await StoreRef<String, Object?>('active_time_sessions')
        .record('task')
        .put(database, {
      'id': 'legacy-session',
      'task_id': 'task',
      'task_text': 'Example',
      'started_at': DateTime(2026, 4, 3, 10).toIso8601String(),
    });
    await database.close();
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      await storage.startTimeTrackingRuntime();
      expect(await storage.readTaskTimer('task'), isNull);
      expect(await storage.readTimeBookings(), isEmpty);
      await storage.stopTimeTrackingRuntime();
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  test('another running app process prevents interrupted timer recovery',
      () async {
    final directory = await mockDocumentsDirectory('timer-process-lock-');
    final storage = SembastStorage();
    Process? process;
    try {
      await storage.init(debugMode: true);
      await storage.startTaskTimer(
          taskId: 'task', taskText: 'Example', now: DateTime(2026, 4, 3, 10));
      await storage.checkpointActiveTimers(now: DateTime(2026, 4, 3, 10, 15));
      final script = File('${directory.path}/lock_holder.dart');
      await script.writeAsString('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final file = await File(args.single).open(mode: FileMode.append);
  await file.lock(FileLock.shared);
  stdout.writeln('locked');
  await stdin.first;
  await file.unlock();
  await file.close();
}
''');
      process = await Process.start('dart', [
        script.path,
        '${directory.path}/simplepresent-debug/time_tracking.lock',
      ]);
      expect(
          await process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first,
          'locked');
      await storage.startTimeTrackingRuntime();
      expect(await storage.readTaskTimer('task'), isNotNull);
      expect(await storage.readTimeBookings(), isEmpty);
      await storage.stopTimeTrackingRuntime(now: DateTime(2026, 4, 3, 10, 15));
      process.stdin.writeln('stop');
      expect(await process.exitCode, 0);
      process = null;
      await storage.startTimeTrackingRuntime();
      expect((await storage.readTimeBookings()).single.trackedSeconds, 900);
      expect(await storage.readTaskTimer('task'), isNull);
      await storage.stopTimeTrackingRuntime();
    } finally {
      process?.kill();
      await storage.stopTimeTrackingRuntime();
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  testWidgets('statistics do not reuse lifetime task minutes on completion day',
      (tester) async {
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(MaterialApp(
      home: app.StatsPage(
        doneList: [
          app.TaskItem(
              id: 'task',
              text: 'Example',
              done: true,
              completedAt: now,
              stopwatchAccumulatedSeconds: 510 * 60)
        ],
        timeEntries: [
          app.TimeEntry(
              taskId: 'task',
              taskText: 'Example',
              date: date,
              taskDone: true,
              taskInProgress: false,
              stopwatchSeconds: 15 * 60,
              workMinutes: 0)
        ],
        textScale: 1,
      ),
    ));
    expect(find.textContaining('Gesamt Zeit: 15 min'), findsOneWidget);
    expect(find.textContaining('510 min'), findsNothing);
    await tester.pumpWidget(MaterialApp(
      home: app.StatsPage(
        doneList: [
          app.TaskItem(
              id: 'task',
              text: 'Example',
              done: true,
              completedAt: now,
              stopwatchAccumulatedSeconds: 510 * 60)
        ],
        timeEntries: const [],
        textScale: 1,
      ),
    ));
    expect(find.textContaining('Gesamt Zeit: 0 min'), findsOneWidget);
    expect(find.textContaining('510 min'), findsNothing);
  });

  test('statistics include completed tasks in today and deduplicate lists', () {
    final tasks = app.completedTasksForStatistics([
      [
        app.TaskItem(id: 'old', text: 'Old', done: true),
        app.TaskItem(id: 'reopened', text: 'Reopened', done: true),
      ],
      [app.TaskItem(id: 'today', text: 'Finished today', done: true)],
      [app.TaskItem(id: 'reopened', text: 'Reopened', done: false)],
    ]);
    expect(tasks.map((task) => task.id), containsAll(['old', 'today']));
    expect(tasks.map((task) => task.id), isNot(contains('reopened')));
    expect(tasks, hasLength(2));
  });

  testWidgets('statistics include tasks completed in today and done lists',
      (tester) async {
    await tester.runAsync(() async {
      final directory =
          await Directory.systemTemp.createTemp('stats-completed-');
      final appDirectory = Directory('${directory.path}/simplepresent-debug');
      await appDirectory.create();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      String dateKey(DateTime date) =>
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      await File('${appDirectory.path}/simplepresent_settings.json')
          .writeAsString(jsonEncode({'lastRunDate': dateKey(today)}));
      final database = await databaseFactoryIo
          .openDatabase('${appDirectory.path}/simplepresent.db');
      final lists = StoreRef<String, Object?>('lists');
      await lists.record('simplepresent_today.json').put(database, [
        {
          'id': 'today',
          'text': 'Completed today',
          'done': true,
          'completed_at': now.toIso8601String()
        },
      ]);
      await lists.record('simplepresent_done.json').put(database, [
        {
          'id': 'done',
          'text': 'Archived completed',
          'done': true,
          'completed_at': now.toIso8601String()
        },
      ]);
      final bookings = StoreRef<String, Object?>('time_bookings');
      for (final (id, date) in [
        ('today-booking', today),
        ('old-booking', yesterday)
      ]) {
        await bookings.record(id).put(
            database,
            TimeBooking(
              id: id,
              bookingDate: dateKey(date),
              bookingTime: '10:00',
              bookedMinutes: 15,
              taskId: 'today',
              taskText: 'Completed today',
            ).toJson());
      }
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
        await tester.pumpWidget(const app.SimplePresentApp());
        for (var attempt = 0; attempt < 200; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byTooltip('statistics').evaluate().isNotEmpty) break;
        }
        await tester.tap(find.byTooltip('statistics'));
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byType(app.StatsPage).evaluate().isNotEmpty) break;
        }
        await tester.pump(const Duration(milliseconds: 500));
        final statsText = (String text) => find.descendant(
            of: find.byType(app.StatsPage), matching: find.text(text));
        expect(statsText('Completed today'), findsOneWidget);
        expect(statsText('Archived completed'), findsOneWidget);
        expect(find.textContaining('Erledigt: 2'), findsOneWidget);
        expect(find.textContaining('Gesamt Zeit: 15 min'), findsOneWidget);
        await tester.tap(find.byTooltip('Vorheriger Tag'));
        await tester.pump();
        expect(find.textContaining('Erledigt: 0'), findsOneWidget);
        expect(find.text('Laufend (nicht abgeschlossen)'), findsOneWidget);
        expect(statsText('Completed today'), findsOneWidget);
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

  testWidgets('statistics include manual corrections on their booking day',
      (tester) async {
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(MaterialApp(
      home: app.StatsPage(
        doneList: [],
        timeEntries: [
          app.TimeEntry(
              taskId: 'task',
              taskText: 'Example',
              date: date,
              taskDone: false,
              taskInProgress: false,
              stopwatchSeconds: 0,
              workMinutes: 60),
          app.TimeEntry(
              taskId: 'task',
              taskText: 'Example',
              date: date,
              taskDone: false,
              taskInProgress: false,
              stopwatchSeconds: 0,
              workMinutes: -30),
        ],
        textScale: 1,
      ),
    ));
    expect(find.textContaining('Gesamt Zeit: 30 min'), findsOneWidget);
  });

  test('booking CRUD preserves the independently selected booking date/time',
      () async {
    final directory = await mockDocumentsDirectory('time-booking-crud-');
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      const booking = TimeBooking(
        id: 'booking-1',
        bookingDate: '2026-04-03',
        bookingTime: '08:35',
        bookedMinutes: 95,
        taskId: 'task-1',
        taskText: 'Prepare report',
      );
      await storage.saveTimeBooking(booking);

      final saved = (await storage.readTimeBookings()).single;
      expect(saved.toJson(), booking.toJson());
      expect((await storage.exportTimeBookings()).single, booking.toJson());

      await storage.saveTimeBooking(TimeBooking(
        id: booking.id,
        bookingDate: booking.bookingDate,
        bookingTime: booking.bookingTime,
        bookedMinutes: 120,
        taskId: booking.taskId,
        taskText: booking.taskText,
      ));
      expect((await storage.readTimeBookings()).single.bookedMinutes, 120);

      await storage.deleteTimeBooking(booking.id);
      expect(await storage.readTimeBookings(), isEmpty);

      await storage.importTimeBookings([booking.toJson()]);
      await storage.importTimeBookings([booking.toJson()], merge: true);
      expect(
          (await storage.readTimeBookings()).single.toJson(), booking.toJson());

      const correction = TimeBooking(
        id: 'correction',
        bookingDate: '2026-04-04',
        bookingTime: '09:00',
        bookedMinutes: -30,
        taskId: 'task-1',
        taskText: 'Prepare report',
      );
      await storage.saveTimeBooking(correction);
      final backup = await storage.exportTimeBookings();
      await storage.importTimeBookings(backup);
      expect(
        (await storage.readTimeBookings())
            .singleWhere((entry) => entry.id == 'correction')
            .bookedMinutes,
        -30,
      );
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await directory.delete(recursive: true);
    }
  });

  test(
      'manual bookings and corrections remain distinct across days and backups',
      () async {
    final directory = await mockDocumentsDirectory('manual-booking-days-');
    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      for (final (id, date, minutes) in [
        ('today', '2026-04-03', 30),
        ('tomorrow', '2026-04-04', 30),
        ('correction', '2026-04-04', -30),
      ]) {
        await storage.saveTimeBooking(TimeBooking(
          id: id,
          bookingDate: date,
          bookingTime: '10:00',
          bookedMinutes: minutes,
          taskId: 'task',
          taskText: 'Example',
        ));
      }
      final backup = await storage.exportTimeBookings();
      await storage.importTimeBookings(backup);
      await storage.resetTaskTimer('task');
      final bookings = await storage.readTimeBookings();
      expect(bookings, hasLength(3));
      expect(
          bookings
              .where((entry) => entry.bookingDate == '2026-04-03')
              .fold<int>(0, (total, entry) => total + entry.bookedMinutes),
          30);
      expect(
          bookings
              .where((entry) => entry.bookingDate == '2026-04-04')
              .fold<int>(0, (total, entry) => total + entry.bookedMinutes),
          0);
      expect(bookings.every((entry) => entry.source == 'manual'), isTrue);
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      await directory.delete(recursive: true);
    }
  });

  test('legacy daily task totals migrate once to booking rows', () async {
    final directory = await mockDocumentsDirectory('time-booking-migration-');
    final appDirectory = Directory('${directory.path}/simplepresent-debug');
    await appDirectory.create();
    final database = await databaseFactoryIo
        .openDatabase('${appDirectory.path}/simplepresent.db');
    final timeStore = StoreRef<String, Object?>('time_entries');
    final recordedAt =
        DateTime(2026, 4, 3, 14, 25).millisecondsSinceEpoch ~/ 1000;
    await timeStore.record('2026-04-03').put(database, [
      {
        'task_id': 'task-2',
        'task_text': 'Review plan',
        'work_minutes': 30,
        'stopwatch_seconds': 3600,
        'recorded_at': recordedAt,
      },
    ]);
    await timeStore.record('2026-04-04').put(database, [
      {
        'task_id': 'task-2',
        'task_text': 'Review plan',
        'work_minutes': 60,
        'stopwatch_seconds': 7200,
        'recorded_at': recordedAt,
      },
    ]);
    await database.close();

    final storage = SembastStorage();
    try {
      await storage.init(debugMode: true);
      final migratedBookings = await storage.readTimeBookings();
      expect(migratedBookings, hasLength(2));
      expect(migratedBookings.first.bookingDate, '2026-04-04');
      expect(migratedBookings.first.bookedMinutes, 90);
      final migrated = migratedBookings.last;
      expect(migrated.bookingDate, '2026-04-03');
      expect(migrated.bookingTime, '14:25');
      expect(migrated.bookedMinutes, 90);
      expect(migrated.taskId, 'task-2');

      await storage.refresh();
      expect(await storage.readTimeBookings(), hasLength(2));
    } finally {
      storage.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      await directory.delete(recursive: true);
    }
  });

  testWidgets('standalone table can add a booking with hour/minute duration',
      (tester) async {
    final storage = _MemoryBookingStorage();
    await tester.pumpWidget(MaterialApp(
      home: TimeBookingsPage(
        storage: storage,
        taskOptions: const {'task-3': 'Past-day task'},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('add booking'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1h 30m');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(find.text('Past-day task'), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(await storage.readTimeBookings(), hasLength(1));
  });

  testWidgets('booking filters combine search and type and can be cleared',
      (tester) async {
    final storage = _MemoryBookingStorage();
    storage.bookings.addAll(const [
      TimeBooking(
          id: 'a',
          bookingDate: '2026-04-03',
          bookingTime: '10:00',
          bookedMinutes: 30,
          taskId: 'a',
          taskText: 'Alpha',
          source: 'manual'),
      TimeBooking(
          id: 'b',
          bookingDate: '2026-04-04',
          bookingTime: '11:00',
          bookedMinutes: 0,
          trackedSeconds: 3600,
          taskId: 'b',
          taskText: 'Beta',
          source: 'stopwatch'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: TimeBookingsPage(
          storage: storage, taskOptions: const {'a': 'Alpha', 'b': 'Beta'}),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 bookings · 1 h 30 min'), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('booking-search')), 'beta');
    await tester.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    expect(find.textContaining('1 booking · 1 h'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('booking-type-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('manual').last);
    await tester.pumpAndSettle();
    expect(find.text('no matching bookings'), findsOneWidget);

    await tester.tap(find.byTooltip('clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.textContaining('2 bookings · 1 h 30 min'), findsOneWidget);
  });

  testWidgets(
      'booking table has a visible horizontal scrollbar on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = _MemoryBookingStorage();
    storage.bookings.add(const TimeBooking(
      id: 'a',
      bookingDate: '2026-04-03',
      bookingTime: '10:00',
      bookedMinutes: 30,
      taskId: 'a',
      taskText: 'A task with a long title',
    ));
    await tester.pumpWidget(MaterialApp(
      home: TimeBookingsPage(
          storage: storage, taskOptions: const {'a': 'A task'}),
    ));
    await tester.pumpAndSettle();
    final scrollbar = tester.widget<Scrollbar>(
        find.byKey(const ValueKey('bookings-horizontal-scrollbar')));
    final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('bookings-horizontal-scroll')));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.controller, same(scroll.controller));
    expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byKey(const ValueKey('bookings-horizontal-scroll')),
        const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking date range filters entries and totals', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    String dateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final storage = _MemoryBookingStorage();
    storage.bookings.addAll([
      TimeBooking(
          id: 'today',
          bookingDate: dateKey(today),
          bookingTime: '10:00',
          bookedMinutes: 30,
          taskId: 'today',
          taskText: 'Today task'),
      TimeBooking(
          id: 'yesterday',
          bookingDate: dateKey(yesterday),
          bookingTime: '10:00',
          bookedMinutes: 60,
          taskId: 'yesterday',
          taskText: 'Yesterday task'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: TimeBookingsPage(storage: storage, taskOptions: const {
        'today': 'Today task',
        'yesterday': 'Yesterday task',
      }),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('all dates'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Today task'), findsOneWidget);
    expect(find.text('Yesterday task'), findsNothing);
    expect(find.textContaining('1 booking · 30 min'), findsOneWidget);
    await tester.tap(find.byTooltip('clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday task'), findsOneWidget);
  });

  testWidgets(
      'manual bookings start empty and accept negative minute corrections',
      (tester) async {
    final storage = _MemoryBookingStorage();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTimeControls(
          storage: storage,
          taskId: 'task',
          taskText: 'Example',
        ),
      ),
    ));
    await tester.pump();

    for (final value in ['30', '30m', '-30m']) {
      await tester.tap(find.byTooltip('add manual booking'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(fields).controller!.text, '');
      await tester.enterText(fields, value);
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
    }

    expect(storage.bookings.map((booking) => booking.bookedMinutes),
        [30, 30, -30]);
    expect(storage.bookings.map((booking) => booking.source),
        ['manual', 'manual', 'manual']);
    expect(find.text('stopwatch: 00:30:00'), findsOneWidget);

    await tester.tap(find.byTooltip('show bookings'));
    await tester.pumpAndSettle();
    expect(find.text('manual'), findsNWidgets(3));
    expect(find.text('-30 min'), findsOneWidget);
    expect(find.textContaining('3 bookings · 30 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual duration defaults to minutes and accepts m and h',
      (tester) async {
    final storage = _MemoryBookingStorage();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTimeControls(
          storage: storage,
          taskId: 'task',
          taskText: 'Example',
        ),
      ),
    ));
    await tester.pump();
    for (final (input, expectedMinutes) in [
      ('30', 30),
      ('30m', 30),
      ('1h', 60),
      ('-30', -30),
      ('-1h', -60),
      ('1h 30m', 90),
    ]) {
      await tester.tap(find.byTooltip('add manual booking'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), input);
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(storage.bookings.last.bookedMinutes, expectedMinutes,
          reason: input);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('manual bookings round up to signed 15 minute blocks',
      (tester) async {
    final storage = _MemoryBookingStorage();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTimeControls(
          storage: storage,
          taskId: 'task',
          taskText: 'Example',
        ),
      ),
    ));
    await tester.pump();
    for (final (input, expectedMinutes) in [
      ('1m', 15),
      ('15m', 15),
      ('16m', 30),
      ('31m', 45),
      ('-1m', -15),
      ('-15m', -15),
      ('-16m', -30),
    ]) {
      await tester.tap(find.byTooltip('add manual booking'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), input);
      await tester.pump();
      if (input == '16m') {
        expect(find.text('booking: 30 min'), findsOneWidget);
      }
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(storage.bookings.last.bookedMinutes, expectedMinutes,
          reason: input);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('editing a timer entry preserves unchanged tracked seconds',
      (tester) async {
    final storage = _MemoryBookingStorage();
    storage.bookings.add(const TimeBooking(
      id: 'timer',
      bookingDate: '2026-04-03',
      bookingTime: '10:00',
      bookedMinutes: 0,
      trackedSeconds: 91,
      source: 'stopwatch',
      taskId: 'task',
      taskText: 'Example',
    ));
    await tester.pumpWidget(MaterialApp(
      home: TimeBookingsPage(
        storage: storage,
        taskOptions: const {'task': 'Example'},
        taskId: 'task',
      ),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('edit'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField))
            .controller!
            .text,
        '2m');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();
    expect(storage.bookings.single.trackedSeconds, 91);
    expect(storage.bookings.single.source, 'stopwatch');
  });

  testWidgets('existing manual duration changes only when edited',
      (tester) async {
    final storage = _MemoryBookingStorage();
    storage.bookings.add(const TimeBooking(
      id: 'existing',
      bookingDate: '2026-04-03',
      bookingTime: '10:00',
      bookedMinutes: 7,
      taskId: 'task',
      taskText: 'Example',
    ));
    await tester.pumpWidget(MaterialApp(
      home: TimeBookingsPage(
        storage: storage,
        taskOptions: const {'task': 'Example'},
        taskId: 'task',
      ),
    ));
    await tester.pumpAndSettle();
    for (final input in [null, '16m']) {
      await tester.ensureVisible(find.byTooltip('edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('edit'));
      await tester.pumpAndSettle();
      if (input != null) {
        await tester.enterText(find.byType(TextFormField), input);
      }
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      expect(storage.bookings.single.bookedMinutes, input == null ? 7 : 30);
    }
  });

  testWidgets('task stopwatch offers start, stop and manual booking',
      (tester) async {
    final storage = _MemoryBookingStorage();
    var started = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTimeControls(
          storage: storage,
          taskId: 'task',
          taskText: 'Example',
          onStarted: () => started = true,
        ),
      ),
    ));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.stop))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('start'));
    await tester.pump();
    expect(started, isTrue);
    expect(storage.runningTaskId, 'task');
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.play_arrow))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('stop'));
    await tester.pump();
    expect(storage.runningTaskId, isNull);
    expect(find.byTooltip('add manual booking'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('task controls show only bookings for the selected task',
      (tester) async {
    final storage = _MemoryBookingStorage();
    storage.bookings.addAll(const [
      TimeBooking(
          id: 'one',
          bookingDate: '2026-04-03',
          bookingTime: '10:00',
          bookedMinutes: 15,
          taskId: 'task',
          taskText: 'Example'),
      TimeBooking(
          id: 'two',
          bookingDate: '2026-04-04',
          bookingTime: '11:00',
          bookedMinutes: 60,
          taskId: 'other',
          taskText: 'Other task'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTimeControls(
          storage: storage,
          taskId: 'task',
          taskText: 'Example',
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byTooltip('show bookings'));
    await tester.pumpAndSettle();

    expect(find.text('bookings: Example'), findsOneWidget);
    expect(find.text('2026-04-03'), findsOneWidget);
    expect(find.text('2026-04-04'), findsNothing);
    expect(find.textContaining('1 booking · 15 min'), findsOneWidget);
    expect(find.byTooltip('edit'), findsOneWidget);
    expect(find.byTooltip('delete'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('delete').last);
    await tester.pumpAndSettle();
    expect(storage.bookings.single.taskId, 'other');
    expect(find.text('add first booking'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _MemoryBookingStorage extends SembastStorage {
  final List<TimeBooking> bookings = [];
  String? runningTaskId;

  @override
  Future<List<TimeBooking>> readTimeBookings(
          {bool includeRunning = false}) async =>
      List.of(bookings);

  @override
  Future<void> saveTimeBooking(TimeBooking booking) async {
    bookings.removeWhere((existing) => existing.id == booking.id);
    bookings.add(booking);
  }

  @override
  Future<void> deleteTimeBooking(String id) async {
    bookings.removeWhere((booking) => booking.id == id);
  }

  @override
  Future<Map<String, dynamic>?> readTaskTimer(String taskId) async =>
      runningTaskId == taskId ? {'task_id': taskId} : null;

  @override
  Future<void> startTaskTimer(
      {required String taskId, required String taskText, DateTime? now}) async {
    runningTaskId = taskId;
  }

  @override
  Future<void> stopTaskTimer(String taskId, {DateTime? now}) async {
    if (runningTaskId == taskId) runningTaskId = null;
  }
}
