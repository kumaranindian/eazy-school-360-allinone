import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/tenant/account_inactive_exception.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/access_messages.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/authentication/domain/phone_otp.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

LoginAccess access({
  String? email = 'a@x.com',
  String? phone = '+919876543210',
  List<LoginMethod> school = LoginMethod.values,
  bool hasAccount = true,
  bool enabled = true,
  List<LoginMethod> methods = const [LoginMethod.password],
}) => LoginAccess(
  id: 't1',
  kind: LoginKind.staff,
  name: 'Asha',
  userType: 'TEACHER',
  registeredEmail: email,
  registeredPhone: phone,
  schoolMethods: school,
  hasAccount: hasAccount,
  enabled: enabled,
  methods: methods,
  effective: methods,
  activation: LoginActivation.active,
  emailVerified: true,
  phoneVerified: false,
  lastLogin: null,
  legacy: false,
  manageable: true,
);

UserProfile profile({LoginState? login}) => UserProfile(
  userId: 'u1',
  schoolId: 's1',
  branchId: 'b1',
  name: 'T',
  email: 't@x.com',
  role: UserRole.teacher,
  status: UserStatus.active,
  login: login,
);

Future<TenantContext?> resolve(UserProfile p, FakeAuthRepository auth) async {
  final c = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(FakeUserRepository({'u1': p})),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
    ],
  );
  addTearDown(c.dispose);
  final sub = c.listen(tenantContextProvider, (_, __) {});
  try {
    return await c.read(tenantContextProvider.future);
  } finally {
    sub.close();
  }
}

void main() {
  group('LoginAccessRules', () {
    test('a method the school turned off is blocked with a reason', () {
      final a = access(school: [LoginMethod.password]);
      expect(
        LoginAccessRules.blocker(LoginMethod.google, a),
        contains('school'),
      );
      expect(LoginAccessRules.blocker(LoginMethod.password, a), isNull);
    });

    test('email and phone methods need the contact on the record', () {
      final a = access(email: null, phone: null);
      expect(
        LoginAccessRules.blocker(LoginMethod.password, a),
        contains('email'),
      );
      expect(
        LoginAccessRules.blocker(LoginMethod.google, a),
        contains('email'),
      );
      expect(
        LoginAccessRules.blocker(LoginMethod.phoneOtp, a),
        contains('mobile'),
      );
    });

    test(
      'validate requires a method when enabling, nothing when disabling',
      () {
        final a = access();
        expect(
          LoginAccessRules.validate(a, enabled: true, selected: {}),
          isNotNull,
        );
        expect(
          LoginAccessRules.validate(a, enabled: false, selected: {}),
          isNull,
        );
        expect(
          LoginAccessRules.validate(
            a,
            enabled: true,
            selected: {LoginMethod.password, LoginMethod.phoneOtp},
          ),
          isNull,
        );
        expect(
          LoginAccessRules.validate(
            access(phone: null),
            enabled: true,
            selected: {LoginMethod.phoneOtp},
          ),
          contains('mobile'),
        );
      },
    );

    test('disabling or removing a method is security-sensitive', () {
      final a = access(methods: [LoginMethod.password, LoginMethod.google]);
      expect(LoginAccessRules.narrows(a, enabled: false, selected: {}), isTrue);
      expect(
        LoginAccessRules.narrows(
          a,
          enabled: true,
          selected: {LoginMethod.password},
        ),
        isTrue,
      );
      expect(
        LoginAccessRules.narrows(
          a,
          enabled: true,
          selected: {
            LoginMethod.password,
            LoginMethod.google,
            LoginMethod.phoneOtp,
          },
        ),
        isFalse,
      );
      expect(
        LoginAccessRules.narrows(
          access(hasAccount: false),
          enabled: false,
          selected: {},
        ),
        isFalse,
      );
    });

    test('changed detects real edits only', () {
      final a = access(methods: [LoginMethod.password]);
      expect(
        LoginAccessRules.changed(
          a,
          enabled: true,
          selected: {LoginMethod.password},
        ),
        isFalse,
      );
      expect(
        LoginAccessRules.changed(
          a,
          enabled: true,
          selected: {LoginMethod.google},
        ),
        isTrue,
      );
      expect(LoginAccessRules.changed(a, enabled: false, selected: {}), isTrue);
    });
  });

  test('LoginAccess.fromMap tolerates missing and unknown values', () {
    final a = LoginAccess.fromMap({
      'id': 'x',
      'name': 'N',
      'userType': 'PARENT',
      'methods': ['PASSWORD', 'SMOKE_SIGNAL'],
      'effective': ['PASSWORD'],
      'schoolMethods': ['PASSWORD', 'GOOGLE'],
      'activation': 'PENDING_ACTIVATION',
      'lastLogin': '2026-01-02T03:04:05.000Z',
    }, LoginKind.parent);
    expect(a.methods, [LoginMethod.password]);
    expect(a.userTypeLabel, 'Parent');
    expect(a.activation, LoginActivation.pendingActivation);
    expect(a.lastLogin, isNotNull);
    expect(a.hasAccount, isFalse);
    expect(a.manageable, isTrue);
  });

  test('school settings track which methods are on', () {
    const s = SchoolAuthSettings(
      emailPassword: true,
      google: true,
      phoneOtp: false,
      phoneOtpConfigured: false,
    );
    expect(s.enabledMethods, [LoginMethod.password, LoginMethod.google]);
    final t = s.withMethod(LoginMethod.google, false);
    expect(t.enabledMethods, [LoginMethod.password]);
    expect(t == s, isFalse);
    expect(s.withMethod(LoginMethod.google, true) == s, isTrue);
  });

  group('tenant gate', () {
    test('legacy profile (no login map) is unaffected', () async {
      final t = await resolve(
        profile(),
        FakeAuthRepository(
          signedInAs: const AppUser(uid: 'u1', email: 't@x.com'),
        ),
      );
      expect(t, isNotNull);
    });

    test('permitted method resolves', () async {
      final t = await resolve(
        profile(
          login: const LoginState(
            enabled: true,
            methods: [LoginMethod.google],
            effective: [LoginMethod.google],
          ),
        ),
        FakeAuthRepository(
          signedInAs: const AppUser(uid: 'u1', email: 't@x.com'),
          signInMethod: LoginMethod.google,
        ),
      );
      expect(t, isNotNull);
    });

    test('disabled login is refused', () async {
      expect(
        resolve(
          profile(
            login: const LoginState(enabled: false, methods: [], effective: []),
          ),
          FakeAuthRepository(
            signedInAs: const AppUser(uid: 'u1', email: 't@x.com'),
          ),
        ),
        throwsA(
          isA<AccountInactiveException>().having(
            (e) => e.cause,
            'cause',
            InactiveCause.loginDisabled,
          ),
        ),
      );
    });

    test(
      'a method that is not permitted is refused and names the allowed ones',
      () async {
        expect(
          resolve(
            profile(
              login: const LoginState(
                enabled: true,
                methods: [LoginMethod.phoneOtp],
                effective: [LoginMethod.phoneOtp],
              ),
            ),
            FakeAuthRepository(
              signedInAs: const AppUser(uid: 'u1', email: 't@x.com'),
            ),
          ),
          throwsA(
            isA<AccountInactiveException>()
                .having(
                  (e) => e.cause,
                  'cause',
                  InactiveCause.methodNotPermitted,
                )
                .having((e) => e.permitted, 'permitted', [
                  LoginMethod.phoneOtp,
                ]),
          ),
        );
      },
    );
  });

  group('phone OTP controller', () {
    ProviderContainer make(FakeAuthRepository auth) {
      final c = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
      );
      addTearDown(c.dispose);
      c.listen(phoneOtpControllerProvider, (_, __) {});
      return c;
    }

    test('request then verify signs in only via the repository', () async {
      final auth = FakeAuthRepository();
      final c = make(auth);
      final n = c.read(phoneOtpControllerProvider.notifier);
      await n.requestCode('+919876543210');
      var s = c.read(phoneOtpControllerProvider);
      expect(s.step, OtpStep.enterCode);
      expect(s.resendAt, isNotNull);
      await n.verify('123456');
      s = c.read(phoneOtpControllerProvider);
      expect(auth.verifiedCodes, ['123456']);
      expect(auth.currentUser, isNotNull);
      expect(s.error, isNull);
    });

    test(
      'provider failures surface a message and stay on the phone step',
      () async {
        final auth = FakeAuthRepository()
          ..otpError = const AccessPolicyFailure(
            'try later',
            reason: 'DELIVERY_FAILED',
          );
        final c = make(auth);
        await c
            .read(phoneOtpControllerProvider.notifier)
            .requestCode('+919876543210');
        final s = c.read(phoneOtpControllerProvider);
        expect(s.step, OtpStep.enterPhone);
        expect(s.error, 'try later');
        expect(s.busy, isFalse);
      },
    );

    test(
      'a wrong code keeps the user on the code step; a locked one frees resend',
      () async {
        final auth = FakeAuthRepository();
        final c = make(auth);
        final n = c.read(phoneOtpControllerProvider.notifier);
        await n.requestCode('+919876543210');
        auth.otpError = const AccessPolicyFailure('bad', reason: 'OTP_INVALID');
        await n.verify('000000');
        expect(c.read(phoneOtpControllerProvider).step, OtpStep.enterCode);
        expect(auth.currentUser, isNull);
        auth.otpError = const AccessPolicyFailure(
          'locked',
          reason: 'OTP_LOCKED',
        );
        await n.verify('000000');
        final s = c.read(phoneOtpControllerProvider);
        expect(s.resendAt!.isAfter(DateTime.now()), isFalse);
      },
    );
  });

  test('input validators', () {
    expect(validatePhoneNumber(''), isNotNull);
    expect(validatePhoneNumber('abc'), isNotNull);
    expect(validatePhoneNumber('98765 43210'), isNull);
    expect(validatePhoneNumber('+1 (415) 555-0100'), isNull);
    expect(validateOtpCode('12345'), isNotNull);
    expect(validateOtpCode('123456'), isNull);
  });

  test('every server reason has a user-facing message', () {
    for (final r in [
      'PERMISSION_DENIED',
      'METHOD_NOT_ENABLED',
      'EMAIL_REQUIRED',
      'PHONE_IN_USE',
      'CALLER_LOCKOUT',
      'ADMIN_LOCKOUT',
      'PHONE_OTP_NOT_CONFIGURED',
      'RATE_LIMITED',
      'RESEND_COOLDOWN',
      'DELIVERY_FAILED',
      'OTP_INVALID',
      'OTP_EXPIRED',
      'OTP_LOCKED',
    ]) {
      expect(accessMessageFor(r), isNot(accessMessageFor('NOPE')), reason: r);
    }
    expect(accessMessageFor('RATE_LIMITED', retryAfterSec: 90), contains('90'));
  });
}
