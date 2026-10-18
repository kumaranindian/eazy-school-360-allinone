import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tenant/tenant_context_provider.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/staff/presentation/providers/staff_providers.dart';

/// "Adding to: BRANCH" for a school admin who runs several branches, so it is
/// always clear which branch an upload or admission lands in (switch it from
/// the header). Renders nothing for anyone else or a single-branch school.
class ActingBranchBanner extends ConsumerWidget {
  final String verb;
  const ActingBranchBanner({super.key, this.verb = 'Adding to'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final schoolId = tenant?.user.schoolId;
    if (tenant == null || schoolId == null || !tenant.user.actsInAnyBranch) {
      return const SizedBox.shrink();
    }
    final branches =
        ref.watch(schoolBranchesProvider(schoolId)).value ?? const [];
    if (branches.length < 2) return const SizedBox.shrink();
    final name = tenant.branch?.name ?? '';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        container: true,
        child: Row(
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$verb branch: $name. Change it from the branch menu in the header.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
