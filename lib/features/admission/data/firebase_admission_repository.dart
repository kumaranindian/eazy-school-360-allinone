import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../../students/domain/paged_result.dart';
import '../domain/admission_enquiry.dart';
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
}
