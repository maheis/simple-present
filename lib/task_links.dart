import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:simple_present/link_patterns.dart';
import 'package:url_launcher/url_launcher.dart';

typedef TaskLinkOpener = Future<bool> Function(Uri uri);

Future<void> _openLink(
    BuildContext context, Uri uri, TaskLinkOpener? openLink) async {
  try {
    final opened = openLink == null
        ? await launchUrl(uri, mode: LaunchMode.externalApplication)
        : await openLink(uri);
    if (opened) return;
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link')),
    );
  }
}

class TaskLinkText extends StatefulWidget {
  const TaskLinkText({
    super.key,
    required this.text,
    required this.rules,
    this.style,
    this.maxLines,
    this.overflow,
    this.openLink,
  });

  final String text;
  final List<LinkPattern> rules;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TaskLinkOpener? openLink;

  @override
  State<TaskLinkText> createState() => _TaskLinkTextState();
}

class _TaskLinkTextState extends State<TaskLinkText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final links = findTaskLinks(widget.text, widget.rules);
    if (links.isEmpty) {
      return Text(widget.text,
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow);
    }
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final link in links) {
      if (link.start > offset) {
        spans.add(TextSpan(text: widget.text.substring(offset, link.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap =
            () => unawaited(_openLink(context, link.uri, widget.openLink));
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: link.text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        recognizer: recognizer,
        mouseCursor: SystemMouseCursors.click,
      ));
      offset = link.end;
    }
    if (offset < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(offset)));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans),
        maxLines: widget.maxLines, overflow: widget.overflow);
  }
}

class TaskLinkActions extends StatelessWidget {
  const TaskLinkActions({
    super.key,
    required this.rules,
    this.text,
    this.controller,
    this.openLink,
  }) : assert((text == null) != (controller == null));

  final List<LinkPattern> rules;
  final String? text;
  final TextEditingController? controller;
  final TaskLinkOpener? openLink;

  Widget _buildLinks(BuildContext context, String value) {
    final links = findTaskLinks(value, rules);
    final seen = <String>{};
    final unique =
        links.where((link) => seen.add('${link.text}|${link.uri}')).toList();
    if (unique.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 4,
        children: [
          for (final link in unique)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Tooltip(
                message: link.uri.toString(),
                child: TextButton.icon(
                  onPressed: () => _openLink(context, link.uri, openLink),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(link.text,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = controller;
    if (input == null) return _buildLinks(context, text!);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: input,
      builder: (context, value, _) => _buildLinks(context, value.text),
    );
  }
}
