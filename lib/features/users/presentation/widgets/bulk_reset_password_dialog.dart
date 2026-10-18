import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/login_provisioning.dart';
import '../../domain/password_reset.dart';
import '../../domain/resilient_batches.dart';
import '../providers/login_access_providers.dart';
import 'password_setup_picker.dart';
import 'provision_logins_dialog.dart' show LoginCandidate;

/// Sets a new password for many staff or parents who already have a login,
/// with the same five choices as when logins are created. The link options
/// email each person a set-password link; the others set the password on the
/// server (everyone must change it at next sign-in and is signed out of every
/// device). Every person gets an outcome, nobody is changed silently, and a
/// password typed or generated here is sent once and never stored. Resolves
/// to true when anything was done.
Future<bool?> showBulkResetPasswordDialog({
  required BuildContext context,
  required String schoolId,
  required String branchId,
  required LoginKind kind,
  required List<LoginCandidate> people,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => BulkResetPasswordDialog(
    schoolId: schoolId,
    branchId: branchId,
    kind: kind,
    people: people,
  ),
);

class BulkResetPasswordDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final LoginKind kind;
  final List<LoginCandidate> people;

  const BulkResetPasswordDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.people,
  });

  @override
  ConsumerState<BulkResetPasswordDialog> createState() =>
      _BulkResetPasswordDialogState();
}

class _BulkResetPasswordDialogState
    extends ConsumerState<BulkResetPasswordDialog> {
  PasswordSetupOption _option = PasswordSetupOption.activationEmail;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPassword = false;
  bool _running = false;
  bool _stopRequested = false;
  String _phase = '';
  int _done = 0;
  int _total = 0;
  String? _error;

  /// Latest outcome per person; a retry replaces only the people it re-ran.
  final Map<String, PasswordResetResult> _byId = {};

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _nameOf(String id) => widget.people.firstWhere((p) => p.id == id).name;

  bool get _canRun =>
      !_running &&
      widget.people.isNotEmpty &&
      PasswordSetupPicker.isValid(_option, _password.text, _confirm.text);

  void _progress(String phase, int done, int total) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _done = done;
      _total = total;
    });
  }

  static bool _emailTransient(Object e) =>
      e is NetworkFailure || e is AuthFailure || e is UnknownFailure;

  Future<void> _run({List<String>? onlyIds}) async {
    final ids = onlyIds ?? [for (final p in widget.people) p.id];
    setState(() {
      _running = true;
      _stopRequested = false;
      _error = null;
    });
    try {
      if (_option.sendsEmail) {
        await _sendLinks(ids);
      } else {
        _progress('Resetting passwords', 0, ids.length);
        final fresh = await ref
            .read(loginAccessRepositoryProvider)
            .resetPasswords(
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              kind: widget.kind,
              ids: ids,
              passwordSetup: PasswordSetup(
                _option,
                password: _option == PasswordSetupOption.adminDefined
                    ? _password.text
                    : null,
              ),
              onProgress: (d, t) => _progress('Resetting passwords', d, t),
              isCancelled: () => _stopRequested,
            );
        for (final r in fresh) {
          _byId[r.id] = PasswordResetResult(
            id: r.id,
            name: r.name ?? _nameOf(r.id),
            outcome: r.outcome,
            tempPassword: r.tempPassword,
          );
        }
      }
    } catch (e) {
      // Whatever finished before the error stays; the rest can be retried.
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _sendLinks(List<String> ids) async {
    final auth = ref.read(authRepositoryProvider);
    final targets = [
      for (final id in ids) widget.people.firstWhere((p) => p.id == id),
    ];
    final withEmail = <LoginCandidate>[];
    for (final p in targets) {
      if ((p.email ?? '').trim().isEmpty) {
        _byId[p.id] = PasswordResetResult(
          id: p.id,
          name: p.name,
          outcome: PasswordResetOutcome.noEmail,
        );
      } else {
        withEmail.add(p);
      }
    }
    _progress('Sending emails', 0, withEmail.length);
    final failed = await sendThrottled<LoginCandidate>(
      items: withEmail,
      send: (p) => auth.sendPasswordResetEmail(p.email!.trim()),
      isTransient: _emailTransient,
      onProgress: (d, t) => _progress('Sending emails', d, t),
      isCancelled: () => _stopRequested,
    );
    final failedIds = {for (final p in failed) p.id};
    for (final p in withEmail) {
      _byId[p.id] = PasswordResetResult(
        id: p.id,
        name: p.name,
        outcome: failedIds.contains(p.id)
            ? PasswordResetOutcome.emailFailed
            : PasswordResetOutcome.reset,
      );
    }
  }

  void _downloadPasswords(List<PasswordResetResult> rows) {
    final csv = StringBuffer('name,temporary_password\n');
    String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    for (final r in rows) {
      csv.writeln('${q(r.name)},${q(r.tempPassword)}');
    }
    FilePicker.saveFile(
      dialogTitle: 'Save temporary passwords',
      fileName: 'temporary_passwords.csv',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      bytes: Uint8List.fromList(utf8.encode(csv.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = [
      for (final p in widget.people)
        if (_byId[p.id] case final r?) r,
    ];
    return PopScope(
      canPop: !_running,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reset passwords', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: results.isEmpty && !_running
                        ? _form(theme)
                        : _report(theme, results),
                  ),
                ),
                const SizedBox(height: 16),
                _actions(results),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(ThemeData theme) {
    final n = widget.people.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set a new password for $n '
          '${widget.kind == LoginKind.staff ? 'staff member' : 'parent'}'
          '${n == 1 ? '' : 's'} who already ${n == 1 ? 'has' : 'have'} a '
          'login. Choose how, the same as when logins are created.',
        ),
        const SizedBox(height: 12),
        PasswordSetupPicker(
          heading: 'How should the new passwords be set?',
          option: _option,
          onOptionChanged: (v) => setState(() => _option = v),
          password: _password,
          confirm: _confirm,
          showPassword: _showPassword,
          onToggleShowPassword: () =>
              setState(() => _showPassword = !_showPassword),
          onChanged: () => setState(() {}),
          enabled: !_running,
        ),
        if (_option.sendsEmail)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'People without an email on their record are listed and skipped.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _report(ThemeData theme, List<PasswordResetResult> results) {
    final done = results.where((r) => r.isReset).length;
    final retry = results
        .where((r) => r.outcome == PasswordResetOutcome.retryLater)
        .toList();
    final skipped = results
        .where(
          (r) => !r.isReset && r.outcome != PasswordResetOutcome.retryLater,
        )
        .toList();
    final temps = results.where((r) => r.tempPassword != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            _option.sendsEmail
                ? '$done of ${results.length} set-password '
                      'email${results.length == 1 ? '' : 's'} sent.'
                : '$done of ${results.length} '
                      'password${results.length == 1 ? '' : 's'} reset. '
                      'They must change it at next sign-in.',
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
        if (!_running && retry.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${retry.length} could not be completed (network or server '
                  'busy). Nothing was changed for them; retrying is safe.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _run(onlyIds: [for (final r in retry) r.id]),
                  icon: const Icon(Icons.refresh),
                  label: Text('Retry ${retry.length}'),
                ),
              ],
            ),
          ),
        if (temps.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Temporary passwords are shown only now and are not saved. '
            'Download them and hand them over securely.',
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
          for (final r in skipped)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(r.name ?? _nameOf(r.id)),
              subtitle: Text(r.outcome.label),
            ),
        ],
      ],
    );
  }

  Widget _progressBlock(ThemeData theme) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _stopRequested
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
        const Text('Please keep this window open.'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _stopRequested
                ? null
                : () => setState(() => _stopRequested = true),
            child: const Text('Stop'),
          ),
        ),
      ],
    ),
  );

  Widget _actions(List<PasswordResetResult> results) {
    final started = results.isNotEmpty || _running;
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (!started)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          FilledButton(
            onPressed: started
                ? (_running ? null : () => Navigator.of(context).pop(true))
                : _canRun
                ? _run
                : null,
            child: Text(
              started
                  ? 'Done'
                  : _option.sendsEmail
                  ? 'Send emails'
                  : 'Reset passwords',
            ),
          ),
        ],
      ),
    );
  }
}
