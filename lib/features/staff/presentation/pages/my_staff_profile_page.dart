import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/staff_providers.dart';
import '../widgets/staff_branch_scope.dart';
import 'staff_profile_page.dart';

/// `/my-profile` — the staff (and, for a teacher, teaching) profile of the
/// signed-in user, found through the staff record's `userId` link. A user
/// with no linked staff record sees an explanation rather than an error.
class MyStaffProfilePage extends ConsumerWidget {
  const MyStaffProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) {
        final own = ref.watch(
          ownStaffProvider((
            schoolId: schoolId,
            branchId: branchId,
            userId: tenant.user.userId,
          )),
        );
        return AsyncValueWidget(
          value: own,
          errorMessage: userMessageFor,
          onRetry: () => ref.invalidate(ownStaffProvider),
          data: (staff) {
            if (staff == null) {
              return const EmptyView(
                icon: Icons.person_search_outlined,
                message:
                    "Your account isn't linked to a staff record yet. Ask an administrator to link it.",
              );
            }
            return StaffProfileView(
              tenant: tenant,
              schoolId: schoolId,
              branchId: branchId,
              staffId: staff.staffId,
            );
          },
        );
      },
    );
  }
}
