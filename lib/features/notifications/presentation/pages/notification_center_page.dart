import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../domain/feed_item.dart';
import '../../domain/notification_category.dart';
import '../providers/notification_providers.dart';

const _pageSize = 30;

/// `/notifications` — everything addressed to the signed-in user: their own
/// notifications and the audience notices they belong to, newest first, with
/// read state. Opening an item marks it read and goes to its screen through
/// the normal route, where access is checked again; a record that is gone or
/// not accessible shows that screen's own "not available" message.
class NotificationCenterPage extends ConsumerStatefulWidget {
  const NotificationCenterPage({super.key});

  @override
  ConsumerState<NotificationCenterPage> createState() =>
      _NotificationCenterPageState();
}

class _NotificationCenterPageState
    extends ConsumerState<NotificationCenterPage> {
  int _limit = _pageSize;
  bool _unreadOnly = false;
  NotificationCategory? _category;
  bool _busy = false;

  IconData _icon(NotificationCategory c) => switch (c) {
    NotificationCategory.announcement => Icons.campaign_outlined,
    NotificationCategory.homework => Icons.menu_book_outlined,
    NotificationCategory.results => Icons.workspace_premium_outlined,
    NotificationCategory.attendance => Icons.fact_check_outlined,
    NotificationCategory.leave => Icons.event_busy_outlined,
    NotificationCategory.fees => Icons.receipt_long_outlined,
    NotificationCategory.timetable => Icons.calendar_view_week_outlined,
    NotificationCategory.messages => Icons.forum_outlined,
    NotificationCategory.administrative => Icons.info_outline,
  };

  Future<void> _open(FeedItem item) async {
    final scope = ref.read(notificationScopeProvider).value;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await markFeedItemRead(ref, item);
    } catch (_) {
      // Failing to record "read" must not stop the user opening it.
    }
    final role = scope?.role;
    final route = role == null
        ? null
        : NotificationNavigator.routeFor(item, role);
    if (route == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('There is nothing more to open.')),
      );
      return;
    }
    router.go(route);
  }

  Future<void> _markAll(FeedState state) async {
    final n = state.unread;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark all as read?'),
        content: Text(
          '$n unread notification${n == 1 ? '' : 's'} will be marked as read.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Mark all as read'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await markAllFeedRead(ref, state.items);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider(_limit));
    return Scaffold(
      appBar: pageAppBar(
        context,
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all),
            onPressed: _busy || feed.value == null || feed.value!.unread == 0
                ? null
                : () => _markAll(feed.value!),
          ),
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.tune),
            onPressed: () => context.go(AppRoutes.notificationPreferences),
          ),
        ],
      ),
      body: feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: userMessageFor(e),
          onRetry: () {
            ref.invalidate(sharedFeedProvider);
            ref.invalidate(notificationScopeProvider);
          },
        ),
        data: (state) {
          final shown = [
            for (final i in state.items)
              if ((!_unreadOnly || !i.read) &&
                  (_category == null || i.category == _category))
                i,
          ];
          return PageColumn(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: !_unreadOnly,
                      onSelected: (_) => setState(() => _unreadOnly = false),
                    ),
                    ChoiceChip(
                      label: Text('Unread (${state.unread})'),
                      selected: _unreadOnly,
                      onSelected: (_) => setState(() => _unreadOnly = true),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<NotificationCategory?>(
                        value: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All'),
                          ),
                          for (final c in NotificationCategory.values)
                            DropdownMenuItem(
                              value: c,
                              child: Text(c.displayName),
                            ),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: EmptyView(
                      icon: Icons.notifications_none,
                      message: 'You\'re all caught up. Nothing to show here.',
                    ),
                  )
                else
                  for (final n in shown)
                    Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      color: n.read
                          ? null
                          : Theme.of(context).colorScheme.secondaryContainer
                                .withValues(alpha: 0.35),
                      child: ListTile(
                        leading: Icon(_icon(n.category)),
                        title: Text(
                          n.title,
                          style: n.read
                              ? null
                              : const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (n.body.isNotEmpty) Text(n.body),
                            Text(
                              '${n.category.displayName} · ${formatInstant(n.createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        isThreeLine: n.body.isNotEmpty,
                        trailing: n.read
                            ? const Icon(Icons.chevron_right)
                            : Semantics(
                                label: 'Unread',
                                child: const Icon(Icons.circle, size: 10),
                              ),
                        onTap: () => _open(n),
                      ),
                    ),
                if (state.mayHaveMore)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _limit += _pageSize),
                        child: const Text('Load earlier notifications'),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
