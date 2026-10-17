import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../domain/push_route.dart';
import '../providers/notification_providers.dart';
import '../providers/push_providers.dart';

/// Tells the user straight away when a new notification arrives while the
/// app is open, and registers the device for push when it is not. The feed is live, so this reacts the moment an admin sends
/// something; muted categories are already filtered out of the feed.
///
/// The first load only records what is already there, so opening the app
/// never replays old notifications as alerts.
class NotificationAlerts extends ConsumerStatefulWidget {
  final Widget child;

  const NotificationAlerts({super.key, required this.child});

  @override
  ConsumerState<NotificationAlerts> createState() => _NotificationAlertsState();
}

class _NotificationAlertsState extends ConsumerState<NotificationAlerts> {
  Set<String>? _seen;
  StreamSubscription<Map<String, String>>? _opened;

  @override
  void initState() {
    super.initState();
    // Tapping a push opens the notification centre (never a destination named
    // by the payload; see [PushRoute]).
    // Best-effort: a messaging failure must never stop the app from opening.
    try {
      final gateway = ref.read(pushGatewayProvider);
      if (!gateway.supported) return;
      _opened = gateway.onOpened.listen(_open, onError: (_) {});
      unawaited(
        gateway
            .launchedBy()
            .then((d) {
              if (d != null) _open(d);
            })
            .catchError((_) {}),
      );
    } catch (_) {}
  }

  void _open(Map<String, String> data) {
    if (mounted) context.go(PushRoute.resolve(data));
  }

  @override
  void dispose() {
    _opened?.cancel();
    super.dispose();
  }

  void _onFeed(AsyncValue<FeedState>? _, AsyncValue<FeedState> next) {
    final feed = next.value;
    if (feed == null) return;
    final unread = [
      for (final i in feed.items)
        if (!i.read) i,
    ];
    final seen = _seen;
    _seen = {...?seen, for (final i in unread) i.id};
    if (seen == null) return;
    final fresh = unread.where((i) => !seen.contains(i.id)).toList();
    if (fresh.isEmpty || !mounted) return;

    final first = fresh.first;
    final text = fresh.length == 1
        ? first.title
        : '${first.title} (+${fresh.length - 1} more)';
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.go(AppRoutes.notifications),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedProvider(30), _onFeed);
    // Registers this device for push (and keeps it in step with the setting).
    ref.watch(pushRegistrationProvider);
    return widget.child;
  }
}
