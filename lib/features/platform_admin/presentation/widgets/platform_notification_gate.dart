import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../domain/platform_ops_models.dart';
import '../providers/platform_ops_providers.dart';

/// Whether this person receives platform notifications (school and branch
/// administrators, never during a support session).
bool receivesPlatformNotifications(TenantContext? tenant) =>
    tenant != null &&
    !tenant.supportSession &&
    (tenant.role == UserRole.schoolAdmin ||
        tenant.role == UserRole.branchAdmin);

/// Shows a notification that needs acknowledgement as a popup that cannot be
/// waved away: it stays (and returns on the next launch) until the
/// administrator presses "I understand" and the server has recorded it.
class PlatformNotificationGate extends ConsumerStatefulWidget {
  final Widget child;

  const PlatformNotificationGate({super.key, required this.child});

  @override
  ConsumerState<PlatformNotificationGate> createState() =>
      _PlatformNotificationGateState();
}

class _PlatformNotificationGateState
    extends ConsumerState<PlatformNotificationGate> {
  bool _showing = false;

  Future<void> _show(PlatformNotification n) async {
    _showing = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NotificationDialog(notification: n),
    );
    _showing = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(tenantContextProvider).value;
    if (!receivesPlatformNotifications(tenant)) return widget.child;
    final list =
        ref.watch(myPlatformNotificationsProvider).value ??
        const <PlatformNotification>[];
    final pending =
        [
          for (final n in list)
            if (n.pendingAck) n,
        ]..sort(
          (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
            b.createdAt ?? DateTime(0),
          ),
        );
    if (pending.isNotEmpty && !_showing) {
      final first = pending.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_showing) _show(first);
      });
    }
    return widget.child;
  }
}

/// One notification with its single required action.
class NotificationDialog extends ConsumerStatefulWidget {
  final PlatformNotification notification;

  const NotificationDialog({super.key, required this.notification});

  @override
  ConsumerState<NotificationDialog> createState() => _NotificationDialogState();
}

class _NotificationDialogState extends ConsumerState<NotificationDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _act() async {
    final n = widget.notification;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(platformOpsRepositoryProvider);
    try {
      if (n.requiresAck) {
        await repo.acknowledgeNotification(n.id);
      } else {
        await repo.dismissNotification(n.id);
      }
    } catch (e) {
      // Offline or refused: keep it open so nothing is lost; it also returns next launch.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = userMessageFor(e);
      });
      return;
    }
    ref.invalidate(myPlatformNotificationsProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (n.severity) {
      NoticeSeverity.critical => (Icons.error_outline, scheme.error),
      NoticeSeverity.warning => (Icons.warning_amber_rounded, scheme.tertiary),
      NoticeSeverity.info => (Icons.info_outline, scheme.primary),
    };
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('platform-notification'),
        icon: Icon(icon.$1, color: icon.$2),
        title: Text(n.title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.body),
                if (n.createdAt != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatInstant(n.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const ValueKey('notification-ack'),
            onPressed: _busy ? null : _act,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(n.requiresAck ? 'I understand' : 'Dismiss'),
          ),
        ],
      ),
    );
  }
}

/// App-bar button: the inbox of every platform notification, with a badge
/// while any still needs acknowledging.
class PlatformMessagesButton extends ConsumerWidget {
  const PlatformMessagesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    if (!receivesPlatformNotifications(tenant)) return const SizedBox.shrink();
    final list =
        ref.watch(myPlatformNotificationsProvider).value ??
        const <PlatformNotification>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final pending = list.where((n) => n.pendingAck).length;
    return IconButton(
      key: const ValueKey('platform-messages'),
      tooltip: 'Messages from Avail404',
      icon: Badge(
        isLabelVisible: pending > 0,
        label: Text('$pending'),
        child: const Icon(Icons.mark_email_unread_outlined),
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => const _InboxDialog(),
      ),
    );
  }
}

class _InboxDialog extends ConsumerWidget {
  const _InboxDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list =
        ref.watch(myPlatformNotificationsProvider).value ??
        const <PlatformNotification>[];
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Messages from Avail404'),
      content: SizedBox(
        width: 460,
        child: list.isEmpty
            ? const Text('No messages.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final n in list)
                    ListTile(
                      key: ValueKey('inbox-${n.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(n.title),
                      subtitle: Text(
                        '${n.body}\n${n.createdAt == null ? '' : formatInstant(n.createdAt)}',
                      ),
                      isThreeLine: true,
                      trailing: n.pendingAck
                          ? TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) =>
                                    NotificationDialog(notification: n),
                              ),
                              child: const Text('Review'),
                            )
                          : Text(
                              n.acknowledged ? 'Acknowledged' : '',
                              style: text.bodySmall,
                            ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
