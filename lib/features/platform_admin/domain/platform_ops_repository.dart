import 'audit_trail.dart';
import 'platform_ops_models.dart';

/// School lifecycle, billing records, dashboard numbers, notices and app
/// requirements for the platform console. Every action is a server call that
/// checks the caller's platform role and writes an audit record.
abstract class PlatformOpsRepository {
  // ---- lifecycle ----
  Future<void> setSchoolStatus({
    required String schoolId,
    required SchoolStatusChoice status,
    String? reason,
  });

  /// Re-applies the school's status to its users (repair).
  Future<void> refreshSchoolAccess(String schoolId);

  /// Creates the school and its first admin; returns the admin's email.
  Future<({String schoolId, String adminEmail})> createSchool(
    NewSchoolInput input,
  );

  Future<String> addSchoolAdmin({
    required String schoolId,
    required String name,
    required String email,
  });

  /// Signs a school admin out everywhere; returns their email.
  Future<String> resetSchoolAdminAccess({
    required String schoolId,
    required String uid,
  });

  /// Switches modules for one school. Switching OFF needs a [reason]; a module
  /// with dependants needs [confirmDependants] (they are switched off too).
  Future<void> setFeatures({
    required String schoolId,
    required Map<String, bool> features,
    String? reason,
    bool confirmDependants = false,
  });

  Future<List<FeatureHistoryEntry>> featureHistory(String schoolId);

  /// The switches copied into schools created from now on.
  Future<Map<String, bool>> featureDefaults();

  Future<void> setFeatureDefaults(Map<String, bool> features);

  /// Moves a school through the validated lifecycle table (activate,
  /// deactivate, suspend, reactivate). Closing goes through offboarding.
  Future<void> transitionSchool({
    required String schoolId,
    required SchoolStatusChoice to,
    String? reason,
    String? remarks,
    String? internalNotes,
    String? message,
  });

  /// Recovery of a CLOSED school: request, a different owner approves, cancel.
  Future<void> requestRecovery({
    required String schoolId,
    required String reason,
  });
  Future<void> approveRecovery(String schoolId);
  Future<void> cancelRecovery(String schoolId);

  Future<void> requestOffboarding({
    required String schoolId,
    required String reason,
  });
  Future<void> approveOffboarding(String schoolId);
  Future<void> cancelOffboarding(String schoolId);

  // ---- billing ----
  Future<BillingSummary> billing({String? schoolId});

  Future<void> saveBillingRecord({
    required String schoolId,
    required String period,
    required int amountMinor,
    required String currency,
    required String dueDate,
    String? reference,
    String? note,
  });

  Future<void> setBillingStatus({
    required String id,
    required String status,
    String? paidDate,
    String? note,
  });

  // ---- dashboard ----
  Stream<PlatformStats?> watchStats();

  /// Recomputes the numbers now; false when it was throttled.
  Future<bool> refreshStats();

  // ---- notices ----
  Future<List<PlatformNotice>> notices();

  Future<void> publishNotice({
    required String title,
    required String body,
    required NoticeSeverity severity,
    required bool audienceAll,
    List<String> schoolIds = const [],
    DateTime? startsAt,
    required DateTime endsAt,
  });

  Future<void> withdrawNotice(String id);

  /// What a school's administrators see (everyone's notices plus theirs).
  Stream<List<SchoolNotice>> watchSchoolNotices(String schoolId);

  // ---- central audit trail (owner and compliance only) ----
  Future<AuditPage> queryAudit(
    AuditFilter filter, {
    Map<String, dynamic>? cursor,
  });

  Future<AuditSummary> auditSummary({int hours = 24});

  /// The filtered events as CSV text (capped by the server; the export is audited).
  Future<({String csv, int rows, bool capped})> exportAudit(AuditFilter filter);

  // ---- subscriptions (owner writes; every platform role reads) ----
  Future<List<PlatformPlan>> plans();

  Future<void> savePlan({
    String? planId,
    required String name,
    required String periodType,
    bool active = true,
  });

  Future<List<SubscriptionHistoryEntry>> subscriptionHistory(String schoolId);

  /// [op]: set | extend | renew | cancel | trial. Only the fields an operation
  /// uses are sent.
  Future<void> subscriptionOp(
    String op, {
    required String schoolId,
    String? planId,
    String? classification,
    String? startDate,
    String? endDate,
    int? gracePeriodDays,
    int? days,
    String? reason,
    String? remarks,
    String? internalNotes,
  });

  /// The signed-in administrator's own platform notifications (newest first).
  Stream<List<PlatformNotification>> watchMyNotifications();

  Future<void> acknowledgeNotification(String id);

  Future<void> dismissNotification(String id);

  // ---- app requirements ----
  Stream<AppRequirements> watchAppRequirements();

  Future<void> setAppRequirements({
    required int minBuildAndroid,
    required int minBuildIos,
    required bool maintenanceOn,
    String? message,
    DateTime? until,
  });
}
