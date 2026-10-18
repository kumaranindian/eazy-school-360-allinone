import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../../core/errors/app_failure.dart';
import '../../domain/login_provisioning.dart';
import '../../domain/resilient_batches.dart';
import '../providers/login_provisioning_providers.dart';
import 'password_setup_picker.dart';

/// One person to give a login to, as the list pages know them.
typedef LoginCandidate = ({String id, String name, String? email});

/// Confirms, runs and reports "give login access" for one or many staff or
/// parents. Each person ends up with their own outcome; nobody is changed
/// silently, and people without a usable email are listed, not skipped
/// quietly. The admin picks how the first password is set (see
/// [PasswordSetupOption]); a password typed or generated here is sent to the
/// server once and never stored, logged or kept after the dialog closes.
/// Editing the email of someone who already has a login moves that login to
/// the new email (the old one stops working).
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

  /// Latest outcome per person. A retry replaces only the people it re-ran,
  /// so what already succeeded is never repeated or lost.
  final Map<String, ProvisionResult> _byId = {};
  List<ProvisionResult> _emailsToSend = const [];
  String _phase = '';
  int _done = 0;
  int _total = 0;
  bool _stopRequested = false;
  final Map<String, TextEditingController> _emailControllers = {};
  int _emailed = 0;
  PasswordSetupOption _option = PasswordSetupOption.activationEmail;
  final _adminPassword = TextEditingController();
  final _adminPasswordConfirm = TextEditingController();
  bool _showPassword = false;

  /// Beyond this many people the dialog stays a plain confirm: editing a long
  /// list of emails belongs in the record itself.
  static const _editAllEmailsUpTo = 20;

  bool get _isStaff => widget.kind == LoginKind.staff;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  @override
  void initState() {
    super.initState();
    final editAll = widget.people.length <= _editAllEmailsUpTo;
    for (final p in widget.people) {
      final email = (p.email ?? '').trim();
      if (email.isEmpty) {
        _emailControllers[p.id] = TextEditingController();
      } else if (editAll) {
        _emailControllers[p.id] = TextEditingController(text: email);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _emailControllers.values) {
      c.dispose();
    }
    _adminPassword.dispose();
    _adminPasswordConfirm.dispose();
    super.dispose();
  }

  String _originalEmail(String id) =>
      widget.people.firstWhere((p) => p.id == id).email?.trim().toLowerCase() ??
      '';

  bool get _passwordSetupValid => PasswordSetupPicker.isValid(
    _option,
    _adminPassword.text,
    _adminPasswordConfirm.text,
  );

  /// Emails typed for people who had none, plus emails edited for people who
  /// had one (unchanged ones are left out). Blank ones are skipped by the
  /// server.
  Map<String, String> get _typedEmails => {
    for (final e in _emailControllers.entries)
      if (e.value.text.trim().isNotEmpty &&
          e.value.text.trim().toLowerCase() != _originalEmail(e.key))
        e.key: e.value.text.trim(),
  };

  bool get _typedEmailsValid =>
      _typedEmails.values.every(_emailPattern.hasMatch);

  /// Network trouble and throttling are worth another try; a rejected
  /// address or a configuration problem is not.
  static bool _emailTransient(Object e) =>
      e is NetworkFailure || e is AuthFailure || e is UnknownFailure;

  bool _wantsEmail(ProvisionResult r) {
    if (!_option.sendsEmail || r.email == null) return false;
    // Activation: only brand-new accounts and moved emails. The reset link
    // also goes to logins that already existed and were mapped.
    return r.outcome == ProvisionOutcome.emailUpdated ||
        (r.outcome == ProvisionOutcome.created &&
            (r.newAccount || _option == PasswordSetupOption.resetLink));
  }

  void _progress(String phase, int done, int total) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _done = done;
      _total = total;
    });
  }

  /// Creates the logins for [ids] (everyone on the first run, only the
  /// unfinished ones on a retry), then sends the set-password emails — both
  /// in small, throttled steps with retries, so a long list neither times out
  /// nor trips rate limits.
  Future<void> _run({List<String>? onlyIds}) async {
    final ids = onlyIds ?? [for (final p in widget.people) p.id];
    setState(() {
      _running = true;
      _stopRequested = false;
      _error = null;
    });
    _progress('Creating logins', 0, ids.length);
    try {
      final fresh = await ref
          .read(loginProvisionerProvider)
          .provision(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            kind: widget.kind,
            ids: ids,
            staffRole: _isStaff ? _staffRole : null,
            enablePortal: !_isStaff && _enablePortal,
            emails: _typedEmails,
            passwordSetup: PasswordSetup(
              _option,
              password: _option == PasswordSetupOption.adminDefined
                  ? _adminPassword.text
                  : null,
            ),
            onProgress: (d, t) => _progress('Creating logins', d, t),
            isCancelled: () => _stopRequested,
          );
      for (final r in fresh) {
        _byId[r.id] = r;
      }
      await _sendEmails([...fresh.where(_wantsEmail), ..._emailsToSend]);
    } catch (e) {
      if (mounted) {
        // Whatever finished before the error stays; the rest can be retried.
        setState(() => _error = userMessageFor(e));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _sendEmails(List<ProvisionResult> targets) async {
    final unique = {for (final r in targets) r.id: r}.values.toList();
    if (unique.isEmpty) {
      _emailsToSend = const [];
      return;
    }
    final auth = ref.read(authRepositoryProvider);
    _progress('Sending emails', 0, unique.length);
    final failed = await sendThrottled<ProvisionResult>(
      items: unique,
      send: (r) => auth.sendPasswordResetEmail(r.email!),
      isTransient: _emailTransient,
      onProgress: (d, t) => _progress('Sending emails', d, t),
      isCancelled: () => _stopRequested,
    );
    if (!mounted) return;
    setState(() {
      _emailed += unique.length - failed.length;
      _emailsToSend = failed;
    });
  }

  Future<void> _resendEmails() async {
    setState(() {
      _running = true;
      _stopRequested = false;
    });
    try {
      await _sendEmails(List.of(_emailsToSend));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Widget _progressBlock(ThemeData theme) {
    final stopping = _stopRequested;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            stopping
                ? 'Stopping after the current step…'
                : '$_phase — $_done of $_total',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _total == 0 ? null : (_done / _total).clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          Text(
            'Please keep this window open. Large lists are processed in small '
            'steps; anything that fails can be retried afterwards without '
            'duplicating logins.',
            style: theme.textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: stopping
                  ? null
                  : () => setState(() => _stopRequested = true),
              child: const Text('Stop'),
            ),
          ),
        ],
      ),
    );
  }

  void _downloadPasswords(List<ProvisionResult> rows) {
    final csv = StringBuffer('name,email,temporary_password\n');
    String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    for (final r in rows) {
      csv.writeln('${q(r.name)},${q(r.email)},${q(r.tempPassword)}');
    }
    FilePicker.saveFile(
      dialogTitle: 'Save temporary passwords',
      fileName: 'temporary_passwords.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv.toString())),
    );
  }

  Widget _passwordSection() => PasswordSetupPicker(
    heading: 'How should the first password be set?',
    option: _option,
    onOptionChanged: (v) => setState(() => _option = v),
    password: _adminPassword,
    confirm: _adminPasswordConfirm,
    showPassword: _showPassword,
    onToggleShowPassword: () => setState(() => _showPassword = !_showPassword),
    onChanged: () => setState(() {}),
    enabled: !_running,
  );

  @override
  Widget build(BuildContext context) {
    // Closing mid-run would leave a half-finished batch with no report.
    return PopScope(canPop: !_running, child: _buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final results = [
      for (final p in widget.people)
        if (_byId[p.id] case final r?) r,
    ];
    final noun = _isStaff ? 'staff' : 'parent';
    final n = widget.people.length;

    if (results.isNotEmpty) {
      final created = results
          .where((r) => r.outcome == ProvisionOutcome.created)
          .length;
      final moved = results
          .where((r) => r.outcome == ProvisionOutcome.emailUpdated)
          .length;
      final retry = results
          .where((r) => r.outcome == ProvisionOutcome.retryLater)
          .toList();
      final skipped = results
          .where(
            (r) =>
                r.outcome != ProvisionOutcome.created &&
                r.outcome != ProvisionOutcome.emailUpdated &&
                r.outcome != ProvisionOutcome.retryLater,
          )
          .toList();
      final temps = results.where((r) => r.tempPassword != null).toList();
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
              '${moved > 0 ? ' $moved email${moved == 1 ? '' : 's'} changed (the new email is active, the old one no longer signs in).' : ''}'
              '${_emailed > 0 ? ' $_emailed set-password email${_emailed == 1 ? '' : 's'} sent.' : ''}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_running)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _progressBlock(theme),
            ),
          if (!_running && _emailsToSend.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_emailsToSend.length} set-password '
                    'email${_emailsToSend.length == 1 ? '' : 's'} could not be '
                    'sent. Resend them, or those people can use "Forgot '
                    'password" on the sign-in page.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _resendEmails,
                    icon: const Icon(Icons.forward_to_inbox_outlined),
                    label: const Text('Resend emails'),
                  ),
                ],
              ),
            ),
          if (!_running && retry.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${retry.length} '
                    'person${retry.length == 1 ? '' : 's'} could not be '
                    'completed (network or server busy). Nothing was changed '
                    'for them; retrying is safe.',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () =>
                        _run(onlyIds: [for (final r in retry) r.id]),
                    icon: const Icon(Icons.refresh),
                    label: Text('Retry ${retry.length}'),
                  ),
                ],
              ),
            ),
          if (temps.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Temporary passwords are shown only now and are not saved. '
              'Download them and hand them over securely; each person must '
              'change theirs at first sign-in.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _downloadPasswords(temps),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download passwords (CSV)'),
            ),
          ],
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
              onPressed: _running
                  ? null
                  : () => Navigator.of(context).pop(true),
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
          'Create a sign-in for $n $noun${n == 1 ? '' : 's'} using the email on '
          'their record. Google and phone-code sign-in are not affected; a '
          'password is only set where the school allows email & password.',
        ),
        if (_emailControllers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Enter an email for anyone without one (leave blank to skip). '
            'Changing an existing email moves their login to the new address — '
            'the new email becomes active and the old one stops working.',
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
                    labelText: (p.email ?? '').trim().isEmpty
                        ? '${p.name} — email'
                        : '${p.name} — email (edit to change)',
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
            isExpanded: true,
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
        const SizedBox(height: 16),
        _passwordSection(),
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
        if (_running)
          _progressBlock(theme)
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _running ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed:
                    _running || !_typedEmailsValid || !_passwordSetupValid
                    ? null
                    : _run,
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
