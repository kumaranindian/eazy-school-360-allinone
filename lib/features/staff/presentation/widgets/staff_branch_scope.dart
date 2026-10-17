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

  /// Whether to draw the "Branch" dropdown row above the page. A screen that
  /// puts the branch choice in its own header (the Teachers hero) turns it
  /// off; the branch is still resolved exactly the same way.
  final bool showBranchRow;

  /// An extra picker that belongs beside the branch picker (an academic-year
  /// dropdown): shown in the same compact row instead of a second row of its
  /// own. Built with the resolved ids.
  final Widget? Function(
    BuildContext context,
    String schoolId,
    String branchId,
  )?
  scopeControl;

  const StaffBranchScope({
    super.key,
    required this.builder,
    this.showBranchRow = true,
    this.scopeControl,
  });

  /// One band holding the scope pickers side by side (wrapping on a phone).
  static Widget scopeRow(List<Widget> controls) => Padding(
    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 12, AppSpacing.md, 0),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: AppSpacing.sm + 4,
        runSpacing: AppSpacing.sm + 4,
        children: [for (final c in controls) SizedBox(width: 260, child: c)],
      ),
    ),
  );

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
          final control = scopeControl?.call(context, schoolId, branchId);
          final page = KeyedSubtree(
            key: ValueKey('$schoolId/$branchId'),
            child: builder(context, tenant, schoolId, branchId),
          );
          if (control == null) return page;
          return Column(
            children: [
              scopeRow([control]),
              Expanded(child: page),
            ],
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
            if ((showBranchRow && branches.length > 1) || scopeControl != null)
              scopeRow([
                if (showBranchRow && branches.length > 1)
                  DropdownButtonFormField<String>(
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
                ?scopeControl?.call(context, schoolId, branchId),
              ]),
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
