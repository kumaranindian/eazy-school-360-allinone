import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/admission/domain/public_portal.dart';
import 'package:eazy_school_360/features/admission/presentation/providers/public_portal_providers.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _FakePublic implements PublicAdmissionRepository {
  Object? loadError;
  Object? submitError;
  final List<Map<String, Object?>> sent = [];

  @override
  Future<PublicPortalInfo> load(String slug) async {
    if (loadError != null) throw loadError!;
    return const PublicPortalInfo(
      schoolName: 'Rosewood High',
      branchName: 'Main',
      introText: 'Welcome to Rosewood.',
      consentText: 'I agree that the school may contact me about this enquiry.',
      consentVersion: 2,
      years: [
        PublicYear('ay1', '2026-27', [
          PublicClass('c1', 'Class 1'),
          PublicClass('c2', 'Class 2'),
        ]),
      ],
    );
  }

  @override
  Future<String> submit({
    required String slug,
    required String requestId,
    required PublicEnquiryInput input,
    required int consentVersion,
    String? captchaToken,
  }) async {
    if (submitError != null) throw submitError!;
    sent.add({
      'slug': slug,
      'requestId': requestId,
      'consentVersion': consentVersion,
      'wire': input.toWire(),
    });
    return 'ENQ-2026-00007';
  }
}

Future<_FakePublic> _open(
  WidgetTester tester, {
  Size size = const Size(390, 2200),
  _FakePublic? repo,
  String slug = 'rosewood',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = repo ?? _FakePublic();
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      // Nobody is signed in.
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      publicAdmissionRepositoryProvider.overrideWithValue(fake),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/admission/$slug');
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _fill(WidgetTester tester, {bool consent = true}) async {
  Future<void> type(String label, String text) async {
    await tester.enterText(find.widgetWithText(TextFormField, label), text);
  }

  await type('First name *', 'Asha');
  await type('Last name', 'Nair');
  await type('Name *', 'Meena Nair');
  await type('Mobile number *', '98765 43210');
  Future<void> pick(String label, String option) async {
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, label),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  await pick('Academic year *', '2026-27');
  await pick('Class *', 'Class 2');
  if (consent) {
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('a signed-out visitor reaches the form (no login redirect)', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Rosewood High'), findsOneWidget);
    expect(find.text('Welcome to Rosewood.'), findsOneWidget);
    expect(find.text('Send enquiry'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending needs the consent box; nothing is sent without it', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _fill(tester, consent: false);
    await tester.tap(find.text('Send enquiry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tick the box'), findsOneWidget);
    expect(repo.sent, isEmpty);
  });

  testWidgets('required fields are checked before anything is sent', (
    tester,
  ) async {
    final repo = await _open(tester);
    await tester.tap(find.text('Send enquiry'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the first name'), findsOneWidget);
    expect(find.text('Choose the academic year'), findsOneWidget);
    expect(find.text('Enter a valid mobile number'), findsOneWidget);
    expect(repo.sent, isEmpty);
  });

  testWidgets(
    'a valid form is sent once with the consent version and shows the reference',
    (tester) async {
      final repo = await _open(tester);
      await _fill(tester);
      await tester.tap(find.text('Send enquiry'));
      await tester.pumpAndSettle();
      expect(repo.sent, hasLength(1));
      final s = repo.sent.single;
      expect(s['slug'], 'rosewood');
      expect(s['consentVersion'], 2);
      expect((s['requestId'] as String).length, greaterThan(8));
      final wire = s['wire']! as Map;
      expect(wire['academicYearId'], 'ay1');
      expect(wire['interestedClassId'], 'c2');
      expect((wire['guardians'] as List).single['phone'], '98765 43210');
      expect(find.textContaining('ENQ-2026-00007'), findsOneWidget);
      expect(find.text('Send enquiry'), findsNothing);
    },
  );

  testWidgets('the class list follows the chosen year', (tester) async {
    await _open(tester);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Class *'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Class 1'), findsNothing);
  });

  testWidgets('a server refusal is shown and the form stays', (tester) async {
    final repo = _FakePublic()
      ..submitError = const ValidationFailure(
        'Too many enquiries were sent from here. Please try again later.',
      );
    await _open(tester, repo: repo);
    await _fill(tester);
    await tester.tap(find.text('Send enquiry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many enquiries'), findsOneWidget);
    expect(find.text('Send enquiry'), findsOneWidget);
  });

  testWidgets('an unknown page says so and shows no form', (tester) async {
    final repo = _FakePublic()
      ..loadError = const NotFoundFailure(
        'This enquiry page is not available.',
      );
    await _open(tester, repo: repo, slug: 'nope');
    expect(find.textContaining('not available'), findsOneWidget);
    expect(find.text('Send enquiry'), findsNothing);
  });

  testWidgets('lays out on a phone, a tablet and a desktop with larger text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _open(tester, size: const Size(360, 800));
    for (final size in const [
      Size(360, 800),
      Size(820, 1000),
      Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
