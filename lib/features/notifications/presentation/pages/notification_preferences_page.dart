import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../domain/notification_category.dart';
import '../../domain/notification_preferences.dart';
import '../providers/notification_providers.dart';
import '../providers/push_providers.dart';

/// `/notifications/preferences` — which categories appear in the centre.
///
/// In-app is always on; push can be switched off per account (email/SMS are
/// listed as not provided rather than offered as switches that do nothing).
/// Category preferences decide what the centre *shows and counts* and what is
/// pushed; events are still recorded for you. Administrative notices cannot
/// be muted.
class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  NotificationPreferences? _local;
  bool _saving = false;
  String? _error;

  Future<void> _toggle(
    NotificationPreferences current,
    NotificationCategory c,
    bool show,
  ) async {
    await _save(current, current.toggled(c, mute: !show));
  }

  Future<void> _save(
    NotificationPreferences current,
    NotificationPreferences next,
  ) async {
    setState(() {
      _local = next;
      _saving = true;
      _error = null;
    });
    try {
      final scope = await ref.read(notificationScopeProvider.future);
      if (scope == null) return;
      await ref
          .read(notificationRepositoryProvider)
          .savePreferences(scope.userId, next);
      ref.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _local = current;
          _error = userMessageFor(e);
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(notificationPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: userMessageFor(e),
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
        ),
        data: (stored) {
          final p = _local ?? stored;
          return PageColumn(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SectionCard(
                  title: 'Channels',
                  child: Column(
                    children: [
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.notifications_active_outlined),
                        title: Text('In-app'),
                        subtitle: Text('Shown in the notification centre.'),
                        trailing: Text('On'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.phone_android),
                        title: const Text('Push notifications'),
                        subtitle: Text(
                          ref.watch(pushGatewayProvider).supported
                              ? 'Alerts on this device, even when the app '
                                    'is closed.'
                              : 'Available in the Android and iOS apps.',
                        ),
                        value: p.pushEnabled,
                        onChanged:
                            ref.watch(pushGatewayProvider).supported && !_saving
                            ? (v) => _save(p, p.withPush(v))
                            : null,
                      ),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.mail_outline),
                        title: Text('Email and SMS'),
                        subtitle: Text('Not provided.'),
                        trailing: Text('Not available'),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'What to show',
                  child: Column(
                    children: [
                      for (final c in NotificationCategory.values)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.displayName),
                          subtitle: c.mutable
                              ? null
                              : const Text(
                                  'Always shown — these follow school policy.',
                                ),
                          value: p.shows(c),
                          onChanged: c.mutable && !_saving
                              ? (v) => _toggle(p, c, v)
                              : null,
                        ),
                    ],
                  ),
                ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
