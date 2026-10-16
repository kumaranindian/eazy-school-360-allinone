import 'package:eazy_school_360/core/routing/route_titles.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/shared/branding/school_brand_logo.dart';
import 'package:eazy_school_360/shared/branding/school_branding.dart';
import 'package:eazy_school_360/shared/branding/school_branding_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _left = Key('left-logo');
const _right = Key('right-logo');

Widget _box(Key key, double size) =>
    SizedBox(key: key, width: size, height: size);

Future<void> _pumpHeader(
  WidgetTester tester, {
  required Size size,
  required Widget schoolLogo,
  required Widget appLogo,
  String title = 'Students',
  List<Widget> actions = const [],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 56,
              width: size.width,
              child: SchoolBrandingHeader(
                schoolLogo: schoolLogo,
                appLogo: appLogo,
                title: title,
                actions: actions,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder get _titleText => find.byType(Text).first;

class _Current extends Notifier<SchoolBranding?> {
  @override
  SchoolBranding? build() => const SchoolBranding(
    schoolId: 's1',
    name: 'Rosewood High School',
    logoUrl: 'https://cdn.example.com/s1.png',
  );

  void set(SchoolBranding? b) => state = b;
}

void main() {
  group('SchoolBrandingHeader layout', () {
    testWidgets('school logo left, title centred on the bar, app logo right', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        size: const Size(800, 600),
        schoolLogo: _box(_left, 36),
        appLogo: _box(_right, 36),
      );
      final l = tester.getRect(find.byKey(_left));
      final r = tester.getRect(find.byKey(_right));
      final t = tester.getRect(_titleText);
      expect(l.left, 0);
      expect(r.right, 800);
      expect(t.center.dx, closeTo(400, 0.5));
      expect(l.right, lessThan(t.left));
      expect(t.right, lessThan(r.left));
    });

    testWidgets('stays centred when the two sides differ a lot in width', (
      tester,
    ) async {
      // Right side carries two action buttons (what the shell adds).
      await _pumpHeader(
        tester,
        size: const Size(800, 600),
        schoolLogo: _box(_left, 24),
        appLogo: _box(_right, 44),
        actions: const [
          IconButton(onPressed: null, icon: Icon(Icons.notifications)),
          IconButton(onPressed: null, icon: Icon(Icons.logout)),
        ],
      );
      expect(tester.getRect(_titleText).center.dx, closeTo(400, 0.5));
    });

    testWidgets('a plain Row would not centre it; this does for every width', (
      tester,
    ) async {
      for (final w in [600.0, 820.0, 1440.0]) {
        await _pumpHeader(
          tester,
          size: Size(w, 800),
          schoolLogo: _box(_left, 32),
          appLogo: _box(_right, 32),
          actions: const [
            IconButton(onPressed: null, icon: Icon(Icons.logout)),
          ],
        );
        expect(tester.getRect(_titleText).center.dx, closeTo(w / 2, 0.5));
      }
    });

    testWidgets(
      'a long title is ellipsised and never touches or overlaps a logo',
      (tester) async {
        await _pumpHeader(
          tester,
          size: const Size(360, 640),
          schoolLogo: _box(_left, 32),
          appLogo: _box(_right, 32),
          title:
              'The Extraordinarily Long Name of the International School of Excellence',
          actions: const [
            IconButton(onPressed: null, icon: Icon(Icons.notifications)),
            IconButton(onPressed: null, icon: Icon(Icons.logout)),
          ],
        );
        expect(tester.takeException(), isNull);
        final l = tester.getRect(find.byKey(_left));
        final r = tester.getRect(find.byKey(_right));
        final t = tester.getRect(_titleText);
        expect(t.left, greaterThanOrEqualTo(l.right));
        expect(t.right, lessThanOrEqualTo(r.left));
        final text = tester.widget<Text>(_titleText);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.maxLines, 1);
      },
    );

    for (final scale in [1.0, 1.5]) {
      for (final size in const [
        Size(320, 568),
        Size(390, 844),
        Size(844, 390), // phone landscape
        Size(820, 1180),
        Size(1440, 900),
      ]) {
        testWidgets(
          'no overflow or overlap at ${size.width.toInt()}x${size.height.toInt()} '
          '@${scale}x text',
          (tester) async {
            await _pumpHeader(
              tester,
              size: size,
              schoolLogo: _box(_left, 32),
              appLogo: _box(_right, 32),
              title: 'Fees Management',
              textScale: scale,
              actions: const [
                IconButton(onPressed: null, icon: Icon(Icons.notifications)),
                IconButton(onPressed: null, icon: Icon(Icons.logout)),
              ],
            );
            expect(tester.takeException(), isNull);
            final l = tester.getRect(find.byKey(_left));
            final r = tester.getRect(find.byKey(_right));
            final t = tester.getRect(_titleText);
            expect(t.left, greaterThanOrEqualTo(l.right));
            expect(t.right, lessThanOrEqualTo(r.left));
            expect(t.left, greaterThanOrEqualTo(0));
            expect(t.right, lessThanOrEqualTo(size.width));
          },
        );
      }
    }

    testWidgets('title is exposed as a header to assistive technology', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpHeader(
        tester,
        size: const Size(800, 600),
        schoolLogo: _box(_left, 32),
        appLogo: _box(_right, 32),
      );
      expect(
        tester.getSemantics(find.text('Students')),
        matchesSemantics(label: 'Students', isHeader: true),
      );
      handle.dispose();
    });
  });

  group('SchoolBrandingAppBar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      SchoolBranding? branding,
      String? screenTitle,
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [schoolBrandingProvider.overrideWithValue(branding)],
          child: MaterialApp(
            home: Scaffold(
              appBar: SchoolBrandingAppBar(
                screenTitle: screenTitle,
                actions: const [
                  IconButton(
                    key: Key('bell'),
                    onPressed: null,
                    icon: Icon(Icons.notifications),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    const school = SchoolBranding(
      schoolId: 's1',
      name: 'Rosewood High School',
      logoUrl: 'https://cdn.example.com/s1.png',
    );

    testWidgets('dashboard: school name in the centre, no screen title', (
      tester,
    ) async {
      await pumpBar(tester, branding: school);
      expect(find.text('Rosewood High School'), findsOneWidget);
      expect(
        tester.getRect(find.text('Rosewood High School')).center.dx,
        closeTo(195, 40),
      );
    });

    testWidgets('module screen: the title replaces the school name (no '
        'duplicate)', (tester) async {
      await pumpBar(
        tester,
        branding: school,
        screenTitle: 'Staff and Teachers',
      );
      expect(find.text('Staff and Teachers'), findsOneWidget);
      expect(find.text('Rosewood High School'), findsNothing);
    });

    testWidgets('school logo left of the title, app mark right of it, then the '
        'actions', (tester) async {
      await pumpBar(tester, branding: school, screenTitle: 'Students');
      final logo = tester.getRect(find.byType(SchoolLogoImage));
      final title = tester.getRect(find.text('Students'));
      final bell = tester.getRect(find.byKey(const Key('bell')));
      expect(logo.right, lessThanOrEqualTo(title.left));
      expect(title.right, lessThanOrEqualTo(bell.left));
      expect(bell.right, lessThanOrEqualTo(390));
      // Two images: the school's logo and the product mark.
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('school without a logo: the initial badge, not a second '
        'EazySchool mark', (tester) async {
      await pumpBar(
        tester,
        branding: const SchoolBranding(schoolId: 's2', name: 'Maple School'),
        screenTitle: 'Parents',
      );
      expect(find.text('M'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget); // only the product mark
    });

    testWidgets('no branding yet (loading / signed out): falls back to the '
        'product name, bar keeps its height', (tester) async {
      await pumpBar(tester);
      expect(find.text('EazySchool 360'), findsOneWidget);
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dead logo URL never breaks the bar', (tester) async {
      await pumpBar(tester, branding: school, screenTitle: 'Exams');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Exams'), findsOneWidget);
    });

    testWidgets('changing tenant changes the branding in place', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final branding = NotifierProvider<_Current, SchoolBranding?>(
        _Current.new,
      );
      final container = ProviderContainer(
        overrides: [
          schoolBrandingProvider.overrideWith((ref) => ref.watch(branding)),
          // The header also hosts the branch switcher, which reads the tenant.
          tenantContextProvider.overrideWith(_NoTenant.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(appBar: SchoolBrandingAppBar()),
          ),
        ),
      );
      expect(find.text('Rosewood High School'), findsOneWidget);
      container
          .read(branding.notifier)
          .set(const SchoolBranding(schoolId: 's9', name: 'Other School'));
      await tester.pump();
      expect(find.text('Other School'), findsOneWidget);
      expect(find.text('Rosewood High School'), findsNothing);
    });
  });

  group('SchoolEmblem (dashboard hero)', () {
    Future<void> pumpEmblem(WidgetTester tester, SchoolBranding? b) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [schoolBrandingProvider.overrideWithValue(b)],
            child: const MaterialApp(
              home: Scaffold(body: Center(child: SchoolEmblem(size: 56))),
            ),
          ),
        );

    testWidgets('school with a logo: only the school logo, square, no product '
        'mark beside it', (tester) async {
      await pumpEmblem(
        tester,
        const SchoolBranding(
          schoolId: 's1',
          name: 'Rosewood',
          logoUrl: 'https://cdn.example.com/s1.png',
        ),
      );
      expect(find.byType(SchoolLogoImage), findsOneWidget);
      expect(tester.getSize(find.byType(SchoolLogoImage)), const Size(56, 56));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('school without a logo: its initial, never the product mark', (
      tester,
    ) async {
      await pumpEmblem(
        tester,
        const SchoolBranding(schoolId: 's2', name: 'Maple School'),
      );
      expect(find.text('M'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('screenTitleForPath', () {
    test('the dashboard has no module title (the school name is shown)', () {
      expect(screenTitleForPath('/dashboard'), isNull);
      expect(screenTitleForPath('/'), isNull);
    });

    test('top-level modules', () {
      expect(screenTitleForPath('/students'), 'Students');
      expect(screenTitleForPath('/parents'), 'Parents');
      expect(screenTitleForPath('/staff'), 'Staff and Teachers');
      expect(screenTitleForPath('/attendance'), 'Attendance');
      expect(screenTitleForPath('/timetable'), 'Timetable');
      expect(screenTitleForPath('/homework'), 'Homework');
      expect(screenTitleForPath('/exams'), 'Exams');
      expect(screenTitleForPath('/fees'), 'Fees Management');
      expect(screenTitleForPath('/settings'), 'School Settings');
      expect(screenTitleForPath('/users'), 'User Management');
    });

    test('nested screens inherit their module; reports are their own', () {
      expect(screenTitleForPath('/fees/invoices/abc'), 'Fees Management');
      expect(screenTitleForPath('/students/new'), 'Students');
      expect(screenTitleForPath('/settings/classes'), 'School Settings');
      expect(screenTitleForPath('/fees/reports'), 'Fee Reports');
      expect(screenTitleForPath('/attendance/reports'), 'Attendance Reports');
      expect(screenTitleForPath('/leave/reports'), 'Leave Reports');
      expect(screenTitleForPath('/fees/'), 'Fees Management');
    });

    test('a prefix must be a whole path segment', () {
      expect(screenTitleForPath('/feesxyz'), isNull);
      expect(screenTitleForPath('/students-archive'), isNull);
    });

    test('parent and teacher self-service screens', () {
      expect(screenTitleForPath('/my-fees/receipts/1'), 'My Fees');
      expect(screenTitleForPath('/my-homework'), 'My Homework');
      expect(screenTitleForPath('/my-results'), 'My Results');
      expect(screenTitleForPath('/my-timetable'), 'My Timetable');
      expect(screenTitleForPath('/my-profile'), 'My Profile');
    });
  });
}

class _NoTenant extends TenantContextNotifier {
  @override
  Future<TenantContext?> build() async => null;
}
