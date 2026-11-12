import '../../students/domain/paged_result.dart';
import 'admission_activity.dart';
import 'admission_enquiry.dart';
import 'admission_settings.dart';
import 'admission_status.dart';
import 'enquiry_query.dart';

/// Reads are direct (Firestore rules allow administrators to read); EVERY
/// write goes through a Cloud Function so numbering, duplicate flagging,
/// branch scoping and the status state machine are enforced server-side.
abstract class AdmissionRepository {
  Stream<AdmissionSettings> watchSettings(String schoolId);

  /// One page of enquiries, newest first. [search] replaces the filters (the
  /// list says so); [cursor] comes from the previous [PagedResult].
  Future<PagedResult<AdmissionEnquiry>> fetchEnquiries({
    required String schoolId,
    required String branchId,
    EnquiryFilters filters = const EnquiryFilters(),
    EnquirySearch? search,
    int pageSize = 25,
    Object? cursor,
  });

  Stream<AdmissionEnquiry?> watchEnquiry(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  Future<List<StatusHistoryEntry>> fetchHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// Server-side `count()` per status (never downloads the enquiries).
  Future<Map<AdmissionStatus, int>> countByStatus(
    String schoolId,
    String branchId,
  );

  Future<int> saveSettings({
    required String schoolId,
    required AdmissionSettings settings,
    int? baseVersion,
  });

  Future<CreatedEnquiry> createEnquiry({
    required String schoolId,
    required String branchId,
    required EnquiryInput input,
    String? assignedTo,
  });

  Future<int> updateEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required EnquiryInput input,
    int? baseRevision,
  });

  Future<int> assignEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String? assignedTo,
  });

  /// [status] is a wire status or `RESUME`.
  Future<int> changeStatus({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String status,
    String? reason,
    int? baseRevision,
  });

  // ---- follow-up activities (phase 4) ---------------------------------

  /// Every activity of one enquiry, open ones first (soonest first), then the
  /// finished ones (newest first). Nothing is ever deleted.
  Future<List<AdmissionActivity>> fetchActivitiesForEnquiry(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// One page of a dashboard list. [todayKey] is today in the SCHOOL's time
  /// zone; [userId] is who "mine" means.
  Future<PagedResult<AdmissionActivity>> fetchFollowUps({
    required String schoolId,
    required String branchId,
    required FollowUpBucket bucket,
    required String todayKey,
    required String userId,
    int pageSize = 25,
    Object? cursor,
  });

  Future<FollowUpCounts> countFollowUps({
    required String schoolId,
    required String branchId,
    required String todayKey,
    required String userId,
  });

  /// Open enquiries that have no follow-up planned.
  Future<PagedResult<AdmissionEnquiry>> fetchWithoutFollowUp({
    required String schoolId,
    required String branchId,
    int pageSize = 25,
    Object? cursor,
  });

  /// [requestId] makes a retry create nothing twice.
  Future<String> scheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  });

  Future<int> rescheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required String scheduledDate,
    String? scheduledTime,
    String? reason,
    int? baseRevision,
  });

  Future<int> reassignActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required String? assignedTo,
    int? baseRevision,
  });

  Future<int> cancelActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required String reason,
    int? baseRevision,
  });

  /// Completes an activity; [next] plans the following contact in the same
  /// server transaction. Returns the new activity's id when [next] is given.
  Future<String?> completeActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required ActivityCompletion completion,
    ActivityInput? next,
    int? baseRevision,
  });
}
