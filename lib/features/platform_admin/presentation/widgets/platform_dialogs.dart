import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Asks the person to type a reason (shown to others and kept in the audit log)
/// before something that matters. Returns the trimmed reason, or null on cancel.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  String label = 'Reason',
  int minLength = 10,
  required String confirmLabel,
  bool destructive = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ReasonDialog(
    title: title,
    message: message,
    label: label,
    minLength: minLength,
    confirmLabel: confirmLabel,
    destructive: destructive,
  ),
);

class _ReasonDialog extends StatefulWidget {
  final String title;
  final String message;
  final String label;
  final int minLength;
  final String confirmLabel;
  final bool destructive;

  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.minLength,
    required this.confirmLabel,
    required this.destructive,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.message),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('reason-field'),
                  controller: _reason,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: InputDecoration(labelText: widget.label),
                  validator: (v) => (v ?? '').trim().length < widget.minLength
                      ? 'Give a little more detail (at least ${widget.minLength} characters)'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('reason-confirm'),
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () {
            if (_form.currentState?.validate() ?? false) {
              Navigator.pop(context, _reason.text.trim());
            }
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A yes/no question. Returns true when confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-yes'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(c).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;
