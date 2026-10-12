import 'fee_enums.dart';
import 'invoice.dart';
import 'payment.dart';

/// One way an invoice's stored (derived) figures disagree with their source
/// records. The reconciler only *reports*: it never changes data. A finding
/// is corrected by a new, attributable transaction (a reversal, waiver or a
/// support-approved correction), never by editing history — see
/// docs/milestone-12-production-readiness.md, "Reconciling financial data".
class ReconciliationIssue {
  /// Stable machine code, e.g. `PAID_MISMATCH`.
  final String code;
  final String message;
  final String invoiceId;
  final String? paymentId;

  const ReconciliationIssue(
    this.code,
    this.message,
    this.invoiceId, {
    this.paymentId,
  });

  @override
  String toString() => '$code: $message';
}

/// Cross-checks an invoice against its payments. Pure and deterministic.
///
/// Every check is an identity the write rules already enforce at write time;
/// this verifies that the *stored* state still satisfies them, which is what
/// an operator needs after a restore, an import or an incident.
abstract final class InvoiceReconciler {
  static List<ReconciliationIssue> check(
    Invoice invoice,
    List<Payment> payments,
  ) {
    final id = invoice.invoiceId;
    final issues = <ReconciliationIssue>[];
    void add(String code, String message, {String? paymentId}) => issues.add(
      ReconciliationIssue(code, message, id, paymentId: paymentId),
    );

    final subtotal = InvoiceMath.subtotal(invoice.lines);
    final discount = InvoiceMath.discount(invoice.lines);
    if (subtotal != invoice.subtotalMinor) {
      add(
        'SUBTOTAL_MISMATCH',
        'lines total $subtotal, invoice says ${invoice.subtotalMinor}',
      );
    }
    if (discount != invoice.discountMinor) {
      add(
        'DISCOUNT_MISMATCH',
        'lines discount $discount, invoice says ${invoice.discountMinor}',
      );
    }
    if (invoice.payableMinor != invoice.subtotalMinor - invoice.discountMinor) {
      add(
        'PAYABLE_MISMATCH',
        'payable ${invoice.payableMinor} != subtotal − discount',
      );
    }

    final mine = payments.where((p) => p.invoiceId == id).toList();
    for (final p in payments.where((p) => p.invoiceId != id)) {
      add(
        'FOREIGN_PAYMENT',
        'payment ${p.paymentId} belongs to invoice ${p.invoiceId}',
        paymentId: p.paymentId,
      );
    }
    for (final p in mine) {
      if (p.studentId != invoice.studentId) {
        add(
          'STUDENT_MISMATCH',
          'payment ${p.paymentId} names another student',
          paymentId: p.paymentId,
        );
      }
      if (p.amountMinor <= 0) {
        add(
          'NON_POSITIVE_PAYMENT',
          'payment ${p.paymentId} amount ${p.amountMinor}',
          paymentId: p.paymentId,
        );
      }
    }

    final receipts = <String, String>{};
    for (final p in mine) {
      final first = receipts[p.receiptNumber];
      if (first != null) {
        add(
          'DUPLICATE_RECEIPT',
          'receipt ${p.receiptNumber} on ${p.paymentId} and $first',
          paymentId: p.paymentId,
        );
      } else {
        receipts[p.receiptNumber] = p.paymentId;
      }
    }

    final active = mine.where((p) => p.status == PaymentStatus.active);
    final paid = active.fold<int>(0, (s, p) => s + p.amountMinor);
    if (paid != invoice.paidMinor) {
      add(
        'PAID_MISMATCH',
        'active payments total $paid, invoice says ${invoice.paidMinor}',
      );
    }
    final balance = InvoiceMath.balance(
      payable: invoice.payableMinor,
      waived: invoice.waivedMinor,
      paid: invoice.paidMinor,
    );
    if (balance != invoice.balanceMinor) {
      add(
        'BALANCE_MISMATCH',
        'payable − waived − paid is $balance, invoice says '
            '${invoice.balanceMinor}',
      );
    }
    if (invoice.balanceMinor < 0) {
      add('OVERPAID', 'balance is ${invoice.balanceMinor}');
    }
    if (!invoice.isVoid) {
      final expected = InvoiceMath.statusFor(
        payable: invoice.payableMinor,
        waived: invoice.waivedMinor,
        paid: invoice.paidMinor,
      );
      if (expected != invoice.status) {
        add(
          'STATUS_MISMATCH',
          'figures imply ${expected.wireValue}, invoice is '
              '${invoice.status.wireValue}',
        );
      }
    } else if (active.isNotEmpty) {
      add('VOID_WITH_PAYMENTS', 'a void invoice still has active payments');
    }
    return issues;
  }
}
