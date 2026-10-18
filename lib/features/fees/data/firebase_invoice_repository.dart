import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../../core/logging/app_logger.dart';
import '../../students/domain/paged_result.dart';
import '../domain/billing_period.dart';
import '../domain/fee_dates.dart';
import '../domain/fee_enums.dart';
import '../domain/fee_planners.dart';
import '../domain/fee_repositories.dart';
import '../domain/fee_structure.dart';
import '../domain/invoice.dart';
import '../domain/payment.dart';
import '../domain/payment_rules.dart';
import 'fee_firestore.dart';
import 'firebase_fee_config_repository.dart';

/// Invoices: billing-run context, generation with safe numbering, search,
/// void and waiver.
///
/// **Numbering.** Each chunk is one transaction that reads the branch/year
/// counter, takes the next `k` numbers, bumps the counter, and writes the
/// invoices together with one `invoiceNumbers/{number}` reservation each.
/// Concurrent runs contend on the counter document and Firestore retries the
/// loser with fresh data; and if a client ever got it wrong, the unique
/// reservation document id and the rules (`numberSeq` must lie in the range
/// the counter moved through) refuse a duplicate. Numbers are unique and
/// increasing, with possible gaps — they are not guaranteed gap-free.
class FirebaseInvoiceRepository implements InvoiceRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFeeConfigRepository _config;

  /// Rules limit a batch to 20 documents read; each invoice needs 2 (its
  /// number reservation and the student) plus a few shared ones (caller
  /// profile, counter before/after, and whatever the staff check reads).
  /// 8 per commit sat right at that ceiling (≈19), so a single extra lookup
  /// rejected every chunk; 6 (≈15) leaves real headroom.
  static const int generateChunkSize = 6;

  FirebaseInvoiceRepository(this._firestore)
    : _config = FirebaseFeeConfigRepository(_firestore);

  FeePaths _paths(String schoolId, String branchId) =>
      FeePaths(_firestore, schoolId, branchId);

  @override
  Future<BillingContext> loadBillingContext({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    required BillingPeriod period,
  }) async {
    try {
      final paths = _paths(schoolId, branchId);
      final students = await _config.loadPlacementStudents(
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: academicYearId,
        classId: classId,
        sectionId: sectionId,
      );
      final structureSnapshot = await paths.structures
          .where('academicYearId', isEqualTo: academicYearId)
          .get();
      final structures = {
        for (final d in structureSnapshot.docs)
          d.id: FeeStructure.fromFirestore(schoolId, branchId, d.id, d.data()),
      };
      final assignments = await _config.fetchAssignmentsForPlacement(
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: academicYearId,
        classId: classId,
        sectionId: sectionId,
      );

      final byStudent = <String, List<BillableAssignment>>{};
      final candidateChargeIds = <String>{};
      for (final a in assignments) {
        final structure = structures[a.structureId];
        byStudent
            .putIfAbsent(a.studentId, () => [])
            .add(BillableAssignment(a, structure));
        if (structure != null && structure.frequency == period.kind) {
          candidateChargeIds.add(
            '${a.assignmentId}__${BillingPeriod.chargeKeyFor(structure.frequency, period.key)}',
          );
        }
      }

      final existingCharges = await _existingIds(
        paths.charges,
        candidateChargeIds.toList(),
      );
      final existingInvoices = await _existingIds(paths.invoices, [
        for (final s in students)
          BillingPeriod.invoiceId(s.studentId, academicYearId, period.key),
      ]);
      return BillingContext(
        students: students,
        assignmentsByStudent: byStudent,
        existingChargeIds: existingCharges,
        existingInvoiceIds: existingInvoices,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  Future<Set<String>> _existingIds(
    CollectionReference<Map<String, dynamic>> collection,
    List<String> ids,
  ) async {
    final found = <String>{};
    for (final chunk in chunked(ids, 30)) {
      final snapshot = await collection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      found.addAll(snapshot.docs.map((d) => d.id));
    }
    return found;
  }

  @override
  Future<BulkResult> generateInvoices({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required BillingPeriod period,
    required String issueDateKey,
    required List<ProposedInvoice> proposals,
    required InvoiceSchoolInfo info,
    required String actorId,
    void Function(int done, int total)? onProgress,
  }) async {
    final paths = _paths(schoolId, branchId);
    final counterRef = paths.counters.doc(
      FeeNumbers.counterId('invoice', academicYearId),
    );
    var created = 0, skipped = 0, failed = 0, done = 0;
    final errors = <String>[];

    for (final chunk in chunked(proposals, generateChunkSize)) {
      try {
        final made = await _firestore.runTransaction<int>((transaction) async {
          final counterSnapshot = await transaction.get(counterRef);
          final last = counterSnapshot.exists
              ? ((counterSnapshot.data()!['last'] as num?)?.toInt() ?? 0)
              : 0;

          // Idempotency: an invoice that already exists is left alone.
          final fresh = <ProposedInvoice>[];
          for (final p in chunk) {
            if (!(await transaction.get(
              paths.invoices.doc(p.invoiceId),
            )).exists) {
              fresh.add(p);
            }
          }
          if (fresh.isEmpty) return 0;

          var seq = last;
          for (final p in fresh) {
            seq++;
            final invoice = Invoice(
              invoiceId: p.invoiceId,
              schoolId: schoolId,
              branchId: branchId,
              invoiceNumber: FeeNumbers.invoice(
                info.academicYearStartYear,
                seq,
              ),
              numberSeq: seq,
              studentId: p.student.studentId,
              studentName: p.student.name,
              admissionNumber: p.student.admissionNumber,
              academicYearId: academicYearId,
              academicYearName: info.academicYearName,
              classId: p.student.classId,
              className: p.student.className,
              sectionId: p.student.sectionId,
              sectionName: p.student.sectionName,
              periodKind: period.kind,
              periodKey: period.key,
              periodLabel: period.label,
              issueDateKey: issueDateKey,
              dueDateKey: p.dueDateKey,
              lines: p.lines,
              subtotalMinor: p.subtotalMinor,
              discountMinor: p.discountMinor,
              payableMinor: p.payableMinor,
              balanceMinor: p.payableMinor,
              status: InvoiceStatus.issued,
              currency: info.currency,
              schoolName: info.schoolName,
              branchName: info.branchName,
            );
            transaction.set(paths.invoiceNumbers.doc(invoice.invoiceNumber), {
              FirestoreFields.schoolId: schoolId,
              FirestoreFields.branchId: branchId,
              'academicYearId': academicYearId,
              'numberSeq': seq,
            });
            transaction.set(
              paths.invoices.doc(p.invoiceId),
              invoice.toFirestoreCreate(createdBy: actorId),
            );
            for (final line in p.lines) {
              transaction.set(paths.charges.doc(line.chargeId), {
                FirestoreFields.schoolId: schoolId,
                FirestoreFields.branchId: branchId,
                'invoiceId': p.invoiceId,
                'assignmentId': line.assignmentId,
              });
            }
          }

          if (counterSnapshot.exists) {
            transaction.update(counterRef, {
              'last': seq,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': actorId,
            });
          } else {
            transaction.set(counterRef, {
              FirestoreFields.schoolId: schoolId,
              FirestoreFields.branchId: branchId,
              'last': seq,
              'updatedAt': FieldValue.serverTimestamp(),
              'updatedBy': actorId,
            });
          }
          return fresh.length;
        });
        created += made;
        skipped += chunk.length - made;
      } catch (error, stackTrace) {
        failed += chunk.length;
        AppLogger.error(
          'Invoice chunk failed (${chunk.length} students, e.g. id '
          '${chunk.first.student.studentId})',
          tag: 'Fees',
          error: error,
          stackTrace: stackTrace,
        );
        errors.add(userMessageFor(mapExceptionToFailure(error, stackTrace)));
      }
      done += chunk.length;
      onProgress?.call(done, proposals.length);
    }

    if (created > 0) {
      try {
        final batch = _firestore.batch();
        paths.audit(
          batch,
          type: 'INVOICES_GENERATED',
          actorId: actorId,
          details: {
            'academicYearId': academicYearId,
            'period': period.key,
            'created': created,
            'skippedExisting': skipped,
            'failed': failed,
          },
        );
        await batch.commit();
      } catch (_) {
        // Invoices are the record; a failed log entry must not mask success.
      }
    }
    return BulkResult(
      created: created,
      skippedExisting: skipped,
      failed: failed,
      errors: errors.toSet().toList(),
    );
  }

  @override
  Future<PagedResult<Invoice>> fetchInvoices({
    required String schoolId,
    required String branchId,
    required InvoiceFilter filter,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final today = FeeDates.todayKey();
      Query<Map<String, dynamic>> q = _paths(
        schoolId,
        branchId,
      ).invoices.where('academicYearId', isEqualTo: filter.academicYearId);
      if (filter.studentId != null) {
        q = q.where('studentId', isEqualTo: filter.studentId);
      }
      if (filter.classId != null) {
        q = q.where('classId', isEqualTo: filter.classId);
      }
      if (filter.sectionId != null) {
        q = q.where('sectionId', isEqualTo: filter.sectionId);
      }

      String? upperExclusive;
      String? upperInclusive = filter.dueToKey;
      if (filter.overdueOnly) {
        q = q.where(
          'status',
          whereIn: [
            InvoiceStatus.issued.wireValue,
            InvoiceStatus.partiallyPaid.wireValue,
          ],
        );
        // "Overdue" = still owing and due strictly before today.
        if (upperInclusive == null || upperInclusive.compareTo(today) >= 0) {
          upperExclusive = today;
          upperInclusive = null;
        }
      } else if (filter.status != null) {
        q = q.where('status', isEqualTo: filter.status!.wireValue);
      }
      if (filter.dueFromKey != null) {
        q = q.where('dueDateKey', isGreaterThanOrEqualTo: filter.dueFromKey);
      }
      if (upperExclusive != null) {
        q = q.where('dueDateKey', isLessThan: upperExclusive);
      }
      if (upperInclusive != null) {
        q = q.where('dueDateKey', isLessThanOrEqualTo: upperInclusive);
      }

      q = q.orderBy('dueDateKey', descending: true).limit(pageSize + 1);
      final start = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (start != null) q = q.startAfterDocument(start);
      final snapshot = await q.get();
      final hasMore = snapshot.docs.length > pageSize;
      final docs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;
      return PagedResult(
        items: docs
            .map(
              (d) => Invoice.fromFirestore(schoolId, branchId, d.id, d.data()),
            )
            .toList(),
        nextCursor: hasMore ? docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<PagedResult<Invoice>> searchInvoicesByNumber({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final term = query.trim().toUpperCase();
      Query<Map<String, dynamic>> q = _paths(
        schoolId,
        branchId,
      ).invoices.orderBy('invoiceNumber');
      final start = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      q = start == null ? q.startAt([term]) : q.startAfterDocument(start);
      q = q.endAt(['$term']).limit(pageSize + 1);
      final snapshot = await q.get();
      final hasMore = snapshot.docs.length > pageSize;
      final docs = hasMore ? snapshot.docs.sublist(0, pageSize) : snapshot.docs;
      return PagedResult(
        items: docs
            .map(
              (d) => Invoice.fromFirestore(schoolId, branchId, d.id, d.data()),
            )
            .toList(),
        nextCursor: hasMore ? docs.last : null,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<Invoice?> watchInvoice(
    String schoolId,
    String branchId,
    String invoiceId,
  ) {
    return _paths(schoolId, branchId).invoices
        .doc(invoiceId)
        .snapshots()
        .map(
          (s) => s.exists
              ? Invoice.fromFirestore(schoolId, branchId, s.id, s.data()!)
              : null,
        )
        .handleError(
          (error, stackTrace) =>
              throw mapExceptionToFailure(error, stackTrace as StackTrace?),
        );
  }

  @override
  Future<List<Invoice>> fetchStudentInvoices({
    required String schoolId,
    required String branchId,
    required String studentId,
    String? academicYearId,
  }) async {
    try {
      final snapshot = await _paths(schoolId, branchId).invoices
          .where('studentId', isEqualTo: studentId)
          .orderBy('dueDateKey', descending: true)
          .limit(200)
          .get();
      final all = snapshot.docs.map(
        (d) => Invoice.fromFirestore(schoolId, branchId, d.id, d.data()),
      );
      return academicYearId == null
          ? all.toList()
          : all.where((i) => i.academicYearId == academicYearId).toList();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> voidInvoice({
    required Invoice invoice,
    required String reason,
    required String actorId,
  }) async {
    final paths = _paths(invoice.schoolId, invoice.branchId);
    final ref = paths.invoices.doc(invoice.invoiceId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          throw const NotFoundFailure('This invoice could not be found.');
        }
        final fresh = Invoice.fromFirestore(
          invoice.schoolId,
          invoice.branchId,
          snapshot.id,
          snapshot.data()!,
        );
        final problem = PaymentRules.checkVoid(
          status: fresh.status,
          paidMinor: fresh.paidMinor,
          reason: reason,
        );
        if (problem != null) throw ValidationFailure(problem);

        // Reads must come before writes in a transaction: find which line
        // locks actually exist (deleting a missing one would be refused).
        final existingCharges = <DocumentReference<Map<String, dynamic>>>[];
        for (final line in fresh.lines) {
          final chargeRef = paths.charges.doc(line.chargeId);
          if ((await transaction.get(chargeRef)).exists) {
            existingCharges.add(chargeRef);
          }
        }

        transaction.update(ref, {
          FirestoreFields.status: InvoiceStatus.voided.wireValue,
          'voidReason': reason.trim(),
          'voidedAt': FieldValue.serverTimestamp(),
          'voidedBy': actorId,
          'lastEventType': 'VOID',
          'lastEventId': ref.id,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
        // Free the lines so they can be billed again on a corrected invoice.
        existingCharges.forEach(transaction.delete);
        paths.auditInTransaction(
          transaction,
          type: 'INVOICE_VOIDED',
          actorId: actorId,
          details: {
            'invoiceId': ref.id,
            'invoiceNumber': fresh.invoiceNumber,
            'payableMinor': fresh.payableMinor,
            'reason': reason.trim(),
          },
        );
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> waiveInvoice({
    required Invoice invoice,
    required int amountMinor,
    required String reason,
    required String actorId,
  }) async {
    final paths = _paths(invoice.schoolId, invoice.branchId);
    final ref = paths.invoices.doc(invoice.invoiceId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) {
          throw const NotFoundFailure('This invoice could not be found.');
        }
        final fresh = Invoice.fromFirestore(
          invoice.schoolId,
          invoice.branchId,
          snapshot.id,
          snapshot.data()!,
        );
        final problem = PaymentRules.checkWaiver(
          status: fresh.status,
          balanceMinor: fresh.balanceMinor,
          amountMinor: amountMinor,
          reason: reason,
        );
        if (problem != null) throw ValidationFailure(problem);

        final waiverRef = paths.waivers.doc();
        final waived = fresh.waivedMinor + amountMinor;
        transaction.set(waiverRef, {
          FirestoreFields.schoolId: invoice.schoolId,
          FirestoreFields.branchId: invoice.branchId,
          'invoiceId': ref.id,
          'studentId': fresh.studentId,
          'academicYearId': fresh.academicYearId,
          'amountMinor': amountMinor,
          'reason': reason.trim(),
          'approvedBy': actorId,
          'waiverDateKey': FeeDates.todayKey(),
          FirestoreFields.createdAt: FieldValue.serverTimestamp(),
        });
        transaction.update(ref, {
          'waivedMinor': waived,
          'balanceMinor': InvoiceMath.balance(
            payable: fresh.payableMinor,
            waived: waived,
            paid: fresh.paidMinor,
          ),
          FirestoreFields.status: InvoiceMath.statusFor(
            payable: fresh.payableMinor,
            waived: waived,
            paid: fresh.paidMinor,
          ).wireValue,
          'lastEventType': 'WAIVER',
          'lastEventId': waiverRef.id,
          FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
          FirestoreFields.updatedBy: actorId,
        });
        paths.auditInTransaction(
          transaction,
          type: 'INVOICE_WAIVED',
          actorId: actorId,
          details: {
            'invoiceId': ref.id,
            'invoiceNumber': fresh.invoiceNumber,
            'amountMinor': amountMinor,
            'reason': reason.trim(),
          },
        );
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Stream<List<InvoiceWaiver>> watchWaivers(
    String schoolId,
    String branchId,
    String invoiceId,
  ) {
    return _paths(schoolId, branchId).waivers
        .where('invoiceId', isEqualTo: invoiceId)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => InvoiceWaiver.fromFirestore(d.id, d.data()))
              .toList(),
        )
        .handleError(
          (error, stackTrace) =>
              throw mapExceptionToFailure(error, stackTrace as StackTrace?),
        );
  }
}
