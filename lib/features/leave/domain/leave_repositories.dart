import '../../students/domain/paged_result.dart';
import 'leave_application.dart';
import 'leave_balance.dart';
import 'leave_enums.dart';
import 'leave_type.dart';

/// Who is acting (recorded on history, ledger and notifications).
class LeaveActor {
  final String userId;
  final String name;

  const LeaveActor({required this.userId, required this.name});
}

class LeaveFilter {
  final LeaveKind kind;
  final LeaveStatus? status;
  final String? typeId;
  final String? classId;
  final String? sectionId;
  final String? subjectId;
  final String? applicantUserId;

  const LeaveFilter({
    required this.kind,
    this.status,
    this.typeId,
    this.classId,
    this.sectionId,
    this.subjectId,
    this.applicantUserId,
  });
}

/// In-app notification (not a delivery receipt: "delivered" means it is
/// readable by its recipient in the app — nothing leaves the system).
class LeaveNotification {
  final String notificationId;
  final String type;
  final String? applicationId;
  final String title;
  final String? body;
  final bool read;
  final DateTime? createdAt;

  const LeaveNotification({
    required this.notificationId,
    required this.type,
    this.applicationId,
    required this.title,
    this.body,
    required this.read,
    this.createdAt,
  });
}

abstract class LeaveTypeRepository {
  Stream<List<LeaveType>> watchTypes(
    String schoolId,
    String branchId, {
    LeaveKind? kind,
  });

  /// Creates (when [isNew]) or updates a type. A type is never deleted.
  Future<void> saveType(
    LeaveType type, {
    required bool isNew,
    required String actorId,
  });

  /// Whether office staff may file a student's leave on a family's behalf
  /// (`leaveSettings/policy.allowAdminOnBehalf`). Off by default.
  Stream<bool> watchAllowAdminOnBehalf(String schoolId, String branchId);

  Future<void> setAllowAdminOnBehalf(
    String schoolId,
    String branchId,
    bool allow, {
    required String actorId,
  });
}

abstract class LeaveApplicationRepository {
  /// Files the application and its history, day-locks and reviewer notice in
  /// one commit. Idempotent on [LeaveApplication.applicationId].
  Future<void> submit(
    LeaveApplication application, {
    required LeaveActor actor,
  });

  /// An applicant's corrected resubmission of a RETURNED application.
  Future<void> resubmit(
    LeaveApplication application, {
    required LeaveActor actor,
  });

  Future<void> withdraw(
    LeaveApplication application, {
    required LeaveActor actor,
  });

  /// Approve / reject / return a PENDING application. Approval of tracked
  /// staff leave consumes the balance in the same transaction.
  Future<void> decide({
    required LeaveApplication application,
    required LeaveStatus target,
    required LeaveActor reviewer,
    String? remarks,
    String? subjectUserId,
    required String todayKey,
  });

  /// A reviewer cancels an APPROVED leave and restores the balance.
  Future<void> cancelApproved({
    required LeaveApplication application,
    required LeaveActor reviewer,
    required String remarks,
    String? subjectUserId,
  });

  Future<PagedResult<LeaveApplication>> fetch({
    required String schoolId,
    required String branchId,
    required LeaveFilter filter,
    int pageSize = 25,
    Object? cursor,
  });

  Stream<LeaveApplication?> watch(
    String schoolId,
    String branchId,
    String applicationId,
  );

  /// A subject's most recent applications (for the overlap pre-check and the
  /// history view). Bounded: at most 100.
  Future<List<LeaveApplication>> fetchForSubject({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String subjectId,
  });

  /// The decision history of one application. [kind] and [subjectId] are part
  /// of the query on purpose: `firestore.rules` can only prove a parent or a
  /// staff member may read the results when the query pins the subject.
  Stream<List<LeaveHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String applicationId, {
    required LeaveKind kind,
    required String subjectId,
  });

  Future<int> countPending({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
  });
}

abstract class LeaveBalanceRepository {
  Future<LeaveBalance?> getBalance(
    String schoolId,
    String branchId,
    String balanceId,
  );

  Stream<List<LeaveBalance>> watchStaffBalances({
    required String schoolId,
    required String branchId,
    required String staffId,
    required String academicYearId,
  });

  Future<PagedResult<LeaveLedgerEntry>> fetchLedger({
    required String schoolId,
    required String branchId,
    required String staffId,
    int pageSize = 25,
    Object? cursor,
  });

  /// A manual adjustment (± units) with a reason; creates the balance first
  /// if the year has none yet.
  ///
  /// [requestId] is generated once per dialog and becomes the ledger entry's
  /// id, so a retried submit cannot adjust twice.
  Future<void> adjust({
    required LeaveBalance balance,
    required bool balanceExists,
    required int units,
    required String reason,
    required LeaveActor actor,
    required String requestId,
    String? staffUserId,
  });

  /// Creates [toBalance] carrying forward [carryUnits] (already capped by the
  /// caller with `LeaveBalanceMath.carryForwardInto`).
  Future<void> carryForward({
    required LeaveBalance toBalance,
    required int carryUnits,
    required LeaveActor actor,
  });

  /// Balances of one leave type for a leave year (report; bounded at 300).
  Future<List<LeaveBalance>> fetchTypeBalances({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String typeId,
  });
}

abstract class LeaveCalendarRepository {
  /// Entries whose range reaches [fromKey]..[toKey]. Bounded at 300.
  Future<List<LeaveCalendarEntry>> fetch({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String fromKey,
    required String toKey,
    String? classId,
    String? sectionId,
    String? subjectId,
  });
}

abstract class LeaveNotificationRepository {
  Stream<List<LeaveNotification>> watchForUser(
    String schoolId,
    String branchId,
    String userId,
  );

  Stream<List<LeaveNotification>> watchForReviewers(
    String schoolId,
    String branchId,
  );

  Future<void> markRead(
    String schoolId,
    String branchId,
    String notificationId,
  );
}

class LeaveStatusCounts {
  final Map<LeaveStatus, int> byStatus;
  const LeaveStatusCounts(this.byStatus);

  int of(LeaveStatus s) => byStatus[s] ?? 0;
  int get total => byStatus.values.fold(0, (a, b) => a + b);
}

class LeaveTypeUsage {
  final String typeId;
  final int applications;
  final int units;
  const LeaveTypeUsage({
    required this.typeId,
    required this.applications,
    required this.units,
  });
}

class LeaveSectionSummary {
  final String classId;
  final String sectionId;
  final int applications;
  final int units;
  const LeaveSectionSummary({
    required this.classId,
    required this.sectionId,
    required this.applications,
    required this.units,
  });
}

/// Report numbers from aggregate queries (count / sum) — no documents are
/// downloaded. "Units" are half-days of APPROVED leave starting in the range.
abstract class LeaveReportRepository {
  Future<LeaveStatusCounts> statusCounts({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String fromKey,
    required String toKey,
  });

  Future<LeaveTypeUsage> typeUsage({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String typeId,
    required String fromKey,
    required String toKey,
  });

  Future<LeaveSectionSummary> sectionSummary({
    required String schoolId,
    required String branchId,
    required String classId,
    required String sectionId,
    required String fromKey,
    required String toKey,
  });

  Future<int> subjectUnits({
    required String schoolId,
    required String branchId,
    required LeaveKind kind,
    required String subjectId,
    required String fromKey,
    required String toKey,
  });
}

/// Supporting documents (often medical) for a leave application. Files live
/// under `…/leaveDocs/{applicantUid}/{applicationId}/…`; Storage rules let
/// only that applicant add to the folder and only they and reviewing admins
/// read it. Files are never replaced or deleted.
abstract class LeaveAttachmentStore {
  Future<LeaveAttachment> upload({
    required String schoolId,
    required String branchId,
    required String applicantUserId,
    required String applicationId,
    required String fileName,
    required List<int> bytes,
  });

  Future<String> downloadUrl(String storagePath);
}
