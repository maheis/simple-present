import 'package:flutter_test/flutter_test.dart';
import 'package:simple_present/recurrence.dart' as app;

void main() {
  test('daily simple', () {
    final base = DateTime(2026, 6, 30, 10, 0);
    final next = app.computeNextRecurrence(base, 'daily');
    expect(next, DateTime(2026, 7, 1, 10, 0));
  });

  test('weekly interval 2', () {
    final base = DateTime(2026, 6, 30, 9, 30);
    final next = app.computeNextRecurrence(base, 'weekly:2');
    expect(next, base.add(Duration(days: 14)));
  });

  test('monthly day', () {
    final base = DateTime(2026, 1, 31, 8, 0);
    final next = app.computeNextRecurrence(base, 'monthly:day=15');
    // next 15th after Jan 31 is Feb 15
    expect(next, DateTime(2026, 2, 15, 8, 0));
  });

  test('monthly weekday first Mon', () {
    final base = DateTime(2026, 6, 10, 12, 0);
    final next = app.computeNextRecurrence(base, 'monthly:weekday=first:1');
    // first Monday after June 10 2026 -> July 6, 2026 (first Mon of July)
    expect(next, DateTime(2026, 7, 6, 12, 0));
  });

  test('yearly', () {
    final base = DateTime(2024, 2, 29, 7, 0);
    final next = app.computeNextRecurrence(base, 'yearly');
    // 2025-02-28 (clamped)
    expect(next, DateTime(2025, 2, 28, 7, 0));
  });
}
