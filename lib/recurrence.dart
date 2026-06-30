DateTime? computeNextRecurrence(DateTime base, String recurrence) {
  try {
    final s = recurrence.trim();
    if (s.isEmpty) return null;

    // DAILY variants
    if (s.startsWith('daily')) {
      if (s == 'daily') {
        return DateTime(base.year, base.month, base.day + 1, base.hour, base.minute, base.second);
      }
      final parts = s.split(':');
      if (parts.length > 1) {
        final daysPart = parts[1];
        final allowed = <int>{};
        for (final p in daysPart.split(',')) {
          final n = int.tryParse(p.trim());
          if (n != null && n >= 1 && n <= 7) allowed.add(n);
        }
        if (allowed.isEmpty) return DateTime(base.year, base.month, base.day + 1, base.hour, base.minute, base.second);
        for (int i = 1; i <= 30; i++) {
          final cand = base.add(Duration(days: i));
          if (allowed.contains(cand.weekday)) return DateTime(cand.year, cand.month, cand.day, base.hour, base.minute, base.second);
        }
        return null;
      }
    }

    // WEEKLY variants
    if (s.startsWith('weekly')) {
      final parts = s.split(':');
      if (parts.length == 1) return base.add(const Duration(days: 7));
      final n = int.tryParse(parts[1]);
      if (n != null && n > 0) return base.add(Duration(days: 7 * n));
      return base.add(const Duration(days: 7));
    }

    // MONTHLY variants
    if (s.startsWith('monthly')) {
      final after = s.contains(':') ? s.split(':').sublist(1).join(':') : '';
      if (after.isEmpty) {
        int y = base.year;
        int m = base.month + 1;
        if (m > 12) { m = 1; y += 1; }
        final lastDay = DateTime(y, m + 1, 0).day;
        final d = base.day <= lastDay ? base.day : lastDay;
        return DateTime(y, m, d, base.hour, base.minute, base.second);
      }
      try {
        if (after.startsWith('day=')) {
          final v = int.tryParse(after.substring(4));
          if (v != null && v >= 1 && v <= 31) {
            for (int add = 1; add <= 24; add++) {
              int y = base.year + ((base.month - 1 + add) ~/ 12);
              int m = ((base.month - 1 + add) % 12) + 1;
              final lastDay = DateTime(y, m + 1, 0).day;
              final day = v <= lastDay ? v : lastDay;
              final cand = DateTime(y, m, day, base.hour, base.minute, base.second);
              if (cand.isAfter(base)) return cand;
            }
            return null;
          }
        }
        if (after.startsWith('weekday=')) {
          final rest = after.substring('weekday='.length);
          final parts2 = rest.split(':');
          if (parts2.length >= 2) {
            final which = parts2[0];
            final wd = int.tryParse(parts2[1]);
            if (wd != null && wd >= 1 && wd <= 7) {
              for (int add = 1; add <= 24; add++) {
                int y = base.year + ((base.month - 1 + add) ~/ 12);
                int m = ((base.month - 1 + add) % 12) + 1;
                DateTime cand;
                if (which == 'first') {
                  final firstOfMonth = DateTime(y, m, 1);
                  int offset = (wd - firstOfMonth.weekday) % 7;
                  if (offset < 0) offset += 7;
                  cand = firstOfMonth.add(Duration(days: offset));
                } else {
                  final lastDayDate = DateTime(y, m + 1, 0);
                  int offset = (lastDayDate.weekday - wd) % 7;
                  if (offset < 0) offset += 7;
                  cand = lastDayDate.subtract(Duration(days: offset));
                }
                cand = DateTime(cand.year, cand.month, cand.day, base.hour, base.minute, base.second);
                if (cand.isAfter(base)) return cand;
              }
            }
          }
        }
      } catch (_) {}
      return null;
    }

    // YEARLY
    if (s.startsWith('yearly')) {
      final parts = s.split(':');
      int years = 1;
      if (parts.length > 1) {
        final p = int.tryParse(parts[1]);
        if (p != null && p > 0) years = p;
      }
      try {
        final y = base.year + years;
        final m = base.month;
        final lastDay = DateTime(y, m + 1, 0).day;
        final d = base.day <= lastDay ? base.day : lastDay;
        return DateTime(y, m, d, base.hour, base.minute, base.second);
      } catch (_) { return null; }
    }

    return null;
  } catch (_) {
    return null;
  }
}
