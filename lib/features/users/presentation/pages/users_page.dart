import 'package:flutter/material.dart';

import '../../../../shared/error/empty_view.dart';

/// Placeholder destination. Staff/user management (and the role/permission
/// matrix it will introduce) is explicitly out of scope for the
/// platform-foundation milestone — see PROJECT_ARCHITECTURE.md
/// "Known limitations".
class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyView(
      icon: Icons.people_outline,
      message: 'User & staff management is coming in a later milestone.',
    );
  }
}
