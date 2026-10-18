import 'package:eazy_school_360/core/regional/currency.dart';
import 'package:eazy_school_360/features/fees/domain/billing_period.dart';
import 'package:eazy_school_360/features/fees/domain/fee_dates.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'Money.parseMinor — typed amounts become exact integers, never silently rounded',
    () {
      test(
        'accepts whole, one- and two-decimal amounts, with thousands separators',
        () {
          expect(Money.parseMinor('1500', currency: 'INR'), 150000);
          expect(Money.parseMinor('1,500', currency: 'INR'), 150000);
          expect(Money.parseMinor('1500.5', currency: 'INR'), 150050);
          expect(Money.parseMinor('1500.05', currency: 'INR'), 150005);
          expect(Money.parseMinor('0.99', currency: 'INR'), 99);
          expect(Money.parseMinor('  250 ', currency: 'INR'), 25000);
          expect(Money.parseMinor('0', currency: 'INR'), 0);
        },
      );

      test(
        'rejects everything that is not a plain non-negative amount of at most two decimals',
        () {
          for (final bad in [
            '',
            'abc',
            '-5',
            '1.234',
            '1.',
            '.5',
            '1e3',
            '12 34',
            '1,2,3.456',
            '99999999999999',
          ]) {
            expect(Money.parseMinor(bad, currency: 'INR'), isNull, reason: bad);
          }
        },
      );

      test('round-trips through plain()', () {
        for (final minor in [0, 1, 99, 100, 150050, 123456789]) {
          expect(
            Money.parseMinor(
              Money.plain(minor, currency: 'INR'),
              currency: 'INR',
            ),
            minor,
          );
        }
      });
    },
  );

  group('Money.format', () {
    test('uses the currency symbol and Indian digit grouping', () {
      expect(Money.format(150000, currency: 'INR'), '₹1,500.00');
      expect(Money.format(123456789, currency: 'INR'), '₹12,34,567.89');
      expect(Money.format(5, currency: 'INR'), '₹0.05');
      expect(Money.format(0, currency: 'INR'), '₹0.00');
    });

    test('other currencies and unknown codes', () {
      expect(Money.format(1050, currency: 'USD'), r'$10.50');
      expect(Money.format(1050, currency: 'XYZ'), 'XYZ 10.50');
      expect(Money.format(-250, currency: 'INR'), '-₹2.50');
      expect(Money.format(123456789, currency: 'USD'), r'$1,234,567.89');
      expect(Money.format(99999900, currency: 'INR'), '₹9,99,999.00');
      expect(Money.format(100000, currency: 'INR'), '₹1,000.00');
    });
  });

  group('Money.percentOf — half-up rounding, in integers', () {
    test('exact results are exact', () {
      expect(Money.percentOf(100000, 1000), 10000); // 10% of 1000.00
      expect(Money.percentOf(100000, 10000), 100000); // 100%
      expect(Money.percentOf(100000, 0), 0);
    });

    test('rounds half up at the minor unit', () {
      expect(
        Money.percentOf(100005, 1000),
        10001,
      ); // 10% of 1000.05 = 100.005 -> 100.01
      expect(Money.percentOf(100000, 3333), 33330); // 33.33% of 1000.00
      expect(Money.percentOf(333, 5000), 167); // 50% of 3.33 = 1.665 -> 1.67
      expect(Money.percentOf(1, 4999), 0); // 0.4999 -> 0
      expect(Money.percentOf(1, 5000), 1); // 0.5 -> 1
    });

    test('never exceeds the amount for a percentage up to 100%', () {
      for (final amount in [1, 7, 99, 100001, 999999]) {
        for (final bp in [1, 3333, 5000, 9999, 10000]) {
          final discount = Money.percentOf(amount, bp);
          expect(discount, lessThanOrEqualTo(amount), reason: '$amount @ $bp');
          expect(discount, greaterThanOrEqualTo(0));
        }
      }
    });
  });

  group('BillingPeriod', () {
    test(
      'keys are stable, prefixed by kind, and safe inside a document id',
      () {
        expect(BillingPeriod.monthly(2026, 6).key, 'M-2026-06');
        expect(BillingPeriod.quarterly(2026, 2).key, 'Q-2026-2');
        expect(BillingPeriod.halfYearly(2026, 1).key, 'H-2026-1');
        expect(BillingPeriod.annual(2026).key, 'A-2026');
        expect(
          BillingPeriod.oneTime('Admission 2026!').key,
          'O-admission-2026',
        );
        expect(BillingPeriod.custom('Term 1').key, 'C-term-1');
        for (final p in [
          BillingPeriod.monthly(2026, 12),
          BillingPeriod.oneTime('A/B  c'),
          BillingPeriod.custom('  Ünï  '),
        ]) {
          expect(
            RegExp(r'^[A-Za-z0-9-]+$').hasMatch(p.key),
            isTrue,
            reason: p.key,
          );
          expect(
            p.key.contains('__'),
            isFalse,
            reason: 'the separator must not appear inside a key',
          );
        }
      },
    );

    test(
      'labels are human-readable and kinds match the fee frequency they bill',
      () {
        expect(BillingPeriod.monthly(2026, 6).label, 'June 2026');
        expect(BillingPeriod.monthly(2026, 6).kind, FeeFrequency.monthly);
        expect(BillingPeriod.quarterly(2026, 3).label, 'Quarter 3 2026');
        expect(BillingPeriod.oneTime('Admission').kind, FeeFrequency.oneTime);
        expect(BillingPeriod.custom('Term 1').kind, FeeFrequency.custom);
      },
    );

    test('one invoice per student, year and period — the id says so', () {
      expect(
        BillingPeriod.invoiceId('stu-1', 'y26', 'M-2026-06'),
        'stu-1__y26__M-2026-06',
      );
      expect(
        BillingPeriod.invoiceId('stu-1', 'y26', 'M-2026-06'),
        isNot(BillingPeriod.invoiceId('stu-1', 'y26', 'M-2026-07')),
      );
      expect(
        BillingPeriod.invoiceId('stu-1', 'y26', 'M-2026-06'),
        isNot(BillingPeriod.invoiceId('stu-2', 'y26', 'M-2026-06')),
      );
    });

    test(
      'a one-time fee has a single charge key whatever period it is billed under; recurring fees follow the period',
      () {
        expect(BillingPeriod.chargeKeyFor(FeeFrequency.oneTime, 'O-a'), 'ONCE');
        expect(BillingPeriod.chargeKeyFor(FeeFrequency.oneTime, 'O-b'), 'ONCE');
        expect(
          BillingPeriod.chargeKeyFor(FeeFrequency.monthly, 'M-2026-06'),
          'M-2026-06',
        );
        expect(
          BillingPeriod.chargeKeyFor(FeeFrequency.monthly, 'M-2026-06'),
          isNot(BillingPeriod.chargeKeyFor(FeeFrequency.monthly, 'M-2026-07')),
        );
      },
    );

    test('custom names need 3-40 characters', () {
      expect(BillingPeriod.validateLabel('ab'), isNotNull);
      expect(BillingPeriod.validateLabel('   '), isNotNull);
      expect(BillingPeriod.validateLabel('x' * 41), isNotNull);
      expect(BillingPeriod.validateLabel('Term 1'), isNull);
    });
  });

  group('FeeDates / FeeNumbers', () {
    test(
      'addDays crosses month and year boundaries with no timezone drift',
      () {
        expect(FeeDates.addDays('2026-06-10', 15), '2026-06-25');
        expect(FeeDates.addDays('2026-06-25', 15), '2026-07-10');
        expect(FeeDates.addDays('2026-12-25', 10), '2027-01-04');
        expect(FeeDates.addDays('2028-02-20', 10), '2028-03-01');
        expect(FeeDates.addDays('2026-06-10', 0), '2026-06-10');
      },
    );

    test('display format', () {
      expect(FeeDates.display('2026-06-09'), '09/06/2026');
      expect(FeeDates.display('nonsense'), 'nonsense');
    });

    test(
      'invoice and receipt numbers: prefix, academic start year, zero-padded sequence',
      () {
        expect(FeeNumbers.invoice(2026, 1), 'INV-2026-000001');
        expect(FeeNumbers.invoice(2026, 123456), 'INV-2026-123456');
        expect(FeeNumbers.invoice(2026, 1234567), 'INV-2026-1234567');
        expect(FeeNumbers.receipt(2026, 45), 'RCT-2026-000045');
        expect(
          RegExp(
            r'^INV-[0-9]{4}-[0-9]{6,}$',
          ).hasMatch(FeeNumbers.invoice(2026, 7)),
          isTrue,
          reason: 'must satisfy the firestore.rules pattern',
        );
        expect(
          RegExp(
            r'^RCT-[0-9]{4}-[0-9]{6,}$',
          ).hasMatch(FeeNumbers.receipt(2026, 7)),
          isTrue,
        );
        expect(FeeNumbers.counterId('invoice', 'y26'), 'invoice_y26');
      },
    );

    test('numbers sort in issue order', () {
      final numbers = [
        for (final n in [10, 2, 33, 1]) FeeNumbers.invoice(2026, n),
      ]..sort();
      expect(numbers, [
        FeeNumbers.invoice(2026, 1),
        FeeNumbers.invoice(2026, 2),
        FeeNumbers.invoice(2026, 10),
        FeeNumbers.invoice(2026, 33),
      ]);
    });
  });

  group('currencies with 0 and 3 decimals (multi-country)', () {
    test('yen has no fraction: minor units are whole yen', () {
      expect(Money.format(1500, currency: 'JPY'), '¥1,500');
      expect(Money.format(0, currency: 'JPY'), '¥0');
      expect(Money.plain(1500, currency: 'JPY'), '1500');
      expect(Money.parseMinor('1,500', currency: 'JPY'), 1500);
      expect(Money.parseMinor('1500.5', currency: 'JPY'), isNull);
      expect(Money.parseMinor('1500.0', currency: 'JPY'), isNull);
    });

    test('dinars have three decimals', () {
      expect(Money.format(1234567, currency: 'KWD'), 'KWD 1,234.567');
      expect(Money.format(5, currency: 'KWD'), 'KWD 0.005');
      expect(Money.plain(1234567, currency: 'KWD'), '1234.567');
      expect(Money.parseMinor('1234.567', currency: 'KWD'), 1234567);
      expect(Money.parseMinor('1.5', currency: 'KWD'), 1500);
      expect(Money.parseMinor('1.5678', currency: 'KWD'), isNull);
    });

    test('a two-decimal currency refuses a third decimal', () {
      expect(Money.parseMinor('1.234', currency: 'USD'), isNull);
    });

    test('grouping follows the currency, not the country of the viewer', () {
      expect(Money.format(123456789, currency: 'USD'), r'$1,234,567.89');
      expect(Money.format(123456789, currency: 'PKR'), 'Rs 12,34,567.89');
      expect(Money.format(123456789, currency: 'EUR'), '€1,234,567.89');
    });

    test('every parsed amount prints back to the same number (round trip)', () {
      for (final c in ['INR', 'JPY', 'KWD', 'USD', 'BHD']) {
        for (final minor in [0, 1, 9, 10, 99, 100, 1234567, 99999999]) {
          expect(
            Money.parseMinor(Money.plain(minor, currency: c), currency: c),
            minor,
            reason: '$c $minor',
          );
        }
      }
    });

    test('every offered currency has a plausible exponent', () {
      for (final c in Currencies.all) {
        expect([0, 2, 3], contains(c.decimals), reason: c.code);
      }
      expect(Currencies.of('JPY').decimals, 0);
      expect(Currencies.of('KWD').decimals, 3);
      expect(Currencies.isSupported('INR'), isTrue);
      expect(Currencies.isSupported('XXX'), isFalse);
    });
  });
}
