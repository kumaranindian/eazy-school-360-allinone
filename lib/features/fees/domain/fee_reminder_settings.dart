import 'money.dart';

/// One reminder step: [days] before (or after) the invoice due date.
class ReminderStep {
  final int days;
  final bool enabled;
  const ReminderStep(this.days, {this.enabled = true});

  ReminderStep copyWith({int? days, bool? enabled}) =>
      ReminderStep(days ?? this.days, enabled: enabled ?? this.enabled);

  @override
  bool operator ==(Object other) =>
      other is ReminderStep && other.days == days && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(days, enabled);
}

/// The school's fee reminder policy (`schools/{s}/feeReminderSettings/config`).
/// Mirrors `functions/fee_reminders.js`, which is the authority: the server
/// validates every save and runs the schedule. The time zone is the school's
/// Regional setting, not stored here.
class FeeReminderSettings {
  static const int maxBeforeDays = 60;
  static const int maxAfterDays = 90;
  static const int maxSteps = 10;

  /// Reminders go out for 3 hours from the delivery time (a missed run is
  /// retried), so the latest start keeps that window before midnight.
  static const String latestDeliveryTime = '21:00';

  final bool enabled;
  final String deliveryTime;
  final bool includeAmount;
  final bool includeInvoiceNumber;
  final bool beforeEnabled;
  final List<ReminderStep> before;
  final bool afterEnabled;
  final List<ReminderStep> after;
  final DateTime? updatedAt;
  final String? updatedBy;

  const FeeReminderSettings({
    required this.enabled,
    required this.deliveryTime,
    required this.includeAmount,
    required this.includeInvoiceNumber,
    required this.beforeEnabled,
    required this.before,
    required this.afterEnabled,
    required this.after,
    this.updatedAt,
    this.updatedBy,
  });

  /// What a school without saved settings runs with: what every school had
  /// before this was configurable (3 days before and on the day, no amount in
  /// the text), plus the overdue steps.
  factory FeeReminderSettings.defaults() => const FeeReminderSettings(
    enabled: true,
    deliveryTime: '08:00',
    includeAmount: false,
    includeInvoiceNumber: false,
    beforeEnabled: true,
    before: [ReminderStep(3), ReminderStep(0)],
    afterEnabled: true,
    after: [ReminderStep(1), ReminderStep(7), ReminderStep(15)],
  );

  factory FeeReminderSettings.fromMap(Map<String, dynamic> d) {
    final def = FeeReminderSettings.defaults();
    List<ReminderStep> steps(Object? g, List<ReminderStep> fallback) {
      final raw = (g is Map ? g['offsets'] : null);
      if (raw is! List) return fallback;
      return [
        for (final o in raw)
          if (o is Map && o['days'] is num)
            ReminderStep(
              (o['days'] as num).toInt(),
              enabled: o['enabled'] != false,
            ),
      ];
    }

    bool group(Object? g) => g is Map ? g['enabled'] != false : true;
    final updated = d['updatedAt'];
    return FeeReminderSettings(
      enabled: d['enabled'] != false,
      deliveryTime: d['deliveryTime'] is String
          ? d['deliveryTime'] as String
          : def.deliveryTime,
      includeAmount: d['includeAmount'] == true,
      includeInvoiceNumber: d['includeInvoiceNumber'] == true,
      beforeEnabled: group(d['beforeDue']),
      before: steps(d['beforeDue'], def.before),
      afterEnabled: group(d['afterDue']),
      after: steps(d['afterDue'], def.after),
      updatedAt: updated is DateTime
          ? updated
          : (updated != null && (updated as dynamic).toDate != null
                ? (updated as dynamic).toDate() as DateTime
                : null),
      updatedBy: d['updatedBy'] as String?,
    );
  }

  /// The payload for `updateFeeReminderSettings` (no audit fields, no school id:
  /// the server stamps those and checks the caller's own school).
  Map<String, dynamic> toCallable() => {
    'enabled': enabled,
    'deliveryTime': deliveryTime,
    'includeAmount': includeAmount,
    'includeInvoiceNumber': includeInvoiceNumber,
    'beforeDue': {
      'enabled': beforeEnabled,
      'offsets': [
        for (final s in before) {'days': s.days, 'enabled': s.enabled},
      ],
    },
    'afterDue': {
      'enabled': afterEnabled,
      'offsets': [
        for (final s in after) {'days': s.days, 'enabled': s.enabled},
      ],
    },
  };

  FeeReminderSettings copyWith({
    bool? enabled,
    String? deliveryTime,
    bool? includeAmount,
    bool? includeInvoiceNumber,
    bool? beforeEnabled,
    List<ReminderStep>? before,
    bool? afterEnabled,
    List<ReminderStep>? after,
  }) => FeeReminderSettings(
    enabled: enabled ?? this.enabled,
    deliveryTime: deliveryTime ?? this.deliveryTime,
    includeAmount: includeAmount ?? this.includeAmount,
    includeInvoiceNumber: includeInvoiceNumber ?? this.includeInvoiceNumber,
    beforeEnabled: beforeEnabled ?? this.beforeEnabled,
    before: before ?? this.before,
    afterEnabled: afterEnabled ?? this.afterEnabled,
    after: after ?? this.after,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  /// Minutes after midnight of "HH:MM", or null when it is not a time.
  static int? minutesOf(String t) {
    final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(t);
    return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }

  /// Why [days] cannot be added to a list, or null. [after] picks the range.
  static String? checkDays(
    int? days,
    List<ReminderStep> existing, {
    required bool after,
  }) {
    final min = after ? 1 : 0;
    final max = after ? maxAfterDays : maxBeforeDays;
    if (days == null) return 'Enter a whole number of days.';
    if (days < min || days > max) {
      return 'Use a number from $min to $max.';
    }
    if (existing.any((s) => s.days == days)) {
      return 'That reminder is already in the list.';
    }
    if (existing.length >= maxSteps) {
      return 'At most $maxSteps reminders in a list.';
    }
    return null;
  }

  /// The first problem with the whole policy, or null. The server repeats
  /// these checks; this is only to show the problem before saving.
  String? validate() {
    final t = minutesOf(deliveryTime);
    if (t == null) return 'Enter the delivery time like 08:00.';
    if (t > minutesOf(latestDeliveryTime)!) {
      return 'Reminders cannot be scheduled after $latestDeliveryTime.';
    }
    for (final isAfter in [false, true]) {
      final list = isAfter ? after : before;
      final label = isAfter ? 'After due date' : 'Before due date';
      if (list.length > maxSteps) return '$label: at most $maxSteps reminders.';
      final seen = <int>{};
      for (final s in list) {
        if (!seen.add(s.days)) return '$label: day ${s.days} is listed twice.';
        final p = checkDays(s.days, const [], after: isAfter);
        if (p != null) return '$label: $p';
      }
    }
    return null;
  }

  bool get nothingWillSend =>
      !enabled ||
      !((beforeEnabled && before.any((s) => s.enabled)) ||
          (afterEnabled && after.any((s) => s.enabled)));

  @override
  bool operator ==(Object other) =>
      other is FeeReminderSettings &&
      other.enabled == enabled &&
      other.deliveryTime == deliveryTime &&
      other.includeAmount == includeAmount &&
      other.includeInvoiceNumber == includeInvoiceNumber &&
      other.beforeEnabled == beforeEnabled &&
      other.afterEnabled == afterEnabled &&
      _same(other.before, before) &&
      _same(other.after, after);

  @override
  int get hashCode => Object.hash(
    enabled,
    deliveryTime,
    includeAmount,
    includeInvoiceNumber,
    beforeEnabled,
    afterEnabled,
    Object.hashAll(before),
    Object.hashAll(after),
  );

  static bool _same(List<ReminderStep> a, List<ReminderStep> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The text of one reminder, as the parent will see it. Mirrors
/// `buildMessage` in `functions/fee_reminders.js` (the server sends it).
class FeeReminderPreview {
  final String title;
  final String body;
  const FeeReminderPreview(this.title, this.body);

  /// [afterDue] true for an overdue step; [days] 0 on the due date.
  factory FeeReminderPreview.build({
    required bool afterDue,
    required int days,
    required String studentName,
    required String invoiceNumber,
    required String dueDateText,
    required int balanceMinor,
    required String currency,
    required FeeReminderSettings settings,
  }) {
    final student = studentName.trim().isEmpty ? 'your child' : studentName;
    final ref = settings.includeInvoiceNumber && invoiceNumber.isNotEmpty
        ? ' (invoice $invoiceNumber)'
        : '';
    final money = Money.format(balanceMinor, currency: currency);
    String amt(String label) =>
        settings.includeAmount ? ' $label: $money.' : '';
    if (afterDue) {
      return FeeReminderPreview(
        'Fee overdue',
        'Dear Parent, the fee payment for $student$ref is overdue by $days '
            'day${days == 1 ? '' : 's'}.${amt('Outstanding amount')} Please '
            'contact the school office if payment has already been made.',
      );
    }
    if (days == 0) {
      return FeeReminderPreview(
        'Fee due today',
        'Dear Parent, the fee payment for $student$ref is due today.'
            '${amt('Amount')}',
      );
    }
    return FeeReminderPreview(
      'Fee due soon',
      'Dear Parent, the fee invoice for $student$ref is due on $dueDateText.'
          '${amt('Amount')} Please complete the payment on time.',
    );
  }
}

/// Reads and saves the policy. Saves go through a Cloud Function that checks
/// the caller is the school admin and validates every value.
abstract interface class FeeReminderSettingsRepository {
  /// The saved policy, or null when the school never saved one (it then runs
  /// with [FeeReminderSettings.defaults]).
  Future<FeeReminderSettings?> load(String schoolId);

  Future<void> save(String schoolId, FeeReminderSettings settings);
}
