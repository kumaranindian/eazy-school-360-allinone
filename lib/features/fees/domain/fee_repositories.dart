import '../../students/domain/paged_result.dart';
import 'billing_period.dart';
import 'fee_enums.dart';
import 'fee_planners.dart';
import 'fee_structure.dart';
import 'fee_summary.dart';
import 'invoice.dart';
import 'payment.dart';
import 'student_fee_assignment.dart';

/// Fee structures and the assignment of fee heads to students.
abstract class FeeConfigRepository {
  Stream<List<FeeStructure>> watchStructures(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  Future<List<FeeStructure>> getStructures(
    String schoolId,
    String branchId,
    Iterable<String> structureIds,
  );

  /// Throws [ValidationFailure] for invalid configuration or a duplicate code.
  Future<void> createStructure(
    FeeStructure structure, {
    required String actorId,
  });

  Future<void> updateStructure(
    FeeStructure structure, {
    required String actorId,
  });

  /// Assignments for one student in one academic year (active and cancelled).
  Stream<List<StudentFeeAssignment>> watchStudentAssignments(
    String schoolId,
    String branchId,
    String studentId,
    String academicYearId,
  );

  /// Every assignment for the students currently placed in a class/section,
  /// so a bulk plan can skip fee heads that are already assigned.
  Future<List<StudentFeeAssignment>> fetchAssignmentsForPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  });

  /// The students currently placed in a class/section for [academicYearId],
  /// as the planners need them (all pages, capped).
  Future<List<FeeStudent>> loadPlacementStudents({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  });

  /// Creates the planned assignments in small atomic chunks. Re-running is
  /// safe: an existing assignment is skipped, never duplicated.
  Future<BulkResult> createAssignments(
    List<PlannedAssignment> planned, {
    required String actorId,
    void Function(int done, int total)? onProgress,
  });

  /// A single student/fee head, optionally with an approved concession.
  Future<void> assignOne({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required FeeStudent student,
    required FeeStructure structure,
    required ConcessionType concessionType,
    required int concessionValue,
    String? concessionReason,
    required String actorId,
  });

  Future<void> setAssignmentActive(
    StudentFeeAssignment assignment,
    bool active, {
    required String actorId,
  });

  Future<void> setConcession(
    StudentFeeAssignment assignment, {
    required ConcessionType type,
    required int value,
    String? reason,
    required String actorId,
  });
}

/// Outcome of a chunked bulk write.
class BulkResult {
  final int created;
  final int skippedExisting;
  final int failed;
  final List<String> errors;

  const BulkResult({
    required this.created,
    required this.skippedExisting,
    required this.failed,
    this.errors = const [],
  });
}

class InvoiceFilter {
  final String academicYearId;
  final String? studentId;
  final String? classId;
  final String? sectionId;
  final InvoiceStatus? status;

  /// Only open invoices whose due date is before today.
  final bool overdueOnly;
  final String? dueFromKey;
  final String? dueToKey;

  const InvoiceFilter({
    required this.academicYearId,
    this.studentId,
    this.classId,
    this.sectionId,
    this.status,
    this.overdueOnly = false,
    this.dueFromKey,
    this.dueToKey,
  });
}

class BillingContext {
  final List<FeeStudent> students;
  final Map<String, List<BillableAssignment>> assignmentsByStudent;
  final Set<String> existingChargeIds;
  final Set<String> existingInvoiceIds;

  const BillingContext({
    required this.students,
    required this.assignmentsByStudent,
    required this.existingChargeIds,
    required this.existingInvoiceIds,
  });
}

class InvoiceSchoolInfo {
  final String schoolName;
  final String branchName;
  final String academicYearName;
  final int academicYearStartYear;
  final String currency;

  const InvoiceSchoolInfo({
    required this.schoolName,
    required this.branchName,
    required this.academicYearName,
    required this.academicYearStartYear,
    required this.currency,
  });
}

abstract class InvoiceRepository {
  /// Everything the preview needs for a billing run, read in bounded queries.
  Future<BillingContext> loadBillingContext({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    required BillingPeriod period,
  });

  /// Writes the planned invoices (numbers from the safe counter), in atomic
  /// chunks of [chunkSize]. Re-running after a failure creates only what is
  /// missing — invoices that exist are skipped, never duplicated.
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
  });

  Future<PagedResult<Invoice>> fetchInvoices({
    required String schoolId,
    required String branchId,
    required InvoiceFilter filter,
    int pageSize = 25,
    Object? cursor,
  });

  Future<PagedResult<Invoice>> searchInvoicesByNumber({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  });

  Stream<Invoice?> watchInvoice(
    String schoolId,
    String branchId,
    String invoiceId,
  );

  /// All of one student's invoices, newest due date first (ledger, parent view).
  Future<List<Invoice>> fetchStudentInvoices({
    required String schoolId,
    required String branchId,
    required String studentId,
    String? academicYearId,
  });

  /// Voids an unpaid invoice and releases its line locks, atomically.
  Future<void> voidInvoice({
    required Invoice invoice,
    required String reason,
    required String actorId,
  });

  /// Records an approved waiver against the balance.
  Future<void> waiveInvoice({
    required Invoice invoice,
    required int amountMinor,
    required String reason,
    required String actorId,
  });

  Stream<List<InvoiceWaiver>> watchWaivers(
    String schoolId,
    String branchId,
    String invoiceId,
  );
}

class CollectPaymentRequest {
  final String schoolId;
  final String branchId;
  final String invoiceId;

  /// The idempotency key — generated once per dialog, reused on every retry.
  final String paymentId;
  final int amountMinor;
  final PaymentMethod method;
  final String? methodLabel;
  final String? referenceNo;
  final String paymentDateKey;
  final String? notes;
  final String collectorId;
  final String collectorName;
  final InvoiceSchoolInfo info;

  const CollectPaymentRequest({
    required this.schoolId,
    required this.branchId,
    required this.invoiceId,
    required this.paymentId,
    required this.amountMinor,
    required this.method,
    this.methodLabel,
    this.referenceNo,
    required this.paymentDateKey,
    this.notes,
    required this.collectorId,
    required this.collectorName,
    required this.info,
  });
}

abstract class PaymentRepository {
  /// Records a payment, its receipt, the number reservation, the counter and
  /// the invoice update in ONE transaction, after re-reading the invoice.
  /// Returns the receipt id (== [CollectPaymentRequest.paymentId]); if that id
  /// already exists the earlier result is returned and nothing is written
  /// (idempotent retry).
  Future<String> collectPayment(CollectPaymentRequest request);

  Future<void> reversePayment({
    required Payment payment,
    required ReversalKind kind,
    required String reason,
    required String actorId,
  });

  Stream<List<Payment>> watchInvoicePayments(
    String schoolId,
    String branchId,
    String invoiceId,
  );

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
  });

  Future<List<Payment>> fetchStudentPayments({
    required String schoolId,
    required String branchId,
    required String studentId,
  });

  Future<Receipt?> getReceipt(
    String schoolId,
    String branchId,
    String receiptId,
  );

  Future<List<Receipt>> fetchStudentReceipts({
    required String schoolId,
    required String branchId,
    required String studentId,
  });

  Future<PaymentReversal?> getReversal(
    String schoolId,
    String branchId,
    String paymentId,
  );
}

abstract class FeeReportRepository {
  Future<FeeSummary> loadSummary({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String todayKey,
  });

  Future<CollectionSummary> loadCollections({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String fromKey,
    required String toKey,
  });

  /// Outstanding balance for one section.
  Future<SectionOutstanding> loadSectionOutstanding({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String className,
    required String sectionId,
    required String sectionName,
  });
}
