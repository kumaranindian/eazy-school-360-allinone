import '../../students/domain/paged_result.dart';
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
}
