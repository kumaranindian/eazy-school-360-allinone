import '../../../../core/utils/date_formatting.dart';
import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../domain/leave_enums.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_scope.dart';

/// `/leave` — the reviewer's dashboard: what is waiting, and where to go.
/// Counts come from `count()` aggregate queries, not from loading the lists.
class LeaveHubPage extends StatelessWidget {
  const LeaveHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageAppBar(context, title: const Text('Leave management')),
      body: LeaveScope(
        showYearSelector: false,
        builder: (context, leave) => _Hub(leave: leave),
      ),
    );
  }
}

class _Hub extends ConsumerWidget {
  final LeaveContext leave;

  const _Hub({required this.leave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final students = ref.watch(
      leavePendingCountProvider((
        schoolId: leave.schoolId,
        branchId: leave.branchId,
        kind: LeaveKind.student,
      )),
    );
    final staff = ref.watch(
      leavePendingCountProvider((
        schoolId: leave.schoolId,
        branchId: leave.branchId,
        kind: LeaveKind.staff,
      )),
    );
    final notices = ref
        .watch(leaveReviewerNotificationsProvider(leave.branchKey))
        .value;

    Widget metric(
      String label,
      AsyncValue<int> value,
      LeaveKind kind,
      IconData icon,
    ) {
      return SizedBox(
        width: 240,
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: () => context.go(
              '/leave/applications?kind=${kind.wireValue}&status=PENDING',
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(icon, size: 32),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        value.when(
                          loading: () => const SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          error: (e, _) =>
                              Text('—', style: theme.textTheme.headlineSmall),
                          data: (n) =>
                              Text('$n', style: theme.textTheme.headlineSmall),
                        ),
                        Text(label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget tile(IconData icon, String title, String description, String path) =>
        HubTile(
          icon: icon,
          title: title,
          description: description,
          onTap: () => context.go(path),
        );

    final err = students.hasError
        ? userMessageFor(students.error!)
        : staff.hasError
        ? userMessageFor(staff.error!)
        : null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            metric(
              'Student requests awaiting review',
              students,
              LeaveKind.student,
              Icons.groups_outlined,
            ),
            metric(
              'Staff requests awaiting review',
              staff,
              LeaveKind.staff,
              Icons.badge_outlined,
            ),
          ],
        ),
        if (err != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text(err)),
                TextButton(
                  onPressed: () => ref.invalidate(leavePendingCountProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        HubGroup(
          title: 'Review and plan',
          tiles: [
            tile(
              Icons.list_alt,
              'All applications',
              'Every leave request, with its status and history',
              '/leave/applications',
            ),
            tile(
              Icons.calendar_month_outlined,
              'Calendar',
              'Who is away, day by day',
              '/leave/calendar',
            ),
            tile(
              Icons.account_balance_wallet_outlined,
              'Staff balances',
              'Entitlement, used and remaining leave per person',
              '/leave/balances',
            ),
            if (leave.tenant.can(Permission.viewLeaveReports))
              tile(
                Icons.assessment_outlined,
                'Reports',
                'Leave summaries and exports',
                '/leave/reports',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        HubGroup(
          title: 'Configure',
          tiles: [
            tile(
              Icons.tune,
              'Leave types & policy',
              'Leave types, limits and approval rules',
              '/leave/types',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Recent activity', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'In-app notices only. Nothing is sent by email, SMS or WhatsApp.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (notices == null)
          const LinearProgressIndicator()
        else if (notices.isEmpty)
          const Text('Nothing new.')
        else
          for (final n in notices.take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_none),
              title: Text(n.title),
              subtitle: n.body == null ? null : Text(n.body!),
              onTap: n.applicationId == null
                  ? null
                  : () => context.go('/leave/applications/${n.applicationId}'),
              trailing: n.createdAt == null
                  ? null
                  : Text(
                      formatInstant(n.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
            ),
      ],
    );
  }
}
