import 'package:flutter/material.dart';
import 'package:simple_present/link_patterns.dart';

class LinkPatternSettings extends StatelessWidget {
  const LinkPatternSettings({
    super.key,
    required this.rules,
    required this.onChanged,
  });

  final List<LinkPattern> rules;
  final ValueChanged<List<LinkPattern>> onChanged;

  Future<void> _edit(BuildContext context, [int? index]) async {
    final rule = index == null ? null : rules[index];
    var pattern = rule?.pattern ?? '';
    var url = rule?.urlTemplate ?? '';
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<LinkPattern>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(index == null ? 'New link rule' : 'Edit link rule'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: pattern,
                    onChanged: (value) => pattern = value,
                    decoration: const InputDecoration(
                      labelText: 'Pattern (regular expression)',
                      hintText: r'PLS-\d+',
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty)
                        return 'Pattern is required';
                      try {
                        RegExp(value!);
                      } on FormatException {
                        return 'Invalid regular expression';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    initialValue: url,
                    onChanged: (value) => url = value,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL template',
                      hintText: 'https://example.com/jira/%PID%',
                    ),
                    validator: (value) => LinkPattern(
                      pattern: r'\S+',
                      urlTemplate: (value ?? '').trim(),
                    ).validate(),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                  context,
                  LinkPattern(
                    pattern: pattern.trim(),
                    urlTemplate: url.trim(),
                  ));
            },
            child: const Text('save'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    final updated = List<LinkPattern>.of(rules);
    if (index == null) {
      updated.add(result);
    } else {
      updated[index] = result;
    }
    onChanged(updated);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ticket link rules',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          for (var index = 0; index < rules.length; index++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(rules[index].pattern),
              subtitle: Text(rules[index].urlTemplate),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'edit link rule',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, index),
                  ),
                  IconButton(
                    tooltip: 'delete link rule',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final updated = List<LinkPattern>.of(rules)
                        ..removeAt(index);
                      onChanged(updated);
                    },
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('new link rule'),
          ),
        ],
      );
}
