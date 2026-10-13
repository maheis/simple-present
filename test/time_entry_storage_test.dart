import 'package:flutter_test/flutter_test.dart';
import 'package:simple_present/storage/sembast_storage.dart';

void main() {
  test('legacy cumulative entries migrate to daily values', () {
    const cumulativeMinutes = [60, 120, 180];
    const cumulativeStopwatchSeconds = [3600, 7200, 10800];
    var previousMinutes = 0;
    var previousSeconds = 0;
    final dailyMinutes = <int>[];
    final dailySeconds = <int>[];

    for (var index = 0; index < cumulativeMinutes.length; index++) {
      final entry = normalizeLegacyTimeEntry(
        <String, dynamic>{
          'work_minutes': cumulativeMinutes[index],
          'stopwatch_seconds': cumulativeStopwatchSeconds[index],
        },
        previousStopwatchSeconds: previousSeconds,
        previousWorkMinutes: previousMinutes,
      );
      dailyMinutes.add(entry['work_minutes'] as int);
      dailySeconds.add(entry['stopwatch_seconds'] as int);
      previousMinutes = entry['total_work_minutes'] as int;
      previousSeconds = entry['total_stopwatch_seconds'] as int;
    }

    expect(dailyMinutes, [60, 60, 60]);
    expect(dailySeconds, [3600, 3600, 3600]);
  });
}
