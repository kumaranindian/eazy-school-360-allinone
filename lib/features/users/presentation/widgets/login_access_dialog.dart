import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/layouts/detail_grid.dart';
import '../../../authentication/domain/login_method.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../domain/login_access.dart';
import '../../domain/login_provisioning.dart';
import '../providers/login_access_providers.dart';

/// Opens the per-person Login Access manager (the key icon on staff and
/// parent lists and profiles). Resolves to true when something changed.
Future<bool?> showLoginAccessDialog({
  required BuildContext context,
  required String schoolId,
  required String branchId,
  required LoginKind kind,
  required String id,
  String? fallbackName,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    // Own frame (not showAdaptiveAppDialog): the body scrolls but the
    // Cancel/Save row stays on screen however long the content gets.
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 40,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LoginAccessDialog(
            schoolId: schoolId,
            branchId: branchId,
            kind: kind,
            id: id,
            fallbackName: fallbackName,
          ),
        ),
      ),
    );
  },
);

/// Shows who the person is, how they can sign in and whether they have used
/// it; lets an administrator switch access on/off and choose the permitted
/// methods. Everything is enforced by the server (functions/access.js and
/// firestore.rules) — this dialog only requests the change.
class LoginAccessDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final LoginKind kind;
  final String id;
  final String? fallbackName;

  const LoginAccessDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.kind,
    required this.id,
    this.fallbackName,
  });

  @override
  ConsumerState<LoginAccessDialog> createState() => _LoginAccessDialogState();
}

class _LoginAccessDialogState extends ConsumerState<LoginAccessDialog> {
  LoginAccess? _access;
  bool _enabled = false;
  Set<LoginMethod> _selected = {};
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await ref
          .read(loginAccessRepositoryProvider)
          .getAccess(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            kind: widget.kind,
            id: widget.id,
          );
      if (!mounted) return;
      setState(() {
        _access = a;
        _enabled = a.hasAccount ? a.enabled : true;
        _selected = {
          ...(a.hasAccount && a.methods.isNotEmpty ? a.methods : _suggested(a)),
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userMessageFor(e);
        _loading = false;
      });
    }
  }

  /// A sensible starting selection for someone without a grant: what the
  /// school allows and the record can support.
  Set<LoginMethod> _suggested(LoginAccess a) => {
    for (final m in LoginMethod.values)
      if (LoginAccessRules.blocker(m, a) == null && m != LoginMethod.phoneOtp)
        m,
  };

  bool get _dirty {
    final a = _access;
    if (a == null) return false;
    if (!a.hasAccount) return _enabled;
    return LoginAccessRules.changed(a, enabled: _enabled, selected: _selected);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save({bool revokeOnly = false}) async {
    final a = _access!;
    if (_saving) return; // prevent duplicate submissions
    if (!revokeOnly) {
      final problem = LoginAccessRules.validate(
        a,
        enabled: _enabled,
        selected: _selected,
      );
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
      final narrows = LoginAccessRules.narrows(
        a,
        enabled: _enabled,
        selected: _selected,
      );
      final ok = await _confirm(
        title: !_enabled
            ? 'Turn off login for ${a.name}?'
            : narrows
            ? 'Remove sign-in methods?'
            : 'Save login access?',
        body: !_enabled
            ? 'They will be signed out of every device and will not be able '
                  'to sign in until you turn access back on. Their records and '
                  'history are kept.'
            : narrows
            ? 'Methods you removed stop working now, and ${a.name} is signed '
                  'out of their devices.'
            : 'Allowed: ${_selected.map((m) => m.label).join(', ')}.',
        action: !_enabled ? 'Turn off' : 'Save',
        destructive: !_enabled || narrows,
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final res = await ref
          .read(loginAccessRepositoryProvider)
          .setAccess(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            kind: widget.kind,
            id: widget.id,
            enabled: revokeOnly ? a.enabled : _enabled,
            methods: revokeOnly ? a.methods : _selected.toList(),
            revokeSessions: revokeOnly,
          );
      _changed = true;
      if (!mounted) return;
      setState(() => _saving = false);
      await _load();
      if (!mounted) return;
      setState(
        () => _notice = revokeOnly
            ? 'Signed out of all devices.'
            : res.created
            ? 'Login created. Send a password setup email if they will use a password.'
            : 'Saved.${res.revoked ? ' Existing sessions were signed out.' : ''}',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userMessageFor(e);
      });
    }
  }

  Future<void> _sendSetup() async {
    final email = _access?.registeredEmail;
    if (email == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = 'A password setup email was sent to $email.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userMessageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = _access;
    final title = a?.name.isNotEmpty == true
        ? a!.name
        : (widget.fallbackName ?? 'Login access');

    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {},
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.vpn_key_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Login access',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (a == null)
                      _ErrorBox(
                        message: _error ?? 'Could not load login access.',
                      )
                    else
                      ..._body(context, a, title),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(_changed),
                  child: Text(_dirty ? 'Cancel' : 'Close'),
                ),
                if (a != null && a.manageable) ...[
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: _saving || !_dirty ? null : () => _save(),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(a.hasAccount ? 'Save' : 'Create login'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, LoginAccess a, String title) {
    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd().add_jm();
    final noMethods = a.schoolMethods.isEmpty;
    return [
      Text(title, style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      DetailGrid(
        minColumnWidth: 200,
        items: [
          DetailItem('User type', a.userTypeLabel),
          DetailItem('Registered mobile', a.registeredPhone ?? 'Not set'),
          DetailItem('Registered email', a.registeredEmail ?? 'Not set'),
          DetailItem(
            'Login access',
            !a.hasAccount
                ? 'Not set up'
                : a.enabled
                ? 'Enabled'
                : 'Disabled',
          ),
          DetailItem(
            'Sign-in methods',
            a.hasAccount && a.methods.isNotEmpty
                ? a.methods.map((m) => m.label).join(', ')
                : a.legacy
                ? 'Email / Google (existing account)'
                : 'None',
          ),
          DetailItem('Account', a.activation.label),
          DetailItem(
            'Last login',
            a.lastLogin == null ? 'Never' : fmt.format(a.lastLogin!),
          ),
        ],
      ),
      if (!a.manageable)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Text(
            'You cannot change login access for your own account or for an '
            'administrator.',
            style: theme.textTheme.bodySmall,
          ),
        )
      else ...[
        const Divider(height: AppSpacing.xl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow this person to sign in'),
          subtitle: const Text(
            'Turning this off blocks sign-in everywhere. Nothing is deleted.',
          ),
          value: _enabled,
          onChanged: _saving
              ? null
              : (v) => setState(() {
                  _enabled = v;
                  _error = null;
                }),
        ),
        if (_enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Permitted sign-in methods', style: theme.textTheme.titleSmall),
          if (noMethods)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('No sign-in methods are enabled for this school.'),
            ),
          for (final m in LoginMethod.values) _methodTile(a, m),
        ],
        if (a.hasAccount) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (a.registeredEmail != null &&
                  a.effective.contains(LoginMethod.password))
                OutlinedButton.icon(
                  onPressed: _saving ? null : _sendSetup,
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: Text(
                    a.activation == LoginActivation.active
                        ? 'Send password reset email'
                        : 'Send password setup email',
                  ),
                ),
              if (a.enabled)
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final ok = await _confirm(
                            title: 'Sign out all devices?',
                            body:
                                '${a.name} will be signed out everywhere and '
                                'must sign in again.',
                            action: 'Sign out',
                            destructive: true,
                          );
                          if (ok && mounted) _save(revokeOnly: true);
                        },
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out all devices'),
                ),
            ],
          ),
        ],
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: _ErrorBox(message: _error!),
        ),
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_notice!)),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _methodTile(LoginAccess a, LoginMethod m) {
    final blocker = LoginAccessRules.blocker(m, a);
    final selected = _selected.contains(m);
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: selected,
      // A method that cannot be used stays visible but unavailable, with the
      // reason, rather than silently disappearing.
      onChanged: _saving || (blocker != null && !selected)
          ? null
          : (v) => setState(() {
              v == true ? _selected.add(m) : _selected.remove(m);
              _error = null;
            }),
      title: Text(m.label),
      subtitle: Text(blocker ?? m.description),
      isThreeLine: false,
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}
