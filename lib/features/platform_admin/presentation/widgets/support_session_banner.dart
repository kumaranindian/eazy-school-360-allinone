import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../providers/platform_console_providers.dart';
import '../providers/support_session_providers.dart';

/// Shown on top of every school screen during a support session: whose school
/// this is, that nothing can be changed, when access ends, and a way out. If the
/// school (or an owner) revokes the grant, the session ends on its own.
class SupportSessionBanner extends ConsumerWidget {
  final Widget child;

  const SupportSessionBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final session = ref.watch(supportSessionProvider);
    if (tenant == null || !tenant.supportSession || session == null) {
      return child;
    }
    // Ends the session when its grant is seen revoked or expired. (A grant that
    // is merely not in the list yet, e.g. a cached first snapshot, does not.)
    ref.listen(myGrantsProvider, (_, next) {
      final grants = next.value;
      if (grants == null) return;
      final now = DateTime.now();
      final mine = grants.where((g) => g.schoolId == session.schoolId);
      if (mine.isNotEmpty && !mine.any((g) => g.isActiveAt(now))) {
        ref.read(supportSessionProvider.notifier).end();
      }
    });

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ends = TimeOfDay.fromDateTime(session.expiresAt).format(context);
    final busy = ref.watch(platformConsoleActionsProvider).isLoading;
    return Column(
      children: [
        Material(
          key: const ValueKey('support-banner'),
          color: scheme.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 18,
                    color: scheme.onTertiaryContainer,
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 160,
                    ),
                    child: Text(
                      'Support session: ${session.schoolName} · read-only · '
                      'ends $ends',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('support-end'),
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await ref
                                .read(platformConsoleActionsProvider.notifier)
                                .endSupportSession();
                            if (!ok && context.mounted) {
                              context.showSnackBar(
                                'Access will end on its own at $ends.',
                              );
                            }
                          },
                    child: const Text('End session'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
