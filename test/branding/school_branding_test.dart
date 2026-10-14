import 'dart:async';

import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/shared/branding/school_brand_logo.dart';
import 'package:eazy_school_360/shared/branding/school_branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

School _school(String id, String name, {String? logoUrl}) => School(
  schoolId: id,
  name: name,
  email: '$id@example.com',
  logoUrl: logoUrl,
  status: SchoolStatus.active,
);

UserProfile _profile(String uid, String schoolId, UserRole role) => UserProfile(
  userId: uid,
  schoolId: schoolId,
  branchId: 'main',
  name: 'User $uid',
  email: '$uid@example.com',
  role: role,
  status: UserStatus.active,
);

/// Auth fake whose session can change after start-up (sign-out / sign-in).
class _SwitchableAuth extends FakeAuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _now;

  _SwitchableAuth(this._now);

  void emit(AppUser? user) {
    _now = user;
    _controller.add(user);
  }

  @override
  AppUser? get currentUser => _now;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _now;
    yield* _controller.stream;
  }
}

const _logoA = 'https://cdn.example.com/a/logo.png?token=1';
const _logoB = 'https://cdn.example.com/b/logo.png?token=2';

class _World {
  final FakeSchoolRepository schools;
  final _SwitchableAuth auth;
  final ProviderContainer container;
  _World(this.schools, this.auth, this.container);
}

_World _world({
  required Map<String, School> schools,
  required Map<String, UserProfile> profiles,
  String? signedInUid,
}) {
  final schoolRepo = FakeSchoolRepository(schools: schools);
  final auth = _SwitchableAuth(
    signedInUid == null
        ? null
        : AppUser(uid: signedInUid, email: '$signedInUid@example.com'),
  );
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(FakeUserRepository(profiles)),
      schoolRepositoryProvider.overrideWithValue(schoolRepo),
    ],
  );
  addTearDown(container.dispose);
  return _World(schoolRepo, auth, container);
}

/// Keeps the (auto-dispose-free) tenant provider alive and waits for it.
Future<SchoolBranding?> _branding(ProviderContainer c) async {
  final sub = c.listen(tenantContextProvider, (_, _) {});
  addTearDown(sub.close);
  await c.read(tenantContextProvider.future);
  return c.read(schoolBrandingProvider);
}

void main() {
  group('schoolBrandingProvider', () {
    test('school with a logo: name, id and url, for every role', () async {
      for (final role in [
        UserRole.schoolAdmin,
        UserRole.teacher,
        UserRole.finance,
        UserRole.parent,
      ]) {
        final w = _world(
          schools: {'s1': _school('s1', 'Rosewood', logoUrl: _logoA)},
          profiles: {'u1': _profile('u1', 's1', role)},
          signedInUid: 'u1',
        );
        final branding = await _branding(w.container);
        expect(branding, isNotNull, reason: role.name);
        expect(branding!.schoolId, 's1');
        expect(branding.name, 'Rosewood');
        expect(branding.logoUrl, _logoA);
        expect(branding.hasLogo, isTrue);
      }
    });

    test('school without a logo has no logoUrl', () async {
      final w = _world(
        schools: {'s1': _school('s1', 'Rosewood')},
        profiles: {'u1': _profile('u1', 's1', UserRole.parent)},
        signedInUid: 'u1',
      );
      final branding = await _branding(w.container);
      expect(branding!.name, 'Rosewood');
      expect(branding.hasLogo, isFalse);
    });

    test('a stored value that is not an http(s) URL counts as no logo', () {
      expect(usableLogoUrl(null), isNull);
      expect(usableLogoUrl('   '), isNull);
      expect(usableLogoUrl('schools/s1/logo.png'), isNull);
      expect(usableLogoUrl('javascript:alert(1)'), isNull);
      expect(usableLogoUrl('file:///etc/passwd'), isNull);
      expect(usableLogoUrl(_logoA), _logoA);
    });

    test('signed out: no branding', () async {
      final w = _world(schools: {}, profiles: {});
      expect(await _branding(w.container), isNull);
    });

    test('replacing the logo refreshes branding without a re-login', () async {
      final w = _world(
        schools: {'s1': _school('s1', 'Rosewood', logoUrl: _logoA)},
        profiles: {'u1': _profile('u1', 's1', UserRole.schoolAdmin)},
        signedInUid: 'u1',
      );
      expect((await _branding(w.container))!.logoUrl, _logoA);

      // What the upload controller does after a successful save.
      w.schools.schools['s1'] = _school('s1', 'Rosewood', logoUrl: _logoB);
      w.container.invalidate(tenantContextProvider);
      await w.container.read(tenantContextProvider.future);

      expect(w.container.read(schoolBrandingProvider)!.logoUrl, _logoB);
    });

    test('sign out then sign in as another school shows only that '
        "school's branding", () async {
      final w = _world(
        schools: {
          's1': _school('s1', 'Rosewood', logoUrl: _logoA),
          's2': _school('s2', 'Maple', logoUrl: _logoB),
        },
        profiles: {
          'u1': _profile('u1', 's1', UserRole.teacher),
          'u2': _profile('u2', 's2', UserRole.parent),
        },
        signedInUid: 'u1',
      );
      expect((await _branding(w.container))!.name, 'Rosewood');

      w.auth.emit(null);
      await pumpEventQueue();
      await w.container.read(tenantContextProvider.future);
      expect(w.container.read(schoolBrandingProvider), isNull);

      w.auth.emit(const AppUser(uid: 'u2', email: 'u2@example.com'));
      await pumpEventQueue();
      await w.container.read(tenantContextProvider.future);
      final branding = w.container.read(schoolBrandingProvider)!;
      expect(branding.schoolId, 's2');
      expect(branding.logoUrl, _logoB);
    });

    test('a user cannot pick up another school: branding follows the '
        'profile school, never a client value', () async {
      final w = _world(
        schools: {
          's1': _school('s1', 'Rosewood', logoUrl: _logoA),
          's2': _school('s2', 'Maple', logoUrl: _logoB),
        },
        profiles: {'u1': _profile('u1', 's1', UserRole.parent)},
        signedInUid: 'u1',
      );
      final branding = await _branding(w.container);
      expect(branding!.schoolId, 's1');
      expect(branding.logoUrl, isNot(_logoB));
    });
  });

  group('SchoolLogoImage', () {
    Future<void> pump(WidgetTester tester, Widget child, {Size? size}) async {
      if (size != null) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );
    }

    testWidgets('no logo: shows the EazySchool mark', (tester) async {
      await pump(
        tester,
        const SchoolLogoImage(url: null, label: 'Rosewood', size: 40),
      );
      final asset = tester.widget<Image>(find.byType(Image));
      expect(asset.image, isA<AssetImage>());
      expect(tester.getSize(find.byType(Image)), const Size(40, 40));
    });

    testWidgets('with a URL: loads a network image that keeps its aspect '
        'ratio and has an accessibility label', (tester) async {
      await pump(
        tester,
        const SchoolLogoImage(url: _logoA, label: 'Rosewood', size: 48),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
      expect(image.fit, BoxFit.contain);
      expect(image.semanticLabel, 'Rosewood');
      // Reserved box: layout does not depend on the load outcome.
      expect(tester.getSize(find.byType(SchoolLogoImage)), const Size(48, 48));
    });

    testWidgets('a failing or dead URL falls back to the product mark and '
        'does not throw', (tester) async {
      await pump(
        tester,
        const SchoolLogoImage(url: _logoA, label: 'Rosewood', size: 48),
      );
      // The test HTTP client answers 400, which is the failed-load path.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .any((i) => i.image is AssetImage),
        isTrue,
      );
      expect(tester.getSize(find.byType(SchoolLogoImage)), const Size(48, 48));
    });

    testWidgets('an unusable stored value never reaches the image layer', (
      tester,
    ) async {
      await pump(
        tester,
        const SchoolLogoImage(url: 'schools/x/logo.png', label: 'X'),
      );
      expect(tester.widget<Image>(find.byType(Image)).image, isA<AssetImage>());
    });

    for (final size in const [
      Size(320, 568),
      Size(768, 1024),
      Size(1920, 1080),
    ]) {
      testWidgets('lays out at ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        await pump(
          tester,
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SchoolLogoImage(url: _logoA, label: 'Rosewood', size: 32),
              SizedBox(width: 12),
              Flexible(child: PoweredByEazySchool(suffix: 'v1.0.0 (1)')),
            ],
          ),
          size: size,
        );
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('Powered by EazySchool 360'),
          findsOneWidget,
        );
      });
    }
  });

  group('SchoolAndProductMarks', () {
    Future<List<Image>> marks(WidgetTester tester, School school) async {
      final w = _world(
        schools: {'s1': school},
        profiles: {'u1': _profile('u1', 's1', UserRole.parent)},
        signedInUid: 'u1',
      );
      final sub = w.container.listen(tenantContextProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.runAsync(
        () => w.container.read(tenantContextProvider.future),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: w.container,
          child: const MaterialApp(
            home: Scaffold(body: SchoolAndProductMarks(size: 32)),
          ),
        ),
      );
      return tester.widgetList<Image>(find.byType(Image)).toList();
    }

    testWidgets('school with a logo: school logo and EazySchool mark', (
      tester,
    ) async {
      final images = await marks(
        tester,
        _school('s1', 'Rosewood', logoUrl: _logoA),
      );
      expect(images, hasLength(2));
      expect(images.first.image, isA<NetworkImage>());
      expect(images.last.image, isA<AssetImage>());
    });

    testWidgets('a logo that fails to load shows the school initial, never '
        'the EazySchool mark twice', (tester) async {
      await marks(tester, _school('s1', 'Rosewood', logoUrl: _logoA));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images.where((i) => i.image is AssetImage), hasLength(1));
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('school without a logo: only the EazySchool mark', (
      tester,
    ) async {
      final images = await marks(tester, _school('s1', 'Rosewood'));
      expect(images, hasLength(1));
      expect(images.single.image, isA<AssetImage>());
    });
  });

  group('SchoolBrandLogo', () {
    testWidgets('uses the signed-in school logo, else the mark', (
      tester,
    ) async {
      final w = _world(
        schools: {'s1': _school('s1', 'Rosewood', logoUrl: _logoA)},
        profiles: {'u1': _profile('u1', 's1', UserRole.parent)},
        signedInUid: 'u1',
      );
      final sub = w.container.listen(tenantContextProvider, (_, _) {});
      addTearDown(sub.close);
      await tester.runAsync(
        () => w.container.read(tenantContextProvider.future),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: w.container,
          child: const MaterialApp(home: Scaffold(body: SchoolBrandLogo())),
        ),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<NetworkImage>(),
      );

      // Logo removed (e.g. school record changed): falls back immediately.
      w.schools.schools['s1'] = _school('s1', 'Rosewood');
      w.container.invalidate(tenantContextProvider);
      await tester.runAsync(
        () => w.container.read(tenantContextProvider.future),
      );
      await tester.pump();
      expect(tester.widget<Image>(find.byType(Image)).image, isA<AssetImage>());
    });
  });
}
