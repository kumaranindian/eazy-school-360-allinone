import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/staff_providers.dart';

/// Resolves which `schoolId`/`branchId` a staff screen operates on and hands
/// them to [builder] — so no staff page repeats tenant plumbing.
///
/// Branch-scoped roles (branch admin, teacher, finance) always get their own
/// branch. School-level roles (school/platform admin) get their own default
/// branch plus a branch switcher when the school has more than one — that
/// switcher is the staff screens' "branch filter". The Firestore rules, not
/// this widget, are what stop anyone reaching a branch they may not.
class StaffBranchScope extends ConsumerWidget {
  final Widget Function(
    BuildContext context,
    TenantContext tenant,
    String schoolId,
    String branchId,
  )
  builder;

  const StaffBranchScope({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        final school = tenant?.school;
        if (tenant == null || school == null) {
          return const EmptyView(
            icon: Icons.groups_outlined,
            message: 'No school found for your account.',
          );
        }
        final schoolId = school.schoolId;

        if (tenant.role.isBranchScoped) {
          final branchId = tenant.branch?.branchId;
          if (branchId == null) {
            return const EmptyView(
              icon: Icons.groups_outlined,
              message: 'No branch found for your account.',
            );
          }
          return KeyedSubtree(
            key: ValueKey('$schoolId/$branchId'),
            child: builder(context, tenant, schoolId, branchId),
          );
        }

        final branches =
            ref.watch(schoolBranchesProvider(schoolId)).value ?? const [];
        final selected = ref.watch(selectedStaffBranchIdProvider);
        final branchId = branches.any((b) => b.branchId == selected)
            ? selected
            : (tenant.branch?.branchId ?? branches.firstOrNull?.branchId);
        if (branchId == null) {
          return const EmptyView(
            icon: Icons.groups_outlined,
            message: 'No branch found for your school.',
          );
        }

        return Column(
          children: [
            if (branches.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: branchId,
                      decoration: const InputDecoration(
                        labelText: 'Branch',
                        isDense: true,
                      ),
                      items: [
                        for (final b in branches)
                          DropdownMenuItem(
                            value: b.branchId,
                            child: Text(b.name),
                          ),
                      ],
                      onChanged: (value) => ref
                          .read(selectedStaffBranchIdProvider.notifier)
                          .select(value),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('$schoolId/$branchId'),
                child: builder(context, tenant, schoolId, branchId),
              ),
            ),
          ],
        );
      },
    );
  }
}
