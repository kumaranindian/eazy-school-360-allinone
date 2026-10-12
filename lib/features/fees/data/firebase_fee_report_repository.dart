import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/fee_enums.dart';
import '../domain/fee_repositories.dart';
import '../domain/fee_summary.dart';
import 'fee_firestore.dart';

/// Reports from Firestore **aggregation queries** (`sum`/`count`): the server
/// adds up the matching documents and returns only the totals, so the cost is
/// per query, not per invoice, and nothing is downloaded and summed by the
/// client. The totals are exact because every amount is an integer and
/// they read the very same documents the money moves on — there is no
/// separate maintained counter to drift out of step.
///
/// Voided invoices are excluded by selecting statuses ISSUED / PARTIALLY_PAID
/// / PAID. Reversed payments are excluded by selecting status ACTIVE.
/// Consistency limit: a total is a snapshot taken query by query; a payment
/// recorded between two queries of one dashboard refresh can make the
/// figures differ by that payment until the next refresh (the dashboard
/// shows [FeeSummary.isBalanced] so this is visible, not hidden).
class FirebaseFeeReportRepository implements FeeReportRepository {
  final FirebaseFirestore _firestore;

  FirebaseFeeReportRepository(this._firestore);

  FeePaths _paths(String schoolId, String branchId) =>
      FeePaths(_firestore, schoolId, branchId);

  static final _live = [
    InvoiceStatus.issued.wireValue,
    InvoiceStatus.partiallyPaid.wireValue,
    InvoiceStatus.paid.wireValue,
  ];
  static final _open = [
    InvoiceStatus.issued.wireValue,
    InvoiceStatus.partiallyPaid.wireValue,
  ];

  int _sum(AggregateQuerySnapshot s, String field) =>
      (s.getSum(field) ?? 0).round();

  @override
  Future<FeeSummary> loadSummary({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String todayKey,
  }) async {
    try {
      final invoices = _paths(
        schoolId,
        branchId,
      ).invoices.where('academicYearId', isEqualTo: academicYearId);

      final totals = await invoices
          .where(FirestoreFields.status, whereIn: _live)
          .aggregate(
            count(),
            sum('subtotalMinor'),
            sum('discountMinor'),
            sum('payableMinor'),
            sum('waivedMinor'),
            sum('paidMinor'),
            sum('balanceMinor'),
          )
          .get();
      final overdue = await invoices
          .where(FirestoreFields.status, whereIn: _open)
          .where('dueDateKey', isLessThan: todayKey)
          .aggregate(count(), sum('balanceMinor'))
          .get();
      final partial = await invoices
          .where(
            FirestoreFields.status,
            isEqualTo: InvoiceStatus.partiallyPaid.wireValue,
          )
          .count()
          .get();
      final paid = await invoices
          .where(
            FirestoreFields.status,
            isEqualTo: InvoiceStatus.paid.wireValue,
          )
          .count()
          .get();

      return FeeSummary(
        invoiceCount: totals.count ?? 0,
        grossMinor: _sum(totals, 'subtotalMinor'),
        discountMinor: _sum(totals, 'discountMinor'),
        payableMinor: _sum(totals, 'payableMinor'),
        waivedMinor: _sum(totals, 'waivedMinor'),
        collectedMinor: _sum(totals, 'paidMinor'),
        outstandingMinor: _sum(totals, 'balanceMinor'),
        overdueMinor: _sum(overdue, 'balanceMinor'),
        overdueInvoiceCount: overdue.count ?? 0,
        partiallyPaidCount: partial.count ?? 0,
        paidCount: paid.count ?? 0,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<CollectionSummary> loadCollections({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String fromKey,
    required String toKey,
  }) async {
    try {
      final paths = _paths(schoolId, branchId);
      Query<Map<String, dynamic>> active = paths.payments
          .where('academicYearId', isEqualTo: academicYearId)
          .where(
            FirestoreFields.status,
            isEqualTo: PaymentStatus.active.wireValue,
          )
          .where('paymentDateKey', isGreaterThanOrEqualTo: fromKey)
          .where('paymentDateKey', isLessThanOrEqualTo: toKey);

      final all = await active.aggregate(count(), sum('amountMinor')).get();
      final byMethod = <String, int>{};
      for (final method in PaymentMethod.values) {
        final snapshot = await active
            .where('method', isEqualTo: method.wireValue)
            .aggregate(sum('amountMinor'))
            .get();
        final value = _sum(snapshot, 'amountMinor');
        if (value > 0) byMethod[method.wireValue] = value;
      }

      Future<int> reversed(ReversalKind kind) async {
        final snapshot = await paths.reversals
            .where('academicYearId', isEqualTo: academicYearId)
            .where('kind', isEqualTo: kind.wireValue)
            .where('reversalDateKey', isGreaterThanOrEqualTo: fromKey)
            .where('reversalDateKey', isLessThanOrEqualTo: toKey)
            .aggregate(sum('amountMinor'))
            .get();
        return _sum(snapshot, 'amountMinor');
      }

      return CollectionSummary(
        paymentCount: all.count ?? 0,
        collectedMinor: _sum(all, 'amountMinor'),
        byMethodMinor: byMethod,
        reversedMinor: await reversed(ReversalKind.reversal),
        refundedMinor: await reversed(ReversalKind.refund),
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<SectionOutstanding> loadSectionOutstanding({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String className,
    required String sectionId,
    required String sectionName,
  }) async {
    try {
      final snapshot = await _paths(schoolId, branchId).invoices
          .where('academicYearId', isEqualTo: academicYearId)
          .where('classId', isEqualTo: classId)
          .where('sectionId', isEqualTo: sectionId)
          .where(FirestoreFields.status, whereIn: _open)
          .aggregate(count(), sum('balanceMinor'))
          .get();
      return SectionOutstanding(
        classId: classId,
        className: className,
        sectionId: sectionId,
        sectionName: sectionName,
        invoiceCount: snapshot.count ?? 0,
        outstandingMinor: _sum(snapshot, 'balanceMinor'),
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
