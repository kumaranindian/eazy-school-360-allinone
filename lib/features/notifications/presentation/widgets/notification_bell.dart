import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../providers/notification_providers.dart';

/// The app bar's bell, with the unread count (capped, from a bounded window).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadBadgeProvider);
    return IconButton(
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () => context.go(AppRoutes.notifications),
    );
  }
}
