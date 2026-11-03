import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/school_admin.dart';
import '../providers/school_admin_providers.dart';
import '../widgets/add_school_admin_dialog.dart';

/// `/users` — People & access. Today this is where a school admin sees who
/// the school's administrators are and adds another one. Everyone else sees
/// a short explanation: staff and parent logins are given from their own
/// lists.
class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        final schoolId = tenant?.school?.schoolId;
        if (tenant == null ||
            schoolId == null ||
            tenant.role != UserRole.schoolAdmin) {
          return const EmptyView(
            icon: Icons.admin_panel_settings_outlined,
            message:
                'Only a school admin can manage school admins. Give staff and '
                'parents logins from their own lists.',
          );
        }
        return _Admins(schoolId: schoolId, myUid: tenant.user.userId);
      },
    );
  }
}

class _Admins extends ConsumerWidget {
  final String schoolId;
  final String myUid;
  const _Admins({required this.schoolId, required this.myUid});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await showAddSchoolAdminDialog(
      context: context,
      schoolId: schoolId,
    );
    if (added == true) ref.invalidate(schoolAdminsProvider(schoolId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final admins = ref.watch(schoolAdminsProvider(schoolId));
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'School admins',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _add(context, ref),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add school admin'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'School admins manage every branch, staff, students, fees '
                  'and settings. There is no limit on how many a school has.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                admins.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => SizedBox(
                    height: 200,
                    child: ErrorView(
                      message: userMessageFor(e),
                      onRetry: () =>
                          ref.invalidate(schoolAdminsProvider(schoolId)),
                    ),
                  ),
                  data: (list) => Column(
                    children: [
                      for (final a in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _AdminTile(admin: a, isYou: a.uid == myUid),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminTile extends StatelessWidget {
  final SchoolAdminSummary admin;
  final bool isYou;
  const _AdminTile({required this.admin, required this.isYou});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = admin.name.isEmpty ? admin.email : admin.name;
    return HomePanel(
      accent: AppColors.brandBlue,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (admin.email.isNotEmpty && admin.email != name)
                  Text(admin.email, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (isYou) ...[
            const StatusPill('You', color: AppColors.brandBlue),
            const SizedBox(width: AppSpacing.xs),
          ],
          StatusPill(
            admin.isActive ? 'Active' : admin.status,
            color: admin.isActive
                ? AppColors.success
                : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
