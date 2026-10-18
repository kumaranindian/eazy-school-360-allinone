import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_logger.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/school_setup/domain/branch_status.dart';
import '../../features/school_setup/presentation/providers/school_providers.dart';
import '../../features/users/domain/user_profile.dart';
import '../../features/users/domain/user_status.dart';
import '../../features/users/presentation/providers/user_providers.dart';
import 'account_inactive_exception.dart';
import 'tenant_context.dart';

/// Assembles [TenantContext] from the signed-in user's profile + school +
/// branch. This is the single place that does so — nothing else should
/// read `/users/{uid}`, resolve a role, or decide "does this account have
/// a school yet" on its own.
///
/// Resolves to:
/// - `null` while signed out, or while signed in but no `/users/{uid}`
///   profile exists yet (a brand-new account that still needs to create
///   or join a school — the router sends this case to `/create-school`).
/// - a populated [TenantContext] once a profile (and, if scoped, a
///   school/branch) is loaded.
/// - an [AsyncError] wrapping [AccountInactiveException] if the profile's
///   status is anything but active (invited or disabled) — the router
///   redirects this to `/account-inactive`, where the user can sign out.
class TenantContextNotifier extends AsyncNotifier<TenantContext?> {
  int _switchRequest = 0;

  @override
  Future<TenantContext?> build() async {
    final authState = await ref.watch(authStateChangesProvider.future);
    if (authState == null) {
      AppLogger.debug('Signed out; no tenant context.', tag: 'Tenant');
      return null;
    }
    AppLogger.debug('Resolving tenant for uid=${authState.uid}', tag: 'Tenant');

    final UserProfile? profile;
    try {
      profile = await ref
          .watch(userRepositoryProvider)
          .getUserProfile(authState.uid);
    } on InvalidProfileException catch (e) {
      AppLogger.error(
        'Profile for uid=${authState.uid} is unusable ($e); refusing access.',
        tag: 'Tenant',
      );
      throw AccountInactiveException(
        UserStatus.disabled,
        cause: InactiveCause.invalidProfile,
      );
    }
    if (profile == null) {
      AppLogger.debug(
        'No /users/${authState.uid} profile; routing to create-school.',
        tag: 'Tenant',
      );
      return null;
    }

    final login0 = profile.login;
    AppLogger.trace(
      'profile uid=${authState.uid} role=${profile.role.wireValue} '
      'status=${profile.status.name} school=${profile.schoolId} '
      'branch=${profile.branchId} linkedParentId=${profile.linkedParentId} '
      'login=${login0 == null ? 'none (legacy)' : 'enabled=${login0.enabled} effective=${login0.effective.map((m) => m.wireValue).toList()} mustChangePassword=${login0.mustChangePassword}'}',
      tag: 'Tenant',
    );
    if (profile.status != UserStatus.active) {
      AppLogger.trace(
        'blocked: profile status is ${profile.status.name}, not active',
        tag: 'Tenant',
      );
      throw AccountInactiveException(profile.status);
    }

    // Login access is switched off by an administrator, or this session
    // used a method the account is not permitted. Legacy profiles (no
    // `login` map) are unaffected. firestore.rules enforces the same.
    final login = profile.login;
    if (login != null) {
      if (!login.enabled) {
        AppLogger.trace(
          'blocked: login access is switched off for this user',
          tag: 'Tenant',
        );
        throw AccountInactiveException(
          profile.status,
          cause: InactiveCause.loginDisabled,
        );
      }
      final method = await ref
          .read(authRepositoryProvider)
          .currentSignInMethod();
      AppLogger.trace(
        'sign-in method used=${method?.wireValue} '
        'permitted=${login.effective.map((m) => m.wireValue).toList()}',
        tag: 'Tenant',
      );
      if (!login.allows(method)) {
        AppLogger.trace(
          'blocked: this sign-in method is not permitted for the user',
          tag: 'Tenant',
        );
        throw AccountInactiveException(
          profile.status,
          cause: InactiveCause.methodNotPermitted,
          permitted: login.effective,
        );
      }
    }

    final schoolRepository = ref.watch(schoolRepositoryProvider);
    final school = profile.schoolId == null
        ? null
        : await schoolRepository.getSchool(profile.schoolId!);
    var acting = profile;
    var branch = (profile.schoolId == null || profile.branchId == null)
        ? null
        : await schoolRepository.getBranch(
            profile.schoolId!,
            profile.branchId!,
          );
    // A school admin with no home branch still needs a branch to work in:
    // start in the first one (they can switch from the header).
    if (branch == null && profile.actsInAnyBranch) {
      final all = await schoolRepository.watchBranches(profile.schoolId!).first;
      if (all.isNotEmpty) {
        branch = all.firstWhere(
          (b) => b.status == BranchStatus.active,
          orElse: () => all.first,
        );
        acting = profile.activeIn(branch.branchId);
      }
    }

    AppLogger.debug(
      'Tenant resolved: role/status=${profile.status.name} '
      'school=${profile.schoolId} branch=${profile.branchId}',
      tag: 'Tenant',
    );
    return TenantContext(user: acting, school: school, branch: branch);
  }

  /// Acts in [branchId] (one of the user's `workingBranchIds`, or any branch of
  /// the school for a school admin). The whole app reads role and branch from
  /// [TenantContext], so every screen follows. Any other branch is ignored.
  Future<void> switchBranch(String branchId) async {
    final current = state.value;
    if (current == null) return;
    final user = current.user;
    if (!user.workingBranchIds.contains(branchId) && !user.actsInAnyBranch) {
      return;
    }
    if (current.branch?.branchId == branchId) return;
    final schoolId = user.schoolId;
    if (schoolId == null) return;
    // The branch lookup is asynchronous. Whatever happened meanwhile (the user
    // signed out or another account signed in, the profile reloaded, a newer
    // switch was requested) wins over this late answer (STATE-6).
    final request = ++_switchRequest;
    final branch = await ref
        .read(schoolRepositoryProvider)
        .getBranch(schoolId, branchId);
    if (branch == null) return;
    if (request != _switchRequest || !identical(state.value, current)) return;
    state = AsyncData(
      TenantContext(
        user: user.activeIn(branchId),
        school: current.school,
        branch: branch,
      ),
    );
  }
}

final tenantContextProvider =
    AsyncNotifierProvider<TenantContextNotifier, TenantContext?>(
      TenantContextNotifier.new,
    );
