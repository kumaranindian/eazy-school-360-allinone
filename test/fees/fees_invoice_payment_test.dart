import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/fee_planners.dart';
import 'package:eazy_school_360/features/fees/domain/fee_summary.dart';
import 'package:eazy_school_360/features/fees/domain/invoice.dart';
import 'package:eazy_school_360/features/fees/domain/payment.dart';
import 'package:eazy_school_360/features/fees/domain/payment_rules.dart';
import 'package:eazy_school_360/features/fees/presentation/widgets/fee_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

InvoiceLine _line(int amount, {int discount = 0}) => InvoiceLine(
  assignmentId: 'a',
  structureId: 's',
  name: 'Tuition',
  category: FeeCategory.tuition,
  amountMinor: amount,
  discountMinor: discount,
  chargeId: 'a__M-2026-06',
);

Invoice _invoice({
  List<InvoiceLine>? lines,
  int waived = 0,
  int paid = 0,
  InvoiceStatus status = InvoiceStatus.issued,
  String due = '2026-06-16',
  String number = 'INV-2026-000012',
}) {
  final l = lines ?? [_line(100000)];
  final subtotal = InvoiceMath.subtotal(l);
  final discount = InvoiceMath.discount(l);
  final payable = subtotal - discount;
  return Invoice(
    invoiceId: 'stu-1__y26__M-2026-06',
    schoolId: 'school-1',
    branchId: 'main',
    invoiceNumber: number,
    numberSeq: 12,
    studentId: 'stu-1',
    studentName: 'Anil Kumar',
    admissionNumber: 'ADM-1',
    academicYearId: 'y26',
    academicYearName: '2026-27',
    classId: 'c5',
    className: 'Class 5',
    sectionId: 'a',
    sectionName: 'A',
    periodKind: FeeFrequency.monthly,
    periodKey: 'M-2026-06',
    periodLabel: 'June 2026',
    issueDateKey: '2026-06-01',
    dueDateKey: due,
    lines: l,
    subtotalMinor: subtotal,
    discountMinor: discount,
    payableMinor: payable,
    waivedMinor: waived,
    paidMinor: paid,
    balanceMinor: InvoiceMath.balance(
      payable: payable,
      waived: waived,
      paid: paid,
    ),
    status: status,
    schoolName: 'Rosewood High',
    branchName: 'Main',
  );
}

void main() {
  group('InvoiceMath', () {
    test('subtotal, discount and payable come from the lines', () {
      final lines = [_line(150000, discount: 37500), _line(50000)];
      expect(InvoiceMath.subtotal(lines), 200000);
      expect(InvoiceMath.discount(lines), 37500);
      expect(InvoiceMath.subtotal(lines) - InvoiceMath.discount(lines), 162500);
    });

    test('balance = payable − waived − paid', () {
      expect(InvoiceMath.balance(payable: 100000, waived: 0, paid: 0), 100000);
      expect(
        InvoiceMath.balance(payable: 100000, waived: 25000, paid: 30000),
        45000,
      );
      expect(InvoiceMath.balance(payable: 100000, waived: 0, paid: 100000), 0);
    });

    test('status follows the money: issued -> partially paid -> paid', () {
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 0, paid: 0),
        InvoiceStatus.issued,
      );
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 0, paid: 1),
        InvoiceStatus.partiallyPaid,
      );
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 0, paid: 99999),
        InvoiceStatus.partiallyPaid,
      );
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 0, paid: 100000),
        InvoiceStatus.paid,
      );
    });

    test('a waiver counts towards "partially paid" and towards "paid"', () {
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 10000, paid: 0),
        InvoiceStatus.partiallyPaid,
      );
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 100000, paid: 0),
        InvoiceStatus.paid,
      );
      expect(
        InvoiceMath.statusFor(payable: 100000, waived: 40000, paid: 60000),
        InvoiceStatus.paid,
      );
    });
  });

  group(
    'A realistic invoice life, applied in order (the same arithmetic firestore.rules enforces)',
    () {
      // payments: [amount], waive/reverse events
      test(
        'multiple partial payments, a waiver, a reversal and a final payment',
        () {
          var paid = 0, waived = 0;
          const payable = 100000;
          InvoiceStatus status() => InvoiceMath.statusFor(
            payable: payable,
            waived: waived,
            paid: paid,
          );
          int balance() =>
              InvoiceMath.balance(payable: payable, waived: waived, paid: paid);

          paid += 30000; // payment 1
          expect((balance(), status()), (70000, InvoiceStatus.partiallyPaid));
          paid += 20000; // payment 2
          expect((balance(), status()), (50000, InvoiceStatus.partiallyPaid));
          waived += 10000; // approved waiver
          expect((balance(), status()), (40000, InvoiceStatus.partiallyPaid));
          paid -= 20000; // payment 2 reversed
          expect((balance(), status()), (60000, InvoiceStatus.partiallyPaid));
          paid += 60000; // final payment of exactly the balance
          expect((balance(), status()), (0, InvoiceStatus.paid));
          expect(paid, 90000);
        },
      );

      test(
        'a refund after full payment makes the invoice owe the money again',
        () {
          var paid = 100000;
          paid -= 100000;
          expect(
            InvoiceMath.statusFor(payable: 100000, waived: 0, paid: paid),
            InvoiceStatus.issued,
          );
          expect(
            InvoiceMath.balance(payable: 100000, waived: 0, paid: paid),
            100000,
          );
        },
      );
    },
  );

  group('Invoice model', () {
    test('overdue is derived from the due date, never stored', () {
      final open = _invoice(due: '2026-06-16');
      expect(
        open.isOverdue('2026-06-16'),
        isFalse,
        reason: 'due today is not overdue',
      );
      expect(open.isOverdue('2026-06-17'), isTrue);
      expect(open.statusLabel('2026-06-17'), 'Overdue');
      expect(open.statusLabel('2026-06-10'), 'Issued');
    });

    test('paid and void invoices are never overdue', () {
      final paid = _invoice(paid: 100000, status: InvoiceStatus.paid);
      final voided = _invoice(status: InvoiceStatus.voided);
      expect(paid.isOverdue('2030-01-01'), isFalse);
      expect(voided.isOverdue('2030-01-01'), isFalse);
      expect(paid.statusLabel('2030-01-01'), 'Paid');
    });

    test(
      'a partially paid invoice past due is overdue for the remaining balance',
      () {
        final partial = _invoice(
          paid: 30000,
          status: InvoiceStatus.partiallyPaid,
        );
        expect(partial.isOverdue('2026-07-01'), isTrue);
        expect(partial.balanceMinor, 70000);
      },
    );

    test(
      'create starts consistent: nothing paid or waived, balance = payable, ISSUED, integers throughout',
      () {
        final data = _invoice(
          lines: [_line(150000, discount: 37500)],
        ).toFirestoreCreate(createdBy: 'fin-1');
        expect(data['status'], 'ISSUED');
        expect(data['subtotalMinor'], 150000);
        expect(data['discountMinor'], 37500);
        expect(data['payableMinor'], 112500);
        expect(
          data['payableMinor'],
          data['subtotalMinor'] - data['discountMinor'],
        );
        expect(data['balanceMinor'], data['payableMinor']);
        expect(data['paidMinor'], 0);
        expect(data['waivedMinor'], 0);
        for (final k in [
          'subtotalMinor',
          'discountMinor',
          'payableMinor',
          'balanceMinor',
          'paidMinor',
          'waivedMinor',
        ]) {
          expect(data[k], isA<int>(), reason: k);
        }
        expect(data['createdBy'], 'fin-1');
        expect(data['createdAt'], isA<FieldValue>());
      },
    );

    test(
      'the issued document keeps a snapshot: names, line descriptions and amounts live on the invoice',
      () {
        final data = _invoice().toFirestoreCreate(createdBy: 'fin-1');
        expect(data['studentName'], 'Anil Kumar');
        expect(data['className'], 'Class 5');
        expect(data['schoolName'], 'Rosewood High');
        final line = (data['lines'] as List).single as Map<String, dynamic>;
        expect(line['name'], 'Tuition');
        expect(line['amountMinor'], 100000);
        expect(line['chargeId'], isNotEmpty);
      },
    );

    test('numberYear reads the academic start year out of the number', () {
      expect(_invoice(number: 'INV-2026-000012').numberYear, 2026);
      expect(_invoice(number: 'INV-2031-000001').numberYear, 2031);
    });

    test('fromFirestore round-trips the lines', () {
      final data =
          _invoice(
              lines: [_line(150000, discount: 37500)],
            ).toFirestoreCreate(createdBy: 'a')
            ..['createdAt'] = Timestamp.now()
            ..['updatedAt'] = Timestamp.now();
      final read = Invoice.fromFirestore('school-1', 'main', 'id', data);
      expect(read.lines.single.netMinor, 112500);
      expect(read.periodKind, FeeFrequency.monthly);
      expect(read.status, InvoiceStatus.issued);
    });
  });

  group('PaymentRules.checkCollect — validation of a payment', () {
    String? check({
      InvoiceStatus status = InvoiceStatus.issued,
      int balance = 100000,
      int amount = 50000,
      PaymentMethod method = PaymentMethod.cash,
      String? label,
      String? reference,
      String date = '2026-06-10',
      String today = '2026-06-10',
    }) => PaymentRules.checkCollect(
      status: status,
      balanceMinor: balance,
      amountMinor: amount,
      method: method,
      methodLabel: label,
      referenceNo: reference,
      paymentDateKey: date,
      todayKey: today,
    );

    test('full and partial payments are accepted', () {
      expect(check(amount: 100000), isNull);
      expect(check(amount: 1), isNull);
      expect(check(amount: 50000), isNull);
      expect(
        check(
          status: InvoiceStatus.partiallyPaid,
          balance: 70000,
          amount: 70000,
        ),
        isNull,
      );
    });

    test('overpayment is rejected, even by one minor unit', () {
      expect(check(amount: 100001), contains('Overpayment'));
      expect(
        check(balance: 70000, amount: 70001),
        contains('more than the balance'),
      );
    });

    test('zero and negative amounts are rejected', () {
      expect(check(amount: 0), contains('greater than zero'));
      expect(check(amount: -500), contains('greater than zero'));
    });

    test('a paid, zero-balance or void invoice accepts no payment', () {
      expect(
        check(status: InvoiceStatus.paid, balance: 0),
        contains('fully paid'),
      );
      expect(check(balance: 0), contains('fully paid'));
      expect(check(status: InvoiceStatus.voided), contains('void'));
    });

    test(
      'UPI, bank transfer and cheque need a reference; cash does not; "other" needs a name',
      () {
        for (final m in [
          PaymentMethod.upi,
          PaymentMethod.bankTransfer,
          PaymentMethod.cheque,
        ]) {
          expect(check(method: m), contains('reference'), reason: m.name);
          expect(check(method: m, reference: 'ab'), isNotNull);
          expect(
            check(method: m, reference: 'UTR123456'),
            isNull,
            reason: m.name,
          );
        }
        expect(check(method: PaymentMethod.cash), isNull);
        expect(check(method: PaymentMethod.other), contains('Name'));
        expect(
          check(method: PaymentMethod.other, label: 'Demand draft'),
          isNull,
        );
      },
    );

    test('a future payment date is rejected; today and earlier are fine', () {
      expect(check(date: '2026-06-11'), contains('future'));
      expect(check(date: '2026-06-10'), isNull);
      expect(check(date: '2026-05-01'), isNull);
    });

    test(
      'an absurd amount is rejected before the balance comparison matters',
      () {
        expect(
          check(balance: 2000000000, amount: PaymentRules.maxPaymentMinor + 1),
          contains('too large'),
        );
      },
    );
  });

  group('reversal, waiver and void rules', () {
    test(
      'only an active payment can be reversed, and a reason is mandatory',
      () {
        expect(
          PaymentRules.checkReverse(isActive: true, reason: 'Wrong amount'),
          isNull,
        );
        expect(
          PaymentRules.checkReverse(isActive: false, reason: 'Wrong amount'),
          contains('already'),
        );
        expect(
          PaymentRules.checkReverse(isActive: true, reason: ' '),
          contains('reason'),
        );
      },
    );

    test(
      'a waiver needs an open invoice, a positive amount within the balance, and a reason',
      () {
        expect(
          PaymentRules.checkWaiver(
            status: InvoiceStatus.issued,
            balanceMinor: 100000,
            amountMinor: 25000,
            reason: 'Hardship',
          ),
          isNull,
        );
        expect(
          PaymentRules.checkWaiver(
            status: InvoiceStatus.issued,
            balanceMinor: 100000,
            amountMinor: 100000,
            reason: 'Hardship',
          ),
          isNull,
        );
        expect(
          PaymentRules.checkWaiver(
            status: InvoiceStatus.issued,
            balanceMinor: 100000,
            amountMinor: 100001,
            reason: 'Hardship',
          ),
          contains('exceed'),
        );
        expect(
          PaymentRules.checkWaiver(
            status: InvoiceStatus.issued,
            balanceMinor: 100000,
            amountMinor: 0,
            reason: 'Hardship',
          ),
          contains('greater than zero'),
        );
        expect(
          PaymentRules.checkWaiver(
            status: InvoiceStatus.paid,
            balanceMinor: 0,
            amountMinor: 1,
            reason: 'Hardship',
          ),
          contains('balance due'),
        );
        expect(
          PaymentRules.checkWaiver(
            status: InvoiceStatus.issued,
            balanceMinor: 100000,
            amountMinor: 5,
            reason: '',
          ),
          contains('reason'),
        );
      },
    );

    test(
      'voiding needs a reason and nothing paid — payments must be reversed first',
      () {
        expect(
          PaymentRules.checkVoid(
            status: InvoiceStatus.issued,
            paidMinor: 0,
            reason: 'Issued twice',
          ),
          isNull,
        );
        expect(
          PaymentRules.checkVoid(
            status: InvoiceStatus.partiallyPaid,
            paidMinor: 30000,
            reason: 'Issued twice',
          ),
          contains('Reverse or refund'),
        );
        expect(
          PaymentRules.checkVoid(
            status: InvoiceStatus.voided,
            paidMinor: 0,
            reason: 'Issued twice',
          ),
          contains('already void'),
        );
        expect(
          PaymentRules.checkVoid(
            status: InvoiceStatus.issued,
            paidMinor: 0,
            reason: 'x',
          ),
          contains('reason'),
        );
      },
    );
  });

  group('Receipt / Payment models', () {
    test(
      'a receipt keeps its point-in-time data and shows reversal without losing anything',
      () {
        final receipt = Receipt.fromFirestore('school-1', 'main', 'pay-1', {
          'receiptNumber': 'RCT-2026-000045',
          'numberSeq': 45,
          'paymentId': 'pay-1',
          'invoiceId': 'inv',
          'invoiceNumber': 'INV-2026-000012',
          'periodLabel': 'June 2026',
          'studentName': 'Anil Kumar',
          'amountMinor': 30000,
          'method': 'UPI',
          'referenceNo': 'UTR1',
          'paymentDateKey': '2026-06-10',
          'balanceAfterMinor': 70000,
          'collectorName': 'Fin Officer',
          'status': 'REVERSED',
        });
        expect(receipt.isReversed, isTrue);
        expect(receipt.receiptNumber, 'RCT-2026-000045');
        expect(receipt.amountMinor, 30000);
        expect(receipt.balanceAfterMinor, 70000);
        expect(receipt.methodDisplay, 'UPI');
      },
    );

    test('"other" methods show their own name', () {
      final p = Payment.fromFirestore('s', 'b', 'p', {
        'method': 'OTHER',
        'methodLabel': 'Demand draft',
        'amountMinor': 1,
        'status': 'ACTIVE',
      });
      expect(p.methodDisplay, 'Demand draft');
      expect(p.isActive, isTrue);
    });

    test(
      'a reversal record carries kind, reason and the amount that came off the invoice',
      () {
        final r = PaymentReversal.fromFirestore('pay-1', {
          'kind': 'REFUND',
          'reason': 'Withdrew',
          'amountMinor': 30000,
          'invoiceId': 'i',
          'studentId': 's',
          'reversalDateKey': '2026-06-11',
        });
        expect(
          (r.kind, r.amountMinor, r.paymentId),
          (ReversalKind.refund, 30000, 'pay-1'),
        );
      },
    );
  });

  group('FeeSummary', () {
    FeeSummary summary({
      int payable = 1000000,
      int waived = 50000,
      int collected = 600000,
      int outstanding = 350000,
    }) => FeeSummary(
      invoiceCount: 10,
      grossMinor: 1100000,
      discountMinor: 100000,
      payableMinor: payable,
      waivedMinor: waived,
      collectedMinor: collected,
      outstandingMinor: outstanding,
      overdueMinor: 100000,
      overdueInvoiceCount: 2,
      partiallyPaidCount: 3,
      paidCount: 4,
    );

    test('payable − waived − collected = outstanding', () {
      expect(summary().isBalanced, isTrue);
      expect(summary(outstanding: 340000).isBalanced, isFalse);
    });

    test(
      'collection rate is collected ÷ (payable − waived); null when nothing is collectable',
      () {
        expect(summary().collectionRate, closeTo(600000 / 950000 * 100, 1e-9));
        expect(
          summary(
            payable: 50000,
            waived: 50000,
            collected: 0,
            outstanding: 0,
          ).collectionRate,
          isNull,
        );
      },
    );
  });

  group(
    'StudentFeeSummary excludes void invoices and splits overdue from upcoming',
    () {
      test('the ledger totals', () {
        final invoices = [
          _invoice(due: '2026-06-16'), // overdue on 2026-07-01: 100000
          _invoice(
            due: '2026-07-20',
            paid: 40000,
            status: InvoiceStatus.partiallyPaid,
          ), // upcoming: 60000
          _invoice(
            due: '2026-05-01',
            paid: 100000,
            status: InvoiceStatus.paid,
          ), // paid
          _invoice(
            due: '2026-06-01',
            status: InvoiceStatus.voided,
          ), // void: ignored
        ];
        final s = StudentFeeSummary.of(invoices, todayKey: '2026-07-01');
        expect(s.payableMinor, 300000);
        expect(s.paidMinor, 140000);
        expect(s.balanceMinor, 160000);
        expect(s.overdueMinor, 100000);
        expect(s.upcomingMinor, 60000);
        expect(s.payableMinor - s.waivedMinor - s.paidMinor, s.balanceMinor);
      });
    },
  );

  group('printable documents', () {
    test(
      'an invoice PDF and a receipt PDF can be produced from their snapshots',
      () async {
        final bytes = await FeePdf.invoice(
          _invoice(lines: [_line(150000, discount: 37500)]),
        );
        expect(bytes.length, greaterThan(500));
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

        final receipt = Receipt.fromFirestore('school-1', 'main', 'pay-1', {
          'receiptNumber': 'RCT-2026-000001',
          'numberSeq': 1,
          'paymentId': 'pay-1',
          'schoolName': 'Rosewood High',
          'studentName': 'Anil Kumar',
          'amountMinor': 30000,
          'method': 'CASH',
          'paymentDateKey': '2026-06-10',
          'balanceAfterMinor': 70000,
          'collectorName': 'Fin Officer',
          'status': 'ACTIVE',
        });
        final receiptBytes = await FeePdf.receipt(receipt);
        expect(String.fromCharCodes(receiptBytes.take(5)), '%PDF-');
      },
    );
  });
}
