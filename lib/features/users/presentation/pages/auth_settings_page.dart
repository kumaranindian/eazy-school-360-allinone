import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../authentication/domain/login_method.dart';
import '../../domain/login_access.dart';
import '../providers/login_access_providers.dart';

/// Settings → Authentication: which sign-in methods this school's people can
/// use. A person's effective methods are these switches intersected with what
/// an administrator permitted them (Login access). The server enforces both.
class AuthSettingsPage extends ConsumerStatefulWidget {
  const AuthSettingsPage({super.key});

  @override
  ConsumerState<AuthSettingsPage> createState() => _AuthSettingsPageState();
}

class _AuthSettingsPageState extends ConsumerState<AuthSettingsPage> {
  SchoolAuthSettings? _draft;
  bool _saving = false;
  String? _error;

  Future<void> _save(String schoolId, SchoolAuthSettings saved) async {
    final draft = _draft;
    if (draft == null || _saving) return;
    if (draft.enabledMethods.isEmpty) {
      setState(() => _error = 'Keep at least one sign-in method switched on.');
      return;
    }
    final removed = [
      for (final m in LoginMethod.values)
        if (saved.isEnabled(m) && !draft.isEnabled(m)) m,
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          removed.isEmpty
              ? 'Save authentication settings?'
              : 'Turn off ${removed.map((m) => m.label).join(' and ')}?',
        ),
        content: Text(
          removed.isEmpty
              ? 'Sign-in will be available with: '
                    '${draft.enabledMethods.map((m) => m.label).join(', ')}.'
              : 'Everyone at this school who signs in that way will be signed '
                    'out and must use another permitted method. Make sure '
                    'people have one, or they will be locked out. Other '
                    'schools are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final n = await ref
          .read(loginAccessRepositoryProvider)
          .updateSchoolSettings(schoolId, draft);
      ref.invalidate(schoolAuthSettingsProvider(schoolId));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = null;
      });
      context.showSnackBar(
        n == 0
            ? 'Authentication settings saved.'
            : 'Authentication settings saved. $n '
                  'account${n == 1 ? '' : 's'} updated.',
      );
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
    final tenantState = ref.watch(tenantContextProvider);
    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'No school found for your account.',
          );
        }
        if (!tenant!.can(Permission.manageSchool)) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'Only school administrators can change authentication.',
          );
        }
        final schoolId = tenant.school!.schoolId;
        final settingsAsync = ref.watch(schoolAuthSettingsProvider(schoolId));
        return AsyncValueWidget(
          value: settingsAsync,
          errorMessage: userMessageFor,
          onRetry: () => ref.invalidate(schoolAuthSettingsProvider(schoolId)),
          data: (saved) {
            final current = _draft ?? saved;
            final dirty = current != saved;
            return SectionPage(
              title: 'Authentication',
              description:
                  'Choose how people at this school can sign in. Each person '
                  'can then be allowed some or all of these from their Login '
                  'access (key icon) on the Staff and Parents screens.',
              parentRoute: AppRoutes.settings,
              parentLabel: 'Settings',
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  for (final m in LoginMethod.values)
                    _MethodCard(
                      method: m,
                      value: current.isEnabled(m),
                      configured: m != LoginMethod.phoneOtp
                          ? true
                          : saved.phoneOtpConfigured,
                      enabled: !_saving,
                      onChanged: (v) => setState(() {
                        _draft = current.withMethod(m, v);
                        _error = null;
                      }),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Turning a method off here removes it for everyone at this '
                    'school. It never deletes accounts or records.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      TextButton(
                        onPressed: _saving || !dirty
                            ? null
                            : () => setState(() {
                                _draft = null;
                                _error = null;
                              }),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: _saving || !dirty
                            ? null
                            : () => _save(schoolId, saved),
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save changes'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MethodCard extends StatelessWidget {
  final LoginMethod method;
  final bool value;
  final bool configured;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _MethodCard({
    required this.method,
    required this.value,
    required this.configured,
    required this.enabled,
    required this.onChanged,
  });

  static const _details = {
    LoginMethod.password:
        'People sign in with their registered email and a password they set '
        'themselves. Password reset is by email.',
    LoginMethod.google:
        'People sign in with the Google account that uses their registered '
        'email. Unknown Google accounts get no access.',
    LoginMethod.phoneOtp:
        'People get a one-time code on WhatsApp at their registered mobile. '
        'Requires the Meta WhatsApp integration to be set up on the server.',
  };

  static const _icons = {
    LoginMethod.password: Icons.password_outlined,
    LoginMethod.google: Icons.g_mobiledata,
    LoginMethod.phoneOtp: Icons.chat_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A method that cannot work yet can be switched off but not on.
    final canToggle = enabled && (configured || value);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(_icons[method]),
              title: Text(method.label),
              subtitle: Text(_details[method]!),
              value: value,
              onChanged: canToggle ? onChanged : null,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                children: [
                  Icon(
                    configured
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: configured
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      configured
                          ? (method == LoginMethod.phoneOtp
                                ? 'WhatsApp integration is configured.'
                                : 'Available (provider enabled in Firebase).')
                          : 'Not configured on the server — it cannot be turned on yet.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
