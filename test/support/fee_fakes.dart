import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/fees/domain/billing_period.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/fee_planners.dart';
import 'package:eazy_school_360/features/fees/domain/fee_repositories.dart';
import 'package:eazy_school_360/features/fees/domain/fee_structure.dart';
import 'package:eazy_school_360/features/fees/domain/fee_summary.dart';
import 'package:eazy_school_360/features/fees/domain/invoice.dart';
import 'package:eazy_school_360/features/fees/domain/payment.dart';
import 'package:eazy_school_360/features/fees/domain/student_fee_assignment.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';

Invoice fakeInvoice({
  String id = 'stu-1__y1__M-2026-06',
  String number = 'INV-2026-000001',
  String studentId = 'stu-1',
  String studentName = 'Anil Kumar',
  int payable = 100000,
  int paid = 0,
  int waived = 0,
  InvoiceStatus? status,
  String due = '2099-06-16',
  String branchId = 'main',
}) {
  final balance = InvoiceMath.balance(
    payable: payable,
    waived: waived,
    paid: paid,
  );
  return Invoice(
    invoiceId: id,
    schoolId: 'school-1',
    branchId: branchId,
    invoiceNumber: number,
    numberSeq: 1,
    studentId: studentId,
    studentName: studentName,
    admissionNumber: 'ADM-1',
    academicYearId: 'y1',
    academicYearName: '2026-27',
    classId: 'c5',
    className: 'Class 5',
    sectionId: 'sa',
    sectionName: 'A',
    periodKind: FeeFrequency.monthly,
    periodKey: 'M-2026-06',
    periodLabel: 'June 2026',
    issueDateKey: '2026-06-01',
    dueDateKey: due,
    lines: [
      InvoiceLine(
        assignmentId: '${studentId}__s1',
        structureId: 's1',
        name: 'Tuition',
        category: FeeCategory.tuition,
        amountMinor: payable,
        chargeId: '${studentId}__s1__M-2026-06',
      ),
    ],
    subtotalMinor: payable,
    discountMinor: 0,
    payableMinor: payable,
    waivedMinor: waived,
    paidMinor: paid,
    balanceMinor: balance,
    status:
        status ??
        InvoiceMath.statusFor(payable: payable, waived: waived, paid: paid),
    schoolName: 'Rosewood High',
    branchName: 'Main',
  );
}

Payment fakePayment({
  String id = 'pay-1',
  int amount = 30000,
  PaymentStatus status = PaymentStatus.active,
  String invoiceId = 'stu-1__y1__M-2026-06',
}) => Payment(
  paymentId: id,
  schoolId: 'school-1',
  branchId: 'main',
  invoiceId: invoiceId,
  invoiceNumber: 'INV-2026-000001',
  studentId: 'stu-1',
  studentName: 'Anil Kumar',
  academicYearId: 'y1',
  classId: 'c5',
  amountMinor: amount,
  method: PaymentMethod.cash,
  paymentDateKey: '2026-06-10',
  receiptNumber: 'RCT-2026-000001',
  balanceAfterMinor: 70000,
  collectedBy: 'u',
  collectorName: 'Fin Officer',
  status: status,
);

FeeStructure fakeStructure({
  String code = 'TUITION',
  int amount = 100000,
  ActivationStatus status = ActivationStatus.active,
}) => FeeStructure(
  structureId: FeeStructure.idFor('y1', code),
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  code: code,
  name: 'Tuition',
  category: FeeCategory.tuition,
  frequency: FeeFrequency.monthly,
  amountMinor: amount,
  status: status,
);

class FakeInvoiceRepository implements InvoiceRepository {
  List<Invoice> invoices;
  final List<InvoiceFilter> fetchFilters = [];
  final List<String> searches = [];
  final List<({int count, String period})> generated = [];
  final List<({String invoiceId, int amount, String reason})> waivers = [];
  final List<({String invoiceId, String reason})> voids = [];
  BillingContext? context;
  Object? error;
  PagedResult<Invoice>? pageOverride;

  FakeInvoiceRepository({this.invoices = const []});

  @override
  Future<PagedResult<Invoice>> fetchInvoices({
    required String schoolId,
    required String branchId,
    required InvoiceFilter filter,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchFilters.add(filter);
    if (error != null) throw error!;
    return pageOverride ?? PagedResult(items: invoices, nextCursor: null);
  }

  @override
  Future<PagedResult<Invoice>> searchInvoicesByNumber({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    searches.add(query);
    return PagedResult(
      items: invoices
          .where((i) => i.invoiceNumber.startsWith(query.toUpperCase()))
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Stream<Invoice?> watchInvoice(
    String schoolId,
    String branchId,
    String invoiceId,
  ) =>
      Stream.value(invoices.where((i) => i.invoiceId == invoiceId).firstOrNull);

  @override
  Future<List<Invoice>> fetchStudentInvoices({
    required String schoolId,
    required String branchId,
    required String studentId,
    String? academicYearId,
  }) async => invoices
      .where(
        (i) =>
            i.studentId == studentId &&
            (academicYearId == null || i.academicYearId == academicYearId),
      )
      .toList();

  @override
  Future<BillingContext> loadBillingContext({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    required BillingPeriod period,
  }) async => context!;

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
    generated.add((count: proposals.length, period: period.key));
    onProgress?.call(proposals.length, proposals.length);
    return BulkResult(created: proposals.length, skippedExisting: 0, failed: 0);
  }

  @override
  Future<void> voidInvoice({
    required Invoice invoice,
    required String reason,
    required String actorId,
  }) async {
    if (error != null) throw error!;
    voids.add((invoiceId: invoice.invoiceId, reason: reason));
  }

  @override
  Future<void> waiveInvoice({
    required Invoice invoice,
    required int amountMinor,
    required String reason,
    required String actorId,
  }) async {
    if (error != null) throw error!;
    waivers.add((
      invoiceId: invoice.invoiceId,
      amount: amountMinor,
      reason: reason,
    ));
  }

  @override
  Stream<List<InvoiceWaiver>> watchWaivers(
    String schoolId,
    String branchId,
    String invoiceId,
  ) => Stream.value(const []);
}

class FakePaymentRepository implements PaymentRepository {
  List<Payment> payments;
  final List<CollectPaymentRequest> collected = [];
  final List<({String paymentId, ReversalKind kind, String reason})> reversed =
      [];
  Object? collectError;
  Future<void> Function()? gate;
  Receipt? receipt;

  FakePaymentRepository({this.payments = const []});

  @override
  Future<String> collectPayment(CollectPaymentRequest request) async {
    collected.add(request);
    if (gate != null) await gate!();
    if (collectError != null) {
      final e = collectError!;
      collectError = null; // fail once, then succeed on retry
      throw e;
    }
    return request.paymentId;
  }

  @override
  Future<void> reversePayment({
    required Payment payment,
    required ReversalKind kind,
    required String reason,
    required String actorId,
  }) async {
    reversed.add((paymentId: payment.paymentId, kind: kind, reason: reason));
  }

  @override
  Stream<List<Payment>> watchInvoicePayments(
    String schoolId,
    String branchId,
    String invoiceId,
  ) => Stream.value(payments.where((p) => p.invoiceId == invoiceId).toList());

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
  }) async => PagedResult(
    items: payments.where((p) => status == null || p.status == status).toList(),
    nextCursor: null,
  );

  @override
  Future<List<Payment>> fetchStudentPayments({
    required String schoolId,
    required String branchId,
    required String studentId,
  }) async => payments.where((p) => p.studentId == studentId).toList();

  @override
  Future<Receipt?> getReceipt(
    String schoolId,
    String branchId,
    String receiptId,
  ) async => receipt;

  @override
  Future<List<Receipt>> fetchStudentReceipts({
    required String schoolId,
    required String branchId,
    required String studentId,
  }) async => const [];

  @override
  Future<PaymentReversal?> getReversal(
    String schoolId,
    String branchId,
    String paymentId,
  ) async => null;
}

class FakeFeeConfigRepository implements FeeConfigRepository {
  List<FeeStructure> structures;
  List<FeeStudent> students;
  List<StudentFeeAssignment> assignments;
  final List<FeeStructure> created = [];
  final List<int> bulkCreated = [];

  FakeFeeConfigRepository({
    this.structures = const [],
    this.students = const [],
    this.assignments = const [],
  });

  @override
  Stream<List<FeeStructure>> watchStructures(
    String schoolId,
    String branchId,
    String academicYearId,
  ) => Stream.value(structures);

  @override
  Future<void> createStructure(
    FeeStructure structure, {
    required String actorId,
  }) async => created.add(structure);

  @override
  Future<void> updateStructure(
    FeeStructure structure, {
    required String actorId,
  }) async {}

  @override
  Stream<List<StudentFeeAssignment>> watchStudentAssignments(
    String schoolId,
    String branchId,
    String studentId,
    String academicYearId,
  ) =>
      Stream.value(assignments.where((a) => a.studentId == studentId).toList());

  @override
  Future<List<StudentFeeAssignment>> fetchAssignmentsForPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  }) async => assignments;

  @override
  Future<List<FeeStudent>> loadPlacementStudents({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  }) async => students;

  @override
  Future<BulkResult> createAssignments(
    List<PlannedAssignment> planned, {
    required String actorId,
    void Function(int done, int total)? onProgress,
  }) async {
    bulkCreated.add(planned.length);
    onProgress?.call(planned.length, planned.length);
    return BulkResult(created: planned.length, skippedExisting: 0, failed: 0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFeeReportRepository implements FeeReportRepository {
  FeeSummary summary;
  Object? error;
  int loads = 0;

  FakeFeeReportRepository({required this.summary});

  @override
  Future<FeeSummary> loadSummary({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String todayKey,
  }) async {
    loads++;
    if (error != null) throw error!;
    return summary;
  }

  @override
  Future<CollectionSummary> loadCollections({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String fromKey,
    required String toKey,
  }) async => const CollectionSummary(
    paymentCount: 0,
    collectedMinor: 0,
    byMethodMinor: {},
    reversedMinor: 0,
    refundedMinor: 0,
  );

  @override
  Future<SectionOutstanding> loadSectionOutstanding({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String className,
    required String sectionId,
    required String sectionName,
  }) async => SectionOutstanding(
    classId: classId,
    className: className,
    sectionId: sectionId,
    sectionName: sectionName,
    invoiceCount: 0,
    outstandingMinor: 0,
  );
}
