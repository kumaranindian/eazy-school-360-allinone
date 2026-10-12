import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';

/// Typed access to the fee collections under one branch, plus the audit
/// writer every sensitive operation uses.
class FeePaths {
  final FirebaseFirestore firestore;
  final String schoolId;
  final String branchId;

  FeePaths(this.firestore, this.schoolId, this.branchId);

  DocumentReference<Map<String, dynamic>> get branch => firestore
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId);

  CollectionReference<Map<String, dynamic>> collection(String name) =>
      branch.collection(name);

  CollectionReference<Map<String, dynamic>> get structures =>
      collection(FirestoreFields.feeStructuresCollection);
  CollectionReference<Map<String, dynamic>> get assignments =>
      collection(FirestoreFields.feeAssignmentsCollection);
  CollectionReference<Map<String, dynamic>> get invoices =>
      collection(FirestoreFields.invoicesCollection);
  CollectionReference<Map<String, dynamic>> get invoiceNumbers =>
      collection(FirestoreFields.invoiceNumbersCollection);
  CollectionReference<Map<String, dynamic>> get counters =>
      collection(FirestoreFields.feeCountersCollection);
  CollectionReference<Map<String, dynamic>> get charges =>
      collection(FirestoreFields.feeChargesCollection);
  CollectionReference<Map<String, dynamic>> get waivers =>
      collection(FirestoreFields.invoiceWaiversCollection);
  CollectionReference<Map<String, dynamic>> get payments =>
      collection(FirestoreFields.paymentsCollection);
  CollectionReference<Map<String, dynamic>> get receipts =>
      collection(FirestoreFields.receiptsCollection);
  CollectionReference<Map<String, dynamic>> get receiptNumbers =>
      collection(FirestoreFields.receiptNumbersCollection);
  CollectionReference<Map<String, dynamic>> get reversals =>
      collection(FirestoreFields.paymentReversalsCollection);
  CollectionReference<Map<String, dynamic>> get students =>
      collection(FirestoreFields.studentsCollection);

  /// An append-only audit entry: who did what to the money, and when.
  /// [details] is small, human-readable context (ids, amounts, reasons).
  void audit(
    WriteBatch batch, {
    required String type,
    required String actorId,
    Map<String, dynamic> details = const {},
  }) {
    batch.set(
      collection(FirestoreFields.financialAuditCollection).doc(),
      _auditData(type, actorId, details),
    );
  }

  void auditInTransaction(
    Transaction transaction, {
    required String type,
    required String actorId,
    Map<String, dynamic> details = const {},
  }) {
    transaction.set(
      collection(FirestoreFields.financialAuditCollection).doc(),
      _auditData(type, actorId, details),
    );
  }

  Map<String, dynamic> _auditData(
    String type,
    String actorId,
    Map<String, dynamic> details,
  ) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'type': type,
    'actorId': actorId,
    'at': FieldValue.serverTimestamp(),
    'details': details,
  };
}

/// `whereIn` accepts at most 30 values.
Iterable<List<T>> chunked<T>(List<T> items, int size) sync* {
  for (var i = 0; i < items.length; i += size) {
    yield items.sublist(i, i + size > items.length ? items.length : i + size);
  }
}
