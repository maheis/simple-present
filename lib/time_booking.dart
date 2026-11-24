class TimeBooking {
  const TimeBooking({
    required this.id,
    required this.bookingDate,
    required this.bookingTime,
    required this.bookedMinutes,
    required this.taskId,
    required this.taskText,
    this.trackedSeconds = 0,
    this.source = 'manual',
  });

  final String id;
  final String bookingDate;
  final String bookingTime;
  final int bookedMinutes;
  final String taskId;
  final String taskText;
  final int trackedSeconds;
  final String source;

  Map<String, dynamic> toJson() => {
        'id': id,
        'booking_date': bookingDate,
        'booking_time': bookingTime,
        'booked_minutes': bookedMinutes,
        'task_id': taskId,
        'task_text': taskText,
        'source': source,
        if (trackedSeconds > 0) 'tracked_seconds': trackedSeconds,
      };

  factory TimeBooking.fromJson(Map<String, dynamic> json) => TimeBooking(
        id: json['id']?.toString() ?? '',
        bookingDate: json['booking_date']?.toString() ?? '',
        bookingTime: json['booking_time']?.toString() ?? '',
        bookedMinutes:
            int.tryParse(json['booked_minutes']?.toString() ?? '') ?? 0,
        taskId: json['task_id']?.toString() ?? '',
        taskText: json['task_text']?.toString() ?? '',
        trackedSeconds:
            int.tryParse(json['tracked_seconds']?.toString() ?? '') ?? 0,
        source: json['source']?.toString() ??
            ((json['id']?.toString() ?? '').startsWith('legacy-')
                ? 'legacy'
                : (int.tryParse(json['tracked_seconds']?.toString() ?? '') ??
                            0) >
                        0
                    ? 'stopwatch'
                    : 'manual'),
      );
}

List<TimeBooking> splitTrackedTime({
  required String sessionId,
  required String taskId,
  required String taskText,
  required DateTime startedAt,
  required DateTime endedAt,
}) {
  final bookings = <TimeBooking>[];
  var start = startedAt.toLocal();
  final end = endedAt.toLocal();
  while (start.isBefore(end)) {
    final nextDay = DateTime(start.year, start.month, start.day + 1);
    final segmentEnd = nextDay.isBefore(end) ? nextDay : end;
    final seconds = segmentEnd.difference(start).inSeconds;
    if (seconds > 0) {
      final date = '${start.year.toString().padLeft(4, '0')}-'
          '${start.month.toString().padLeft(2, '0')}-'
          '${start.day.toString().padLeft(2, '0')}';
      bookings.add(TimeBooking(
        id: '$sessionId-$date',
        bookingDate: date,
        bookingTime: '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}',
        bookedMinutes: 0,
        trackedSeconds: seconds,
        source: 'stopwatch',
        taskId: taskId,
        taskText: taskText,
      ));
    }
    start = segmentEnd;
  }
  return bookings;
}
