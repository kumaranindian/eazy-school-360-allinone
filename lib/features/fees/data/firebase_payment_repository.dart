import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/fee_dates.dart';
import '../domain/fee_enums.dart';
import '../domain/fee_repositories.dart';
import '../domain/invoice.dart';
import '../domain/payment.dart';
import '../domain/payment_rules.dart';
import 'fee_firestore.dart';

/// Payments, receipts, reversals.
///
/// **What makes a payment safe.** [collectPayment] is one Firestore
/// transaction: it re-reads the invoice, validates the amount against the
/// *current* balance, takes the next receipt number from the counter, and
/// writes payment + receipt + number reservation + counter + invoice update
/// together. The payment document's id is the caller's idempotency key. Two
/// cashiers racing are serialised by Firestore (the loser's transaction
/// re-runs against the new balance and is refused if it no longer fits), and
/// `firestore.rules` independently refuses any commit whose invoice change
/// is not exactly this payment — so even a hand-built request cannot overpay
/// or double-count. What rules cannot stop is a user who legitimately holds
/// the collect permission recording a payment that never happened; that is an
/// audit matter (every payment names its collector and reversal is recorded).
class FirebasePaymentRepository implements PaymentRepository {
  final FirebaseFirestore _firestore;

  FirebasePaymentRepository(this._firestore);

  FeePaths _paths(String schoolId, String branchId) =>
      FeePaths(_firestore, schoolId, branchId);

  @override
  Future<String> collectPayment(CollectPaymentRequest r) async {
    final paths = _paths(r.schoolId, r.branchId);
    final paymentRef = paths.payments.doc(r.paymentId);
    final invoiceRef = paths.invoices.doc(r.invoiceId);
    try {
      return await _firestore.runTransaction<String>((transaction) async {
        // Idempotent retry: if this key already produced a payment, return it.
        final existing = await transaction.get(paymentRef);
        if (existing.exists) {
          final d = existing.data()!;
          if (d['invoiceId'] == r.invoiceId &&
              d['amountMinor'] == r.amountMinor) {
            return r.paymentId;
          }
          throw const ValidationFailure(
            'This payment reference was already used for a different payment.',
          );
        }

        final invoiceSnapshot = await transaction.get(invoiceRef);
        if (!invoiceSnapshot.exists) {
          throw const NotFoundFailure('This invoice could not be found.');
        }
        final invoice = Invoice.fromFirestore(
          r.schoolId,
          r.branchId,
          invoiceSnapshot.id,
          invoiceSnapshot.data()!,
        );

        final problem = PaymentRules.checkCollect(
          status: invoice.status,
          balanceMinor: invoice.balanceMinor,
          amountMinor: r.amountMinor,
          method: r.method,
          methodLabel: r.methodLabel,
          referenceNo: r.referenceNo,
          paymentDateKey: r.paymentDateKey,
          todayKey: FeeDates.todayKey(),
          currency: invoice.currency,
        );
        if (problem != null) throw ValidationFailure(problem);

        final counterRef = paths.counters.doc(
          FeeNumbers.counterId('receipt', invoice.academicYearId),
        );
        final counterSnapshot = await transaction.get(counterRef);
        final seq =
            (counterSnapshot.exists
                ? ((counterSnapshot.data()!['last'] as num?)?.toInt() ?? 0)
                : 0) +
            1;
        final receiptNumber = FeeNumbers.receipt(
          r.info.academicYearStartYear,
          seq,
        );

        final paid = invoice.paidMinor + r.amountMinor;
        final balanceAfter = InvoiceMath.balance(
          payable: invoice.payableMinor,
          waived: invoice.waivedMinor,
          paid: paid,
        );
        final status = InvoiceMath.statusFor(
          payable: invoice.payableMinor,
          waived: invoice.waivedMinor,
          paid: paid,
        );

        transaction.set(paths.payments.doc(r.paymentId), {
          FirestoreFields.schoolId: r.schoolId,
          FirestoreFields.branchId: r.branchId,
          'invoiceId': r.invoiceId,
          'invoiceNumber': invoice.invoiceNumber,
          'studentId': invoice.studentId,
          'studentName': invoice.studentName,
          'academicYearId': invoice.academicYearId,
          'classId': invoice.classId,
          'sectionId': invoice.sectionId,
          'amountMinor': r.amountMinor,
          'method': r.method.wireValue,
          'methodLabel': r.method == PaymentMethod.other
              ? r.methodLabel?.trim()
              : null,
          'referenceNo': (r.referenceNo ?? '').trim().isEmpty
              ? null
              : r.referenceNo!.trim(),
          'paymentDateKey': r.paymentDateKey,
          'notes': (r.notes ?? '').trim().isEmpty ? null : r.notes!.trim(),
          'receiptNumber': receiptNumber,
          'balanceAfterMinor': balanceAfter,
          'collectedBy': r.collectorId,
          'collectorName': r.collectorName,
          FirestoreFields.status: PaymentStatus.active.wireValue,
          FirestoreFields.createdAt: FieldValue.serverTimestamp(),
          FirestoreFields.createdBy: r.collectorId,
        });
        transaction.set(paths.receipts.doc(r.paymentId), {
          FirestoreFields.schoolId: r.schoolId,
          FirestoreFields.branchId: r.branchId,
          'receiptNumber': receiptNumber,
          'numberSeq': seq,
          'paymentId': r.paymentId,
          'invoiceId': r.invoiceId,
          'invoiceNumber': invoice.invoiceNumber,
          'periodLabel': invoice.periodLabel,
          'studentId': invoice.studentId,
          'studentName': invoice.studentName,
          'admissionNumber': invoice.admissionNumber,
          'className': invoice.className,
          'sectionName': invoice.sectionName,
          'academicYearId': invoice.academicYearId,
          'academicYearName': invoice.academicYearName,
          'schoolName': invoice.schoolName,
          'branchName': invoice.branchName,
          'amountMinor': r.amountMinor,
          'method': r.method.wireValue,
          'methodLabel': r.method == PaymentMethod.other
              ? r.methodLabel?.trim()
              : null,
          'referenceNo': (r.referenceNo ?? '').trim().isEmpty
              ? null
              : r.referenceNo!.trim(),
          'paymentDateKey': r.paymentDateKey,
          'balanceAfterMinor': balanceAfter,
          'collectorName': r.collectorName,
          'currency': invoice.currency,
          FirestoreFields.status: PaymentStatus.active.wireValue,
          FirestoreFields.createdAt: FieldValue.serverTimestamp(),
          FirestoreFields.createdBy: r.collectorId,
        });
        transaction.set(paths.receiptNumbers.doc(receiptNumber), {
          FirestoreFields.schoolId: r.schoolId,
          FirestoreFields.branchId: r.branchId,
          'academicYearId': invoice.academicYearId,
          'numberSeq': seq,
        });
        if (counterSnapshot.exists) {
          transaction.update(counterRef, {
            'last': seq,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': r.collectorId,
          });
        } else {
          transaction.set(counterRef, {
            FirestoreFields.schoolId: r.schoolId,
            FirestoreFields.branchId: r.branchId,
            'last': seq,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': r.collectorId,
          });
        }
        transaction.update(invoiceRef, {
          'paidMinor': paid,
          'balanceMinor': balanceAfter,
          FirestoreFields.status: status.wireValue,
          'lastEventType': 'PAYMENT',
          'lastEventId': r.paymentId,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: r.collectorId,
        });
        return r.paymentId;
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> reversePayment({
    required Payment payment,
    required ReversalKind kind,
    required String reason,
    required String actorId,
  }) async {
    final paths = _paths(payment.schoolId, payment.branchId);
    final paymentRef = paths.payments.doc(payment.paymentId);
    final invoiceRef = paths.invoices.doc(payment.invoiceId);
    try {
      await _firestore.runTransaction((transaction) async {
        final paymentSnapshot = await transaction.get(paymentRef);
        if (!paymentSnapshot.exists) {
          throw const NotFoundFailure('This payment could not be found.');
        }
        final fresh = Payment.fromFirestore(
          payment.schoolId,
          payment.branchId,
          paymentSnapshot.id,
          paymentSnapshot.data()!,
        );
        final problem = PaymentRules.checkReverse(
          isActive: fresh.isActive,
          reason: reason,
        );
        if (problem != null) throw ValidationFailure(problem);

        final invoiceSnapshot = await transaction.get(invoiceRef);
        if (!invoiceSnapshot.exists) {
          throw const NotFoundFailure(
            'The invoice for this payment could not be found.',
          );
        }
        final invoice = Invoice.fromFirestore(
          payment.schoolId,
          payment.branchId,
          invoiceSnapshot.id,
          invoiceSnapshot.data()!,
        );

        final paid = invoice.paidMinor - fresh.amountMinor;
        if (paid < 0) {
          throw const ValidationFailure(
            'This payment no longer matches the invoice. Reload and try again.',
          );
        }

        transaction.set(paths.reversals.doc(payment.paymentId), {
          FirestoreFields.schoolId: payment.schoolId,
          FirestoreFields.branchId: payment.branchId,
          'paymentId': payment.paymentId,
          'kind': kind.wireValue,
          'reason': reason.trim(),
          'amountMinor': fresh.amountMinor,
          'invoiceId': fresh.invoiceId,
          'studentId': fresh.studentId,
          'academicYearId': fresh.academicYearId,
          'reversalDateKey': FeeDates.todayKey(),
          'reversedBy': actorId,
          FirestoreFields.createdAt: FieldValue.serverTimestamp(),
        });
        transaction.update(paymentRef, {
          FirestoreFields.status: PaymentStatus.reversed.wireValue,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
        transaction.update(paths.receipts.doc(payment.paymentId), {
          FirestoreFields.status: PaymentStatus.reversed.wireValue,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
        transaction.update(invoiceRef, {
          'paidMinor': paid,
          'balanceMinor': InvoiceMath.balance(
            payable: invoice.payableMinor,
            waived: invoice.waivedMinor,
            paid: paid,
          ),
          FirestoreFields.status: InvoiceMath.statusFor(
            payable: invoice.payableMinor,
            waived: invoice.waivedMinor,
            paid: paid,
          ).wireValue,
          'lastEventType': 'REVERSAL',
          'lastEventId': payment.paymentId,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
        paths.auditInTransaction(
          transaction,
          type: kind == ReversalKind.refund
              ? 'PAYMENT_REFUNDED'
              : 'PAYMENT_REVERSED',
          actorId: actorId,
          details: {
            'paymentId': payment.paymentId,
            'receiptNumber': fresh.receiptNumber,
            'invoiceId': fresh.invoiceId,
            'amountMinor': fresh.amountMinor,
            'reason': reason.trim(),
          },
        );
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<Payment>> watchInvoicePayments(
    String schoolId,
    String branchId,
    String invoiceId,
  ) {
    return _paths(schoolId, branchId).payments
        .where('invoiceId', isEqualTo: invoiceId)
        .snapshots()
        .map(
          (s) =>
              (s.docs
                  .map(
                    (d) => Payment.fromFirestore(
                      schoolId,
                      branchId,
                      d.id,
                      d.data(),
                    ),
                  )
                  .toList()
                ..sort(
                  (a, b) => (a.createdAt ?? DateTime.now()).compareTo(
                    b.createdAt ?? DateTime.now(),
                  ),
                )),
        )
        .handleError(
          (error, stackTrace) =>
              throw mapExceptionToFailure(error, stackTrace as StackTrace?),
        );
  }

  @override
  Future<PagedResult<Payment>> fetchPayments({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    PaymentStatus? status,
    PaymentMethod? method,
    String? fromKey,
    String? toKey,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _paths(
        schoolId,
        branchId,
      ).payments.where('academicYearId', isEqualTo: academicYearId);
      if (status != null) {
        q = q.where(FirestoreFields.status, isEqualTo: status.wireValue);
      }
      if (method != null) q = q.where('method', isEqualTo: method.wireValue);
      if (fromKey != null) {
        q = q.where('paymentDateKey', isGreaterThanOrEqualTo: fromKey);
      }
      if (toKey != null) {
        q = q.where('paymentDateKey', isLessThanOrEqualTo: toKey);
      }
      q = q.orderBy('paymentDateKey', descending: true).limit(pageSize + 1);
      final start = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (start != null) q = q.startAfterDocument(start);
      final snapshot = await q.get();
      final hasMore = snapshot.docs.length > pageSize;
      final docs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;
      return PagedResult(
        items: docs
            .map(
              (d) => Payment.fromFirestore(schoolId, branchId, d.id, d.data()),
            )
            .toList(),
        nextCursor: hasMore ? docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Payment>> fetchStudentPayments({
    required String schoolId,
    required String branchId,
    required String studentId,
  }) async {
    try {
      final snapshot = await _paths(schoolId, branchId).payments
          .where('studentId', isEqualTo: studentId)
          .orderBy('paymentDateKey', descending: true)
          .limit(200)
          .get();
      return snapshot.docs
          .map((d) => Payment.fromFirestore(schoolId, branchId, d.id, d.data()))
          .toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<Receipt?> getReceipt(
    String schoolId,
    String branchId,
    String receiptId,
  ) async {
    try {
      final snapshot = await _paths(
        schoolId,
        branchId,
      ).receipts.doc(receiptId).get();
      return snapshot.exists
          ? Receipt.fromFirestore(
              schoolId,
              branchId,
              snapshot.id,
              snapshot.data()!,
            )
          : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<List<Receipt>> fetchStudentReceipts({
    required String schoolId,
    required String branchId,
    required String studentId,
  }) async {
    try {
      final snapshot = await _paths(schoolId, branchId).receipts
          .where('studentId', isEqualTo: studentId)
          .orderBy('paymentDateKey', descending: true)
          .limit(200)
          .get();
      return snapshot.docs
          .map((d) => Receipt.fromFirestore(schoolId, branchId, d.id, d.data()))
          .toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<PaymentReversal?> getReversal(
    String schoolId,
    String branchId,
    String paymentId,
  ) async {
    try {
      final snapshot = await _paths(
        schoolId,
        branchId,
      ).reversals.doc(paymentId).get();
      return snapshot.exists
          ? PaymentReversal.fromFirestore(snapshot.id, snapshot.data()!)
          : null;
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
