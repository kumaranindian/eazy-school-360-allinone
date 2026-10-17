import 'package:flutter/material.dart';

import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/widgets/login_access_dialog.dart';
import '../../domain/staff.dart';

/// Opens the Login access dialog for one staff member (the key icon on a
/// staff or teacher row). Returns whether the access changed, so the list can
/// reload.
Future<bool> openStaffLoginAccess(
  BuildContext context, {
  required String schoolId,
  required String branchId,
  required Staff staff,
}) async {
  final changed = await showLoginAccessDialog(
    context: context,
    schoolId: schoolId,
    branchId: branchId,
    kind: LoginKind.staff,
    id: staff.staffId,
    fallbackName: staff.displayName,
  );
  return changed == true;
}
