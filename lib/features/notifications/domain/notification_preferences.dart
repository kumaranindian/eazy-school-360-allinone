import 'notification_category.dart';

/// A user's choices: which categories are shown and counted, and whether
/// this account receives push notifications on its devices. Push is on unless
/// the user turned it off; the sending side also skips muted categories.
class NotificationPreferences {
  final Set<NotificationCategory> muted;
  final bool pushEnabled;

  const NotificationPreferences({
    this.muted = const {},
    this.pushEnabled = true,
  });

  NotificationPreferences withPush(bool enabled) =>
      NotificationPreferences(muted: muted, pushEnabled: enabled);

  /// Whether items of [category] are shown and counted. A critical category
  /// is always shown, whatever was stored.
  bool shows(NotificationCategory category) =>
      !category.mutable || !muted.contains(category);

  NotificationPreferences toggled(
    NotificationCategory c, {
    required bool mute,
  }) {
    if (!c.mutable) return this;
    final next = {...muted};
    mute ? next.add(c) : next.remove(c);
    return NotificationPreferences(muted: next, pushEnabled: pushEnabled);
  }

  Map<String, dynamic> toMap() => {
    'mutedCategories': [
      for (final c in muted)
        if (c.mutable) c.wireValue,
    ],
    'pushEnabled': pushEnabled,
  };

  factory NotificationPreferences.fromMap(Map<String, dynamic>? m) =>
      NotificationPreferences(
        muted: {
          for (final v in (m?['mutedCategories'] as List? ?? const []))
            NotificationCategory.fromWireValue(v as String),
        }.where((c) => c.mutable).toSet(),
        pushEnabled: m?['pushEnabled'] != false,
      );
}
