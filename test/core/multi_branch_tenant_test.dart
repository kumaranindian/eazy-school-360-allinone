import 'dart:async';

import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
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
  schoolId: 's1',
  name: 'Rosewood',
  email: 'o@r.example',
  status: SchoolStatus.active,
);

Branch _branch(String id) => Branch(
  branchId: id,
  schoolId: 's1',
  name: id.toUpperCase(),
  status: BranchStatus.active,
);

UserProfile _profile({
  UserRole role = UserRole.teacher,
  String? branchId = 'north',
  Map<String, UserRole> branchRoles = const {},
}) => UserProfile(
  userId: 'u1',
  schoolId: 's1',
  branchId: branchId,
  name: 'Asha',
  email: 'a@x.example',
  role: role,
  status: UserStatus.active,
  branchRoles: branchRoles,
);

void main() {
  group('UserProfile.branchRoles', () {
    Map<String, dynamic> data(Object? roles, {String role = 'TEACHER'}) => {
      'schoolId': 's1',
      'branchId': 'north',
      'name': 'A',
      'email': 'a@x.example',
      'role': role,
      'status': 'ACTIVE',
      'branchRoles': roles,
    };

    test('parses staff roles and drops everything else', () {
      final p = UserProfile.fromFirestore(
        'u1',
        data({
          'south': 'FINANCE',
          'east': 'SCHOOL_ADMIN', // never a per-branch role
          'west': 'PLATFORM_ADMIN',
          'nowhere': 'WIZARD', // unknown
          'bad': 7,
        }),
      );
      expect(p.branchRoles, {'south': UserRole.finance});
      expect(
        () => p.branchRoles['x'] = UserRole.teacher,
        throwsUnsupportedError,
      );
    });

    test('absent or malformed means none', () {
      expect(UserProfile.fromFirestore('u', data(null)).branchRoles, isEmpty);
      expect(UserProfile.fromFirestore('u', data('x')).branchRoles, isEmpty);
    });

    test('working branches: home first, then the others sorted', () {
      final p = _profile(
        branchRoles: {'west': UserRole.finance, 'south': UserRole.teacher},
      );
      expect(p.workingBranchIds, ['north', 'south', 'west']);
      expect(p.worksInMultipleBranches, isTrue);
      expect(_profile().worksInMultipleBranches, isFalse);
    });

    test('admins and parents never get a branch list', () {
      final roles = {'south': UserRole.teacher};
      expect(
        _profile(
          role: UserRole.schoolAdmin,
          branchRoles: roles,
        ).workingBranchIds,
        isEmpty,
      );
      expect(
        _profile(role: UserRole.parent, branchRoles: roles).workingBranchIds,
        isEmpty,
      );
    });

    test('activeIn swaps branch and role, keeps the home identity', () {
      final p = _profile(branchRoles: {'south': UserRole.branchAdmin});
      final south = p.activeIn('south');
      expect(south.branchId, 'south');
      expect(south.role, UserRole.branchAdmin);
      expect(south.homeBranchId, 'north');
      expect(south.homeRole, UserRole.teacher);
      // back home, from the switched view
      final home = south.activeIn('north');
      expect(home.branchId, 'north');
      expect(home.role, UserRole.teacher);
      // switching to a branch with no role changes nothing
      expect(p.activeIn('east'), same(p));
    });
  });

  group('TenantContextNotifier.switchBranch', () {
    ProviderContainer container(UserProfile profile) {
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              signedInAs: const AppUser(uid: 'u1', email: 'a@x.example'),
            ),
          ),
          userRepositoryProvider.overrideWithValue(
            FakeUserRepository({'u1': profile}),
          ),
          schoolRepositoryProvider.overrideWithValue(
            FakeSchoolRepository(
              schools: {'s1': _school},
              branches: {
                's1/north': _branch('north'),
                's1/south': _branch('south'),
              },
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'the tenant follows the chosen branch, with that branch\'s role',
      () async {
        final c = container(
          _profile(branchRoles: {'south': UserRole.branchAdmin}),
        );
        c.listen(tenantContextProvider, (_, __) {});
        var t = (await c.read(tenantContextProvider.future))!;
        expect(t.role, UserRole.teacher);
        expect(t.branch?.branchId, 'north');
        expect(t.can(Permission.manageStaff), isFalse);

        await c.read(tenantContextProvider.notifier).switchBranch('south');
        t = c.read(tenantContextProvider).value!;
        expect(t.role, UserRole.branchAdmin);
        expect(t.branch?.branchId, 'south');
        expect(t.user.branchId, 'south');
        expect(t.can(Permission.manageStaff), isTrue);

        await c.read(tenantContextProvider.notifier).switchBranch('north');
        t = c.read(tenantContextProvider).value!;
        expect(t.role, UserRole.teacher);
        expect(t.branch?.branchId, 'north');
      },
    );

    test(
      'a school admin may act in any branch of the school, not other schools',
      () async {
        final c = container(_profile(role: UserRole.schoolAdmin));
        c.listen(tenantContextProvider, (_, __) {});
        var t = (await c.read(tenantContextProvider.future))!;
        expect(t.branch?.branchId, 'north');
        await c.read(tenantContextProvider.notifier).switchBranch('south');
        t = c.read(tenantContextProvider).value!;
        expect(t.role, UserRole.schoolAdmin);
        expect(t.branch?.branchId, 'south');
        // A branch that does not exist in the school is ignored.
        await c.read(tenantContextProvider.notifier).switchBranch('elsewhere');
        expect(c.read(tenantContextProvider).value!.branch?.branchId, 'south');
      },
    );

    test(
      'a school admin with no home branch starts in the first branch',
      () async {
        final c = container(
          _profile(role: UserRole.schoolAdmin, branchId: null),
        );
        c.listen(tenantContextProvider, (_, __) {});
        final t = (await c.read(tenantContextProvider.future))!;
        expect(t.branch?.branchId, isNotNull);
        expect(t.user.branchId, t.branch?.branchId);
      },
    );

    test(
      'a teacher still cannot switch into a branch they have no role in',
      () async {
        final c = container(_profile());
        c.listen(tenantContextProvider, (_, __) {});
        await c.read(tenantContextProvider.future);
        await c.read(tenantContextProvider.notifier).switchBranch('south');
        expect(c.read(tenantContextProvider).value!.branch?.branchId, 'north');
      },
    );

    test(
      'STATE-6: a late branch lookup cannot overwrite a newer state',
      () async {
        final slow = Completer<void>();
        late final _SlowBranches slowRepo;
        final c = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(
                signedInAs: const AppUser(uid: 'u1', email: 'a@x.example'),
              ),
            ),
            userRepositoryProvider.overrideWithValue(
              FakeUserRepository({
                'u1': _profile(branchRoles: {'south': UserRole.branchAdmin}),
              }),
            ),
            schoolRepositoryProvider.overrideWithValue(
              slowRepo = _SlowBranches(slow.future, {
                's1/north': _branch('north'),
                's1/south': _branch('south'),
              }),
            ),
          ],
        );
        addTearDown(c.dispose);
        c.listen(tenantContextProvider, (_, __) {});
        await c.read(tenantContextProvider.future);
        slowRepo.armed = true;

        final pending = c
            .read(tenantContextProvider.notifier)
            .switchBranch('south');
        // Meanwhile the tenant is replaced (as a sign-out / re-login would).
        c.read(tenantContextProvider.notifier).state = const AsyncData(null);
        slow.complete();
        await pending;
        expect(c.read(tenantContextProvider).value, isNull);
      },
    );

    test('a branch the user does not work in is ignored', () async {
      final c = container(_profile(branchRoles: {'south': UserRole.finance}));
      c.listen(tenantContextProvider, (_, __) {});
      await c.read(tenantContextProvider.future);
      await c.read(tenantContextProvider.notifier).switchBranch('east');
      expect(c.read(tenantContextProvider).value!.branch?.branchId, 'north');
    });

    test('a single-branch user cannot switch', () async {
      final c = container(_profile());
      c.listen(tenantContextProvider, (_, __) {});
      await c.read(tenantContextProvider.future);
      await c.read(tenantContextProvider.notifier).switchBranch('south');
      expect(c.read(tenantContextProvider).value!.branch?.branchId, 'north');
    });
  });
}

/// Answers branch lookups only once [gate] completes.
class _SlowBranches extends FakeSchoolRepository {
  final Future<void> gate;
  bool armed = false;
  _SlowBranches(this.gate, Map<String, Branch> branches)
    : super(schools: {'s1': _school}, branches: branches);

  @override
  Future<Branch?> getBranch(String schoolId, String branchId) async {
    if (armed) await gate;
    return super.getBranch(schoolId, branchId);
  }
}
