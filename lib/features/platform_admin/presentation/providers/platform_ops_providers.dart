import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_platform_ops_repository.dart';
import '../../domain/platform_ops_models.dart';
import '../../domain/platform_ops_repository.dart';
import 'platform_console_providers.dart';

final platformOpsRepositoryProvider = Provider<PlatformOpsRepository>(
  (ref) => FirebasePlatformOpsRepository(ref.watch(firestoreProvider)),
  retry: (retryCount, error) => null,
);

/// The dashboard numbers (computed nightly and on demand).
final platformStatsProvider = StreamProvider.autoDispose<PlatformStats?>(
  (ref) => ref.watch(platformOpsRepositoryProvider).watchStats(),
  retry: (retryCount, error) => null,
);

/// Billing records and what is owed; null = every school.
final billingProvider = FutureProvider.autoDispose
    .family<BillingSummary, String?>(
      (ref, schoolId) =>
          ref.watch(platformOpsRepositoryProvider).billing(schoolId: schoolId),
      retry: (retryCount, error) => null,
    );

final platformNoticesProvider =
    FutureProvider.autoDispose<List<PlatformNotice>>(
      (ref) => ref.watch(platformOpsRepositoryProvider).notices(),
      retry: (retryCount, error) => null,
    );

/// What a school's administrators see from Avail404.
final schoolNoticesProvider = StreamProvider.autoDispose
    .family<List<SchoolNotice>, String>(
      (ref, schoolId) =>
          ref.watch(platformOpsRepositoryProvider).watchSchoolNotices(schoolId),
      retry: (retryCount, error) => null,
    );

/// Maintenance mode and the oldest allowed build. A read failure means "no
/// requirements" so a network blip never locks anyone out.
final appRequirementsProvider = StreamProvider<AppRequirements>((ref) async* {
  try {
    yield* ref.watch(platformOpsRepositoryProvider).watchAppRequirements();
  } catch (_) {
    yield AppRequirements.none;
  }
}, retry: (retryCount, error) => null);

/// Platform lifecycle, billing and operations actions. Not auto-dispose: an
/// action finishes (and refreshes the lists) even after its screen has closed.
class PlatformOpsActions extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    T? result;
    state = await AsyncValue.guard(() async => result = await action());
    return state.hasError ? null : result;
  }

  PlatformOpsRepository get _repo => ref.read(platformOpsRepositoryProvider);

  void _refreshSchool(String schoolId) {
    ref.invalidate(schoolOverviewProvider(schoolId));
    ref.invalidate(platformSchoolsProvider);
  }

  /// Sends the "choose your password" email. Never throws: the account exists
  /// either way and the email can be resent.
  Future<bool> _email(String address) async {
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetEmail(address);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setStatus(
    String schoolId,
    SchoolStatusChoice status, {
    String? reason,
  }) async {
    final ok = await _run(() async {
      await _repo.setSchoolStatus(
        schoolId: schoolId,
        status: status,
        reason: reason,
      );
      return true;
    });
    if (ok == true) _refreshSchool(schoolId);
    return ok ?? false;
  }

  Future<bool> refreshAccess(String schoolId) async =>
      await _run(() async {
        await _repo.refreshSchoolAccess(schoolId);
        return true;
      }) ??
      false;

  /// Creates the school and emails its administrator. `emailSent` is false when
  /// the school exists but the email failed (use "Send setup email").
  Future<({String schoolId, bool emailSent})?> createSchool(
    NewSchoolInput input,
  ) async {
    final out = await _run(() async {
      final r = await _repo.createSchool(input);
      return (schoolId: r.schoolId, emailSent: await _email(r.adminEmail));
    });
    if (out != null) ref.invalidate(platformSchoolsProvider);
    return out;
  }

  Future<bool?> addAdmin({
    required String schoolId,
    required String name,
    required String email,
  }) async {
    final sent = await _run(() async {
      final used = await _repo.addSchoolAdmin(
        schoolId: schoolId,
        name: name,
        email: email,
      );
      return _email(used);
    });
    if (sent != null) _refreshSchool(schoolId);
    return sent;
  }

  Future<bool?> resetAdmin({required String schoolId, required String uid}) =>
      _run(() async {
        final email = await _repo.resetSchoolAdminAccess(
          schoolId: schoolId,
          uid: uid,
        );
        return _email(email);
      });

  Future<bool> setFeatures(String schoolId, Map<String, bool> features) async {
    final ok = await _run(() async {
      await _repo.setFeatures(schoolId: schoolId, features: features);
      return true;
    });
    if (ok == true) _refreshSchool(schoolId);
    return ok ?? false;
  }

  Future<bool> offboarding(
    String schoolId,
    String step, {
    String? reason,
  }) async {
    final ok = await _run(() async {
      switch (step) {
        case 'request':
          await _repo.requestOffboarding(
            schoolId: schoolId,
            reason: reason ?? '',
          );
        case 'approve':
          await _repo.approveOffboarding(schoolId);
        case 'cancel':
          await _repo.cancelOffboarding(schoolId);
      }
      return true;
    });
    if (ok == true) _refreshSchool(schoolId);
    return ok ?? false;
  }

  Future<bool> saveBilling({
    required String schoolId,
    required String period,
    required int amountMinor,
    required String currency,
    required String dueDate,
    String? reference,
    String? note,
  }) async {
    final ok = await _run(() async {
      await _repo.saveBillingRecord(
        schoolId: schoolId,
        period: period,
        amountMinor: amountMinor,
        currency: currency,
        dueDate: dueDate,
        reference: reference,
        note: note,
      );
      return true;
    });
    if (ok == true) ref.invalidate(billingProvider);
    return ok ?? false;
  }

  Future<bool> setBilling(
    String id,
    String status, {
    String? paidDate,
    String? note,
  }) async {
    final ok = await _run(() async {
      await _repo.setBillingStatus(
        id: id,
        status: status,
        paidDate: paidDate,
        note: note,
      );
      return true;
    });
    if (ok == true) ref.invalidate(billingProvider);
    return ok ?? false;
  }

  /// Recomputes the dashboard numbers; null on failure, false when throttled.
  Future<bool?> refreshStats() => _run(() => _repo.refreshStats());

  Future<bool> publishNotice({
    required String title,
    required String body,
    required NoticeSeverity severity,
    required bool audienceAll,
    List<String> schoolIds = const [],
    DateTime? startsAt,
    required DateTime endsAt,
  }) async {
    final ok = await _run(() async {
      await _repo.publishNotice(
        title: title,
        body: body,
        severity: severity,
        audienceAll: audienceAll,
        schoolIds: schoolIds,
        startsAt: startsAt,
        endsAt: endsAt,
      );
      return true;
    });
    if (ok == true) ref.invalidate(platformNoticesProvider);
    return ok ?? false;
  }

  Future<bool> withdrawNotice(String id) async {
    final ok = await _run(() async {
      await _repo.withdrawNotice(id);
      return true;
    });
    if (ok == true) ref.invalidate(platformNoticesProvider);
    return ok ?? false;
  }

  Future<bool> setAppRequirements({
    required int minBuildAndroid,
    required int minBuildIos,
    required bool maintenanceOn,
    String? message,
    DateTime? until,
  }) async =>
      await _run(() async {
        await _repo.setAppRequirements(
          minBuildAndroid: minBuildAndroid,
          minBuildIos: minBuildIos,
          maintenanceOn: maintenanceOn,
          message: message,
          until: until,
        );
        return true;
      }) ??
      false;
}

final platformOpsActionsProvider =
    AsyncNotifierProvider<PlatformOpsActions, void>(PlatformOpsActions.new);
