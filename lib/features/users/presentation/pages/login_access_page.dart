import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/login_provisioning.dart';
import '../widgets/login_access_dialog.dart';

/// Login access of one person as a full screen (used for parents). Pops with
/// `true` when something changed, like the dialog it replaces. All behaviour
/// lives in [LoginAccessDialog]; this only supplies the school and branch.
class LoginAccessPage extends ConsumerWidget {
  final LoginKind kind;
  final String id;
  final String? fallbackName;

  const LoginAccessPage({
    super.key,
    required this.kind,
    required this.id,
    this.fallbackName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        final schoolId = tenant?.school?.schoolId;
        final branchId = tenant?.branch?.branchId;
        if (schoolId == null || branchId == null) {
          return const EmptyView(
            icon: Icons.vpn_key_outlined,
            message: 'No branch found for your account.',
          );
        }
        return LoginAccessDialog(
          schoolId: schoolId,
          branchId: branchId,
          kind: kind,
          id: id,
          fallbackName: fallbackName,
          layout: LoginAccessLayout.page,
        );
      },
    );
  }
}
