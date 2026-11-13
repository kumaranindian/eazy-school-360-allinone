import 'package:eazy_school_360/features/admission/domain/admission_activity.dart';
import 'package:eazy_school_360/features/admission/domain/admission_application.dart';
import 'package:eazy_school_360/features/admission/domain/admission_conversion.dart';
import 'package:eazy_school_360/features/admission/domain/admission_enquiry.dart';
import 'package:eazy_school_360/features/admission/domain/admission_report.dart';
import 'package:eazy_school_360/features/admission/domain/admission_fee.dart';
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
  String? channel,
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
  'channel': channel,
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
  VisitPurpose? purpose,
}) => AdmissionActivity.fromMap(id, {
  'purpose': purpose?.wire,
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

AdmissionApplication fakeApplication(
  String enquiryId, {
  ApplicationStatus status = ApplicationStatus.draft,
  int revision = 1,
  String number = 'APP-2026-00001',
  String? decisionComment,
}) => AdmissionApplication.fromMap(enquiryId, {
  'schoolId': 'school-1',
  'branchId': 'main',
  'enquiryId': enquiryId,
  'enquiryNumber': 'ENQ-2026-${enquiryId.padLeft(5, '0')}',
  'applicationNumber': number,
  'status': status.wire,
  'student': {
    'firstName': 'Asha',
    'lastName': 'Nair',
    'dateOfBirth': '2020-05-01',
    'gender': 'FEMALE',
  },
  'academicYearId': 'y1',
  'classId': 'c5',
  'guardians': [
    {'name': 'Meena Nair', 'phone': '9876543210', 'primary': true},
  ],
  'decisionComment': decisionComment,
  'revision': revision,
});

AdmissionDocument fakeDocument(
  String id, {
  String type = 'BIRTH_CERTIFICATE',
  DocumentStatus status = DocumentStatus.uploaded,
  String fileName = 'birth.pdf',
  String contentType = 'application/pdf',
  int size = 2048,
  String? rejectionReason,
  int revision = 2,
}) => AdmissionDocument.fromMap(id, {
  'type': type,
  'label': builtInDocumentTypes[type] ?? type,
  'fileName': fileName,
  'contentType': contentType,
  'sizeBytes': size,
  'storagePath':
      'schools/school-1/branches/main/admissionDocs/1/$id/document.pdf',
  'status': status.wire,
  'rejectionReason': rejectionReason,
  'revision': revision,
});

/// Records uploads and serves reads; can be told to fail the first uploads.
class FakeDocumentStore implements AdmissionDocumentStore {
  final List<({String path, int size, String contentType})> uploads = [];
  final Map<String, List<int>> files = {};
  int failUploads = 0;
  int attempts = 0;
  Object? failReadWith;

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    attempts++;
    if (failUploads > 0) {
      failUploads--;
      throw StateError('network');
    }
    uploads.add((path: path, size: bytes.length, contentType: contentType));
    files[path] = bytes;
  }

  @override
  Future<List<int>> read(String path) async {
    final f = failReadWith;
    if (f != null) throw f;
    return files[path] ?? const [];
  }
}

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

  AdmissionApplication? application;
  List<AdmissionDocument> documents = [];
  AdmissionConversion? conversion;
  AdmissionReport? report;
  final List<Map<String, String?>> reportRequests = [];
  final List<ConversionInput> conversions = [];
  List<AdmissionFee> fees = [];
  List<AdmissionFeePayment> feePayments = [];
  final List<String> feeCalls = [];
  final List<Map<String, Object?>> recordedPayments = [];
  List<ApplicationEvent> applicationEvents = [];
  Map<ApplicationStatus, int> applicationCounts = const {};
  final List<ApplicationStatus?> fetchedApplicationStatuses = [];
  final List<String> applicationCalls = [];
  final List<ApplicationInput> applicationUpdates = [];
  final List<({String action, String? comment})> reviews = [];
  final List<({String decision, String? comment})> decisions = [];
  final List<
    ({
      String type,
      String fileName,
      String contentType,
      int size,
      String requestId,
    })
  >
  uploadRequests = [];
  final List<String> confirmedDocuments = [];
  final List<({String id, String decision, String? reason, int? base})>
  documentDecisions = [];
  final List<({String id, String? reason})> removedDocuments = [];
  Object? confirmFailsWith;

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
        FollowUpBucket.visits =>
          a.isOpen && a.isVisit && a.scheduledDate.compareTo(todayKey) >= 0,
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

  final List<({String enquiryId, ActivityInput input, String requestId})>
  visitsBooked = [];
  List<ActivityHistoryEntry> activityHistory = [];

  @override
  Future<String> scheduleVisit({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async {
    _maybeFail();
    visitsBooked.add((
      enquiryId: enquiryId,
      input: input,
      requestId: requestId,
    ));
    return 'new-visit';
  }

  @override
  Future<List<ActivityHistoryEntry>> fetchActivityHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => activityHistory;

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

  // ---- applications and documents -------------------------------------

  @override
  Stream<AdmissionApplication?> watchApplication(
    String schoolId,
    String branchId,
    String enquiryId,
  ) => Stream.value(application?.enquiryId == enquiryId ? application : null);

  @override
  Future<PagedResult<AdmissionApplication>> fetchApplications({
    required String schoolId,
    required String branchId,
    ApplicationStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchedApplicationStatuses.add(status);
    final a = application;
    return PagedResult(
      items: [if (a != null && (status == null || a.status == status)) a],
      nextCursor: null,
    );
  }

  @override
  Future<List<ApplicationEvent>> fetchApplicationHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => applicationEvents;

  @override
  Future<List<AdmissionFee>> fetchFees(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => fees;

  @override
  Future<List<AdmissionFeePayment>> fetchFeePayments(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => feePayments;

  @override
  Future<List<AdmissionFee>> fetchOpenFees(
    String schoolId,
    String branchId,
  ) async => [
    for (final f in fees)
      if (f.status == AdmissionFeeStatus.due ||
          f.status == AdmissionFeeStatus.partial)
        f,
  ];

  @override
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
  }) async {
    if (failWith != null) throw failWith!;
    feeCalls.add(
      'set ${category.wire} $amountMinor'
      '${feeStructureId == null ? '' : ' via $feeStructureId'}',
    );
  }

  @override
  Future<void> cancelFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String reason,
  }) async {
    if (failWith != null) throw failWith!;
    feeCalls.add('cancel ${category.wire} $reason');
  }

  @override
  Future<void> waiveFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String reason,
  }) async {
    if (failWith != null) throw failWith!;
    feeCalls.add('waive ${category.wire} $reason');
  }

  @override
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
  }) async {
    if (failWith != null) throw failWith!;
    recordedPayments.add({
      'category': category.wire,
      'requestId': requestId,
      'amountMinor': amountMinor,
      'method': method.wire,
      'referenceNo': referenceNo,
    });
    return 'RCT-2026-000001';
  }

  @override
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
  }) async {
    if (failWith != null) throw failWith!;
    feeCalls.add('refund ${category.wire} $amountMinor $reason');
  }

  @override
  Future<AdmissionConversion?> fetchConversion(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => conversion;

  @override
  Future<ConversionResult> convertToStudent({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ConversionInput input,
  }) async {
    if (failWith != null) throw failWith!;
    conversions.add(input);
    conversion = const AdmissionConversion(
      studentId: 's_1',
      admissionNumber: 'ADM-0001',
    );
    return const ConversionResult(
      studentId: 's_1',
      admissionNumber: 'ADM-0001',
      duplicate: false,
    );
  }

  @override
  Future<AdmissionReport> fetchReport({
    required String schoolId,
    String? branchId,
    String? academicYearId,
    String? from,
    String? to,
  }) async {
    if (failWith != null) throw failWith!;
    reportRequests.add({
      'branchId': branchId,
      'academicYearId': academicYearId,
      'from': from,
      'to': to,
    });
    return report ?? fakeReport();
  }

  @override
  Future<List<AdmissionDocument>> fetchDocuments(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async => documents;

  @override
  Future<Map<ApplicationStatus, int>> countApplications(
    String schoolId,
    String branchId,
  ) async => applicationCounts;

  @override
  Future<String> createApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
  }) async {
    _maybeFail();
    applicationCalls.add('create:$enquiryId');
    application = fakeApplication(enquiryId);
    return 'APP-2026-00001';
  }

  @override
  Future<int> updateApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ApplicationInput input,
    int? baseRevision,
  }) async {
    _maybeFail();
    applicationUpdates.add(input);
    applicationCalls.add('update:$enquiryId:$baseRevision');
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<int> submitApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    int? baseRevision,
  }) async {
    _maybeFail();
    applicationCalls.add('submit:$enquiryId:$baseRevision');
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<int> reviewApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String action,
    String? comment,
    int? baseRevision,
  }) async {
    _maybeFail();
    reviews.add((action: action, comment: comment));
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<int> decideApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String decision,
    String? comment,
    int? baseRevision,
  }) async {
    _maybeFail();
    decisions.add((decision: decision, comment: comment));
    return (baseRevision ?? 0) + 1;
  }

  @override
  Future<DocumentUploadIntent> requestDocumentUpload({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String type,
    required String fileName,
    required String contentType,
    required int sizeBytes,
    required String requestId,
  }) async {
    _maybeFail();
    uploadRequests.add((
      type: type,
      fileName: fileName,
      contentType: contentType,
      size: sizeBytes,
      requestId: requestId,
    ));
    return const DocumentUploadIntent(
      id: 'doc-new',
      storagePath:
          'schools/school-1/branches/main/admissionDocs/1/doc-new/document.pdf',
    );
  }

  @override
  Future<void> confirmDocumentUpload({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
  }) async {
    final f = confirmFailsWith;
    if (f != null) throw f;
    confirmedDocuments.add(documentId);
  }

  @override
  Future<void> verifyDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
    required String decision,
    String? reason,
    int? baseRevision,
  }) async {
    _maybeFail();
    documentDecisions.add((
      id: documentId,
      decision: decision,
      reason: reason,
      base: baseRevision,
    ));
  }

  @override
  Future<void> removeDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
    String? reason,
  }) async {
    _maybeFail();
    removedDocuments.add((id: documentId, reason: reason));
  }
}

AdmissionReport fakeReport({bool schoolWide = false, bool truncated = false}) =>
    AdmissionReport.fromMap({
      'total': 10,
      'scope': schoolWide ? 'SCHOOL' : 'BRANCH',
      'truncated': truncated,
      'byStatus': {'NEW': 4, 'ADMISSION_CONFIRMED': 2, 'NOT_INTERESTED': 4},
      'conversion': {'confirmed': 2, 'total': 10, 'ratePercent': 20},
      'bySource': [
        {'source': 'Website', 'count': 6, 'confirmed': 2, 'ratePercent': 33.3},
        {'source': 'Walk-in', 'count': 4, 'confirmed': 0, 'ratePercent': 0},
      ],
      'byClass': [
        {'classId': 'c5', 'count': 10, 'confirmed': 2, 'ratePercent': 20},
      ],
      'byAssignee': [
        {
          'userId': null,
          'name': 'Unassigned',
          'count': 7,
          'confirmed': 1,
          'ratePercent': 14.3,
        },
        {
          'userId': 'u1',
          'name': 'Ravi Menon',
          'count': 3,
          'confirmed': 1,
          'ratePercent': 33.3,
        },
      ],
      'byBranch': [
        {
          'branchId': 'main',
          'name': 'Main',
          'count': 6,
          'confirmed': 1,
          'ratePercent': 16.7,
        },
        {
          'branchId': 'north',
          'name': 'North',
          'count': 4,
          'confirmed': 1,
          'ratePercent': 25,
        },
      ],
      'byMonth': [
        {'month': '2026-10', 'count': 6, 'confirmed': 1},
        {'month': '2026-11', 'count': 4, 'confirmed': 1},
      ],
      'lost': {
        'total': 4,
        'NOT_INTERESTED': 3,
        'REJECTED': 1,
        'WITHDRAWN': 0,
        'reasons': [
          {'reason': 'fees too high', 'count': 3},
          {'reason': '=cmd|evil', 'count': 1},
        ],
      },
      'followUps': {
        'total': 8,
        'completed': 4,
        'cancelled': 1,
        'open': 3,
        'overdueOpen': 2,
        'completionRatePercent': 50,
      },
      'fees': {
        'currency': 'INR',
        'amountMinor': 500000,
        'netPaidMinor': 300000,
        'balanceMinor': 200000,
        'byCategory': [
          {
            'category': 'APPLICATION',
            'amountMinor': 500000,
            'netPaidMinor': 300000,
            'balanceMinor': 200000,
          },
        ],
      },
      'classNames': {'c5': 'Class 5'},
    });
