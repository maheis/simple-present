class LinkPattern {
  const LinkPattern({required this.pattern, required this.urlTemplate});

  final String pattern;
  final String urlTemplate;

  String? validate() {
    if (pattern.trim().isEmpty) return 'Pattern is required';
    try {
      RegExp(pattern);
    } on FormatException {
      return 'Invalid regular expression';
    }
    if (!urlTemplate.contains('%PID%')) return 'URL must contain %PID%';
    final uri = Uri.tryParse(urlTemplate.replaceAll('%PID%', 'TEST-1'));
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return 'Enter a valid http or https URL';
    }
    return null;
  }

  Map<String, String> toJson() => {'pattern': pattern, 'url': urlTemplate};

  static LinkPattern? fromJson(dynamic value) {
    if (value is! Map) return null;
    final rule = LinkPattern(
      pattern: value['pattern']?.toString() ?? '',
      urlTemplate: value['url']?.toString() ?? '',
    );
    return rule.validate() == null ? rule : null;
  }
}

List<LinkPattern> linkPatternsFromJson(dynamic value) {
  if (value is! List) return [];
  return value.map(LinkPattern.fromJson).whereType<LinkPattern>().toList();
}

class TaskLinkMatch {
  const TaskLinkMatch({
    required this.start,
    required this.end,
    required this.text,
    required this.uri,
  });

  final int start;
  final int end;
  final String text;
  final Uri uri;
}

List<TaskLinkMatch> findTaskLinks(String text, List<LinkPattern> rules) {
  final matches = <({TaskLinkMatch match, int priority})>[];
  for (var priority = 0; priority < rules.length; priority++) {
    final rule = rules[priority];
    if (rule.validate() != null) continue;
    for (final match in RegExp(rule.pattern).allMatches(text)) {
      if (match.start == match.end) continue;
      final matched = match.group(0)!;
      final uri = Uri.tryParse(
          rule.urlTemplate.replaceAll('%PID%', Uri.encodeComponent(matched)));
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) continue;
      matches.add((
        match: TaskLinkMatch(
          start: match.start,
          end: match.end,
          text: matched,
          uri: uri,
        ),
        priority: priority,
      ));
    }
  }
  matches.sort((first, second) {
    final start = first.match.start.compareTo(second.match.start);
    if (start != 0) return start;
    final length = second.match.end.compareTo(first.match.end);
    return length != 0 ? length : first.priority.compareTo(second.priority);
  });
  final nonOverlapping = <TaskLinkMatch>[];
  var end = 0;
  for (final candidate in matches) {
    final match = candidate.match;
    if (match.start < end) continue;
    nonOverlapping.add(match);
    end = match.end;
  }
  return nonOverlapping;
}
