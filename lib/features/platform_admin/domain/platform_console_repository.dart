import 'audit_entry.dart';
import 'deletion_review.dart';
import 'platform_school.dart';
import 'school_overview.dart';
import 'support_grant.dart';

/// Everything the platform console reads and does outside the school app:
/// the schools directory, support sessions, the deletion-review queue and the
/// audit log. Each action is a server call that checks the caller and writes
/// an audit record.
abstract class PlatformConsoleRepository {
  Future<List<PlatformSchool>> listSchools();

  Future<SchoolOverview> schoolOverview(String schoolId);

  /// Opens a read-only support session. Returns when the grant ends.
  Future<DateTime> requestSupportAccess({
    required String schoolId,
    required String reason,
    String? ticket,
    required int minutes,
  });

  /// Ends a grant early ([adminUid] null = the caller's own).
  Future<void> revokeSupportAccess({
    required String schoolId,
    String? adminUid,
  });

  /// The signed-in platform admin's own grants (live).
  Stream<List<SupportGrant>> watchMyGrants(String uid);

  /// The grants and the access log of ONE school, for its administrators.
  Stream<List<SupportGrant>> watchSchoolGrants(String schoolId);
  Stream<List<SupportAccessLogEntry>> watchSupportAccessLog(String schoolId);

  Future<List<AuditEntry>> recentAudit();

  Future<List<DeletionReviewItem>> deletionRequests({required bool closed});

  Future<void> reviewDeletion({
    required String reference,
    required DeletionDecision decision,
    String? reasonCode,
  });
}
