import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/platform_ops_models.dart';
import '../providers/platform_ops_providers.dart';

/// Notice ids a person has dismissed in this session.
class DismissedNotices extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void dismiss(String id) => state = {...state, id};
}

final dismissedNoticesProvider =
    NotifierProvider<DismissedNotices, Set<String>>(DismissedNotices.new);

/// What Avail404 wants a school's administrators to know, above every screen:
/// live notices addressed to everyone or to this school, newest first, each
/// dismissible for the session. Nothing is shown to teachers, parents or to a
/// platform admin looking in through a support session.
class PlatformNoticeBanner extends ConsumerWidget {
  final Widget child;

  const PlatformNoticeBanner({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final schoolId = tenant?.school?.schoolId;
    final admin =
        tenant != null &&
        !tenant.supportSession &&
        (tenant.role == UserRole.schoolAdmin ||
            tenant.role == UserRole.branchAdmin);
    if (!admin || schoolId == null) return child;
    final dismissed = ref.watch(dismissedNoticesProvider);
    final now = DateTime.now();
    final live = [
      for (final n
          in ref.watch(schoolNoticesProvider(schoolId)).value ??
              const <SchoolNotice>[])
        if (n.isLiveAt(now) && !dismissed.contains(n.id)) n,
    ]..sort((a, b) => (b.startsAt ?? now).compareTo(a.startsAt ?? now));
    if (live.isEmpty) return child;
    return Column(
      children: [
        for (final n in live.take(2)) _NoticeTile(notice: n),
        Expanded(child: child),
      ],
    );
  }
}

class _NoticeTile extends ConsumerWidget {
  final SchoolNotice notice;

  const _NoticeTile({required this.notice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (notice.severity) {
      NoticeSeverity.critical => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
      NoticeSeverity.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      NoticeSeverity.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
    };
    return Material(
      key: ValueKey('notice-${notice.id}'),
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: fg),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    notice.body,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: fg),
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('notice-dismiss-${notice.id}'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 18, color: fg),
              onPressed: () => ref
                  .read(dismissedNoticesProvider.notifier)
                  .dismiss(notice.id),
            ),
          ],
        ),
      ),
    );
  }
}
