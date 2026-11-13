import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/support_access_rules.dart';
import '../providers/platform_console_providers.dart';

/// Asks why access is needed and for how long, then opens a read-only support
/// session. The reason is shown to the school's administrators and kept in the
/// audit log, so it must say something real.
class RequestSupportAccessDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String schoolName;

  const RequestSupportAccessDialog({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  ConsumerState<RequestSupportAccessDialog> createState() =>
      _RequestSupportAccessDialogState();
}

class _RequestSupportAccessDialogState
    extends ConsumerState<RequestSupportAccessDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _ticket = TextEditingController();
  int _minutes = SupportAccessRules.defaultMinutes;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _ticket.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final ok = await ref
        .read(platformConsoleActionsProvider.notifier)
        .startSupportSession(
          schoolId: widget.schoolId,
          schoolName: widget.schoolName,
          reason: _reason.text,
          ticket: _ticket.text,
          minutes: _minutes,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(
        () => _error = userMessageFor(
          ref.read(platformConsoleActionsProvider).error!,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformConsoleActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Support access: ${widget.schoolName}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You will be able to LOOK at this school\'s screens, not '
                  'change anything. The school\'s administrators can see who '
                  'looked, why and until when, and can end it at any time.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('support-reason'),
                  controller: _reason,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: SupportAccessRules.reasonMax,
                  decoration: const InputDecoration(
                    labelText: 'Why do you need access?',
                    helperText: 'Shown to the school. Be specific.',
                  ),
                  validator: SupportAccessRules.validateReason,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const ValueKey('support-ticket'),
                  controller: _ticket,
                  enabled: !busy,
                  maxLength: SupportAccessRules.ticketMax,
                  decoration: const InputDecoration(
                    labelText: 'Ticket or reference (optional)',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                DropdownButtonFormField<int>(
                  key: const ValueKey('support-minutes'),
                  value: _minutes,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Access for'),
                  items: [
                    for (final m in SupportAccessRules.minutes)
                      DropdownMenuItem(
                        value: m,
                        child: Text(SupportAccessRules.durationLabel(m)),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _minutes = v ?? _minutes),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('support-start'),
          onPressed: busy ? null : _start,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Start session'),
        ),
      ],
    );
  }
}
