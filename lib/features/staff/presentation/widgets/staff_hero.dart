import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/branding/page_hero.dart';
import '../providers/staff_providers.dart';

/// The compact header of the staff directories (Staff and Teachers): one short
/// strip with the title and subtitle, and — on the right (below the title on a phone) — the
/// school · branch label and, for school-level roles of a school with several
/// branches, the branch selector. It replaces the tall hero banner and the
/// separate "Branch" row; the selector drives the same
/// [selectedStaffBranchIdProvider] the old row did.
class StaffHero extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final ScreenSize layout;
  final String title;
  final String subtitle;
  final IconData icon;

  const StaffHero({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.layout,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final branches =
        ref.watch(schoolBranchesProvider(schoolId)).value ?? const [];
    final branchName = branches
        .where((b) => b.branchId == branchId)
        .map((b) => b.name)
        .firstOrNull;
    final place = [
      tenant?.school?.name,
      branchName ?? tenant?.branch?.name,
    ].whereType<String>().where((e) => e.isNotEmpty).join(' · ');
    final canChoose =
        tenant != null && !tenant.role.isBranchScoped && branches.length > 1;

    final phone = layout.isMobile;
    final text = Theme.of(context).textTheme;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleLarge?.copyWith(
            color: Colors.white,
            fontSize: phone ? 20 : 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(
            color: const Color(0xFFD9EAFF),
            fontSize: 13,
          ),
        ),
      ],
    );
    final controls = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: phone ? WrapAlignment.start : WrapAlignment.end,
      children: [
        if (place.isNotEmpty) HeroPill(place),
        if (canChoose)
          _BranchSelector(
            branches: [for (final b in branches) (b.branchId, b.name)],
            selectedId: branchId,
            onSelected: (id) =>
                ref.read(selectedStaffBranchIdProvider.notifier).select(id),
          ),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: phone ? 12 : 20,
        vertical: phone ? 12 : 16,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PageHero.iconBadge(icon, size: 40),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: heading),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                controls,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PageHero.iconBadge(icon, size: 44),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: heading),
                const SizedBox(width: AppSpacing.md),
                Flexible(flex: 2, child: controls),
              ],
            ),
    );
  }
}

/// A pill that opens the list of branches. Its look matches [HeroPill].
class _BranchSelector extends StatelessWidget {
  final List<(String, String)> branches;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _BranchSelector({
    required this.branches,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final current = branches
        .where((b) => b.$1 == selectedId)
        .map((b) => b.$2)
        .firstOrNull;
    return PopupMenuButton<String>(
      tooltip: 'Choose branch',
      initialValue: selectedId,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final (id, name) in branches)
          PopupMenuItem<String>(
            value: id,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Branch: ${current ?? ''}',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_tree_outlined,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    current ?? 'Branch',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
