import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/invoice.dart';
import 'package:eazy_school_360/features/fees/domain/invoice_reconciler.dart';
import 'package:eazy_school_360/features/fees/domain/payment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fee_fakes.dart';

Payment _p(
  String id,
  int amount, {
  PaymentStatus status = PaymentStatus.active,
  String receipt = 'RCT-1',
  String? invoiceId,
  String student = 'stu-1',
}) {
  final base = fakePayment(id: id, amount: amount, status: status);
  return Payment(
    paymentId: base.paymentId,
    schoolId: base.schoolId,
    branchId: base.branchId,
    invoiceId: invoiceId ?? base.invoiceId,
    invoiceNumber: base.invoiceNumber,
    studentId: student,
    studentName: base.studentName,
    academicYearId: base.academicYearId,
    classId: base.classId,
    amountMinor: amount,
    method: base.method,
    paymentDateKey: base.paymentDateKey,
    receiptNumber: receipt,
    balanceAfterMinor: base.balanceAfterMinor,
    collectedBy: base.collectedBy,
    collectorName: base.collectorName,
    status: status,
  );
}

Set<String> _codes(Invoice i, List<Payment> p) => {
  for (final x in InvoiceReconciler.check(i, p)) x.code,
};

void main() {
  test('a consistent invoice with partial payments reconciles cleanly', () {
    final inv = fakeInvoice(payable: 100000, paid: 70000);
    final pays = [_p('a', 30000, receipt: 'R1'), _p('b', 40000, receipt: 'R2')];
    expect(InvoiceReconciler.check(inv, pays), isEmpty);
  });

  test('a reversed payment is excluded from the paid total', () {
    final inv = fakeInvoice(payable: 100000, paid: 30000);
    final pays = [
      _p('a', 30000, receipt: 'R1'),
      _p('b', 40000, receipt: 'R2', status: PaymentStatus.reversed),
    ];
    expect(InvoiceReconciler.check(inv, pays), isEmpty);
  });

  test('boundary: exactly paid, and one minor unit short', () {
    final paid = fakeInvoice(payable: 100000, paid: 100000);
    expect(InvoiceReconciler.check(paid, [_p('a', 100000)]), isEmpty);
    final short = fakeInvoice(payable: 100000, paid: 99999);
    expect(InvoiceReconciler.check(short, [_p('a', 99999)]), isEmpty);
    // stored paid says 100000 but payments only reach 99999
    expect(_codes(paid, [_p('a', 99999)]), contains('PAID_MISMATCH'));
  });

  test('detects a paid total that disagrees with its payments', () {
    final inv = fakeInvoice(payable: 100000, paid: 50000);
    expect(_codes(inv, [_p('a', 30000)]), contains('PAID_MISMATCH'));
  });

  test('detects duplicate receipts, foreign and cross-student payments', () {
    final inv = fakeInvoice(payable: 100000, paid: 60000);
    final dup = [_p('a', 30000, receipt: 'R1'), _p('b', 30000, receipt: 'R1')];
    expect(_codes(inv, dup), contains('DUPLICATE_RECEIPT'));
    final foreign = [_p('a', 60000, invoiceId: 'other-invoice')];
    expect(
      _codes(inv, foreign),
      containsAll(['FOREIGN_PAYMENT', 'PAID_MISMATCH']),
    );
    final stranger = [_p('a', 60000, student: 'stu-2')];
    expect(_codes(inv, stranger), contains('STUDENT_MISMATCH'));
  });

  test('detects a status that does not follow the figures', () {
    final inv = fakeInvoice(
      payable: 100000,
      paid: 100000,
      status: InvoiceStatus.partiallyPaid,
    );
    expect(_codes(inv, [_p('a', 100000)]), contains('STATUS_MISMATCH'));
  });

  test('a void invoice with active payments is flagged', () {
    final inv = fakeInvoice(
      payable: 100000,
      paid: 30000,
      status: InvoiceStatus.voided,
    );
    expect(_codes(inv, [_p('a', 30000)]), contains('VOID_WITH_PAYMENTS'));
  });

  test('is read-only and deterministic', () {
    final inv = fakeInvoice(payable: 100000, paid: 50000);
    final pays = [_p('a', 30000)];
    final first = InvoiceReconciler.check(inv, pays).map((i) => '$i').toList();
    final second = InvoiceReconciler.check(inv, pays).map((i) => '$i').toList();
    expect(second, first);
    expect(pays.single.amountMinor, 30000);
  });
}
