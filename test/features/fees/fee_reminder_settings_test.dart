import 'package:eazy_school_360/features/fees/domain/fee_reminder_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a school without saved settings gets the standard reminders', () {
    final d = FeeReminderSettings.defaults();
    expect(d.before.map((s) => s.days), [3, 0]);
    expect(d.after.map((s) => s.days), [1, 7, 15]);
    expect(d.deliveryTime, '08:00');
    expect(d.enabled, isTrue);
    expect(d.includeAmount, isFalse);
    expect(d.validate(), isNull);
  });

  test('round trip through the stored shape', () {
    final s = FeeReminderSettings.defaults().copyWith(
      includeAmount: true,
      deliveryTime: '09:30',
      after: const [ReminderStep(2), ReminderStep(9, enabled: false)],
    );
    final stored = s.toCallable();
    final back = FeeReminderSettings.fromMap(stored);
    expect(back, s);
    expect((stored['afterDue'] as Map)['offsets'], [
      {'days': 2, 'enabled': true},
      {'days': 9, 'enabled': false},
    ]);
    expect(stored.containsKey('schoolId'), isFalse);
    expect(stored.containsKey('updatedBy'), isFalse);
  });

  test('validation: times, ranges, duplicates, counts', () {
    final d = FeeReminderSettings.defaults();
    expect(d.copyWith(deliveryTime: '8am').validate(), contains('08:00'));
    expect(d.copyWith(deliveryTime: '22:00').validate(), contains('21:00'));
    expect(d.copyWith(deliveryTime: '21:00').validate(), isNull);
    expect(
      d.copyWith(before: const [ReminderStep(61)]).validate(),
      contains('0 to 60'),
    );
    expect(
      d.copyWith(after: const [ReminderStep(0)]).validate(),
      contains('1 to 90'),
    );
    expect(
      d.copyWith(after: const [ReminderStep(7), ReminderStep(7)]).validate(),
      contains('twice'),
    );
    expect(
      d
          .copyWith(before: [for (var i = 0; i < 11; i++) ReminderStep(i)])
          .validate(),
      contains('at most 10'),
    );
  });

  test('checkDays refuses duplicates, junk and out-of-range numbers', () {
    const existing = [ReminderStep(3)];
    expect(
      FeeReminderSettings.checkDays(3, existing, after: false),
      contains('already'),
    );
    expect(
      FeeReminderSettings.checkDays(null, existing, after: false),
      isNotNull,
    );
    expect(FeeReminderSettings.checkDays(0, existing, after: true), isNotNull);
    expect(FeeReminderSettings.checkDays(0, existing, after: false), isNull);
    expect(FeeReminderSettings.checkDays(91, existing, after: true), isNotNull);
  });

  test('nothingWillSend is true for every way of silencing the school', () {
    final d = FeeReminderSettings.defaults();
    expect(d.nothingWillSend, isFalse);
    expect(d.copyWith(enabled: false).nothingWillSend, isTrue);
    expect(
      d.copyWith(beforeEnabled: false, afterEnabled: false).nothingWillSend,
      isTrue,
    );
    expect(
      d
          .copyWith(
            before: const [ReminderStep(3, enabled: false)],
            after: const [ReminderStep(1, enabled: false)],
          )
          .nothingWillSend,
      isTrue,
    );
  });

  test('preview wording matches the server, with and without amount', () {
    FeeReminderPreview p(bool after, int days, FeeReminderSettings s) =>
        FeeReminderPreview.build(
          afterDue: after,
          days: days,
          studentName: 'Asha Rao',
          invoiceNumber: 'INV-7',
          dueDateText: '6 Aug 2026',
          balanceMinor: 150000,
          currency: 'INR',
          settings: s,
        );
    final plain = FeeReminderSettings.defaults();
    final full = plain.copyWith(
      includeAmount: true,
      includeInvoiceNumber: true,
    );
    expect(
      p(false, 3, plain).body,
      'Dear Parent, the fee invoice for Asha Rao is due on 6 Aug 2026. '
      'Please complete the payment on time.',
    );
    expect(
      p(false, 3, full).body,
      'Dear Parent, the fee invoice for Asha Rao (invoice INV-7) is due on '
      '6 Aug 2026. Amount: ₹1,500.00. Please complete the payment on time.',
    );
    expect(
      p(false, 0, full).body,
      'Dear Parent, the fee payment for Asha Rao (invoice INV-7) is due '
      'today. Amount: ₹1,500.00.',
    );
    expect(p(true, 1, plain).body, contains('overdue by 1 day.'));
    expect(
      p(true, 7, full).body,
      'Dear Parent, the fee payment for Asha Rao (invoice INV-7) is overdue '
      'by 7 days. Outstanding amount: ₹1,500.00. Please contact the school '
      'office if payment has already been made.',
    );
  });
}
