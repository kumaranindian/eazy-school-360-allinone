import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'fee_enums.dart';

/// A `.../payments/{paymentId}` document — one payment against one invoice.
///
/// **The document id is the idempotency key** (a UUID created when the
/// collect dialog opens and reused on every retry), so submitting the same
/// payment twice can only ever address one document. Money fields are
/// immutable; the only permitted change is ACTIVE -> REVERSED, alongside a
/// `paymentReversals/{paymentId}` record. A completed payment is never edited
/// or deleted.
class Payment {
  final String paymentId;
  final String schoolId;
  final String branchId;
  final String invoiceId;
  final String invoiceNumber;
  final String studentId;
  final String studentName;
  final String academicYearId;
  final String classId;
  final String? sectionId;
  final int amountMinor;
  final PaymentMethod method;
  final String? methodLabel;
  final String? referenceNo;
  final String paymentDateKey;
  final String? notes;
  final String receiptNumber;
  final int balanceAfterMinor;
  final String collectedBy;
  final String collectorName;
  final PaymentStatus status;
  final DateTime? createdAt;

  const Payment({
    required this.paymentId,
    required this.schoolId,
    required this.branchId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.studentId,
    required this.studentName,
    required this.academicYearId,
    required this.classId,
    this.sectionId,
    required this.amountMinor,
    required this.method,
    this.methodLabel,
    this.referenceNo,
    required this.paymentDateKey,
    this.notes,
    required this.receiptNumber,
    required this.balanceAfterMinor,
    required this.collectedBy,
    required this.collectorName,
    this.status = PaymentStatus.active,
    this.createdAt,
  });

  bool get isActive => status == PaymentStatus.active;

  String get methodDisplay =>
      method == PaymentMethod.other && (methodLabel ?? '').trim().isNotEmpty
      ? methodLabel!.trim()
      : method.displayName;

  factory Payment.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> d,
  ) => Payment(
    paymentId: id,
    schoolId: schoolId,
    branchId: branchId,
    invoiceId: d['invoiceId'] as String? ?? '',
    invoiceNumber: d['invoiceNumber'] as String? ?? '',
    studentId: d['studentId'] as String? ?? '',
    studentName: d['studentName'] as String? ?? '',
    academicYearId: d['academicYearId'] as String? ?? '',
    classId: d['classId'] as String? ?? '',
    sectionId: d['sectionId'] as String?,
    amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
    method: PaymentMethod.fromWireValue(d['method'] as String? ?? 'OTHER'),
    methodLabel: d['methodLabel'] as String?,
    referenceNo: d['referenceNo'] as String?,
    paymentDateKey: d['paymentDateKey'] as String? ?? '',
    notes: d['notes'] as String?,
    receiptNumber: d['receiptNumber'] as String? ?? '',
    balanceAfterMinor: (d['balanceAfterMinor'] as num?)?.toInt() ?? 0,
    collectedBy: d['collectedBy'] as String? ?? '',
    collectorName: d['collectorName'] as String? ?? '',
    status: PaymentStatus.fromWireValue(
      d[FirestoreFields.status] as String? ?? 'ACTIVE',
    ),
    createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
  );
}

/// A `.../receipts/{paymentId}` document — the receipt of exactly one
/// payment (same id), numbered from a gap-tolerant, never-reused sequence.
/// It is a point-in-time snapshot (names, balance after the payment), so it
/// stays accurate whatever happens to the student or invoice later. A
/// reversed payment keeps its receipt; only [status] flips to REVERSED.
class Receipt {
  final String receiptId;
  final String schoolId;
  final String branchId;
  final String receiptNumber;
  final int numberSeq;
  final String paymentId;
  final String invoiceId;
  final String invoiceNumber;
  final String periodLabel;
  final String studentId;
  final String studentName;
  final String admissionNumber;
  final String className;
  final String sectionName;
  final String academicYearId;
  final String academicYearName;
  final String schoolName;
  final String branchName;
  final int amountMinor;
  final PaymentMethod method;
  final String? methodLabel;
  final String? referenceNo;
  final String paymentDateKey;
  final int balanceAfterMinor;
  final String collectorName;
  final String currency;
  final PaymentStatus status;
  final DateTime? createdAt;

  const Receipt({
    required this.receiptId,
    required this.schoolId,
    required this.branchId,
    required this.receiptNumber,
    required this.numberSeq,
    required this.paymentId,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.periodLabel,
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.className,
    required this.sectionName,
    required this.academicYearId,
    required this.academicYearName,
    required this.schoolName,
    required this.branchName,
    required this.amountMinor,
    required this.method,
    this.methodLabel,
    this.referenceNo,
    required this.paymentDateKey,
    required this.balanceAfterMinor,
    required this.collectorName,
    this.currency = 'INR',
    this.status = PaymentStatus.active,
    this.createdAt,
  });

  bool get isReversed => status == PaymentStatus.reversed;

  String get methodDisplay =>
      method == PaymentMethod.other && (methodLabel ?? '').trim().isNotEmpty
      ? methodLabel!.trim()
      : method.displayName;

  factory Receipt.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> d,
  ) => Receipt(
    receiptId: id,
    schoolId: schoolId,
    branchId: branchId,
    receiptNumber: d['receiptNumber'] as String? ?? '',
    numberSeq: (d['numberSeq'] as num?)?.toInt() ?? 0,
    paymentId: d['paymentId'] as String? ?? id,
    invoiceId: d['invoiceId'] as String? ?? '',
    invoiceNumber: d['invoiceNumber'] as String? ?? '',
    periodLabel: d['periodLabel'] as String? ?? '',
    studentId: d['studentId'] as String? ?? '',
    studentName: d['studentName'] as String? ?? '',
    admissionNumber: d['admissionNumber'] as String? ?? '',
    className: d['className'] as String? ?? '',
    sectionName: d['sectionName'] as String? ?? '',
    academicYearId: d['academicYearId'] as String? ?? '',
    academicYearName: d['academicYearName'] as String? ?? '',
    schoolName: d['schoolName'] as String? ?? '',
    branchName: d['branchName'] as String? ?? '',
    amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
    method: PaymentMethod.fromWireValue(d['method'] as String? ?? 'OTHER'),
    methodLabel: d['methodLabel'] as String?,
    referenceNo: d['referenceNo'] as String?,
    paymentDateKey: d['paymentDateKey'] as String? ?? '',
    balanceAfterMinor: (d['balanceAfterMinor'] as num?)?.toInt() ?? 0,
    collectorName: d['collectorName'] as String? ?? '',
    currency: d['currency'] as String? ?? 'INR',
    status: PaymentStatus.fromWireValue(
      d[FirestoreFields.status] as String? ?? 'ACTIVE',
    ),
    createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
  );
}

/// `.../paymentReversals/{paymentId}` — append-only record that a payment was
/// reversed or refunded. The id is the payment's, so a payment can be
/// reversed at most once.
class PaymentReversal {
  final String paymentId;
  final ReversalKind kind;
  final String reason;
  final int amountMinor;
  final String invoiceId;
  final String studentId;
  final String academicYearId;
  final String reversalDateKey;
  final String reversedBy;
  final DateTime? createdAt;

  const PaymentReversal({
    required this.paymentId,
    required this.kind,
    required this.reason,
    required this.amountMinor,
    required this.invoiceId,
    required this.studentId,
    required this.academicYearId,
    required this.reversalDateKey,
    required this.reversedBy,
    this.createdAt,
  });

  factory PaymentReversal.fromFirestore(String id, Map<String, dynamic> d) =>
      PaymentReversal(
        paymentId: id,
        kind: ReversalKind.fromWireValue(d['kind'] as String? ?? 'REVERSAL'),
        reason: d['reason'] as String? ?? '',
        amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
        invoiceId: d['invoiceId'] as String? ?? '',
        studentId: d['studentId'] as String? ?? '',
        academicYearId: d['academicYearId'] as String? ?? '',
        reversalDateKey: d['reversalDateKey'] as String? ?? '',
        reversedBy: d['reversedBy'] as String? ?? '',
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      );
}

/// `.../invoiceWaivers/{id}` — an approved post-issue waiver that reduces an
/// invoice's balance. Append-only.
class InvoiceWaiver {
  final String waiverId;
  final String invoiceId;
  final String studentId;
  final int amountMinor;
  final String reason;
  final String approvedBy;
  final String waiverDateKey;
  final DateTime? createdAt;

  const InvoiceWaiver({
    required this.waiverId,
    required this.invoiceId,
    required this.studentId,
    required this.amountMinor,
    required this.reason,
    required this.approvedBy,
    required this.waiverDateKey,
    this.createdAt,
  });

  factory InvoiceWaiver.fromFirestore(String id, Map<String, dynamic> d) =>
      InvoiceWaiver(
        waiverId: id,
        invoiceId: d['invoiceId'] as String? ?? '',
        studentId: d['studentId'] as String? ?? '',
        amountMinor: (d['amountMinor'] as num?)?.toInt() ?? 0,
        reason: d['reason'] as String? ?? '',
        approvedBy: d['approvedBy'] as String? ?? '',
        waiverDateKey: d['waiverDateKey'] as String? ?? '',
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      );
}
