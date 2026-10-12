import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../providers/leave_providers.dart';

/// `/my-leave/notifications` — in-app notices about the signed-in person's own
/// leave (decisions, returns, cancellations, balance adjustments). A notice
/// exists only because the event it announces was committed with it; nothing
/// is sent outside the app, so there is no "delivered" claim beyond "you can
/// read it here".
class LeaveNotificationsPage extends ConsumerWidget {
  const LeaveNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: BackButton(onPressed: () => context.go('/my-leave')),
      ),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final schoolId = tenant?.school?.schoolId;
          final branchId = tenant?.user.branchId ?? tenant?.branch?.branchId;
          if (tenant == null || schoolId == null || branchId == null) {
            return const EmptyView(
              icon: Icons.notifications_none,
              message: 'No notifications.',
            );
          }
          final key = (
            schoolId: schoolId,
            branchId: branchId,
            userId: tenant.user.userId,
          );
          final list = ref.watch(leaveUserNotificationsProvider(key));
          return list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () =>
                  ref.invalidate(leaveUserNotificationsProvider(key)),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const EmptyView(
                  icon: Icons.notifications_none,
                  message: 'No notifications yet.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final n = items[i];
                  return ListTile(
                    leading: Icon(
                      n.read
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                    ),
                    title: Text(
                      n.title,
                      style: n.read
                          ? null
                          : const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: n.body == null ? null : Text(n.body!),
                    onTap: () async {
                      if (!n.read) {
                        try {
                          await ref
                              .read(leaveNotificationRepositoryProvider)
                              .markRead(schoolId, branchId, n.notificationId);
                        } catch (_) {
                          // Reading is best-effort; navigation still works.
                        }
                      }
                      if (!context.mounted) return;
                      if (n.applicationId != null) {
                        context.go(
                          '/my-leave/applications/${n.applicationId}?b=$branchId',
                        );
                      } else if (n.type.startsWith('TIMETABLE_') ||
                          n.type.startsWith('SUBSTITUTION_')) {
                        context.go('/my-timetable');
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
