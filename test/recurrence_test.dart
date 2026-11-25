import 'package:simple_present/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_present/recurrence.dart' as recurrence;

void main() {
  test('overdue recurrence base keeps scheduled time', () {
    final base = recurrence.recurrenceBase(
      DateTime(2026, 6, 29, 18, 45),
      DateTime(2026, 6, 30, 10, 12),
    );

    expect(base, DateTime(2026, 6, 30, 18, 45));
    expect(recurrence.computeNextRecurrence(base, 'daily'),
        DateTime(2026, 7, 1, 18, 45));
  });

  test('daily simple', () {
    final base = DateTime(2026, 6, 30, 10, 0);
    final next = recurrence.computeNextRecurrence(base, 'daily');
    expect(next, DateTime(2026, 7, 1, 10, 0));
  });

  test('weekly interval 2', () {
    final base = DateTime(2026, 6, 30, 9, 30);
    final next = recurrence.computeNextRecurrence(base, 'weekly:2');
    expect(next, base.add(Duration(days: 14)));
  });

  test('monthly day', () {
    final base = DateTime(2026, 1, 31, 8, 0);
    final next = recurrence.computeNextRecurrence(base, 'monthly:day=15');
    // next 15th after Jan 31 is Feb 15
    expect(next, DateTime(2026, 2, 15, 8, 0));
  });

  test('monthly weekday first Mon', () {
    final base = DateTime(2026, 6, 10, 12, 0);
    final next =
        recurrence.computeNextRecurrence(base, 'monthly:weekday=first:1');
    // first Monday after June 10 2026 -> July 6, 2026 (first Mon of July)
    expect(next, DateTime(2026, 7, 6, 12, 0));
  });

  test('yearly', () {
    final base = DateTime(2024, 2, 29, 7, 0);
    final next = recurrence.computeNextRecurrence(base, 'yearly');
    // 2025-02-28 (clamped)
    expect(next, DateTime(2025, 2, 28, 7, 0));
  });

  test('recurrence parent id persists and identifies existing follow-ups', () {
    final followUp = app.TaskItem(
      id: 'follow-up',
      text: 'Repeated task',
      recurrenceParentId: 'original',
    );
    final restored = app.TaskItem.fromJson(followUp.toJson());
    expect(restored.recurrenceParentId, 'original');
    expect(
        app.hasExistingFollowUp('original', [
          app.TaskItem(id: 'original', text: 'Repeated task'),
          restored,
        ]),
        isTrue);
    expect(app.hasExistingFollowUp('other', [restored]), isFalse);
    final duplicate = restored.copyWith(
      id: 'manual-copy',
      recurrenceParentId: null,
    );
    expect(duplicate.recurrenceParentId, isNull);
    expect(app.hasExistingFollowUp('original', [duplicate]), isFalse);

    final legacy = app.TaskItem.fromJson({
      'id': 'legacy-follow-up',
      'text': 'Repeated task',
      'repeat': 'daily',
    });
    expect(legacy.recurrenceParentId, isNull);
  });

  test('legacy generated follow-ups are detected from redo history', () {
    final events = [
      {
        'action': 'create',
        'task_id': 'old-follow-up',
        'details': {'generated_from': 'original'},
      },
    ];
    expect(
      app.hasLegacyGeneratedFollowUp('original', events, {'old-follow-up'}),
      isTrue,
    );
    expect(
      app.hasLegacyGeneratedFollowUp('original', events, const {}),
      isFalse,
    );
    expect(
      app.hasLegacyGeneratedFollowUp('other', events, {'old-follow-up'}),
      isFalse,
    );
  });
}
