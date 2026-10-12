import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/branding/brand_logo.dart';

/// Shown at `/` while initial auth/tenant resolution is in flight — see
/// `app_router.dart`'s redirect for how little time is actually spent
/// here (it redirects away the instant auth + tenant context resolve).
///
/// Also absorbs non-terminal tenant-loading failures (e.g. a transient
/// network error reading the user's profile) with a retry action, rather
/// than the router having to encode every error path itself.
class SplashPage extends ConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantContextProvider);

    return Scaffold(
      body: tenantState.hasError && !tenantState.isLoading
          ? ErrorView(
              message:
                  'Something went wrong while loading your account. Please try again.',
              onRetry: () => ref.invalidate(tenantContextProvider),
            )
          : const _BrandedLoading(),
    );
  }
}

class _BrandedLoading extends StatelessWidget {
  const _BrandedLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandMark(size: 88),
          SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 120,
            child: LinearProgressIndicator(
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
        ],
      ),
    );
  }
}
