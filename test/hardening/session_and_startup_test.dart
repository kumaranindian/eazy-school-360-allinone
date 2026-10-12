import 'dart:async';
import 'dart:ui';

import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/app/bootstrap.dart';
import 'package:eazy_school_360/app/startup_error_app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/auth_repository.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_repository.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// An auth repository whose user can be changed during a test.
class _SwitchableAuth implements AuthRepository {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  _SwitchableAuth(this._user);

  void emit(AppUser? user) {
    _user = user;
    _controller.add(user);
  }

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  AppUser? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Profiles by uid; a uid can be held back until [release] is called, to
/// observe what the app shows while the new account's profile is loading.
class _Users implements UserRepository {
  final Map<String, UserProfile> profiles;
  final Map<String, Completer<void>> gates = {};

  _Users(this.profiles);

  void hold(String uid) => gates[uid] = Completer<void>();
  void release(String uid) => gates[uid]!.complete();

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    await gates[userId]?.future;
    return profiles[userId];
  }

  @override
  Stream<UserProfile?> watchUserProfile(String userId) =>
      Stream.fromFuture(getUserProfile(userId));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserProfile _profile(String uid, String name, UserRole role) => UserProfile(
  userId: uid,
  schoolId: 'school-1',
  branchId: 'main',
  name: name,
  email: '$uid@example.com',
  role: role,
  status: UserStatus.active,
);

const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'o@r.example',
  status: SchoolStatus.active,
);

void main() {
  group('account switching and sign-out', () {
    testWidgets(
      'while the next account loads, the previous account\'s screens are not shown',
      (tester) async {
        final auth = _SwitchableAuth(
          const AppUser(uid: 'admin-1', email: 'a@example.com'),
        );
        final users = _Users({
          'admin-1': _profile('admin-1', 'Ada Admin', UserRole.schoolAdmin),
          'parent-1': _profile('parent-1', 'Pam Parent', UserRole.parent),
        });
        final container = ProviderContainer(
          overrides: [
            envConfigProvider.overrideWithValue(
              EnvConfig.forEnvironment(AppEnvironment.test),
            ),
            authRepositoryProvider.overrideWithValue(auth),
            userRepositoryProvider.overrideWithValue(users),
            schoolRepositoryProvider.overrideWithValue(
              FakeSchoolRepository(schools: {'school-1': _school}),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(container: container, child: const App()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Welcome, Ada Admin'), findsOneWidget);
        expect(find.text('Users'), findsWidgets); // admin-only navigation

        // A different account signs in; its profile is slow to load.
        users.hold('parent-1');
        auth.emit(const AppUser(uid: 'parent-1', email: 'p@example.com'));
        await tester.pump();
        await tester.pump(
          const Duration(milliseconds: 500),
        ); // route transition
        expect(find.text('Welcome, Ada Admin'), findsNothing);
        expect(find.text('Users'), findsNothing);
        final router = container.read(appRouterProvider);
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          isNot(AppRoutes.dashboard),
        );

        users.release('parent-1');
        await tester.pumpAndSettle();
        expect(find.text('Welcome, Pam Parent'), findsOneWidget);
        expect(find.text('Users'), findsNothing);
      },
    );

    testWidgets('signing out returns to login and shows nothing private', (
      tester,
    ) async {
      final auth = _SwitchableAuth(
        const AppUser(uid: 'admin-1', email: 'a@example.com'),
      );
      final container = ProviderContainer(
        overrides: [
          envConfigProvider.overrideWithValue(
            EnvConfig.forEnvironment(AppEnvironment.test),
          ),
          authRepositoryProvider.overrideWithValue(auth),
          userRepositoryProvider.overrideWithValue(
            _Users({
              'admin-1': _profile('admin-1', 'Ada Admin', UserRole.schoolAdmin),
            }),
          ),
          schoolRepositoryProvider.overrideWithValue(
            FakeSchoolRepository(schools: {'school-1': _school}),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const App()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Ada Admin'), findsOneWidget);
      auth.emit(null);
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Ada Admin'), findsNothing);
      expect(
        container
            .read(appRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        AppRoutes.login,
      );
      // A direct link to a protected route while signed out stays on login.
      container.read(appRouterProvider).go('/students');
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        AppRoutes.login,
      );
    });

    test(
      'the staff branch choice does not survive an account change',
      () async {
        final auth = _SwitchableAuth(
          const AppUser(uid: 'u1', email: 'u1@example.com'),
        );
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(auth)],
        );
        addTearDown(container.dispose);
        container.listen(authStateChangesProvider, (_, __) {});
        container.listen(selectedStaffBranchIdProvider, (_, __) {});
        await container.read(authStateChangesProvider.future);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        container.read(selectedStaffBranchIdProvider.notifier).select('north');
        expect(container.read(selectedStaffBranchIdProvider), 'north');
        auth.emit(const AppUser(uid: 'u2', email: 'u2@example.com'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(container.read(selectedStaffBranchIdProvider), isNull);
      },
    );
  });

  group('startup safety', () {
    test(
      'every environment is checked; the placeholder environments refuse',
      () {
        for (final env in [AppEnvironment.test, AppEnvironment.uat]) {
          expect(
            EnvConfig.forEnvironment(env).hasPlaceholderFirebaseOptions,
            isTrue,
            reason: '${env.name} has no Firebase project configured',
          );
        }
      },
    );

    testWidgets(
      'the startup error screen is clear and shows no technical detail',
      (tester) async {
        await tester.pumpWidget(
          const StartupErrorApp(appName: 'EazySchool 360'),
        );
        expect(find.text("EazySchool 360 can't start"), findsOneWidget);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.textContaining('REPLACE_'), findsNothing);
      },
    );

    test(
      'unhandled errors are routed to the logger and do not crash the app',
      () {
        final previous = installErrorHandlers();
        addTearDown(() {
          FlutterError.onError = previous.flutter;
          PlatformDispatcher.instance.onError = previous.platform;
        });
        final handled = PlatformDispatcher.instance.onError!(
          StateError('boom'),
          StackTrace.current,
        );
        expect(handled, isTrue);
        // Reporting a Flutter error must not rethrow.
        FlutterError.onError!(
          FlutterErrorDetails(exception: StateError('widget failure')),
        );
      },
    );
  });
}
