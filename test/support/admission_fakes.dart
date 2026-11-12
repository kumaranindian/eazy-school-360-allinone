import 'package:eazy_school_360/features/admission/domain/admission_activity.dart';
import 'package:eazy_school_360/features/admission/domain/admission_enquiry.dart';
import 'package:eazy_school_360/features/admission/domain/admission_repository.dart';
import 'package:eazy_school_360/features/admission/domain/admission_settings.dart';
import 'package:eazy_school_360/features/admission/domain/admission_status.dart';
import 'package:eazy_school_360/features/admission/domain/enquiry_query.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';

AdmissionEnquiry fakeEnquiry(
  String id, {
  String first = 'Asha',
  String last = 'Nair',
  AdmissionStatus status = AdmissionStatus.newEnquiry,
  String? heldFrom,
  String phone = '9876543210',
  String classId = 'c5',
  String yearId = 'y1',
  String source = 'Walk-in',
  List<String> duplicateOf = const [],
  String? remarks,
  int revision = 1,
  String? nextFollowUp,
  int activityCount = 0,
  int openActivityCount = 0,
}) => AdmissionEnquiry.fromMap(id, {
  'schoolId': 'school-1',
  'branchId': 'main',
  'enquiryNumber': 'ENQ-2026-${id.padLeft(5, '0')}',
  'enquiryDate': '2026-11-02',
  'student': {
    'firstName': first,
    'lastName': last,
    'dateOfBirth': '2020-05-01',
  },
  'academicYearId': yearId,
  'interestedClassId': classId,
  'source': source,
  'guardians': [
    {'name': 'Meena Nair', 'phone': phone, 'primary': true},
  ],
  'status': status.wire,
  'heldFrom': heldFrom,
  'duplicateOf': duplicateOf,
  'remarks': remarks,
  'nextFollowUpDate': nextFollowUp,
  'activityCount': activityCount,
  'openActivityCount': openActivityCount,
  'revision': revision,
});

AdmissionActivity fakeActivity(
  String id, {
  String enquiryId = '1',
  ActivityType type = ActivityType.phoneCall,
  ActivityStatus status = ActivityStatus.scheduled,
  String date = '2026-11-10',
  String? time,
  String? assignedTo,
  String? outcome,
  int revision = 1,
  int rescheduleCount = 0,
  String student = 'Asha Nair',
}) => AdmissionActivity.fromMap(id, {
  'enquiryId': enquiryId,
  'enquiryNumber': 'ENQ-2026-${enquiryId.padLeft(5, '0')}',
  'studentName': student,
  'type': type.wire,
  'status': status.wire,
  'scheduledDate': date,
  'scheduledTime': time,
  'assignedTo': assignedTo,
  'outcome': outcome,
  'revision': revision,
  'rescheduleCount': rescheduleCount,
});

/// In-memory [AdmissionRepository] that records what the UI asks for.
class FakeAdmissionRepository implements AdmissionRepository {
  AdmissionSettings settings;
  final List<AdmissionEnquiry> enquiries;
  final List<StatusHistoryEntry> history;
  Map<AdmissionStatus, int> counts;

  final List<EnquiryFilters> fetchedFilters = [];
  final List<EnquirySearch?> fetchedSearches = [];
  final List<({EnquiryInput input, String? assignedTo})> created = [];
  final List<({String id, EnquiryInput input, int? base})> updated = [];
  final List<({String id, String status, String? reason, int? base})>
  statusChanges = [];
  final List<({String id, String? to})> assigned = [];
  final List<AdmissionSettings> savedSettings = [];
  Object? failWith;

  final List<AdmissionActivity> activities;
  FollowUpCounts followUpCounts;
  final List<FollowUpBucket> fetchedBuckets = [];
  final List<({String enquiryId, ActivityInput input, String requestId})>
  scheduled = [];
  final List<
    ({String id, String date, String? time, String? reason, int? base})
  >
  rescheduled = [];
  final List<({String id, String? to})> reassigned = [];
  final List<({String id, String reason})> cancelled = [];
  final List<({String id, ActivityCompletion completion, ActivityInput? next})>
  completed = [];

  FakeAdmissionRepository({
    this.settings = const AdmissionSettings(enabled: true, version: 1),
    List<AdmissionEnquiry>? enquiries,
    List<AdmissionActivity>? activities,
    this.followUpCounts = const FollowUpCounts(
      today: 2,
      overdue: 1,
      upcoming: 3,
    ),
    this.history = const [],
    this.counts = const {
      AdmissionStatus.newEnquiry: 3,
      AdmissionStatus.interested: 2,
      AdmissionStatus.approved: 1,
      AdmissionStatus.admissionConfirmed: 2,
      AdmissionStatus.rejected: 1,
    },
  }) : enquiries = enquiries ?? [fakeEnquiry('1')],
       activities = activities ?? [];

  void _maybeFail() {
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Stream<AdmissionSettings> watchSettings(String schoolId) =>
      Stream.value(settings);

  @override
  Future<PagedResult<AdmissionEnquiry>> fetchEnquiries({
    required String schoolId,
    required String branchId,
    EnquiryFilters filters = const EnquiryFilters(),
    EnquirySearch? search,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchedFilters.add(filters);
    fetchedSearches.add(search);
    final plan = EnquiryQueryPlan.of(filters);
    var items = enquiries.where(plan.clientTest);
    if (plan.server != null) {
      final (field, value) = plan.server!;
      items = items.where(
        (e) => switch (field) {
          'status' => e.status.wire == value,
          'assignedTo' => e.assignedTo == value,
          'interestedClassId' => e.interestedClassId == value,
          'academicYearId' => e.academicYearId == value,
          'source' => e.source == value,
          _ => true,
        },
      );
    }
    if (search != null && search.kind == EnquirySearchKind.name) {
      items = items.where(
        (e) => e.studentName.toLowerCase().startsWith(search.value),
      );
    }
    return PagedResult(items: items.toList(), nextCursor: null);
  }

  @override
  Stream<AdmissionEnquiry?> watchEnquiry(
    String schoolId,
    String branchId,
    String enquiryId,
  ) => Stream.value(enquiries.where((e) => e.id == enquiryId).firstOrNull);

  @override
  Future<List<StatusHistoryEntry>> fetchHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => history;

  @override
  Future<Map<AdmissionStatus, int>> countByStatus(
    String schoolId,
    String branchId,
  ) async => counts;

  @override
  Future<int> saveSettings({
    required String schoolId,
    required AdmissionSettings settings,
    int? baseVersion,
  }) async {
    _maybeFail();
    savedSettings.add(settings);
    return (baseVersion ?? 0) + 1;
  }

  @override
  Future<CreatedEnquiry> createEnquiry({
    required String schoolId,
    required String branchId,
    required EnquiryInput input,
    String? assignedTo,
  }) async {
    _maybeFail();
    created.add((input: input, assignedTo: assignedTo));
    return const CreatedEnquiry(id: '9', enquiryNumber: 'ENQ-2026-00009');
  }

  @override
  Future<int> updateEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required EnquiryInput input,
    int? baseRevision,
  }) async {
    _maybeFail();
    updated.add((id: enquiryId, input: input, base: baseRevision));
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<int> assignEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String? assignedTo,
  }) async {
    _maybeFail();
    assigned.add((id: enquiryId, to: assignedTo));
    return 2;
  }

  @override
  Future<int> changeStatus({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String status,
    String? reason,
    int? baseRevision,
  }) async {
    _maybeFail();
    statusChanges.add((
      id: enquiryId,
      status: status,
      reason: reason,
      base: baseRevision,
    ));
    return (baseRevision ?? 0) + 1;
  }

  // ---- follow-up activities -------------------------------------------

  @override
  Future<List<AdmissionActivity>> fetchActivitiesForEnquiry(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => [
    for (final a in activities)
      if (a.enquiryId == enquiryId) a,
  ];

  @override
  Future<PagedResult<AdmissionActivity>> fetchFollowUps({
    required String schoolId,
    required String branchId,
    required FollowUpBucket bucket,
    required String todayKey,
    required String userId,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchedBuckets.add(bucket);
    final items = activities.where((a) {
      return switch (bucket) {
        FollowUpBucket.today => a.isOpen && a.scheduledDate == todayKey,
        FollowUpBucket.overdue =>
          a.isOpen && a.scheduledDate.compareTo(todayKey) < 0,
        FollowUpBucket.upcoming =>
          a.isOpen && a.scheduledDate.compareTo(todayKey) > 0,
        FollowUpBucket.mine => a.isOpen && a.assignedTo == userId,
        FollowUpBucket.unassigned => a.isOpen && a.assignedTo == null,
        FollowUpBucket.completed => a.status == ActivityStatus.completed,
      };
    }).toList();
    return PagedResult(items: items, nextCursor: null);
  }

  @override
  Future<FollowUpCounts> countFollowUps({
    required String schoolId,
    required String branchId,
    required String todayKey,
    required String userId,
  }) async => followUpCounts;

  @override
  Future<PagedResult<AdmissionEnquiry>> fetchWithoutFollowUp({
    required String schoolId,
    required String branchId,
    int pageSize = 25,
    Object? cursor,
  }) async => PagedResult(
    items: [
      for (final e in enquiries)
        if (e.status.isOpen && e.nextFollowUpDate == null) e,
    ],
    nextCursor: null,
  );

  @override
  Future<String> scheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async {
    _maybeFail();
    scheduled.add((enquiryId: enquiryId, input: input, requestId: requestId));
    return 'new-activity';
  }

  @override
  Future<int> rescheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required String scheduledDate,
    String? scheduledTime,
    String? reason,
    int? baseRevision,
  }) async {
    _maybeFail();
    rescheduled.add((
      id: activityId,
      date: scheduledDate,
      time: scheduledTime,
      reason: reason,
      base: baseRevision,
    ));
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<int> reassignActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required String? assignedTo,
    int? baseRevision,
  }) async {
    _maybeFail();
    reassigned.add((id: activityId, to: assignedTo));
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<int> cancelActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required String reason,
    int? baseRevision,
  }) async {
    _maybeFail();
    cancelled.add((id: activityId, reason: reason));
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<String?> completeActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String activityId,
    required ActivityCompletion completion,
    ActivityInput? next,
    int? baseRevision,
  }) async {
    _maybeFail();
    completed.add((id: activityId, completion: completion, next: next));
    return next == null ? null : 'next-activity';
  }
}
