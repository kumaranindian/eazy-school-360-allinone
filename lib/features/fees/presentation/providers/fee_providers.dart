import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_fee_config_repository.dart';
import '../../data/firebase_fee_report_repository.dart';
import '../../data/firebase_invoice_repository.dart';
import '../../data/firebase_payment_repository.dart';
import '../../domain/fee_repositories.dart';
import '../../domain/fee_structure.dart';
import '../../domain/fee_summary.dart';
import '../../domain/invoice.dart';
import '../../domain/payment.dart';
import '../../domain/student_fee_assignment.dart';

final feeConfigRepositoryProvider = Provider<FeeConfigRepository>(
  (ref) => FirebaseFeeConfigRepository(ref.watch(firestoreProvider)),
);
final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => FirebaseInvoiceRepository(ref.watch(firestoreProvider)),
);
final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => FirebasePaymentRepository(ref.watch(firestoreProvider)),
);
final feeReportRepositoryProvider = Provider<FeeReportRepository>(
  (ref) => FirebaseFeeReportRepository(ref.watch(firestoreProvider)),
);

typedef FeeYearKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
});
typedef FeeStudentKey = ({
  String schoolId,
  String branchId,
  String studentId,
  String academicYearId,
});
typedef FeeInvoiceKey = ({String schoolId, String branchId, String invoiceId});
typedef FeeSummaryKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String todayKey,
});

final feeStructuresProvider = StreamProvider.autoDispose
    .family<List<FeeStructure>, FeeYearKey>((ref, key) {
      return ref
          .watch(feeConfigRepositoryProvider)
          .watchStructures(key.schoolId, key.branchId, key.academicYearId);
    });

final studentAssignmentsProvider = StreamProvider.autoDispose
    .family<List<StudentFeeAssignment>, FeeStudentKey>((ref, key) {
      return ref
          .watch(feeConfigRepositoryProvider)
          .watchStudentAssignments(
            key.schoolId,
            key.branchId,
            key.studentId,
            key.academicYearId,
          );
    });

final invoiceProvider = StreamProvider.autoDispose
    .family<Invoice?, FeeInvoiceKey>((ref, key) {
      return ref
          .watch(invoiceRepositoryProvider)
          .watchInvoice(key.schoolId, key.branchId, key.invoiceId);
    });

final invoicePaymentsProvider = StreamProvider.autoDispose
    .family<List<Payment>, FeeInvoiceKey>((ref, key) {
      return ref
          .watch(paymentRepositoryProvider)
          .watchInvoicePayments(key.schoolId, key.branchId, key.invoiceId);
    });

final invoiceWaiversProvider = StreamProvider.autoDispose
    .family<List<InvoiceWaiver>, FeeInvoiceKey>((ref, key) {
      return ref
          .watch(invoiceRepositoryProvider)
          .watchWaivers(key.schoolId, key.branchId, key.invoiceId);
    });

final feeSummaryProvider = FutureProvider.autoDispose
    .family<FeeSummary, FeeSummaryKey>((ref, key) {
      return ref
          .watch(feeReportRepositoryProvider)
          .loadSummary(
            schoolId: key.schoolId,
            branchId: key.branchId,
            academicYearId: key.academicYearId,
            todayKey: key.todayKey,
          );
    });

/// A fresh idempotency key for one payment attempt: created when the collect
/// dialog opens and reused on every retry of that attempt, so a double-click
/// or a retried request addresses the same payment document.
String newPaymentKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  return 'pay_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}
