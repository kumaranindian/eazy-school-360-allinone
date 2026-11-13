import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_platform_console_repository.dart';
import '../../domain/audit_entry.dart';
import '../../domain/deletion_review.dart';
import '../../domain/platform_console_repository.dart';
import '../../domain/platform_school.dart';
import '../../domain/school_overview.dart';
import '../../domain/support_grant.dart';
import 'support_session_providers.dart';

final platformConsoleRepositoryProvider = Provider<PlatformConsoleRepository>(
  (ref) => FirebasePlatformConsoleRepository(ref.watch(firestoreProvider)),
  retry: (retryCount, error) => null,
);

final platformSchoolsProvider =
    FutureProvider.autoDispose<List<PlatformSchool>>(
      (ref) => ref.watch(platformConsoleRepositoryProvider).listSchools(),
      retry: (retryCount, error) => null,
    );

final schoolOverviewProvider = FutureProvider.autoDispose
    .family<SchoolOverview, String>(
      (ref, schoolId) =>
          ref.watch(platformConsoleRepositoryProvider).schoolOverview(schoolId),
      retry: (retryCount, error) => null,
    );

/// The signed-in platform admin's own support grants (live).
final myGrantsProvider = StreamProvider.autoDispose<List<SupportGrant>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return const Stream.empty();
  return ref.watch(platformConsoleRepositoryProvider).watchMyGrants(uid);
}, retry: (retryCount, error) => null);

/// What a school's own administrators see.
final schoolGrantsProvider = StreamProvider.autoDispose
    .family<List<SupportGrant>, String>(
      (ref, schoolId) => ref
          .watch(platformConsoleRepositoryProvider)
          .watchSchoolGrants(schoolId),
      retry: (retryCount, error) => null,
    );

final supportAccessLogProvider = StreamProvider.autoDispose
    .family<List<SupportAccessLogEntry>, String>(
      (ref, schoolId) => ref
          .watch(platformConsoleRepositoryProvider)
          .watchSupportAccessLog(schoolId),
      retry: (retryCount, error) => null,
    );

final auditLogProvider = FutureProvider.autoDispose<List<AuditEntry>>(
  (ref) => ref.watch(platformConsoleRepositoryProvider).recentAudit(),
  retry: (retryCount, error) => null,
);

/// `true` = recently closed requests, `false` = open ones.
final deletionRequestsProvider = FutureProvider.autoDispose
    .family<List<DeletionReviewItem>, bool>(
      (ref, closed) => ref
          .watch(platformConsoleRepositoryProvider)
          .deletionRequests(closed: closed),
      retry: (retryCount, error) => null,
    );

/// Platform console actions: start/end a support session, revoke a grant, decide
/// a deletion request.
class PlatformConsoleActions extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    T? result;
    state = await AsyncValue.guard(() async => result = await action());
    return state.hasError ? null : result;
  }

  /// Asks for access and, once granted, opens the school (read-only).
  Future<bool> startSupportSession({
    required String schoolId,
    required String schoolName,
    required String reason,
    String? ticket,
    required int minutes,
  }) async {
    final expires = await _run(
      () => ref
          .read(platformConsoleRepositoryProvider)
          .requestSupportAccess(
            schoolId: schoolId,
            reason: reason,
            ticket: ticket,
            minutes: minutes,
          ),
    );
    if (expires == null) return false;
    ref
        .read(supportSessionProvider.notifier)
        .start(
          SupportSession(
            schoolId: schoolId,
            schoolName: schoolName,
            expiresAt: expires,
          ),
        );
    return true;
  }

  /// Opens a school again from a grant that is still active.
  void resumeSupportSession({
    required String schoolId,
    required String schoolName,
    required DateTime expiresAt,
  }) => ref
      .read(supportSessionProvider.notifier)
      .start(
        SupportSession(
          schoolId: schoolId,
          schoolName: schoolName,
          expiresAt: expiresAt,
        ),
      );

  /// Ends the session AND the grant, so nothing stays open on the server.
  Future<bool> endSupportSession() async {
    final session = ref.read(supportSessionProvider);
    if (session == null) return true;
    final ok = await _run(() async {
      await ref
          .read(platformConsoleRepositoryProvider)
          .revokeSupportAccess(schoolId: session.schoolId);
      return true;
    });
    // The person leaves the school either way: a failed revoke still ends the
    // session here, and the grant expires on its own.
    ref.read(supportSessionProvider.notifier).end();
    return ok ?? false;
  }

  /// A school administrator ends someone's access to their school.
  Future<bool> revokeGrant({
    required String schoolId,
    required String adminUid,
  }) async =>
      await _run(() async {
        await ref
            .read(platformConsoleRepositoryProvider)
            .revokeSupportAccess(schoolId: schoolId, adminUid: adminUid);
        return true;
      }) ??
      false;

  Future<bool> decideDeletion({
    required String reference,
    required DeletionDecision decision,
    String? reasonCode,
  }) async {
    final ok = await _run(() async {
      await ref
          .read(platformConsoleRepositoryProvider)
          .reviewDeletion(
            reference: reference,
            decision: decision,
            reasonCode: reasonCode,
          );
      return true;
    });
    if (ok == true) {
      ref.invalidate(deletionRequestsProvider);
    }
    return ok ?? false;
  }
}

// Not auto-dispose: an action keeps running (and ends the support session) even
// when the screen that started it has already gone.
final platformConsoleActionsProvider =
    AsyncNotifierProvider<PlatformConsoleActions, void>(
      PlatformConsoleActions.new,
    );
