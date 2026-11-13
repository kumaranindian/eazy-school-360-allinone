import '../../students/domain/paged_result.dart';
import 'admission_activity.dart';
import 'admission_application.dart';
import 'admission_conversion.dart';
import 'admission_enquiry.dart';
import 'admission_report.dart';
import 'admission_fee.dart';
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

  /// Books a school visit ([input] carries the purpose). The server also moves
  /// the enquiry to VISIT_SCHEDULED when it is not there already.
  Future<String> scheduleVisit({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  });

  /// The history of every activity of one enquiry, newest first.
  Future<List<ActivityHistoryEntry>> fetchActivityHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  );

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

  // ---- applications and documents (phase 6) ---------------------------

  /// The application of an enquiry (its id is the enquiry id), or null.
  Stream<AdmissionApplication?> watchApplication(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// One page of applications, newest first; [status] narrows the list.
  Future<PagedResult<AdmissionApplication>> fetchApplications({
    required String schoolId,
    required String branchId,
    ApplicationStatus? status,
    int pageSize = 25,
    Object? cursor,
  });

  Future<List<ApplicationEvent>> fetchApplicationHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// Every document record of an application, newest first.
  Future<List<AdmissionDocument>> fetchDocuments(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// Counts of applications by status (server-side).
  Future<Map<ApplicationStatus, int>> countApplications(
    String schoolId,
    String branchId,
  );

  /// Starts the application (one per enquiry; repeating returns the same one).
  Future<String> createApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
  });

  Future<int> updateApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ApplicationInput input,
    int? baseRevision,
  });

  Future<int> submitApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    int? baseRevision,
  });

  /// [action] is `START` (take into review) or `COMMENT` (an internal note).
  Future<int> reviewApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String action,
    String? comment,
    int? baseRevision,
  });

  /// [decision] is `APPROVE` or `REJECT` (a rejection needs [comment]).
  Future<int> decideApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String decision,
    String? comment,
    int? baseRevision,
  });

  /// Step 1 of an upload: the server validates and says where to put the bytes.
  Future<DocumentUploadIntent> requestDocumentUpload({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String type,
    required String fileName,
    required String contentType,
    required int sizeBytes,
    required String requestId,
  });

  /// Step 3: the server checks the stored object and marks it uploaded.
  Future<void> confirmDocumentUpload({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
  });

  /// [decision] is `VERIFY` or `REJECT` (a rejection needs [reason]).
  Future<void> verifyDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
    required String decision,
    String? reason,
    int? baseRevision,
  });

  Future<void> removeDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
    String? reason,
  });

  // ---- admission fees (phase 7) ---------------------------------------

  Future<List<AdmissionFee>> fetchFees(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// Payments and refunds of an enquiry, newest first.
  Future<List<AdmissionFeePayment>> fetchFeePayments(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// Fee records of the branch that still have something to collect
  /// (due or part paid). Readable by Finance staff.
  Future<List<AdmissionFee>> fetchOpenFees(String schoolId, String branchId);

  Future<void> setFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required int amountMinor,
    String? feeStructureId,
    String? dueDate,
    String? note,
    int? baseRevision,
  });

  Future<void> cancelFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String reason,
  });

  Future<void> waiveFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String reason,
  });

  /// Records one manual payment; returns the receipt number. [requestId]
  /// makes a retry return the same payment.
  Future<String> recordPayment({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String requestId,
    required int amountMinor,
    required AdmissionPaymentMethod method,
    String? referenceNo,
    String? paymentDate,
    String? notes,
  });

  Future<void> refund({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String requestId,
    required int amountMinor,
    required AdmissionPaymentMethod method,
    required String reason,
    String? referenceNo,
  });

  // ---- conversion to a student (phase 8) ------------------------------

  /// The conversion record of an enquiry, or null when it was not converted.
  Future<AdmissionConversion?> fetchConversion(
    String schoolId,
    String branchId,
    String enquiryId,
  );

  /// Creates the student, placement, parents and links in one server
  /// transaction. Repeating the call returns the first result.
  Future<ConversionResult> convertToStudent({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ConversionInput input,
  });

  // ---- reports (phase 11) ----------------------------------------------

  /// Server-computed aggregates. [branchId] null = every branch (school
  /// administrators only). Dates are yyyy-mm-dd enquiry dates.
  Future<AdmissionReport> fetchReport({
    required String schoolId,
    String? branchId,
    String? academicYearId,
    String? from,
    String? to,
  });
}

/// The bytes of admission documents. Kept apart from the repository so the
/// upload flow can be tested without Firebase Storage. Reads go through the
/// authenticated Storage SDK (rules decide), never a shareable download link.
abstract class AdmissionDocumentStore {
  /// Puts [bytes] at [path] (create-only: the Storage rules refuse overwrites).
  Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  });

  /// The stored bytes (at most [AdmissionDocumentStore.maxRead]).
  Future<List<int>> read(String path);

  static const int maxRead = 6 * 1024 * 1024;
}
