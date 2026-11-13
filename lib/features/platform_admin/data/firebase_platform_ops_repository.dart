import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/platform_ops_models.dart';
import '../domain/platform_ops_repository.dart';
import 'firebase_platform_admin_repository.dart' show platformFailureFrom;
import 'polling_stream.dart';

/// [PlatformOpsRepository] backed by the platform callables and the Firestore
/// documents the rules open to platform admins, school admins and the public.
class FirebasePlatformOpsRepository implements PlatformOpsRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  FirebasePlatformOpsRepository(this._db, [FirebaseFunctions? functions])
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

  @override
  Future<void> setSchoolStatus({
    required String schoolId,
    required SchoolStatusChoice status,
    String? reason,
  }) async {
    await _call('setSchoolStatus', {
      'schoolId': schoolId,
      'status': status.wire,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  @override
  Future<void> refreshSchoolAccess(String schoolId) async {
    await _call('refreshSchoolAccess', {'schoolId': schoolId});
  }

  @override
  Future<({String schoolId, String adminEmail})> createSchool(
    NewSchoolInput input,
  ) async {
    final out = await _call('createSchoolWithAdmin', input.toCallable());
    return (
      schoolId: out['schoolId'] as String,
      adminEmail: out['adminEmail'] as String,
    );
  }

  @override
  Future<String> addSchoolAdmin({
    required String schoolId,
    required String name,
    required String email,
  }) async {
    final out = await _call('addSchoolAdmin', {
      'schoolId': schoolId,
      'name': name.trim(),
      'email': email.trim(),
    });
    return out['adminEmail'] as String;
  }

  @override
  Future<String> resetSchoolAdminAccess({
    required String schoolId,
    required String uid,
  }) async {
    final out = await _call('resetSchoolAdminAccess', {
      'schoolId': schoolId,
      'uid': uid,
    });
    return out['email'] as String;
  }

  @override
  Future<void> setFeatures({
    required String schoolId,
    required Map<String, bool> features,
  }) async {
    await _call('setSchoolFeatures', {
      'schoolId': schoolId,
      'features': features,
    });
  }

  @override
  Future<void> requestOffboarding({
    required String schoolId,
    required String reason,
  }) async {
    await _call('requestSchoolOffboarding', {
      'schoolId': schoolId,
      'reason': reason.trim(),
    });
  }

  @override
  Future<void> approveOffboarding(String schoolId) async {
    await _call('approveSchoolOffboarding', {'schoolId': schoolId});
  }

  @override
  Future<void> cancelOffboarding(String schoolId) async {
    await _call('cancelSchoolOffboarding', {'schoolId': schoolId});
  }

  @override
  Future<BillingSummary> billing({String? schoolId}) async =>
      BillingSummary.fromMap(
        await _call('listBillingRecords', {'schoolId': ?schoolId}),
      );

  @override
  Future<void> saveBillingRecord({
    required String schoolId,
    required String period,
    required int amountMinor,
    required String currency,
    required String dueDate,
    String? reference,
    String? note,
  }) async {
    await _call('saveBillingRecord', {
      'schoolId': schoolId,
      'period': period.trim(),
      'amountMinor': amountMinor,
      'currency': currency,
      'dueDate': dueDate,
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  @override
  Future<void> setBillingStatus({
    required String id,
    required String status,
    String? paidDate,
    String? note,
  }) async {
    await _call('setBillingStatus', {
      'id': id,
      'status': status,
      'paidDate': ?paidDate,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  @override
  Stream<PlatformStats?> watchStats() => pollingStream(() async {
    final out = await _call('getPlatformStats', const {});
    final stats = out['stats'];
    return stats is Map
        ? PlatformStats.fromMap(Map<String, dynamic>.from(stats))
        : null;
  }, const Duration(minutes: 5));

  @override
  Future<bool> refreshStats() async {
    final out = await _call('refreshPlatformStats', const {});
    return out['throttled'] != true;
  }

  @override
  Future<List<PlatformNotice>> notices() async {
    final out = await _call('listPlatformNotices', const {});
    return [
      for (final n in (out['notices'] as List? ?? const []))
        PlatformNotice.fromMap(Map<String, dynamic>.from(n as Map)),
    ];
  }

  @override
  Future<void> publishNotice({
    required String title,
    required String body,
    required NoticeSeverity severity,
    required bool audienceAll,
    List<String> schoolIds = const [],
    DateTime? startsAt,
    required DateTime endsAt,
  }) async {
    await _call('publishPlatformNotice', {
      'title': title.trim(),
      'body': body.trim(),
      'severity': severity.wire,
      'audienceAll': audienceAll,
      if (!audienceAll) 'schoolIds': schoolIds,
      if (startsAt != null) 'startsAtMs': startsAt.millisecondsSinceEpoch,
      'endsAtMs': endsAt.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> withdrawNotice(String id) async {
    await _call('withdrawPlatformNotice', {'id': id});
  }

  DateTime? _ts(Object? v) => v is Timestamp ? v.toDate() : null;

  @override
  Stream<List<SchoolNotice>> watchSchoolNotices(String schoolId) =>
      pollingStream(() async {
        final out = await _call('listMyNotices', const {});
        DateTime? at(Object? ms) =>
            ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
        return [
          for (final n in (out['notices'] as List? ?? const []))
            () {
              final m = Map<String, dynamic>.from(n as Map);
              return SchoolNotice(
                id: m['id'] as String,
                title: (m['title'] as String?) ?? '',
                body: (m['body'] as String?) ?? '',
                severity: NoticeSeverity.parse(m['severity']),
                startsAt: at(m['startsAtMs']),
                endsAt: at(m['endsAtMs']),
                withdrawn: m['withdrawn'] == true,
              );
            }(),
        ];
      }, const Duration(minutes: 5));

  @override
  Stream<AppRequirements> watchAppRequirements() =>
      _db.collection('platformSettings').doc('app').snapshots().map((s) {
        final raw = s.data();
        if (raw == null) return AppRequirements.none;
        final m = Map<String, dynamic>.from(
          (raw['maintenance'] as Map?) ?? const {},
        );
        return AppRequirements.fromMap({
          ...raw,
          'maintenance': {...m, 'until': _ts(m['until'])},
        });
      });

  @override
  Future<void> setAppRequirements({
    required int minBuildAndroid,
    required int minBuildIos,
    required bool maintenanceOn,
    String? message,
    DateTime? until,
  }) async {
    await _call('setAppRequirements', {
      'minBuild': {'android': minBuildAndroid, 'ios': minBuildIos},
      'maintenance': {
        'enabled': maintenanceOn,
        'message': message?.trim() ?? '',
        if (until != null) 'untilMs': until.millisecondsSinceEpoch,
      },
    });
  }
}

/// Emits a combined value whenever either stream emits, once both have. Closes
/// the sources when the listener cancels.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? sa;
  StreamSubscription<B>? sb;
  A? lastA;
  B? lastB;
  var haveA = false;
  var haveB = false;
  void emit() {
    if (haveA && haveB) controller.add(combine(lastA as A, lastB as B));
  }

  controller = StreamController<R>(
    onListen: () {
      sa = a.listen((v) {
        lastA = v;
        haveA = true;
        emit();
      }, onError: controller.addError);
      sb = b.listen((v) {
        lastB = v;
        haveB = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return controller.stream;
}
