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

  Future<void> setFeatures({
    required String schoolId,
    required Map<String, bool> features,
  });

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
