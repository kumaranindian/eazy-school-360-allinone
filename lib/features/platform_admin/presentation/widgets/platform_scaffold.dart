import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_version_footer.dart';
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

  /// Extra app-bar buttons, shown before the account and sign-out buttons.
  final List<Widget> actions;

  const PlatformScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBack = true,
    this.floatingActionButton,
    this.actions = const [],
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
          ...actions,
          if (user != null)
            _Account(
              key: const ValueKey('platform-account'),
              email: user.email,
              role: role,
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
      // Version, build and (outside prod) environment, as on every other
      // screen, so QA can tell which build they are testing.
      bottomNavigationBar: const SafeArea(child: AppVersionFooter()),
    );
  }
}

/// Who is signed in, sized to the screen. A `Flexible` here made the actions
/// row fill the whole app bar and pushed the other actions over the back
/// arrow (QA DEF-02 / DEF-09), so the text gets a bounded width instead:
/// email and role on wide screens, the role on narrow ones, and only an icon
/// (with the full text as its tooltip) on very narrow ones.
class _Account extends StatelessWidget {
  final String email;
  final String? role;

  const _Account({super.key, required this.email, this.role});

  @override
  Widget build(BuildContext context) {
    final full = role == null ? email : '$email · $role';
    final width = MediaQuery.sizeOf(context).width;
    if (width < 360) {
      return Tooltip(
        message: full,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Icon(Icons.account_circle_outlined),
        ),
      );
    }
    final wide = width >= 720;
    return Tooltip(
      message: full,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 320 : 120),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Center(
            child: Text(
              wide ? full : (role ?? email),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
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
