import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_routes.dart';
import '../../core/tenant/tenant_context_provider.dart';
import '../../features/staff/presentation/providers/staff_providers.dart';

/// Lets a staff member who works in more than one branch choose the branch
/// they are acting in. Renders nothing for everyone else.
///
/// The role can differ per branch (Teacher in North, Finance in South), so a
/// switch lands on the dashboard: the screen the user was on may not exist for
/// the role they hold in the other branch.
class BranchSwitcher extends ConsumerWidget {
  const BranchSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final user = tenant?.user;
    final schoolId = user?.schoolId;
    if (tenant == null ||
        user == null ||
        schoolId == null ||
        !user.worksInMultipleBranches) {
      return const SizedBox.shrink();
    }
    final names = {
      for (final b
          in ref.watch(schoolBranchesProvider(schoolId)).value ?? const [])
        b.branchId: b.name,
    };
    String nameOf(String id) => names[id] ?? id;
    final active = tenant.branch?.branchId ?? user.branchId;
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return PopupMenuButton<String>(
      tooltip: 'Switch branch',
      onSelected: (id) async {
        await ref.read(tenantContextProvider.notifier).switchBranch(id);
        if (context.mounted) context.go(AppRoutes.dashboard);
      },
      itemBuilder: (context) => [
        for (final id in user.workingBranchIds)
          PopupMenuItem<String>(
            value: id,
            child: Row(
              children: [
                Icon(
                  id == active ? Icons.check : null,
                  size: 18,
                  semanticLabel: id == active ? 'Current branch' : null,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${nameOf(id)} · ${(id == user.homeBranchId ? user.homeRole : user.branchRoles[id])?.displayName ?? ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_tree_outlined),
            if (wide) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  active == null ? 'Branch' : nameOf(active),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
