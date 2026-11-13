/// Admission fees of an enquiry (`functions/admission_fees.js`, phase 7).
///
/// One record per enquiry and category. Money is integer minor units in the
/// school's currency; nothing is "paid" except by a recorded payment.
enum FeeCategory {
  application('APPLICATION', 'Application fee'),
  registration('REGISTRATION', 'Registration fee'),
  admission('ADMISSION', 'Admission fee'),
  confirmation('CONFIRMATION', 'Confirmation fee');

  final String wire;
  final String label;
  const FeeCategory(this.wire, this.label);

  static FeeCategory? tryParse(String? wire) {
    for (final c in values) {
      if (c.wire == wire) return c;
    }
    return null;
  }
}

enum AdmissionFeeStatus {
  due('DUE', 'Due'),
  partial('PARTIAL', 'Part paid'),
  paid('PAID', 'Paid'),
  waived('WAIVED', 'Waived'),
  cancelled('CANCELLED', 'Cancelled');

  final String wire;
  final String label;
  const AdmissionFeeStatus(this.wire, this.label);

  static AdmissionFeeStatus parse(String? wire) => values.firstWhere(
    (s) => s.wire == wire,
    orElse: () => AdmissionFeeStatus.due,
  );
}

enum AdmissionPaymentMethod {
  cash('CASH', 'Cash', false),
  cheque('CHEQUE', 'Cheque', true),
  bankTransfer('BANK_TRANSFER', 'Bank transfer', true),
  upi('UPI', 'UPI', true),
  card('CARD', 'Card', true),
  other('OTHER', 'Other', false);

  final String wire;
  final String label;

  /// A reference (cheque number, transaction id) is required.
  final bool needsReference;
  const AdmissionPaymentMethod(this.wire, this.label, this.needsReference);

  static AdmissionPaymentMethod? tryParse(String? wire) {
    for (final m in values) {
      if (m.wire == wire) return m;
    }
    return null;
  }
}

class AdmissionFee {
  final String id;
  final String enquiryId;

  /// The only enquiry detail Finance sees.
  final String? enquiryNumber;
  final FeeCategory category;
  final String currency;
  final int amountMinor;
  final int waivedMinor;
  final int paidMinor;
  final int refundedMinor;
  final AdmissionFeeStatus status;
  final String? feeStructureId;
  final String? dueDate;
  final String? note;
  final String? lastReceiptNumber;
  final int revision;

  const AdmissionFee({
    required this.id,
    this.enquiryId = '',
    this.enquiryNumber,
    required this.category,
    required this.currency,
    required this.amountMinor,
    this.waivedMinor = 0,
    this.paidMinor = 0,
    this.refundedMinor = 0,
    this.status = AdmissionFeeStatus.due,
    this.feeStructureId,
    this.dueDate,
    this.note,
    this.lastReceiptNumber,
    this.revision = 1,
  });

  /// Money currently held for this fee (paid minus refunded).
  int get netPaidMinor => paidMinor - refundedMinor;

  int get balanceMinor => status == AdmissionFeeStatus.cancelled
      ? 0
      : (amountMinor - waivedMinor - netPaidMinor).clamp(0, amountMinor);

  bool get isCancelled => status == AdmissionFeeStatus.cancelled;

  bool get canTakePayment => !isCancelled && balanceMinor > 0;

  factory AdmissionFee.fromMap(String id, Map<String, dynamic> d) =>
      AdmissionFee(
        id: id,
        enquiryId: d['enquiryId'] as String? ?? '',
        enquiryNumber: d['enquiryNumber'] as String?,
        category:
            FeeCategory.tryParse(d['category'] as String?) ??
            FeeCategory.application,
        currency: d['currency'] as String? ?? 'INR',
        amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
        waivedMinor: (d['waivedMinor'] as num?)?.toInt() ?? 0,
        paidMinor: (d['paidMinor'] as num?)?.toInt() ?? 0,
        refundedMinor: (d['refundedMinor'] as num?)?.toInt() ?? 0,
        status: AdmissionFeeStatus.parse(d['status'] as String?),
        feeStructureId: d['feeStructureId'] as String?,
        dueDate: d['dueDate'] as String?,
        note: d['note'] as String?,
        lastReceiptNumber: d['lastReceiptNumber'] as String?,
        revision: (d['revision'] as num?)?.toInt() ?? 1,
      );
}

class AdmissionFeePayment {
  final String id;
  final String feeId;
  final FeeCategory category;
  final bool isRefund;
  final int amountMinor;
  final String currency;
  final AdmissionPaymentMethod method;
  final String? referenceNo;
  final String paymentDate;
  final String? notes;
  final String? receiptNumber;
  final DateTime? recordedAt;

  const AdmissionFeePayment({
    required this.id,
    required this.feeId,
    required this.category,
    required this.isRefund,
    required this.amountMinor,
    required this.currency,
    required this.method,
    required this.paymentDate,
    this.referenceNo,
    this.notes,
    this.receiptNumber,
    this.recordedAt,
  });

  factory AdmissionFeePayment.fromMap(
    String id,
    Map<String, dynamic> d, {
    DateTime? recordedAt,
  }) => AdmissionFeePayment(
    id: id,
    feeId: d['feeId'] as String? ?? '',
    category:
        FeeCategory.tryParse(d['category'] as String?) ??
        FeeCategory.application,
    isRefund: d['kind'] == 'REFUND',
    amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
    currency: d['currency'] as String? ?? 'INR',
    method:
        AdmissionPaymentMethod.tryParse(d['method'] as String?) ??
        AdmissionPaymentMethod.other,
    referenceNo: d['referenceNo'] as String?,
    paymentDate: d['paymentDate'] as String? ?? '',
    notes: d['notes'] as String?,
    receiptNumber: d['receiptNumber'] as String?,
    recordedAt: recordedAt,
  );
}

/// Totals over an enquiry's live (not cancelled) fees.
class AdmissionFeeSummary {
  final int amountMinor;
  final int netPaidMinor;
  final int balanceMinor;
  const AdmissionFeeSummary({
    required this.amountMinor,
    required this.netPaidMinor,
    required this.balanceMinor,
  });

  factory AdmissionFeeSummary.of(Iterable<AdmissionFee> fees) {
    final live = fees.where((f) => !f.isCancelled);
    return AdmissionFeeSummary(
      amountMinor: live.fold(0, (t, f) => t + f.amountMinor),
      netPaidMinor: live.fold(0, (t, f) => t + f.netPaidMinor),
      balanceMinor: live.fold(0, (t, f) => t + f.balanceMinor),
    );
  }
}
