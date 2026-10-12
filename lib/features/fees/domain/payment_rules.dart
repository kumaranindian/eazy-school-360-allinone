import 'fee_enums.dart';
import 'money.dart';

/// The business checks for every money-moving action, as pure functions that
/// return a user-readable reason or null. The repositories call them for good
/// messages; `firestore.rules` independently re-enforces the same invariants
/// (positive integer amounts, amount ≤ balance, balance = payable − waived −
/// paid, status consistency) so the UI is never the only enforcement.
abstract final class PaymentRules {
  static const int maxPaymentMinor = 1000000000;

  static String? checkCollect({
    required InvoiceStatus status,
    required int balanceMinor,
    required int amountMinor,
    required PaymentMethod method,
    String? methodLabel,
    String? referenceNo,
    required String paymentDateKey,
    required String todayKey,
    String currency = 'INR',
  }) {
    if (status == InvoiceStatus.voided) {
      return 'This invoice is void and cannot receive payments.';
    }
    if (status == InvoiceStatus.paid || balanceMinor <= 0) {
      return 'This invoice is already fully paid.';
    }
    if (amountMinor <= 0) return 'Enter an amount greater than zero.';
    if (amountMinor > maxPaymentMinor) return 'That amount is too large.';
    if (amountMinor > balanceMinor) {
      return 'The amount is more than the balance due (${Money.format(balanceMinor, currency: currency)}). Overpayment is not accepted.';
    }
    if (method.needsReference && (referenceNo ?? '').trim().length < 3) {
      return 'Enter the ${method.displayName.toLowerCase()} reference number.';
    }
    if (method == PaymentMethod.other && (methodLabel ?? '').trim().isEmpty) {
      return 'Name the payment method.';
    }
    if (paymentDateKey.compareTo(todayKey) > 0) {
      return 'The payment date cannot be in the future.';
    }
    return null;
  }

  static String? checkReverse({
    required bool isActive,
    required String reason,
  }) {
    if (!isActive) return 'This payment has already been reversed.';
    if (reason.trim().length < 3) return 'Give a reason.';
    return null;
  }

  static String? checkWaiver({
    required InvoiceStatus status,
    required int balanceMinor,
    required int amountMinor,
    required String reason,
  }) {
    if (!status.isOpen) {
      return 'Only an invoice with a balance due can be waived.';
    }
    if (amountMinor <= 0) return 'Enter an amount greater than zero.';
    if (amountMinor > balanceMinor) {
      return 'A waiver cannot exceed the balance due.';
    }
    if (reason.trim().length < 3) return 'Give a reason for the waiver.';
    return null;
  }

  /// Voiding is only allowed when nothing is paid — reverse or refund the
  /// payments first so the money trail stays explicit.
  static String? checkVoid({
    required InvoiceStatus status,
    required int paidMinor,
    required String reason,
  }) {
    if (status == InvoiceStatus.voided) return 'This invoice is already void.';
    if (paidMinor > 0) {
      return 'This invoice has payments. Reverse or refund them before voiding it.';
    }
    if (reason.trim().length < 3) {
      return 'Give a reason for voiding the invoice.';
    }
    return null;
  }
}
