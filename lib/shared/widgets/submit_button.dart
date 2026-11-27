import 'package:flutter/material.dart';

import '../forms/submit_lock.dart';

/// The primary create/save/publish button: on the first tap it locks, shows a
/// spinner and ignores further taps until [onPressed] completes
/// (STU-01-DEF-01). [busy] keeps it locked for work the page tracks itself
/// (an upload, a save started from the keyboard).
class SubmitButton extends StatefulWidget {
  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final bool busy;
  final bool tonal;

  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.tonal = false,
  });

  @override
  State<SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<SubmitButton> {
  final _lock = SubmitLock();

  Future<void> _press() async {
    final action = widget.onPressed;
    if (action == null || widget.busy) return;
    final run = _lock.run(action);
    if (mounted) setState(() {});
    await run;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final working = widget.busy || _lock.busy;
    final onPressed = widget.onPressed == null || working ? null : _press;
    // Always a plain FilledButton (not .icon) so the widget type stays the
    // same while it is busy.
    final Widget? lead = working
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (widget.icon == null ? null : Icon(widget.icon, size: 18));
    final child = lead == null
        ? Text(widget.label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              lead,
              const SizedBox(width: 8),
              Flexible(child: Text(widget.label)),
            ],
          );
    return widget.tonal
        ? FilledButton.tonal(onPressed: onPressed, child: child)
        : FilledButton(onPressed: onPressed, child: child);
  }
}
