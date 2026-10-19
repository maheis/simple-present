import 'package:flutter_test/flutter_test.dart';
import 'package:simple_present/main.dart' as app;

void main() {
  test('subtask in-progress state persists and transitions correctly', () {
    final started = app.TaskStep(id: 'step-1', text: 'Write tests')
        .copyWith(inProgress: true);

    expect(started.done, isFalse);
    expect(started.inProgress, isTrue);

    final restored = app.TaskStep.fromJson(started.toJson());
    expect(restored.inProgress, isTrue);

    final completed = restored.copyWith(done: true);
    expect(completed.done, isTrue);
    expect(completed.inProgress, isFalse);

    final reopened = completed.copyWith(inProgress: true);
    expect(reopened.done, isFalse);
    expect(reopened.inProgress, isTrue);
  });

  test('legacy subtasks default to not in progress', () {
    final step = app.TaskStep.fromJson({
      'id': 'step-2',
      'text': 'Legacy step',
      'done': false,
    });

    expect(step.inProgress, isFalse);
  });
}
