import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/tenant/account_inactive_exception.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);
const _branch = Branch(
  branchId: 'main',
  schoolId: 'school-1',
  name: 'Main Branch',
  status: BranchStatus.active,
);

/// Reads [tenantContextProvider] to completion.
///
/// Riverpod's auto-dispose providers only stay alive while something is
/// actively watching/listening to them. In a widget tree, `ref.watch` in a
/// `build()` method does that for free; here, in a bare `ProviderContainer`
/// with no widget, a plain `container.read(provider.future)` has nothing
/// keeping the provider (or its `authStateChangesProvider` dependency)
/// alive between the synchronous read and the async value arriving, so it
/// gets disposed first and the future never completes. Holding an active
/// `container.listen` on the provider for the duration of the read is the
/// fix — and only a test-infrastructure concern, since production code
/// only ever reads this through a widget's `ref.watch`.
Future<TenantContext?> _resolveTenant(ProviderContainer container) {
  final subscription = container.listen(tenantContextProvider, (_, __) {});
  return container
      .read(tenantContextProvider.future)
      .whenComplete(subscription.close);
}

void main() {
  test('resolves to null while signed out', () async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedInAs: null),
        ),
        userRepositoryProvider.overrideWithValue(FakeUserRepository()),
        schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      ],
    );
    addTearDown(container.dispose);

    final tenant = await _resolveTenant(container);
    expect(tenant, isNull);
  });

  test(
    'resolves to null (needs onboarding) when signed in with no profile',
    () async {
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              signedInAs: const AppUser(uid: 'uid-1', email: 'new@example.com'),
            ),
          ),
          userRepositoryProvider.overrideWithValue(FakeUserRepository()),
          schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
        ],
      );
      addTearDown(container.dispose);

      final tenant = await _resolveTenant(container);
      expect(tenant, isNull);
    },
  );

  test(
    'resolves a full TenantContext for an active, school-scoped user',
    () async {
      final profile = UserProfile(
        userId: 'uid-1',
        schoolId: 'school-1',
        branchId: 'main',
        name: 'Grace Hopper',
        email: 'grace@example.com',
        role: UserRole.teacher,
        status: UserStatus.active,
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              signedInAs: const AppUser(
                uid: 'uid-1',
                email: 'grace@example.com',
              ),
            ),
          ),
          userRepositoryProvider.overrideWithValue(
            FakeUserRepository({'uid-1': profile}),
          ),
          schoolRepositoryProvider.overrideWithValue(
            FakeSchoolRepository(
              schools: {'school-1': _school},
              branches: {'school-1/main': _branch},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final tenant = await _resolveTenant(container);
      expect(tenant, isNotNull);
      expect(tenant!.role, UserRole.teacher);
      expect(tenant.school?.name, 'Rosewood High');
      expect(tenant.branch?.name, 'Main Branch');
      expect(tenant.can(Permission.viewUsers), isTrue);
      expect(tenant.can(Permission.manageSchool), isFalse);
    },
  );

  test('platformAdmin resolves without a school/branch', () async {
    final profile = UserProfile(
      userId: 'uid-admin',
      schoolId: null,
      branchId: null,
      name: 'Platform Owner',
      email: 'owner@example.com',
      role: UserRole.platformAdmin,
      status: UserStatus.active,
    );

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            signedInAs: const AppUser(
              uid: 'uid-admin',
              email: 'owner@example.com',
            ),
          ),
        ),
        userRepositoryProvider.overrideWithValue(
          FakeUserRepository({'uid-admin': profile}),
        ),
        schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      ],
    );
    addTearDown(container.dispose);

    final tenant = await _resolveTenant(container);
    expect(tenant, isNotNull);
    expect(tenant!.school, isNull);
    expect(tenant.branch, isNull);
    expect(tenant.can(Permission.managePlatform), isTrue);
  });

  test('throws AccountInactiveException for a disabled account', () async {
    final profile = UserProfile(
      userId: 'uid-1',
      schoolId: 'school-1',
      branchId: 'main',
      name: 'Disabled User',
      email: 'disabled@example.com',
      role: UserRole.teacher,
      status: UserStatus.disabled,
    );

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            signedInAs: const AppUser(
              uid: 'uid-1',
              email: 'disabled@example.com',
            ),
          ),
        ),
        userRepositoryProvider.overrideWithValue(
          FakeUserRepository({'uid-1': profile}),
        ),
        schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      _resolveTenant(container),
      throwsA(isA<AccountInactiveException>()),
    );
  });
}
