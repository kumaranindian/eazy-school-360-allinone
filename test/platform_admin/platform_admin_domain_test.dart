import 'package:cloud_functions/cloud_functions.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/authentication/domain/mfa.dart';
import 'package:eazy_school_360/features/platform_admin/data/firebase_platform_admin_repository.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_admin_entry.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _data(
  Object? platformRole, {
  String role = 'PLATFORM_ADMIN',
}) => {
  'role': role,
  'status': 'ACTIVE',
  'name': 'Admin',
  'email': 'admin@avail404.com',
  'schoolId': null,
  'branchId': null,
  if (platformRole != null) 'platformRole': platformRole,
};

void main() {
  group('PlatformRole', () {
    test('wire values round-trip; unknown values grant nothing', () {
      for (final r in PlatformRole.values) {
        expect(PlatformRole.tryParse(r.wireValue), r);
      }
      expect(PlatformRole.tryParse('GOD'), isNull);
      expect(PlatformRole.tryParse(null), isNull);
      expect(PlatformRole.tryParse('owner'), isNull, reason: 'case matters');
    });
  });

  group('UserProfile.platformRole', () {
    test('a legacy platform admin without the field is an owner', () {
      expect(
        UserProfile.fromFirestore('u', _data(null)).platformRole,
        PlatformRole.owner,
      );
    });

    test('a known role is read; an unknown one is null (grants nothing)', () {
      expect(
        UserProfile.fromFirestore('u', _data('SUPPORT')).platformRole,
        PlatformRole.support,
      );
      expect(UserProfile.fromFirestore('u', _data('GOD')).platformRole, isNull);
    });

    test('other roles never carry a platform role, whatever is stored', () {
      final p = UserProfile.fromFirestore(
        'u',
        _data('OWNER', role: 'SCHOOL_ADMIN'),
      );
      expect(p.platformRole, isNull);
    });
  });

  group('PlatformAdminEntry.fromMap', () {
    test('reads the callable row', () {
      final e = PlatformAdminEntry.fromMap({
        'uid': 'u1',
        'name': 'Asha',
        'email': 'asha@avail404.com',
        'platformRole': 'COMPLIANCE',
        'roleAssigned': true,
        'status': 'DISABLED',
        'mfaEnrolled': false,
        'lastSignIn': 'yesterday',
        'isSelf': false,
      });
      expect(e.role, PlatformRole.compliance);
      expect(e.active, isFalse);
      expect(e.mfaEnrolled, isFalse);
      expect(e.lastSignIn, 'yesterday');
    });

    test('an unknown stored role is shown as unknown, not as a power', () {
      final e = PlatformAdminEntry.fromMap({
        'uid': 'u',
        'platformRole': 'NONE',
        'status': 'ACTIVE',
      });
      expect(e.role, isNull);
    });
  });

  group('validateTotpCode', () {
    test('accepts exactly six digits (spaces ignored)', () {
      expect(validateTotpCode('123456'), isNull);
      expect(validateTotpCode('123 456'), isNull);
    });

    test('refuses empty, short, long and non-numeric codes', () {
      for (final bad in [null, '', '12345', '1234567', 'abcdef', '12 34 5a']) {
        expect(validateTotpCode(bad), isNotNull, reason: '$bad');
      }
    });
  });

  group('platformFailureFrom', () {
    AppFailure map(String code, Object? details) => platformFailureFrom(
      FirebaseFunctionsException(message: 'x', code: code, details: details),
      StackTrace.empty,
    );

    test('plain-language messages, never raw server text', () {
      expect(
        map('already-exists', {'reason': 'EMAIL_IN_USE'}),
        isA<ConflictFailure>(),
      );
      expect(
        map('permission-denied', {'reason': 'MFA_REQUIRED'}).message,
        contains('two-step'),
      );
      expect(
        map('permission-denied', {'reason': 'PERMISSION_DENIED'}).message,
        contains('owner'),
      );
      expect(map('not-found', {'reason': 'NOT_FOUND'}), isA<NotFoundFailure>());
      expect(
        map('failed-precondition', {'reason': 'FAILED_PRECONDITION'}).message,
        contains('your own'),
      );
      expect(
        map('invalid-argument', {
          'reason': 'INVALID_ARGUMENT',
          'cause': 'emailDomain',
        }).message,
        contains('company'),
      );
      expect(
        map('invalid-argument', {
          'reason': 'INVALID_ARGUMENT',
          'cause': 'email',
        }).message,
        contains('invalid'),
      );
      expect(map('permission-denied', null), isA<PermissionFailure>());
    });
  });
}
