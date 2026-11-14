import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_platform_ops_repository.dart';
import '../../domain/audit_trail.dart';
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

/// One school's module switch history, newest first.
final featureHistoryProvider = FutureProvider.autoDispose
    .family<List<FeatureHistoryEntry>, String>(
      (ref, schoolId) =>
          ref.watch(platformOpsRepositoryProvider).featureHistory(schoolId),
      retry: (retryCount, error) => null,
    );

/// The module switches new schools start with.
final featureDefaultsProvider = FutureProvider.autoDispose<Map<String, bool>>(
  (ref) => ref.watch(platformOpsRepositoryProvider).featureDefaults(),
  retry: (retryCount, error) => null,
);

/// Subscription plans.
final platformPlansProvider = FutureProvider.autoDispose<List<PlatformPlan>>(
  (ref) => ref.watch(platformOpsRepositoryProvider).plans(),
  retry: (retryCount, error) => null,
);

/// One school's subscription history, newest first.
final subscriptionHistoryProvider = FutureProvider.autoDispose
    .family<List<SubscriptionHistoryEntry>, String>(
      (ref, schoolId) => ref
          .watch(platformOpsRepositoryProvider)
          .subscriptionHistory(schoolId),
      retry: (retryCount, error) => null,
    );

/// The administrator's own platform notifications.
final myPlatformNotificationsProvider =
    StreamProvider.autoDispose<List<PlatformNotification>>(
      (ref) => ref.watch(platformOpsRepositoryProvider).watchMyNotifications(),
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

  /// Activate / deactivate / suspend / reactivate through the validated table.
  Future<bool> transition(
    String schoolId,
    SchoolStatusChoice to, {
    String? reason,
    String? remarks,
    String? internalNotes,
    String? message,
  }) async {
    final ok = await _run(() async {
      await _repo.transitionSchool(
        schoolId: schoolId,
        to: to,
        reason: reason,
        remarks: remarks,
        internalNotes: internalNotes,
        message: message,
      );
      return true;
    });
    if (ok == true) _refreshSchool(schoolId);
    return ok ?? false;
  }

  Future<bool> recovery(String schoolId, String step, {String? reason}) async {
    final ok = await _run(() async {
      switch (step) {
        case 'request':
          await _repo.requestRecovery(schoolId: schoolId, reason: reason ?? '');
        case 'approve':
          await _repo.approveRecovery(schoolId);
        case 'cancel':
          await _repo.cancelRecovery(schoolId);
      }
      return true;
    });
    if (ok == true) _refreshSchool(schoolId);
    return ok ?? false;
  }

  /// A subscription operation (see [PlatformOpsRepository.subscriptionOp]).
  Future<bool> subscription(
    String op,
    String schoolId, {
    String? planId,
    String? classification,
    String? startDate,
    String? endDate,
    int? gracePeriodDays,
    int? days,
    String? reason,
    String? remarks,
    String? internalNotes,
  }) async {
    final ok = await _run(() async {
      await _repo.subscriptionOp(
        op,
        schoolId: schoolId,
        planId: planId,
        classification: classification,
        startDate: startDate,
        endDate: endDate,
        gracePeriodDays: gracePeriodDays,
        days: days,
        reason: reason,
        remarks: remarks,
        internalNotes: internalNotes,
      );
      return true;
    });
    if (ok == true) {
      _refreshSchool(schoolId);
      ref.invalidate(subscriptionHistoryProvider(schoolId));
    }
    return ok ?? false;
  }

  Future<bool> savePlan({
    String? planId,
    required String name,
    required String periodType,
    bool active = true,
  }) async {
    final ok = await _run(() async {
      await _repo.savePlan(
        planId: planId,
        name: name,
        periodType: periodType,
        active: active,
      );
      return true;
    });
    if (ok == true) ref.invalidate(platformPlansProvider);
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

  Future<bool> setFeatures(
    String schoolId,
    Map<String, bool> features, {
    String? reason,
    bool confirmDependants = false,
  }) async {
    final ok = await _run(() async {
      await _repo.setFeatures(
        schoolId: schoolId,
        features: features,
        reason: reason,
        confirmDependants: confirmDependants,
      );
      return true;
    });
    if (ok == true) {
      _refreshSchool(schoolId);
      ref.invalidate(featureHistoryProvider(schoolId));
    }
    return ok ?? false;
  }

  Future<bool> setFeatureDefaults(Map<String, bool> features) async {
    final ok = await _run(() async {
      await _repo.setFeatureDefaults(features);
      return true;
    });
    if (ok == true) ref.invalidate(featureDefaultsProvider);
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
  Future<bool?> refreshStats() async {
    final fresh = await _run(() => _repo.refreshStats());
    if (fresh != null) ref.invalidate(platformStatsProvider);
    return fresh;
  }

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

/// The filter the audit trail page is showing.
class AuditFilterNotifier extends Notifier<AuditFilter> {
  @override
  AuditFilter build() => const AuditFilter();

  void set(AuditFilter f) => state = f;
}

final auditFilterProvider =
    NotifierProvider.autoDispose<AuditFilterNotifier, AuditFilter>(
      AuditFilterNotifier.new,
    );

/// Headline numbers for the last 24 hours.
final auditSummaryProvider = FutureProvider.autoDispose<AuditSummary>(
  (ref) => ref.watch(platformOpsRepositoryProvider).auditSummary(hours: 24),
  retry: (retryCount, error) => null,
);

/// Everything loaded so far for the current filter, and where the next page starts.
class AuditTrailState {
  final List<AuditEventView> events;
  final Map<String, dynamic>? nextCursor;
  final bool truncated;
  final bool loadingMore;
  final Object? moreError;

  const AuditTrailState({
    required this.events,
    this.nextCursor,
    this.truncated = false,
    this.loadingMore = false,
    this.moreError,
  });

  AuditTrailState copyWith({
    List<AuditEventView>? events,
    Object? nextCursor = _keepCursor,
    bool? truncated,
    bool? loadingMore,
    Object? moreError = _keepCursor,
  }) => AuditTrailState(
    events: events ?? this.events,
    nextCursor: identical(nextCursor, _keepCursor)
        ? this.nextCursor
        : nextCursor as Map<String, dynamic>?,
    truncated: truncated ?? this.truncated,
    loadingMore: loadingMore ?? this.loadingMore,
    moreError: identical(moreError, _keepCursor) ? this.moreError : moreError,
  );
}

const Object _keepCursor = Object();

class AuditTrailController extends AsyncNotifier<AuditTrailState> {
  @override
  Future<AuditTrailState> build() async {
    final filter = ref.watch(auditFilterProvider);
    final page = await ref
        .watch(platformOpsRepositoryProvider)
        .queryAudit(filter);
    return AuditTrailState(
      events: page.events,
      nextCursor: page.nextCursor,
      truncated: page.truncated,
    );
  }

  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || cur.nextCursor == null || cur.loadingMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true, moreError: null));
    try {
      final page = await ref
          .read(platformOpsRepositoryProvider)
          .queryAudit(ref.read(auditFilterProvider), cursor: cur.nextCursor);
      state = AsyncData(
        cur.copyWith(
          events: [...cur.events, ...page.events],
          nextCursor: page.nextCursor,
          truncated: page.truncated,
          loadingMore: false,
        ),
      );
    } catch (e) {
      state = AsyncData(cur.copyWith(loadingMore: false, moreError: e));
    }
  }
}

final auditTrailProvider =
    AsyncNotifierProvider.autoDispose<AuditTrailController, AuditTrailState>(
      AuditTrailController.new,
      retry: (retryCount, error) => null,
    );
