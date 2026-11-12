import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/admission_activity.dart';
import '../domain/admission_application.dart';
import '../domain/admission_conversion.dart';
import '../domain/admission_enquiry.dart';
import '../domain/admission_fee.dart';
import '../domain/admission_repository.dart';
import '../domain/admission_settings.dart';
import '../domain/admission_status.dart';
import '../domain/enquiry_query.dart';

class FirebaseAdmissionRepository implements AdmissionRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  FirebaseAdmissionRepository({
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  }) : _db = db ?? FirebaseFirestore.instance,
       _functions = functions ?? appFunctions();

  static const _enquiries = 'admissionEnquiries';
  static const _history = 'admissionStatusHistory';
  static const _activities = 'admissionActivities';
  static const _activityHistory = 'admissionActivityHistory';
  static const _applications = 'admissionApplications';
  static const _applicationHistory = 'admissionApplicationHistory';
  static const _documents = 'admissionDocuments';
  static const _fees = 'admissionFees';
  static const _conversions = 'admissionConversions';
  static const _feePayments = 'admissionFeePayments';

  DocumentReference<Map<String, dynamic>> _settingsDoc(String schoolId) => _db
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection('admissionSettings')
      .doc('config');

  CollectionReference<Map<String, dynamic>> _col(
    String schoolId,
    String branchId,
    String name,
  ) => _db
      .collection(FirestoreFields.schoolsCollection)
      .doc(schoolId)
      .collection(FirestoreFields.branchesCollection)
      .doc(branchId)
      .collection(name);

  AdmissionEnquiry _enquiry(DocumentSnapshot<Map<String, dynamic>> d) =>
      AdmissionEnquiry.fromMap(
        d.id,
        d.data() ?? const {},
        createdAt: (d.data()?['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (d.data()?['updatedAt'] as Timestamp?)?.toDate(),
        lastActivityAt: (d.data()?['lastActivityAt'] as Timestamp?)?.toDate(),
      );

  @override
  Stream<AdmissionSettings> watchSettings(String schoolId) => _settingsDoc(
    schoolId,
  ).snapshots().map((s) => AdmissionSettings.fromMap(s.data()));

  @override
  Future<PagedResult<AdmissionEnquiry>> fetchEnquiries({
    required String schoolId,
    required String branchId,
    EnquiryFilters filters = const EnquiryFilters(),
    EnquirySearch? search,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      final col = _col(schoolId, branchId, _enquiries);
      if (search != null) {
        return _searchPage(col, search, pageSize, cursor);
      }
      final plan = EnquiryQueryPlan.of(filters);
      Query<Map<String, dynamic>> base = col;
      final server = plan.server;
      if (server != null) base = base.where(server.$1, isEqualTo: server.$2);
      base = base.orderBy('createdAt', descending: true);

      // Remaining filters are applied here, so a page may need more than one
      // read to fill; bounded so a very selective filter cannot loop.
      final items = <AdmissionEnquiry>[];
      DocumentSnapshot<Map<String, dynamic>>? last =
          cursor as DocumentSnapshot<Map<String, dynamic>>?;
      var exhausted = false;
      for (var reads = 0; reads < 4 && items.length < pageSize; reads++) {
        var q = base.limit(pageSize);
        if (last != null) q = q.startAfterDocument(last);
        final snap = await q.get();
        for (final d in snap.docs) {
          final e = _enquiry(d);
          if (plan.clientTest(e) && items.length < pageSize) items.add(e);
          last = d;
        }
        if (snap.docs.length < pageSize) {
          exhausted = true;
          break;
        }
      }
      return PagedResult(items: items, nextCursor: exhausted ? null : last);
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  Future<PagedResult<AdmissionEnquiry>> _searchPage(
    CollectionReference<Map<String, dynamic>> col,
    EnquirySearch search,
    int pageSize,
    Object? cursor,
  ) async {
    Query<Map<String, dynamic>> q;
    switch (search.kind) {
      case EnquirySearchKind.name:
        q = col
            .where('studentNameLower', isGreaterThanOrEqualTo: search.value)
            .where('studentNameLower', isLessThan: '${search.value}')
            .orderBy('studentNameLower');
      case EnquirySearchKind.phone:
        q = col.where('primaryPhone', isEqualTo: search.value);
      case EnquirySearchKind.number:
        q = col.where('enquiryNumber', isEqualTo: search.value);
    }
    q = q.limit(pageSize);
    if (cursor != null) {
      q = q.startAfterDocument(
        cursor as DocumentSnapshot<Map<String, dynamic>>,
      );
    }
    final snap = await q.get();
    return PagedResult(
      items: [for (final d in snap.docs) _enquiry(d)],
      nextCursor: snap.docs.length < pageSize ? null : snap.docs.last,
    );
  }

  @override
  Stream<AdmissionEnquiry?> watchEnquiry(
    String schoolId,
    String branchId,
    String enquiryId,
  ) => _col(
    schoolId,
    branchId,
    _enquiries,
  ).doc(enquiryId).snapshots().map((d) => d.exists ? _enquiry(d) : null);

  @override
  Future<List<StatusHistoryEntry>> fetchHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(
        schoolId,
        branchId,
        _history,
      ).where('enquiryId', isEqualTo: enquiryId).orderBy('revision').get();
      return [
        for (final d in snap.docs)
          StatusHistoryEntry.fromMap(
            d.data(),
            at: (d.data()['at'] as Timestamp?)?.toDate(),
          ),
      ];
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<Map<AdmissionStatus, int>> countByStatus(
    String schoolId,
    String branchId,
  ) async {
    try {
      final col = _col(schoolId, branchId, _enquiries);
      final entries = await Future.wait([
        for (final s in AdmissionStatus.values)
          col
              .where('status', isEqualTo: s.wire)
              .count()
              .get()
              .then((r) => MapEntry(s, r.count ?? 0)),
      ]);
      return Map.fromEntries(entries);
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return (r.data as Map?)?.cast<String, dynamic>() ?? const {};
    } on FirebaseFunctionsException catch (e, st) {
      final cause = (e.details is Map ? (e.details as Map)['cause'] : null)
          ?.toString();
      switch (e.code) {
        case 'invalid-argument':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'Some details were not accepted. Check the form and try again.'
                : 'Some details were not accepted ($cause).',
          );
        case 'permission-denied':
          throw const PermissionFailure(
            'You do not have permission to manage admissions here.',
          );
        case 'not-found':
          throw const NotFoundFailure('That enquiry could not be found.');
        case 'aborted':
          throw const ValidationFailure(
            'This enquiry was changed by someone else. Reload and try again.',
          );
        case 'failed-precondition':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'That is not possible right now.'
                : _precondition(cause),
          );
        default:
          throw mapExceptionToFailure(e, st);
      }
    } catch (e, st) {
      if (e is AppFailure) rethrow;
      throw mapExceptionToFailure(e, st);
    }
  }

  static String _precondition(String cause) {
    if (cause.contains('not enabled')) {
      return 'Admissions are not switched on for this school yet. Ask a '
          'school administrator to enable them in Admission settings.';
    }
    return cause[0].toUpperCase() + cause.substring(1);
  }

  @override
  Future<int> saveSettings({
    required String schoolId,
    required AdmissionSettings settings,
    int? baseVersion,
  }) async {
    final r = await _call('saveAdmissionSettings', {
      'schoolId': schoolId,
      'settings': settings.toWire(),
      'baseVersion': ?baseVersion,
    });
    return r['version'] is int ? r['version'] as int : 0;
  }

  @override
  Future<CreatedEnquiry> createEnquiry({
    required String schoolId,
    required String branchId,
    required EnquiryInput input,
    String? assignedTo,
  }) async {
    final r = await _call('createAdmissionEnquiry', {
      'schoolId': schoolId,
      'branchId': branchId,
      'enquiry': input.toWire(),
      'assignedTo': ?assignedTo,
    });
    return CreatedEnquiry(
      id: r['id'] as String? ?? '',
      enquiryNumber: r['enquiryNumber'] as String? ?? '',
      duplicateOf: [
        for (final x in (r['duplicateOf'] as List? ?? const []))
          if (x is String) x,
      ],
    );
  }

  @override
  Future<int> updateEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required EnquiryInput input,
    int? baseRevision,
  }) async {
    final r = await _call('updateAdmissionEnquiry', {
      'schoolId': schoolId,
      'branchId': branchId,
      'enquiryId': enquiryId,
      'enquiry': input.toWire(),
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
  }

  @override
  Future<int> assignEnquiry({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String? assignedTo,
  }) async {
    final r = await _call('assignAdmissionEnquiry', {
      'schoolId': schoolId,
      'branchId': branchId,
      'enquiryId': enquiryId,
      'assignedTo': assignedTo,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('changeAdmissionEnquiryStatus', {
      'schoolId': schoolId,
      'branchId': branchId,
      'enquiryId': enquiryId,
      'status': status,
      'reason': ?reason,
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
  }

  // ---- follow-up activities (phase 4) ---------------------------------

  AdmissionActivity _activity(DocumentSnapshot<Map<String, dynamic>> d) =>
      AdmissionActivity.fromMap(
        d.id,
        d.data() ?? const {},
        completedAt: (d.data()?['completedAt'] as Timestamp?)?.toDate(),
      );

  @override
  Future<List<AdmissionActivity>> fetchActivitiesForEnquiry(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(schoolId, branchId, _activities)
          .where('enquiryId', isEqualTo: enquiryId)
          .orderBy('scheduledDate', descending: true)
          .limit(100)
          .get();
      final all = [for (final d in snap.docs) _activity(d)];
      final open = all.where((a) => a.isOpen).toList()
        ..sort((a, b) {
          final c = a.scheduledDate.compareTo(b.scheduledDate);
          return c != 0
              ? c
              : (a.scheduledTime ?? '').compareTo(b.scheduledTime ?? '');
        });
      return [...open, ...all.where((a) => !a.isOpen)];
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  Query<Map<String, dynamic>> _bucketQuery(
    CollectionReference<Map<String, dynamic>> col,
    FollowUpBucket bucket,
    String todayKey,
    String userId,
  ) {
    final open = col.where('status', isEqualTo: ActivityStatus.scheduled.wire);
    return switch (bucket) {
      FollowUpBucket.today => open.where('scheduledDate', isEqualTo: todayKey),
      FollowUpBucket.overdue =>
        open
            .where('scheduledDate', isLessThan: todayKey)
            .orderBy('scheduledDate'),
      FollowUpBucket.upcoming =>
        open
            .where('scheduledDate', isGreaterThan: todayKey)
            .orderBy('scheduledDate'),
      FollowUpBucket.visits =>
        open
            .where('type', isEqualTo: ActivityType.schoolVisit.wire)
            .where('scheduledDate', isGreaterThanOrEqualTo: todayKey)
            .orderBy('scheduledDate'),
      FollowUpBucket.mine =>
        open.where('assignedTo', isEqualTo: userId).orderBy('scheduledDate'),
      FollowUpBucket.unassigned =>
        open.where('assignedTo', isNull: true).orderBy('scheduledDate'),
      FollowUpBucket.completed =>
        col
            .where('status', isEqualTo: ActivityStatus.completed.wire)
            .orderBy('completedAt', descending: true),
    };
  }

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
    try {
      var q = _bucketQuery(
        _col(schoolId, branchId, _activities),
        bucket,
        todayKey,
        userId,
      ).limit(pageSize);
      if (cursor != null) {
        q = q.startAfterDocument(
          cursor as DocumentSnapshot<Map<String, dynamic>>,
        );
      }
      final snap = await q.get();
      return PagedResult(
        items: [for (final d in snap.docs) _activity(d)],
        nextCursor: snap.docs.length < pageSize ? null : snap.docs.last,
      );
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  static final _openStatuses = [
    for (final s in AdmissionStatus.values)
      if (s.isOpen) s.wire,
  ];

  @override
  Future<FollowUpCounts> countFollowUps({
    required String schoolId,
    required String branchId,
    required String todayKey,
    required String userId,
  }) async {
    try {
      final col = _col(schoolId, branchId, _activities);
      Future<int> n(Query<Map<String, dynamic>> q) =>
          q.count().get().then((r) => r.count ?? 0);
      final results = await Future.wait([
        for (final b in FollowUpBucket.values)
          n(_bucketQuery(col, b, todayKey, userId)),
        n(
          _col(schoolId, branchId, _enquiries)
              .where('status', whereIn: _openStatuses)
              .where('nextFollowUpDate', isNull: true),
        ),
      ]);
      return FollowUpCounts(
        today: results[FollowUpBucket.today.index],
        overdue: results[FollowUpBucket.overdue.index],
        upcoming: results[FollowUpBucket.upcoming.index],
        visits: results[FollowUpBucket.visits.index],
        mine: results[FollowUpBucket.mine.index],
        unassigned: results[FollowUpBucket.unassigned.index],
        completed: results[FollowUpBucket.completed.index],
        withoutFollowUp: results.last,
      );
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<PagedResult<AdmissionEnquiry>> fetchWithoutFollowUp({
    required String schoolId,
    required String branchId,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      var q = _col(schoolId, branchId, _enquiries)
          .where('status', whereIn: _openStatuses)
          .where('nextFollowUpDate', isNull: true)
          .limit(pageSize);
      if (cursor != null) {
        q = q.startAfterDocument(
          cursor as DocumentSnapshot<Map<String, dynamic>>,
        );
      }
      final snap = await q.get();
      return PagedResult(
        items: [for (final d in snap.docs) _enquiry(d)],
        nextCursor: snap.docs.length < pageSize ? null : snap.docs.last,
      );
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  Map<String, dynamic> _target(
    String schoolId,
    String branchId,
    String enquiryId,
  ) => {'schoolId': schoolId, 'branchId': branchId, 'enquiryId': enquiryId};

  @override
  Future<String> scheduleActivity({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async {
    final r = await _call('scheduleAdmissionActivity', {
      ..._target(schoolId, branchId, enquiryId),
      'activity': input.toWire(),
      'requestId': requestId,
    });
    return r['id'] as String? ?? '';
  }

  @override
  Future<String> scheduleVisit({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ActivityInput input,
    required String requestId,
  }) async {
    final r = await _call('scheduleAdmissionVisit', {
      ..._target(schoolId, branchId, enquiryId),
      'visit': input.toWire(),
      'requestId': requestId,
    });
    return r['id'] as String? ?? '';
  }

  @override
  Future<List<ActivityHistoryEntry>> fetchActivityHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(schoolId, branchId, _activityHistory)
          .where('enquiryId', isEqualTo: enquiryId)
          .orderBy('at', descending: true)
          .limit(100)
          .get();
      return [
        for (final d in snap.docs)
          ActivityHistoryEntry.fromMap(
            d.data(),
            at: (d.data()['at'] as Timestamp?)?.toDate(),
          ),
      ];
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
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
    final r = await _call('rescheduleAdmissionActivity', {
      ..._target(schoolId, branchId, enquiryId),
      'activityId': activityId,
      'scheduledDate': scheduledDate,
      'scheduledTime': scheduledTime,
      'reason': ?reason,
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('reassignAdmissionActivity', {
      ..._target(schoolId, branchId, enquiryId),
      'activityId': activityId,
      'assignedTo': assignedTo,
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('cancelAdmissionActivity', {
      ..._target(schoolId, branchId, enquiryId),
      'activityId': activityId,
      'reason': reason,
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('completeAdmissionActivity', {
      ..._target(schoolId, branchId, enquiryId),
      'activityId': activityId,
      'completion': completion.toWire(),
      'next': ?next?.toWire(),
      'baseRevision': ?baseRevision,
    });
    return r['nextId'] as String?;
  }

  // ---- applications and documents (phase 6) ---------------------------

  AdmissionApplication _application(DocumentSnapshot<Map<String, dynamic>> d) =>
      AdmissionApplication.fromMap(
        d.id,
        d.data() ?? const {},
        submittedAt: (d.data()?['submittedAt'] as Timestamp?)?.toDate(),
        decidedAt: (d.data()?['decidedAt'] as Timestamp?)?.toDate(),
      );

  @override
  Stream<AdmissionApplication?> watchApplication(
    String schoolId,
    String branchId,
    String enquiryId,
  ) => _col(
    schoolId,
    branchId,
    _applications,
  ).doc(enquiryId).snapshots().map((d) => d.exists ? _application(d) : null);

  @override
  Future<PagedResult<AdmissionApplication>> fetchApplications({
    required String schoolId,
    required String branchId,
    ApplicationStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _col(schoolId, branchId, _applications);
      if (status != null) q = q.where('status', isEqualTo: status.wire);
      q = q.orderBy('createdAt', descending: true).limit(pageSize);
      if (cursor != null) {
        q = q.startAfterDocument(
          cursor as DocumentSnapshot<Map<String, dynamic>>,
        );
      }
      final snap = await q.get();
      return PagedResult(
        items: [for (final d in snap.docs) _application(d)],
        nextCursor: snap.docs.length < pageSize ? null : snap.docs.last,
      );
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<List<ApplicationEvent>> fetchApplicationHistory(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(schoolId, branchId, _applicationHistory)
          .where('enquiryId', isEqualTo: enquiryId)
          .orderBy('at', descending: true)
          .limit(100)
          .get();
      return [
        for (final d in snap.docs)
          ApplicationEvent.fromMap(
            d.data(),
            at: (d.data()['at'] as Timestamp?)?.toDate(),
          ),
      ];
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<List<AdmissionDocument>> fetchDocuments(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(
        schoolId,
        branchId,
        _documents,
      ).where('applicationId', isEqualTo: enquiryId).limit(100).get();
      final docs = [
        for (final d in snap.docs)
          AdmissionDocument.fromMap(
            d.id,
            d.data(),
            uploadedAt: (d.data()['uploadedAt'] as Timestamp?)?.toDate(),
            verifiedAt: (d.data()['verifiedAt'] as Timestamp?)?.toDate(),
          ),
      ];
      docs.sort(
        (a, b) => (b.uploadedAt ?? DateTime.now()).compareTo(
          a.uploadedAt ?? DateTime.now(),
        ),
      );
      return docs;
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<Map<ApplicationStatus, int>> countApplications(
    String schoolId,
    String branchId,
  ) async {
    try {
      final col = _col(schoolId, branchId, _applications);
      final entries = await Future.wait([
        for (final s in ApplicationStatus.values)
          col
              .where('status', isEqualTo: s.wire)
              .count()
              .get()
              .then((r) => MapEntry(s, r.count ?? 0)),
      ]);
      return Map.fromEntries(entries);
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<String> createApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
  }) async {
    final r = await _call(
      'createAdmissionApplication',
      _target(schoolId, branchId, enquiryId),
    );
    return r['applicationNumber'] as String? ?? '';
  }

  @override
  Future<int> updateApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ApplicationInput input,
    int? baseRevision,
  }) async {
    final r = await _call('updateAdmissionApplication', {
      ..._target(schoolId, branchId, enquiryId),
      'application': input.toWire(),
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
  }

  @override
  Future<int> submitApplication({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    int? baseRevision,
  }) async {
    final r = await _call('submitAdmissionApplication', {
      ..._target(schoolId, branchId, enquiryId),
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('reviewAdmissionApplication', {
      ..._target(schoolId, branchId, enquiryId),
      'action': action,
      'comment': ?comment,
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('decideAdmissionApplication', {
      ..._target(schoolId, branchId, enquiryId),
      'decision': decision,
      'comment': ?comment,
      'baseRevision': ?baseRevision,
    });
    return r['revision'] is int ? r['revision'] as int : 0;
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
    final r = await _call('requestAdmissionDocumentUpload', {
      ..._target(schoolId, branchId, enquiryId),
      'document': {
        'type': type,
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
      },
      'requestId': requestId,
    });
    return DocumentUploadIntent(
      id: r['id'] as String? ?? '',
      storagePath: r['storagePath'] as String? ?? '',
    );
  }

  @override
  Future<void> confirmDocumentUpload({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
  }) async {
    await _call('confirmAdmissionDocumentUpload', {
      ..._target(schoolId, branchId, enquiryId),
      'documentId': documentId,
    });
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
    await _call('verifyAdmissionDocument', {
      ..._target(schoolId, branchId, enquiryId),
      'documentId': documentId,
      'decision': decision,
      'reason': ?reason,
      'baseRevision': ?baseRevision,
    });
  }

  @override
  Future<void> removeDocument({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required String documentId,
    String? reason,
  }) async {
    await _call('removeAdmissionDocument', {
      ..._target(schoolId, branchId, enquiryId),
      'documentId': documentId,
      'reason': ?reason,
    });
  }
  // ---- admission fees (phase 7) ---------------------------------------

  @override
  Future<List<AdmissionFee>> fetchFees(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(
        schoolId,
        branchId,
        _fees,
      ).where('enquiryId', isEqualTo: enquiryId).limit(20).get();
      final fees = [
        for (final d in snap.docs) AdmissionFee.fromMap(d.id, d.data()),
      ];
      fees.sort((a, b) => a.category.index.compareTo(b.category.index));
      return fees;
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<List<AdmissionFeePayment>> fetchFeePayments(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(schoolId, branchId, _feePayments)
          .where('enquiryId', isEqualTo: enquiryId)
          .orderBy('recordedAt', descending: true)
          .limit(100)
          .get();
      return [
        for (final d in snap.docs)
          AdmissionFeePayment.fromMap(
            d.id,
            d.data(),
            recordedAt: (d.data()['recordedAt'] as Timestamp?)?.toDate(),
          ),
      ];
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

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
    await _call('setAdmissionFee', {
      ..._target(schoolId, branchId, enquiryId),
      'category': category.wire,
      'amountMinor': amountMinor,
      'feeStructureId': ?feeStructureId,
      'dueDate': ?dueDate,
      'note': ?note,
      'baseRevision': ?baseRevision,
    });
  }

  @override
  Future<void> cancelFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String reason,
  }) async {
    await _call('cancelAdmissionFee', {
      ..._target(schoolId, branchId, enquiryId),
      'category': category.wire,
      'reason': reason,
    });
  }

  @override
  Future<void> waiveFee({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required FeeCategory category,
    required String reason,
  }) async {
    await _call('waiveAdmissionFee', {
      ..._target(schoolId, branchId, enquiryId),
      'category': category.wire,
      'reason': reason,
    });
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
    final r = await _call('recordAdmissionFeePayment', {
      ..._target(schoolId, branchId, enquiryId),
      'category': category.wire,
      'requestId': requestId,
      'amountMinor': amountMinor,
      'method': method.wire,
      'referenceNo': ?referenceNo,
      'paymentDate': ?paymentDate,
      'notes': ?notes,
    });
    return r['receiptNumber'] as String? ?? '';
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
    await _call('refundAdmissionFee', {
      ..._target(schoolId, branchId, enquiryId),
      'category': category.wire,
      'requestId': requestId,
      'amountMinor': amountMinor,
      'method': method.wire,
      'reason': reason,
      'referenceNo': ?referenceNo,
    });
  }
  // ---- conversion to a student (phase 8) ------------------------------

  @override
  Future<AdmissionConversion?> fetchConversion(
    String schoolId,
    String branchId,
    String enquiryId,
  ) async {
    try {
      final snap = await _col(
        schoolId,
        branchId,
        _conversions,
      ).doc(enquiryId).get();
      final d = snap.data();
      if (d == null) return null;
      return AdmissionConversion.fromMap(
        d,
        convertedAt: (d['convertedAt'] as Timestamp?)?.toDate(),
      );
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<ConversionResult> convertToStudent({
    required String schoolId,
    required String branchId,
    required String enquiryId,
    required ConversionInput input,
  }) async {
    final r = await _call('convertAdmissionToStudent', {
      ..._target(schoolId, branchId, enquiryId),
      'conversion': input.toWire(),
    });
    return ConversionResult(
      studentId: r['studentId'] as String? ?? '',
      admissionNumber: r['admissionNumber'] as String? ?? '',
      duplicate: r['duplicate'] == true,
    );
  }
}

/// Admission documents in Firebase Storage. Uploads and reads are authorised by
/// `storage.rules`; a read uses the authenticated SDK (`getData`), so no link
/// that could be forwarded is ever created.
class FirebaseAdmissionDocumentStore implements AdmissionDocumentStore {
  final FirebaseStorage _storage;
  FirebaseAdmissionDocumentStore({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    try {
      await _storage
          .ref(path)
          .putData(
            Uint8List.fromList(bytes),
            SettableMetadata(contentType: contentType),
          )
          .timeout(const Duration(minutes: 2));
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<List<int>> read(String path) async {
    try {
      final data = await _storage
          .ref(path)
          .getData(AdmissionDocumentStore.maxRead)
          .timeout(const Duration(minutes: 2));
      if (data == null) {
        throw const NotFoundFailure('That file could not be found.');
      }
      return data;
    } catch (e, st) {
      if (e is AppFailure) rethrow;
      throw mapExceptionToFailure(e, st);
    }
  }
}
