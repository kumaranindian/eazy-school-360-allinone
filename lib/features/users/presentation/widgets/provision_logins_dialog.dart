import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/login_provisioning.dart';
import '../providers/login_provisioning_providers.dart';

/// One person to give a login to, as the list pages know them.
typedef LoginCandidate = ({String id, String name, String? email});

/// Confirms, runs and reports "give login access" for one or many staff or
/// parents. Each person ends up with their own outcome; nobody is changed
/// silently, and people without a usable email are listed, not skipped
/// quietly. New accounts get a "set your password" email — no password is
/// ever shown or stored here.
class ProvisionLoginsDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final LoginKind kind;
  final List<LoginCandidate> people;

  /// May this admin create branch admins (school admins only)?
  final bool canGrantBranchAdmin;

  const ProvisionLoginsDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.people,
    this.canGrantBranchAdmin = false,
  });

  @override
  ConsumerState<ProvisionLoginsDialog> createState() =>
      _ProvisionLoginsDialogState();
}

class _ProvisionLoginsDialogState extends ConsumerState<ProvisionLoginsDialog> {
  UserRole _staffRole = UserRole.finance;
  bool _enablePortal = true;
  bool _running = false;
  String? _error;
  List<ProvisionResult>? _results;
  final Map<String, TextEditingController> _emailControllers = {};
  int _emailed = 0;
  int _emailFailed = 0;

  bool get _isStaff => widget.kind == LoginKind.staff;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  @override
  void initState() {
    super.initState();
    for (final p in widget.people) {
      if ((p.email ?? '').trim().isEmpty) {
        _emailControllers[p.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _emailControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Emails typed for people who had none (blank ones are left out and so
  /// get skipped by the server).
  Map<String, String> get _typedEmails => {
    for (final e in _emailControllers.entries)
      if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
  };

  bool get _typedEmailsValid =>
      _typedEmails.values.every(_emailPattern.hasMatch);

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(loginProvisionerProvider)
          .provision(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            kind: widget.kind,
            ids: [for (final p in widget.people) p.id],
            staffRole: _isStaff ? _staffRole : null,
            enablePortal: !_isStaff && _enablePortal,
            emails: _typedEmails,
          );
      var sent = 0;
      var failed = 0;
      final auth = ref.read(authRepositoryProvider);
      for (final r in results) {
        if (r.outcome != ProvisionOutcome.created ||
            !r.newAccount ||
            r.email == null) {
          continue;
        }
        try {
          await auth.sendPasswordResetEmail(r.email!);
          sent++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      setState(() {
        _results = results;
        _emailed = sent;
        _emailFailed = failed;
      });
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = _results;
    final noun = _isStaff ? 'staff' : 'parent';
    final n = widget.people.length;

    if (results != null) {
      final created = results
          .where((r) => r.outcome == ProvisionOutcome.created)
          .length;
      final skipped = results
          .where((r) => r.outcome != ProvisionOutcome.created)
          .toList();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Login access', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              '$created of ${results.length} login${results.length == 1 ? '' : 's'} created.'
              '${_emailed > 0 ? ' $_emailed set-password email${_emailed == 1 ? '' : 's'} sent.' : ''}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (_emailFailed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '$_emailFailed set-password email${_emailFailed == 1 ? '' : 's'} '
                'could not be sent. Those people can use "Forgot password" '
                'on the sign-in page.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Not changed', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final r in skipped)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(r.name ?? r.id),
                subtitle: Text(r.outcome.label),
              ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Done'),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Give login access', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          'Create a sign-in for $n $noun${n == 1 ? '' : 's'}. Each person '
          'gets an email to set their own password, using the email on '
          'their record.',
        ),
        if (_emailControllers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'No email on record — enter one to give them a login, or leave '
            'blank to skip.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          for (final p in widget.people)
            if (_emailControllers[p.id] case final c?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: c,
                  enabled: !_running,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: '${p.name} — email',
                    isDense: true,
                    errorText:
                        c.text.trim().isNotEmpty &&
                            !_emailPattern.hasMatch(c.text.trim())
                        ? 'Not a valid email'
                        : null,
                  ),
                ),
              ),
        ],
        if (_isStaff) ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<UserRole>(
            value: _staffRole,
            decoration: const InputDecoration(
              labelText: 'Role for non-teaching staff',
              helperText: 'Teachers always get the Teacher role.',
            ),
            items: [
              const DropdownMenuItem(
                value: UserRole.finance,
                child: Text('Finance'),
              ),
              const DropdownMenuItem(
                value: UserRole.teacher,
                child: Text('Teacher'),
              ),
              if (widget.canGrantBranchAdmin)
                const DropdownMenuItem(
                  value: UserRole.branchAdmin,
                  child: Text('Branch admin'),
                ),
            ],
            onChanged: _running
                ? null
                : (v) => setState(() => _staffRole = v ?? _staffRole),
          ),
        ] else
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _enablePortal,
            onChanged: _running
                ? null
                : (v) => setState(() => _enablePortal = v ?? true),
            title: const Text('Allow portal access to their children'),
            subtitle: const Text(
              'Lets them see their linked children\'s homework, fees, '
              'results and timetable. Without it they can sign in but see '
              'nothing.',
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _running ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _running || !_typedEmailsValid ? null : _run,
              child: _running
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Create login${n == 1 ? '' : 's'}'),
            ),
          ],
        ),
      ],
    );
  }
}
