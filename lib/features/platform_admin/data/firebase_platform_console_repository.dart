import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/audit_entry.dart';
import '../domain/deletion_review.dart';
import '../domain/platform_console_repository.dart';
import '../domain/platform_school.dart';
import '../domain/school_overview.dart';
import '../domain/support_grant.dart';
import 'firebase_platform_admin_repository.dart' show platformFailureFrom;

/// [PlatformConsoleRepository] backed by Firestore (read paths the rules allow
/// platform admins and school admins) and the platform callables.
class FirebasePlatformConsoleRepository implements PlatformConsoleRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  FirebasePlatformConsoleRepository(this._db, [FirebaseFunctions? functions])
    : _functions = functions ?? appFunctions();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return Map<String, dynamic>.from(r.data as Map);
    } on FirebaseFunctionsException catch (e, st) {
      throw platformFailureFrom(e, st);
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  Future<T> _read<T>(Future<T> Function() read) async {
    try {
      return await read();
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

  @override
  Future<List<PlatformSchool>> listSchools() => _read(() async {
    // Metadata only: the rules let a platform admin read any school document.
    final snap = await _db
        .collection('schools')
        .orderBy('name')
        .limit(500)
        .get();
    return [
      for (final d in snap.docs)
        PlatformSchool(
          id: d.id,
          name: (d.data()['name'] as String?) ?? '',
          code: (d.data()['code'] as String?) ?? '',
          status: (d.data()['status'] as String?) ?? '',
          city: (d.data()['city'] as String?) ?? '',
          country: (d.data()['country'] as String?) ?? '',
          createdAt: _ts(d.data()['createdAt']),
        ),
    ];
  });

  @override
  Future<SchoolOverview> schoolOverview(String schoolId) async =>
      SchoolOverview.fromMap(
        await _call('getSchoolOverview', {'schoolId': schoolId}),
      );

  @override
  Future<DateTime> requestSupportAccess({
    required String schoolId,
    required String reason,
    String? ticket,
    required int minutes,
  }) async {
    final out = await _call('requestSupportAccess', {
      'schoolId': schoolId,
      'reason': reason.trim(),
      if (ticket != null && ticket.trim().isNotEmpty) 'ticket': ticket.trim(),
      'minutes': minutes,
    });
    return DateTime.fromMillisecondsSinceEpoch(
      (out['expiresAtMs'] as num).toInt(),
    );
  }

  @override
  Future<void> revokeSupportAccess({
    required String schoolId,
    String? adminUid,
  }) async {
    await _call('revokeSupportAccess', {
      'schoolId': schoolId,
      'adminUid': ?adminUid,
    });
  }

  @override
  Stream<List<SupportGrant>> watchMyGrants(String uid) => _db
      .collection('supportGrants')
      .where('adminUid', isEqualTo: uid)
      .snapshots()
      .map((s) => [for (final d in s.docs) SupportGrant.fromMap(d.data())]);

  @override
  Stream<List<SupportGrant>> watchSchoolGrants(String schoolId) => _db
      .collection('supportGrants')
      .where('schoolId', isEqualTo: schoolId)
      .snapshots()
      .map((s) => [for (final d in s.docs) SupportGrant.fromMap(d.data())]);

  @override
  Stream<List<SupportAccessLogEntry>> watchSupportAccessLog(String schoolId) =>
      _db
          .collection('schools')
          .doc(schoolId)
          .collection('supportAccessLog')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (s) => [
              for (final d in s.docs) SupportAccessLogEntry.fromMap(d.data()),
            ],
          );

  @override
  Future<List<AuditEntry>> recentAudit() => _read(() async {
    final snap = await _db
        .collection('platformAuditLog')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    return [
      for (final d in snap.docs)
        AuditEntry(
          id: d.id,
          action: (d.data()['action'] as String?) ?? '',
          actorEmail: (d.data()['actorEmail'] as String?) ?? '',
          actorRole: (d.data()['actorPlatformRole'] as String?) ?? '',
          targetEmail: (d.data()['targetEmail'] as String?) ?? '',
          schoolId: (d.data()['schoolId'] as String?) ?? '',
          reason: (d.data()['reason'] as String?) ?? '',
          result: (d.data()['result'] as String?) ?? '',
          source: (d.data()['source'] as String?) ?? '',
          at: _ts(d.data()['createdAt']),
        ),
    ];
  });

  @override
  Future<List<DeletionReviewItem>> deletionRequests({
    required bool closed,
  }) async {
    final out = await _call('listAccountDeletionRequests', {
      'scope': closed ? 'closed' : 'open',
    });
    return [
      for (final r in (out['requests'] as List? ?? const []))
        DeletionReviewItem.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  @override
  Future<void> reviewDeletion({
    required String reference,
    required DeletionDecision decision,
    String? reasonCode,
  }) async {
    await _call('reviewAccountDeletion', {
      'reference': reference,
      'decision': decision.wire,
      'reasonCode': ?reasonCode,
    });
  }
}
