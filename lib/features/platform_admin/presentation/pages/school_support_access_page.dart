import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/support_grant.dart';
import '../providers/platform_console_providers.dart';

/// Settings -> Support access, for the school's own administrators: who from
/// Avail404 can look at the school's data right now (and why), the history of
/// every access, and a button to end access at once. Support access is
/// read-only, time-boxed and never includes uploaded files.
class SchoolSupportAccessPage extends ConsumerWidget {
  const SchoolSupportAccessPage({super.key});

  Future<void> _end(
    BuildContext context,
    WidgetRef ref,
    String schoolId,
    SupportGrant g,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('End this access now?'),
        content: Text(
          '${g.adminName.isEmpty ? g.adminEmail : g.adminName} will no longer '
          'be able to look at your school\'s data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('support-revoke-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('End access'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final ok = await ref
        .read(platformConsoleActionsProvider.notifier)
        .revokeGrant(schoolId: schoolId, adminUid: g.adminUid);
    if (!context.mounted) return;
    if (ok) {
      context.showSnackBar('Access ended.');
    } else {
      context.showSnackBar(
        userMessageFor(ref.read(platformConsoleActionsProvider).error!),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = ref.watch(tenantContextProvider).value?.school?.schoolId;
    return SectionPage(
      title: 'Support access',
      description:
          'When Avail404 support looks at your school to help you. It is '
          'read-only, limited in time, never includes uploaded files, and '
          'you can end it at any moment.',
      parentRoute: AppRoutes.settings,
      child: schoolId == null
          ? const EmptyView(
              icon: Icons.school_outlined,
              message: 'No school found for your account.',
            )
          : _Body(schoolId: schoolId, onEnd: _end),
    );
  }
}

class _Body extends ConsumerWidget {
  final String schoolId;
  final Future<void> Function(BuildContext, WidgetRef, String, SupportGrant)
  onEnd;

  const _Body({required this.schoolId, required this.onEnd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Access right now', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        AsyncValueWidget(
          value: ref.watch(schoolGrantsProvider(schoolId)),
          errorMessage: userMessageFor,
          data: (grants) {
            final active = [
              for (final g in grants)
                if (g.isActiveAt(now)) g,
            ];
            if (active.isEmpty) {
              return const Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Text('Nobody from Avail404 has access right now.'),
                ),
              );
            }
            return Column(
              children: [
                for (final g in active)
                  Card(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      title: Text(
                        g.adminName.isEmpty ? g.adminEmail : g.adminName,
                      ),
                      subtitle: Text(
                        '${g.reason}\nUntil ${formatInstant(g.expiresAt)}'
                        '${g.ticket == null ? '' : '  ·  ${g.ticket}'}',
                      ),
                      isThreeLine: true,
                      trailing: OutlinedButton(
                        key: ValueKey('support-revoke-${g.adminUid}'),
                        onPressed: () => onEnd(context, ref, schoolId, g),
                        child: const Text('End access'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text('History', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        AsyncValueWidget(
          value: ref.watch(supportAccessLogProvider(schoolId)),
          errorMessage: userMessageFor,
          data: (log) => log.isEmpty
              ? const Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Avail404 support has never accessed your school.',
                    ),
                  ),
                )
              : Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final e in log)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            e.event == 'GRANTED'
                                ? Icons.visibility_outlined
                                : Icons.block_outlined,
                          ),
                          title: Text(
                            e.event == 'GRANTED'
                                ? '${e.adminName.isEmpty ? e.adminEmail : e.adminName} was given read-only access'
                                : 'Access ended for ${e.adminName.isEmpty ? e.adminEmail : e.adminName}'
                                      '${e.revokedBy == 'SCHOOL_ADMIN' ? ' by your school' : ''}',
                          ),
                          subtitle: Text(
                            [
                              if (e.event == 'GRANTED' && e.reason != null)
                                e.reason!,
                              formatInstant(e.at),
                            ].join('\n'),
                          ),
                          isThreeLine: e.event == 'GRANTED' && e.reason != null,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
