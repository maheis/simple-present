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

    await tester.tap(find.byTooltip('Buchung hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '1');
    await tester.enterText(find.byType(TextFormField).at(1), '30');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Past-day task'), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(await storage.readTimeBookings(), hasLength(1));
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
    expect(find.byTooltip('Zeit manuell buchen'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Buchungen anzeigen'));
    await tester.pumpAndSettle();

    expect(find.text('Buchungen: Example'), findsOneWidget);
    expect(find.text('2026-04-03'), findsOneWidget);
    expect(find.text('2026-04-04'), findsNothing);
    expect(find.textContaining('1 Buchung · 15 min'), findsOneWidget);
    expect(find.byTooltip('Bearbeiten'), findsOneWidget);
    expect(find.byTooltip('Löschen'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen').last);
    await tester.pumpAndSettle();
    expect(storage.bookings.single.taskId, 'other');
    expect(find.text('Erste Buchung erfassen'), findsOneWidget);
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
