import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_balance.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/domain/leave_repositories.dart';
import 'package:eazy_school_360/features/leave/domain/leave_type.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';

LeaveApplication fakeLeave({
  String id = 'lv-1',
  LeaveKind kind = LeaveKind.student,
  String subjectId = 'stu-1',
  String subjectName = 'Anil Kumar',
  String applicant = 'u-parent',
  LeaveStatus status = LeaveStatus.pending,
  String start = '2026-08-03',
  String end = '2026-08-04',
  int units = 4,
  HalfDay half = HalfDay.none,
  String typeId = 'STUDENT__sick',
  String typeName = 'Sick leave',
  LeavePayType pay = LeavePayType.notApplicable,
  String? balanceId,
  int revision = 1,
  String? reason = 'Fever',
  String branchId = 'main',
  String? decisionRemarks,
  List<LeaveAttachment> attachments = const [],
}) => LeaveApplication(
  applicationId: id,
  schoolId: 'school-1',
  branchId: branchId,
  kind: kind,
  subjectId: subjectId,
  subjectName: subjectName,
  subjectCode: 'ADM-1',
  academicYearId: 'y1',
  classId: kind == LeaveKind.student ? 'c5' : null,
  className: kind == LeaveKind.student ? 'Class 5' : null,
  sectionId: kind == LeaveKind.student ? 'sa' : null,
  sectionName: kind == LeaveKind.student ? 'A' : null,
  applicantUserId: applicant,
  applicantName: 'Parent',
  relation: kind == LeaveKind.student
      ? ApplicantRelation.parent
      : ApplicantRelation.self,
  typeId: typeId,
  typeName: typeName,
  payType: pay,
  startDateKey: start,
  endDateKey: end,
  halfDay: half,
  units: units,
  countedDateKeys: start == end ? [start] : [start, end],
  reason: reason,
  attachments: attachments,
  status: status,
  revision: revision,
  balanceId: balanceId,
  leaveYearStartKey: '2026-06-01',
  decisionRemarks: decisionRemarks,
);

class FakeLeaveApplicationRepository implements LeaveApplicationRepository {
  List<LeaveApplication> applications;
  final List<LeaveApplication> submitted = [];
  final List<LeaveApplication> resubmitted = [];
  final List<LeaveApplication> withdrawn = [];
  final List<
    ({String id, LeaveStatus target, String? remarks, String reviewer})
  >
  decisions = [];
  final List<({String id, String remarks})> cancellations = [];
  final List<LeaveFilter> filters = [];
  List<LeaveHistoryEntry> history = const [];
  Object? error;
  Future<void> Function()? gate;
  int pending;

  FakeLeaveApplicationRepository({
    this.applications = const [],
    this.pending = 0,
  });

  @override
  Future<void> submit(
    LeaveApplication application, {
    required LeaveActor actor,
  }) async {
    submitted.add(application);
    if (gate != null) await gate!();
    if (error != null) {
      final e = error!;
      error = null;
      throw e;
    }
  }

  @override
  Future<void> resubmit(
    LeaveApplication application, {
    required LeaveActor actor,
  }) async {
    resubmitted.add(application);
  }

  @override
  Future<void> withdraw(
    LeaveApplication application, {
    required LeaveActor actor,
  }) async {
    withdrawn.add(application);
    if (error != null) throw error!;
  }

  @override
  Future<void> decide({
    required LeaveApplication application,
    required LeaveStatus target,
    required LeaveActor reviewer,
    String? remarks,
    String? subjectUserId,
    required String todayKey,
  }) async {
    decisions.add((
      id: application.applicationId,
      target: target,
      remarks: remarks,
      reviewer: reviewer.userId,
    ));
    if (gate != null) await gate!();
    if (error != null) throw error!;
  }

  @override
  Future<void> cancelApproved({
    required LeaveApplication application,
    required LeaveActor reviewer,
    required String remarks,
    String? subjectUserId,
  }) async {
    cancellations.add((id: application.applicationId, remarks: remarks));
    if (error != null) throw error!;
  }

  @override
  Future<PagedResult<LeaveApplication>> fetch({
    required String schoolId,
    required String branchId,
    required LeaveFilter filter,
    int pageSize = 25,
    Object? cursor,
  }) async {
    filters.add(filter);
    if (error != null) throw error!;
    return PagedResult(
      items: [
        for (final a in applications)
          if (a.kind == filter.kind &&
              (filter.status == null || a.status == filter.status))
            a,
      ],
      nextCursor: null,
    );
  }

  @override
  Stream<LeaveApplication?> watch(
    String schoolId,
    String branchId,
    String applicationId,
  ) => Stream.value(
    applications.where((a) => a.applicationId == applicationId).firstOrNull,
  );

  @override
  Future<List<LeaveApplication>> fetchForSubject({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String subjectId,
  }) async => [
    for (final a in applications)
      if (a.kind == kind && a.subjectId == subjectId) a,
  ];

  @override
  Stream<List<LeaveHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String applicationId, {
    required LeaveKind kind,
    required String subjectId,
  }) => Stream.value(history);

  @override
  Future<int> countPending({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
  }) async => pending;
}

class FakeLeaveTypeRepository implements LeaveTypeRepository {
  List<LeaveType> types;
  final List<LeaveType> saved = [];
  bool allowOnBehalf;

  FakeLeaveTypeRepository({this.types = const [], this.allowOnBehalf = false});

  @override
  Stream<List<LeaveType>> watchTypes(
    String schoolId,
    String branchId, {
    LeaveKind? kind,
  }) => Stream.value([
    for (final t in types)
      if (kind == null || t.kind == kind) t,
  ]);

  @override
  Future<void> saveType(
    LeaveType type, {
    required bool isNew,
    required String actorId,
  }) async {
    saved.add(type);
  }

  @override
  Stream<bool> watchAllowAdminOnBehalf(String schoolId, String branchId) =>
      Stream.value(allowOnBehalf);

  @override
  Future<void> setAllowAdminOnBehalf(
    String schoolId,
    String branchId,
    bool allow, {
    required String actorId,
  }) async {
    allowOnBehalf = allow;
  }
}

class FakeLeaveBalanceRepository implements LeaveBalanceRepository {
  List<LeaveBalance> balances;
  final List<({int units, String reason, String requestId})> adjustments = [];

  FakeLeaveBalanceRepository({this.balances = const []});

  @override
  Future<LeaveBalance?> getBalance(
    String schoolId,
    String branchId,
    String balanceId,
  ) async => balances.where((b) => b.balanceId == balanceId).firstOrNull;

  @override
  Stream<List<LeaveBalance>> watchStaffBalances({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String academicYearId,
  }) => Stream.value([
    for (final b in balances)
      if (b.staffId == staffId && b.academicYearId == academicYearId) b,
  ]);

  @override
  Future<PagedResult<LeaveLedgerEntry>> fetchLedger({
    required String schoolId,
    required String branchId,
    required String staffId,
    int pageSize = 25,
    Object? cursor,
  }) async => const PagedResult(items: [], nextCursor: null);

  @override
  Future<void> adjust({
    required LeaveBalance balance,
    required bool balanceExists,
    required int units,
    required String reason,
    required LeaveActor actor,
    required String requestId,
    String? staffUserId,
  }) async {
    adjustments.add((units: units, reason: reason, requestId: requestId));
  }

  @override
  Future<void> carryForward({
    required LeaveBalance toBalance,
    required int carryUnits,
    required LeaveActor actor,
  }) async {}

  @override
  Future<List<LeaveBalance>> fetchTypeBalances({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String typeId,
  }) async => [
    for (final b in balances)
      if (b.typeId == typeId) b,
  ];
}

class FakeLeaveCalendarRepository implements LeaveCalendarRepository {
  List<LeaveCalendarEntry> entries;
  final List<({LeaveKind kind, String? sectionId, String from})> queries = [];
  Object? error;

  FakeLeaveCalendarRepository({this.entries = const []});

  @override
  Future<List<LeaveCalendarEntry>> fetch({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String fromKey,
    required String toKey,
    String? classId,
    String? sectionId,
    String? subjectId,
  }) async {
    queries.add((kind: kind, sectionId: sectionId, from: fromKey));
    if (error != null) throw error!;
    return [
      for (final e in entries)
        if (e.kind == kind &&
            e.endDateKey.compareTo(fromKey) >= 0 &&
            e.startDateKey.compareTo(toKey) <= 0 &&
            (sectionId == null || e.sectionId == sectionId))
          e,
    ];
  }
}

class FakeLeaveNotificationRepository implements LeaveNotificationRepository {
  List<LeaveNotification> forUser;
  List<LeaveNotification> forReviewers;
  final List<String> marked = [];

  FakeLeaveNotificationRepository({
    this.forUser = const [],
    this.forReviewers = const [],
  });

  @override
  Stream<List<LeaveNotification>> watchForUser(
    String schoolId,
    String branchId,
    String userId,
  ) => Stream.value(forUser);

  @override
  Stream<List<LeaveNotification>> watchForReviewers(
    String schoolId,
    String branchId,
  ) => Stream.value(forReviewers);

  @override
  Future<void> markRead(
    String schoolId,
    String branchId,
    String notificationId,
  ) async {
    marked.add(notificationId);
  }
}

class FakeLeaveReportRepository implements LeaveReportRepository {
  @override
  Future<LeaveStatusCounts> statusCounts({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String fromKey,
    required String toKey,
  }) async => const LeaveStatusCounts({
    LeaveStatus.pending: 3,
    LeaveStatus.approved: 7,
    LeaveStatus.rejected: 1,
  });

  @override
  Future<LeaveTypeUsage> typeUsage({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String typeId,
    required String fromKey,
    required String toKey,
  }) async => LeaveTypeUsage(typeId: typeId, applications: 4, units: 9);

  @override
  Future<LeaveSectionSummary> sectionSummary({
    required String schoolId,
    required String branchId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  }) async => LeaveSectionSummary(
    classId: classId,
    sectionId: sectionId,
    applications: 2,
    units: 5,
  );

  @override
  Future<int> subjectUnits({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String subjectId,
    required String fromKey,
    required String toKey,
  }) async => 0;
}

class FakeLeaveAttachmentStore implements LeaveAttachmentStore {
  final List<String> uploads = [];

  @override
  Future<LeaveAttachment> upload({
    required String schoolId,
    required String branchId,
    required String applicantUserId,
    required String applicationId,
    required String fileName,
    required List<int> bytes,
  }) async {
    uploads.add(fileName);
    return LeaveAttachment(
      path: 'p/$fileName',
      name: fileName,
      contentType: 'application/pdf',
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<String> downloadUrl(String storagePath) async =>
      'https://example.test/$storagePath';
}
