import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'fee_enums.dart';

/// One billed fee on an invoice — a **frozen copy** of the structure's name,
/// category and amount at the moment of issue, plus the concession applied.
class InvoiceLine {
  final String assignmentId;
  final String structureId;
  final String name;
  final FeeCategory category;
  final String? description;
  final int amountMinor;
  final int discountMinor;
  final String? concessionNote;

  /// `assignmentId__{chargeKey}` — the `feeCharges` lock this line holds.
  final String chargeId;

  const InvoiceLine({
    required this.assignmentId,
    required this.structureId,
    required this.name,
    required this.category,
    this.description,
    required this.amountMinor,
    this.discountMinor = 0,
    this.concessionNote,
    required this.chargeId,
  });

  int get netMinor => amountMinor - discountMinor;

  factory InvoiceLine.fromMap(Map<String, dynamic> m) => InvoiceLine(
    assignmentId: m['assignmentId'] as String? ?? '',
    structureId: m['structureId'] as String? ?? '',
    name: m['name'] as String? ?? '',
    category: FeeCategory.fromWireValue(m['category'] as String? ?? 'OTHER'),
    description: m['description'] as String?,
    amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
    discountMinor: (m['discountMinor'] as num?)?.toInt() ?? 0,
    concessionNote: m['concessionNote'] as String?,
    chargeId: m['chargeId'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'assignmentId': assignmentId,
    'structureId': structureId,
    'name': name,
    'category': category.wireValue,
    'description': description,
    'amountMinor': amountMinor,
    'discountMinor': discountMinor,
    'concessionNote': concessionNote,
    'chargeId': chargeId,
  };
}

/// The balance arithmetic, in one place (and mirrored in `firestore.rules`):
///
/// ```text
/// subtotal = Σ line.amount
/// discount = Σ line.discount            (approved concessions, applied at issue)
/// payable  = subtotal − discount
/// balance  = payable − waived − paid    (never negative)
/// ```
/// `paid` counts only ACTIVE payments; reversed/refunded payments are
/// removed from it. `waived` is approved post-issue waivers.
abstract final class InvoiceMath {
  static int subtotal(Iterable<InvoiceLine> lines) =>
      lines.fold(0, (s, l) => s + l.amountMinor);

  static int discount(Iterable<InvoiceLine> lines) =>
      lines.fold(0, (s, l) => s + l.discountMinor);

  static int balance({
    required int payable,
    required int waived,
    required int paid,
  }) => payable - waived - paid;

  static InvoiceStatus statusFor({
    required int payable,
    required int waived,
    required int paid,
  }) {
    if (balance(payable: payable, waived: waived, paid: paid) <= 0) {
      return InvoiceStatus.paid;
    }
    return (paid + waived) > 0
        ? InvoiceStatus.partiallyPaid
        : InvoiceStatus.issued;
  }
}

/// A `.../branches/{branchId}/invoices/{studentId}__{yearId}__{periodKey}`
/// document. The id makes "one invoice per student per period" structural;
/// the amounts and descriptions are a snapshot and never change after issue.
/// Only the *derived* money fields ([waivedMinor], [paidMinor],
/// [balanceMinor], [status]) move, each only alongside the payment, waiver or
/// void record that justifies it.
class Invoice {
  final String invoiceId;
  final String schoolId;
  final String branchId;
  final String invoiceNumber;
  final int numberSeq;
  final String studentId;
  final String studentName;
  final String admissionNumber;
  final String academicYearId;
  final String academicYearName;
  final String classId;
  final String className;
  final String? sectionId;
  final String sectionName;
  final FeeFrequency periodKind;
  final String periodKey;
  final String periodLabel;
  final String issueDateKey;
  final String dueDateKey;
  final List<InvoiceLine> lines;
  final int subtotalMinor;
  final int discountMinor;
  final int payableMinor;
  final int waivedMinor;
  final int paidMinor;
  final int balanceMinor;
  final InvoiceStatus status;
  final String currency;
  final String schoolName;
  final String branchName;
  final String? voidReason;
  final DateTime? voidedAt;
  final String? voidedBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const Invoice({
    required this.invoiceId,
    required this.schoolId,
    required this.branchId,
    required this.invoiceNumber,
    required this.numberSeq,
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.academicYearId,
    required this.academicYearName,
    required this.classId,
    required this.className,
    this.sectionId,
    required this.sectionName,
    required this.periodKind,
    required this.periodKey,
    required this.periodLabel,
    required this.issueDateKey,
    required this.dueDateKey,
    required this.lines,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.payableMinor,
    this.waivedMinor = 0,
    this.paidMinor = 0,
    required this.balanceMinor,
    required this.status,
    this.currency = 'INR',
    this.schoolName = '',
    this.branchName = '',
    this.voidReason,
    this.voidedAt,
    this.voidedBy,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  bool get isVoid => status == InvoiceStatus.voided;

  /// The year token inside the number (`INV-2026-000012` -> 2026): the
  /// academic year's starting year, reused for this invoice's receipts.
  int get numberYear =>
      int.tryParse(invoiceNumber.split('-').elementAtOrNull(1) ?? '') ??
      DateTime.now().year;

  /// Overdue is derived: still owing and past the due date.
  bool isOverdue(String todayKey) =>
      status.isOpen && balanceMinor > 0 && dueDateKey.compareTo(todayKey) < 0;

  /// "Overdue", or the stored status label.
  String statusLabel(String todayKey) =>
      isOverdue(todayKey) ? 'Overdue' : status.displayName;

  factory Invoice.fromFirestore(
    String schoolId,
    String branchId,
    String id,
    Map<String, dynamic> d,
  ) {
    int n(String k) => (d[k] as num?)?.toInt() ?? 0;
    return Invoice(
      invoiceId: id,
      schoolId: schoolId,
      branchId: branchId,
      invoiceNumber: d['invoiceNumber'] as String? ?? '',
      numberSeq: n('numberSeq'),
      studentId: d['studentId'] as String? ?? '',
      studentName: d['studentName'] as String? ?? '',
      admissionNumber: d['admissionNumber'] as String? ?? '',
      academicYearId: d['academicYearId'] as String? ?? '',
      academicYearName: d['academicYearName'] as String? ?? '',
      classId: d['classId'] as String? ?? '',
      className: d['className'] as String? ?? '',
      sectionId: d['sectionId'] as String?,
      sectionName: d['sectionName'] as String? ?? '',
      periodKind: FeeFrequency.fromWireValue(
        d['periodKind'] as String? ?? 'CUSTOM',
      ),
      periodKey: d['periodKey'] as String? ?? '',
      periodLabel: d['periodLabel'] as String? ?? '',
      issueDateKey: d['issueDateKey'] as String? ?? '',
      dueDateKey: d['dueDateKey'] as String? ?? '',
      lines: [
        for (final l in (d['lines'] as List<dynamic>? ?? const []))
          InvoiceLine.fromMap(Map<String, dynamic>.from(l as Map)),
      ],
      subtotalMinor: n('subtotalMinor'),
      discountMinor: n('discountMinor'),
      payableMinor: n('payableMinor'),
      waivedMinor: n('waivedMinor'),
      paidMinor: n('paidMinor'),
      balanceMinor: n('balanceMinor'),
      status: InvoiceStatus.fromWireValue(d[FirestoreFields.status] as String),
      currency: d['currency'] as String? ?? 'INR',
      schoolName: d['schoolName'] as String? ?? '',
      branchName: d['branchName'] as String? ?? '',
      voidReason: d['voidReason'] as String?,
      voidedAt: (d['voidedAt'] as Timestamp?)?.toDate(),
      voidedBy: d['voidedBy'] as String?,
      createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
      updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      createdBy: d[FirestoreFields.createdBy] as String?,
    );
  }

  /// The complete document written at issue. Money fields start consistent:
  /// nothing paid or waived, `balance == payable`.
  Map<String, dynamic> toFirestoreCreate({required String createdBy}) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'invoiceNumber': invoiceNumber,
    'numberSeq': numberSeq,
    'studentId': studentId,
    'studentName': studentName,
    'admissionNumber': admissionNumber,
    'academicYearId': academicYearId,
    'academicYearName': academicYearName,
    'classId': classId,
    'className': className,
    'sectionId': sectionId,
    'sectionName': sectionName,
    'periodKind': periodKind.wireValue,
    'periodKey': periodKey,
    'periodLabel': periodLabel,
    'issueDateKey': issueDateKey,
    'dueDateKey': dueDateKey,
    'lines': [for (final l in lines) l.toMap()],
    'subtotalMinor': subtotalMinor,
    'discountMinor': discountMinor,
    'payableMinor': payableMinor,
    'waivedMinor': 0,
    'paidMinor': 0,
    'balanceMinor': payableMinor,
    FirestoreFields.status: InvoiceStatus.issued.wireValue,
    'currency': currency,
    'schoolName': schoolName,
    'branchName': branchName,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: createdBy,
    FirestoreFields.updatedBy: createdBy,
  };
}
