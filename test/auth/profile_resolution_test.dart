import 'package:eazy_school_360/core/tenant/account_inactive_exception.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_repository.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Map<String, dynamic> _doc({
  Object? role = 'TEACHER',
  Object? status = 'ACTIVE',
}) => {
  'schoolId': 's1',
  'branchId': 'b1',
  'name': 'T',
  'email': 't@x.com',
  'role': role,
  'status': status,
};

class _ThrowingUsers extends FakeUserRepository {
  final Map<String, dynamic> raw;
  _ThrowingUsers(this.raw);

  @override
  Future<UserProfile?> getUserProfile(String userId) async =>
      UserProfile.fromFirestore(userId, raw);
}

void main() {
  group('UserProfile.fromFirestore', () {
    test('accepts known role and status', () {
      final p = UserProfile.fromFirestore('u1', _doc());
      expect(p.isActive, isTrue);
    });

    test('rejects unknown, lowercase, missing or non-string role/status', () {
      for (final bad in [
        _doc(role: 'ACADEMIC_ADMIN'),
        _doc(role: 'teacher'),
        _doc(role: null),
        _doc(role: 5),
        _doc(status: 'active'),
        _doc(status: null),
      ]) {
        expect(
          () => UserProfile.fromFirestore('u1', bad),
          throwsA(isA<InvalidProfileException>()),
          reason: '$bad',
        );
      }
    });
  });

  test(
    'an unusable profile resolves to a clear "not set up" state, not a crash',
    () async {
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              signedInAs: const AppUser(uid: 'u1', email: 't@x.com'),
            ),
          ),
          userRepositoryProvider.overrideWithValue(
            _ThrowingUsers(_doc(role: 'ACADEMIC_ADMIN')) as UserRepository,
          ),
          schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(tenantContextProvider, (_, __) {});
      addTearDown(sub.close);
      await expectLater(
        c.read(tenantContextProvider.future),
        throwsA(
          isA<AccountInactiveException>().having(
            (e) => e.cause,
            'cause',
            InactiveCause.invalidProfile,
          ),
        ),
      );
    },
  );
}
