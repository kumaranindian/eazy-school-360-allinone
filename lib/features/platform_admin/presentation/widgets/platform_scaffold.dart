import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../authentication/presentation/sign_out.dart';

/// Frame of every platform-admin screen. These screens have no school or
/// branch, so they sit outside the school app shell: a title, who is signed
/// in with their platform role, and Sign out.
class PlatformScaffold extends ConsumerWidget {
  final String title;
  final Widget child;

  /// Show a back arrow to the platform home.
  final bool showBack;

  /// A primary action (e.g. "Create school").
  final Widget? floatingActionButton;

  const PlatformScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = true,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(tenantContextProvider).value?.user;
    final role = user?.platformRole?.displayName;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                tooltip: 'Platform home',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(AppRoutes.platformHome),
              )
            : null,
        actions: [
          if (user != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    role == null ? user.email : '${user.email} · $role',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => signOutWithCleanup(ref),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: child),
    );
  }
}

/// Centres platform content at a readable width.
class PlatformBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const PlatformBody({super.key, required this.child, this.maxWidth = 960});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
