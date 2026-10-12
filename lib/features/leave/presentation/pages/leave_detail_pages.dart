import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../widgets/leave_detail_body.dart';

/// `/leave/applications/:applicationId` — reviewer view.
class LeaveApplicationPage extends StatelessWidget {
  final String applicationId;

  const LeaveApplicationPage({super.key, required this.applicationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave application')),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) =>
            LeaveApplicationDetail(
              tenant: tenant,
              schoolId: schoolId,
              branchId: branchId,
              applicationId: applicationId,
            ),
      ),
    );
  }
}

/// `/my-leave/applications/:applicationId?b=branch` — the applicant's view
/// (a staff member's own, or a parent's child's). Same body: what is shown
/// and allowed follows the signed-in person's permissions and ownership.
class MyLeaveApplicationPage extends ConsumerWidget {
  final String applicationId;
  final String? branchId;

  const MyLeaveApplicationPage({
    super.key,
    required this.applicationId,
    this.branchId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave application')),
      body: AsyncValueWidget(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final schoolId = tenant?.school?.schoolId;
          final branch = branchId ?? tenant?.branch?.branchId;
          if (tenant == null || schoolId == null || branch == null) {
            return const EmptyView(
              icon: Icons.event_busy,
              message: 'No school found for your account.',
            );
          }
          return LeaveApplicationDetail(
            tenant: tenant,
            schoolId: schoolId,
            branchId: branch,
            applicationId: applicationId,
          );
        },
      ),
    );
  }
}
