import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_version.dart';
import '../../core/permissions/user_role.dart';
import '../../core/tenant/tenant_context_provider.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_formatting.dart';
import '../../features/authentication/presentation/sign_out.dart';
import '../../features/platform_admin/domain/platform_ops_models.dart';
import '../../features/platform_admin/presentation/providers/platform_ops_providers.dart';

/// Enforces what the platform sets in "App availability":
///  * a build older than the minimum must update (Android and iOS; the web app
///    always runs the latest);
///  * maintenance mode pauses the app for school users. Platform admins are
///    never blocked, so they can lift it, and the sign-in screen stays usable
///    (with a notice) so they can get in.
/// A failure to read the setting never blocks anyone.
class AppRequirementsGate extends ConsumerStatefulWidget {
  final Widget child;

  /// Overridable in tests; the real app uses the build in `app_version.dart`.
  final int? build;

  const AppRequirementsGate({super.key, required this.child, this.build});

  @override
  ConsumerState<AppRequirementsGate> createState() =>
      _AppRequirementsGateState();
}

class _AppRequirementsGateState extends ConsumerState<AppRequirementsGate> {
  Timer? _lift;
  DateTime? _liftAt;

  /// A maintenance window with an end time lifts itself: one timer for exactly
  /// that moment (no polling).
  void _armLift(DateTime? until) {
    if (until == _liftAt) return;
    _lift?.cancel();
    _liftAt = until;
    if (until == null) return;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) return;
    _lift = Timer(left, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _lift?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final req =
        ref.watch(appRequirementsProvider).value ?? AppRequirements.none;
    final build = widget.build ?? int.tryParse(appBuildNumber) ?? 0;
    if (req.buildTooOld(
      build: build,
      isAndroid: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      isIos: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
    )) {
      return const _UpdateRequired();
    }
    _armLift(req.maintenanceOn ? req.maintenanceUntil : null);
    final now = DateTime.now();
    if (!req.maintenanceActiveAt(now)) return widget.child;

    final tenant = ref.watch(tenantContextProvider).value;
    if (tenant != null && tenant.role == UserRole.platformAdmin) {
      return Column(
        children: [
          _MaintenanceStrip(req: req, forStaff: true),
          Expanded(child: widget.child),
        ],
      );
    }
    if (tenant != null) return _Maintenance(req: req);
    // Signed out (or still loading): the sign-in screen stays reachable.
    return Column(
      children: [
        _MaintenanceStrip(req: req, forStaff: false),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _MaintenanceStrip extends StatelessWidget {
  final AppRequirements req;
  final bool forStaff;

  const _MaintenanceStrip({required this.req, required this.forStaff});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('maintenance-strip'),
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            forStaff
                ? 'Maintenance mode is ON: school users are paused. ${req.maintenanceMessage}'
                : 'Maintenance in progress. ${req.maintenanceMessage}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Maintenance extends ConsumerWidget {
  final AppRequirements req;

  const _Maintenance({required this.req});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      key: const ValueKey('maintenance-screen'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.construction_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Back soon',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(req.maintenanceMessage, textAlign: TextAlign.center),
                  if (req.maintenanceUntil != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Expected back around ${formatInstant(req.maintenanceUntil)}.',
                      style: text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton(
                    key: const ValueKey('maintenance-sign-out'),
                    onPressed: () => signOutWithCleanup(ref),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      key: const ValueKey('update-required'),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Please update the app',
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'This version of EazySchool 360 is no longer supported. Open the app store and install the latest version to continue.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('You have $appVersionLabel.', style: text.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
