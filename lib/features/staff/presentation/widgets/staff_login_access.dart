import 'package:flutter/material.dart';

import '../../../../core/utils/responsive.dart';
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

/// The key button of a directory row. Shown only to people who may manage
/// staff; the server and rules decide what the dialog then allows.
class LoginAccessButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LoginAccessButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // A table row is 46px tall, so the button is compact there; on a phone it
    // keeps the full 48px touch target.
    final compact = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    return IconButton(
      icon: const Icon(Icons.vpn_key_outlined),
      iconSize: compact ? 20 : 24,
      tooltip: 'Login access',
      onPressed: onPressed,
      style: compact
          ? IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 34),
              maximumSize: const Size(40, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )
          : IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}
