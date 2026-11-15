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
import 'polling_stream.dart';

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
          email: (d.data()['email'] as String?) ?? '',
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

  // Platform data has no client rules: it is read through callables that check
  // the caller's role and second factor, and polled lightly.
  @override
  Stream<List<SupportGrant>> watchMyGrants(String uid) =>
      pollingStream(() async {
        final out = await _call('listMySupportGrants', const {});
        return [
          for (final g in (out['grants'] as List? ?? const []))
            SupportGrant.fromCallable(Map<String, dynamic>.from(g as Map)),
        ];
      }, const Duration(seconds: 30));

  Future<Map<String, dynamic>> _schoolAccess() =>
      _call('listSchoolSupportAccess', const {});

  @override
  Stream<List<SupportGrant>> watchSchoolGrants(String schoolId) =>
      pollingStream(() async {
        final out = await _schoolAccess();
        return [
          for (final g in (out['grants'] as List? ?? const []))
            SupportGrant.fromCallable(Map<String, dynamic>.from(g as Map)),
        ];
      }, const Duration(seconds: 60));

  @override
  Stream<List<SupportAccessLogEntry>> watchSupportAccessLog(String schoolId) =>
      pollingStream(() async {
        final out = await _schoolAccess();
        return [
          for (final e in (out['log'] as List? ?? const []))
            SupportAccessLogEntry.fromCallable(
              Map<String, dynamic>.from(e as Map),
            ),
        ];
      }, const Duration(seconds: 60));

  @override
  Future<List<AuditEntry>> recentAudit() async {
    final out = await _call('listAuditLog', const {});
    DateTime? at(Object? ms) =>
        ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
    return [
      for (final e in (out['entries'] as List? ?? const []))
        () {
          final m = Map<String, dynamic>.from(e as Map);
          return AuditEntry(
            id: (m['id'] as String?) ?? '',
            action: (m['action'] as String?) ?? '',
            actorEmail: (m['actorEmail'] as String?) ?? '',
            actorRole: (m['actorPlatformRole'] as String?) ?? '',
            targetEmail: (m['targetEmail'] as String?) ?? '',
            schoolId: (m['schoolId'] as String?) ?? '',
            reason: (m['reason'] as String?) ?? '',
            result: (m['result'] as String?) ?? '',
            source: (m['source'] as String?) ?? '',
            at: at(m['atMs']),
          );
        }(),
    ];
  }

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
