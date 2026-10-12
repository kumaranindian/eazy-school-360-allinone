/// Totals over an academic year's **non-void** invoices, computed by
/// Firestore aggregation queries (not by downloading documents).
///
/// ```text
/// payable     = Σ payable          (after concessions given at issue)
/// collected   = Σ paid             (= Σ ACTIVE payments; reversed ones are gone)
/// waived      = Σ waived
/// outstanding = Σ balance          = payable − waived − collected   (always)
/// overdue     = Σ balance of OPEN invoices whose due date is before today
/// ```
class FeeSummary {
  final int invoiceCount;
  final int grossMinor;
  final int discountMinor;
  final int payableMinor;
  final int waivedMinor;
  final int collectedMinor;
  final int outstandingMinor;
  final int overdueMinor;
  final int overdueInvoiceCount;
  final int partiallyPaidCount;
  final int paidCount;

  const FeeSummary({
    required this.invoiceCount,
    required this.grossMinor,
    required this.discountMinor,
    required this.payableMinor,
    required this.waivedMinor,
    required this.collectedMinor,
    required this.outstandingMinor,
    required this.overdueMinor,
    required this.overdueInvoiceCount,
    required this.partiallyPaidCount,
    required this.paidCount,
  });

  /// `payable − waived − collected == outstanding` — a cheap integrity check
  /// the dashboard can surface if the stored numbers ever disagree.
  bool get isBalanced =>
      payableMinor - waivedMinor - collectedMinor == outstandingMinor;

  /// Share of the collectable amount (payable − waived) that has been
  /// collected, 0-100; null when nothing is collectable.
  double? get collectionRate {
    final collectable = payableMinor - waivedMinor;
    return collectable <= 0 ? null : collectedMinor / collectable * 100;
  }
}

/// Payments received in a period (ACTIVE only — reversed payments are
/// excluded), with the reversals and refunds recorded in the same period.
class CollectionSummary {
  final int paymentCount;
  final int collectedMinor;
  final Map<String, int> byMethodMinor;
  final int reversedMinor;
  final int refundedMinor;

  const CollectionSummary({
    required this.paymentCount,
    required this.collectedMinor,
    required this.byMethodMinor,
    required this.reversedMinor,
    required this.refundedMinor,
  });
}

class SectionOutstanding {
  final String classId;
  final String className;
  final String sectionId;
  final String sectionName;
  final int invoiceCount;
  final int outstandingMinor;

  const SectionOutstanding({
    required this.classId,
    required this.className,
    required this.sectionId,
    required this.sectionName,
    required this.invoiceCount,
    required this.outstandingMinor,
  });
}
