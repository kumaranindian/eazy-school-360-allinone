import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/platform_admin_entry.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_admin_providers.dart';
import '../widgets/add_platform_admin_dialog.dart';
import '../widgets/platform_scaffold.dart';

/// Owner-only: who can administer the platform, with their role, whether
/// two-step verification is set up, and when they last signed in.
class PlatformAdminsPage extends ConsumerWidget {
  const PlatformAdminsPage({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<PlatformAdminCreated>(
      context: context,
      builder: (_) => const AddPlatformAdminDialog(),
    );
    if (result == null || !context.mounted) return;
    context.showSnackBar(
      result == PlatformAdminCreated.emailSent
          ? 'Added. A password-setup email is on its way.'
          : 'Added, but the email could not be sent. Use "Send setup email" '
                'on their row.',
      isError: result == PlatformAdminCreated.emailFailed,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(tenantContextProvider).value?.user.platformRole;
    return PlatformScaffold(
      title: 'Platform administrators',
      child: role != PlatformRole.owner
          ? const EmptyView(
              icon: Icons.lock_outline,
              message: 'Only a platform owner can manage administrators.',
            )
          : Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButton: FloatingActionButton.extended(
                key: const ValueKey('pa-add'),
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add administrator'),
              ),
              body: AsyncValueWidget(
                value: ref.watch(platformAdminsProvider),
                errorMessage: userMessageFor,
                onRetry: () => ref.invalidate(platformAdminsProvider),
                data: (admins) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(platformAdminsProvider);
                    await ref.read(platformAdminsProvider.future);
                  },
                  child: PlatformBody(
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        96,
                      ),
                      itemCount: admins.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (_, i) => _AdminCard(admin: admins[i]),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _AdminCard extends ConsumerWidget {
  final PlatformAdminEntry admin;

  const _AdminCard({required this.admin});

  Future<void> _setRole(
    BuildContext context,
    WidgetRef ref,
    PlatformRole role,
  ) async {
    final ok = await ref
        .read(platformAdminActionsProvider.notifier)
        .setRole(admin.uid, role);
    if (!context.mounted) return;
    ref.read(platformAdminActionsProvider).hasError
        ? context.showSnackBar(
            userMessageFor(ref.read(platformAdminActionsProvider).error!),
            isError: true,
          )
        : ok
        ? context.showSnackBar('${admin.name} is now ${role.displayName}.')
        : null;
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    bool active,
  ) async {
    if (!active) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Disable this administrator?'),
          content: Text(
            '${admin.name} will be signed out everywhere and cannot sign in '
            'until you enable them again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Disable'),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
    }
    final ok = await ref
        .read(platformAdminActionsProvider.notifier)
        .setActive(admin.uid, active);
    if (!context.mounted) return;
    if (ok) {
      context.showSnackBar(
        active ? '${admin.name} can sign in again.' : '${admin.name} disabled.',
      );
    } else {
      context.showSnackBar(
        userMessageFor(ref.read(platformAdminActionsProvider).error!),
        isError: true,
      );
    }
  }

  Future<void> _setupEmail(BuildContext context, WidgetRef ref) async {
    final ok = await ref
        .read(platformAdminActionsProvider.notifier)
        .sendSetupEmail(admin.email);
    if (!context.mounted) return;
    context.showSnackBar(
      ok ? 'Email sent to ${admin.email}.' : 'The email could not be sent.',
      isError: !ok,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(platformAdminActionsProvider).isLoading;
    final role = admin.role;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    admin.isSelf ? '${admin.name} (you)' : admin.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (!admin.isSelf)
                  PopupMenuButton<String>(
                    key: ValueKey('pa-menu-${admin.uid}'),
                    enabled: !busy,
                    tooltip: 'Actions',
                    onSelected: (v) {
                      if (v == 'email') _setupEmail(context, ref);
                      if (v == 'disable') _setActive(context, ref, false);
                      if (v == 'enable') _setActive(context, ref, true);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'email',
                        child: Text('Send setup email'),
                      ),
                      if (admin.active)
                        const PopupMenuItem(
                          value: 'disable',
                          child: Text('Disable'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'enable',
                          child: Text('Enable'),
                        ),
                    ],
                  ),
              ],
            ),
            Text(admin.email, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (admin.isSelf || role == null)
                  Chip(
                    label: Text(
                      role == null ? 'Unknown role' : role.displayName,
                    ),
                  )
                else
                  DropdownButton<PlatformRole>(
                    key: ValueKey('pa-role-${admin.uid}'),
                    value: role,
                    underline: const SizedBox.shrink(),
                    onChanged: busy || !admin.active
                        ? null
                        : (v) {
                            if (v != null && v != role) {
                              _setRole(context, ref, v);
                            }
                          },
                    items: [
                      for (final r in PlatformRole.values)
                        DropdownMenuItem(value: r, child: Text(r.displayName)),
                    ],
                  ),
                Chip(
                  avatar: Icon(
                    admin.mfaEnrolled
                        ? Icons.verified_user_outlined
                        : Icons.warning_amber_rounded,
                    size: 18,
                    color: admin.mfaEnrolled
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                  label: Text(
                    admin.mfaEnrolled ? 'Two-step on' : 'Two-step not set up',
                  ),
                ),
                if (!admin.active) const Chip(label: Text('Disabled')),
                if (!admin.roleAssigned)
                  const Chip(label: Text('Role not assigned yet')),
              ],
            ),
            if (admin.lastSignIn != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Last sign-in: ${admin.lastSignIn}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
