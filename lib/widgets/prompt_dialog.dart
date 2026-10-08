import 'package:flutter/material.dart';

class PromptField {
  final String label;
  final String initialValue;
  final int maxLines;
  final TextInputType keyboardType;

  const PromptField({
    required this.label,
    this.initialValue = '',
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });
}

/// Shows a simple dialog with one or more text fields and Cancel/Save
/// buttons. Returns the entered values in the same order as [fields], or
/// null if cancelled.
Future<List<String>?> showPromptDialog(
  BuildContext context, {
  required String title,
  required List<PromptField> fields,
  String confirmLabel = 'Save',
}) {
  final controllers = fields.map((f) => TextEditingController(text: f.initialValue)).toList();

  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              TextField(
                controller: controllers[i],
                maxLines: fields[i].maxLines,
                keyboardType: fields[i].keyboardType,
                autofocus: i == 0,
                decoration: InputDecoration(hintText: fields[i].label),
              ),
              if (i != fields.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            controllers.map((c) => c.text.trim()).toList(),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool isDanger = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: isDanger
              ? FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error)
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
