import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/calendar_providers.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
import '../support/fakes.dart';
import '../support/school_year_fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  phone: '+91 98765 43210',
  addressLine1: '12 Boulevard',
  city: 'Chennai',
  status: SchoolStatus.active,
);

final _year = AcademicYear(
  academicYearId: 'y26',
  schoolId: 'school-1',
  branchId: 'main',
  name: '2026-27',
  startDate: DateTime(2026, 6, 1),
  endDate: DateTime(2027, 3, 31),
  status: AcademicYearStatus.active,
);

/// Mon-Fri and Saturday work; only Sunday is off.
WorkingDays _sundayOff({bool configured = false}) => WorkingDays(
  schoolId: 'school-1',
  branchId: 'main',
  isWorkingDay: {for (final d in Weekday.values) d: d != Weekday.sunday},
  updatedAt: configured ? DateTime(2026, 6, 1) : null,
  updatedBy: configured ? 'uid-0' : null,
);

Future<void> _pump(
  WidgetTester tester,
  FakeCalendarRepository calendar, {
  UserRole role = UserRole.schoolAdmin,
  Size size = const Size(1200, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: role,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school},
          branches: {
            'school-1/main': const Branch(
              branchId: 'main',
              schoolId: 'school-1',
              name: 'Main Branch',
              code: 'MAIN',
              city: 'Chennai',
              status: BranchStatus.active,
            ),
          },
        ),
      ),
      academicStructureRepositoryProvider.overrideWithValue(
        FakeAcademicStructureRepository(years: [_year]),
      ),
      calendarRepositoryProvider.overrideWithValue(calendar),
      schoolYearRepositoryProvider.overrideWithValue(
        FakeSchoolYearRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.settingsWorkingDays);
  await tester.pumpAndSettle();
}

Finder _save() => find.widgetWithText(FilledButton, 'Save');
String _summary(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('weeklyOffSummary'))).data!;

void main() {
  group('weekly offs page', () {
    testWidgets('shows the saved weekly offs in words', (tester) async {
      await _pump(tester, FakeCalendarRepository(workingDays: _sundayOff()));
      expect(find.text('Weekly offs'), findsWidgets);
      expect(_summary(tester), 'Sunday');
      expect(
        tester
            .widget<RadioListTile<Object?>>(
              find.byKey(const ValueKey('sat-working')),
            )
            .checked,
        isTrue,
      );
      // Nothing to save until something changes.
      expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
    });

    testWidgets('alternate Saturdays: 2nd and 4th, saved as off-weeks', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await _pump(tester, calendar);
      await tester.tap(find.byKey(const ValueKey('sat-alternate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alternate')), findsOneWidget);
      // alternate defaults to 1st/3rd/5th; switch to 2nd/4th
      await tester.tap(find.text('2nd, 4th'));
      await tester.pumpAndSettle();
      expect(_summary(tester), 'Sunday · 2nd, 4th Saturday');
      await tester.tap(_save());
      await tester.pumpAndSettle();
      expect(calendar.savedWorkingDays, hasLength(1));
      final saved = calendar.savedWorkingDays.single;
      expect(saved.saturdayOffWeeks, {2, 4});
      expect(saved.isWorkingDay[Weekday.saturday], isTrue);
      expect(saved.isWorkingDay[Weekday.sunday], isFalse);
      expect(find.textContaining('Weekly offs saved'), findsOneWidget);
    });

    testWidgets('selected Saturdays: any combination of the five', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await _pump(tester, calendar);
      await tester.tap(find.byKey(const ValueKey('sat-selected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('week-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('week-3')));
      await tester.pumpAndSettle();
      expect(_summary(tester), 'Sunday · 1st, 3rd Saturday');
      await tester.tap(_save());
      await tester.pumpAndSettle();
      expect(calendar.savedWorkingDays.single.saturdayOffWeeks, {1, 3});
    });

    testWidgets('selected Saturdays with none chosen is refused', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await _pump(tester, calendar);
      await tester.tap(find.byKey(const ValueKey('sat-selected')));
      await tester.pumpAndSettle();
      // the rhythm is unchanged (nothing selected = all Saturdays work), so
      // make a real change first, then try to save with no Saturday chosen
      await tester.tap(find.byKey(const ValueKey('day-friday')));
      await tester.pumpAndSettle();
      await tester.tap(_save());
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Choose at least one Saturday'),
        findsOneWidget,
      );
      expect(calendar.savedWorkingDays, isEmpty);
    });

    testWidgets('every Saturday hides the per-Saturday choices', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await _pump(tester, calendar);
      await tester.tap(find.byKey(const ValueKey('sat-selected')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('week-2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sat-off')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('week-2')), findsNothing);
      expect(find.byKey(const ValueKey('alternate')), findsNothing);
      expect(_summary(tester), 'Sunday · Every Saturday');
      await tester.tap(_save());
      await tester.pumpAndSettle();
      final saved = calendar.savedWorkingDays.single;
      expect(saved.isWorkingDay[Weekday.saturday], isFalse);
      expect(saved.saturdayOffWeeks, isEmpty); // nothing ambiguous is stored
    });

    testWidgets('Cancel restores the saved weekly offs', (tester) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await _pump(tester, calendar);
      await tester.tap(find.byKey(const ValueKey('day-wednesday')));
      await tester.pumpAndSettle();
      expect(_summary(tester), 'Wednesday · Sunday');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(_summary(tester), 'Sunday');
      expect(calendar.savedWorkingDays, isEmpty);
    });

    testWidgets('a failed save keeps the edit and says why', (tester) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await _pump(tester, calendar);
      await tester.tap(find.byKey(const ValueKey('sat-off')));
      await tester.pumpAndSettle();
      calendar.error = const PermissionFailure(); // the page has loaded
      await tester.tap(_save());
      await tester.pumpAndSettle();
      expect(find.textContaining('permission'), findsOneWidget);
      expect(find.textContaining('Weekly offs saved'), findsNothing);
      expect(_summary(tester), 'Sunday · Every Saturday'); // still editable
    });

    testWidgets('a configured branch picks the date a change takes effect', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(
        workingDays: _sundayOff(configured: true),
      );
      await _pump(tester, calendar);
      expect(find.text('Takes effect from'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sat-off')));
      await tester.pumpAndSettle();
      await tester.tap(_save());
      await tester.pumpAndSettle();
      final saved = calendar.savedWorkingDays.single;
      expect(saved.effectiveFrom, WorkingDays.keyOf(DateTime.now()));
      // the pattern it replaces is kept for earlier dates
      expect(saved.history, hasLength(1));
      expect(saved.history.single.isWorkingDay[Weekday.saturday], isTrue);
    });

    testWidgets('a branch that was never configured has nothing to preserve', (
      tester,
    ) async {
      await _pump(tester, FakeCalendarRepository(workingDays: _sundayOff()));
      expect(find.text('Takes effect from'), findsNothing);
    });

    testWidgets('a teacher sees the settings but cannot change them', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeCalendarRepository(workingDays: _sundayOff()),
        role: UserRole.teacher,
      );
      expect(find.byKey(const ValueKey('weeklyOffSummary')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(
        tester
            .widget<RadioListTile<Object?>>(
              find.byKey(const ValueKey('sat-off')),
            )
            .onChanged,
        isNull,
      );
    });

    for (final size in const [
      Size(360, 740),
      Size(768, 1024),
      Size(1400, 900),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        await _pump(
          tester,
          FakeCalendarRepository(workingDays: _sundayOff(configured: true)),
          size: size,
        );
        await tester.tap(find.byKey(const ValueKey('sat-selected')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('holidays page', () {
    Holiday vacation() {
      final now = DateTime.now();
      final start = DateTime.utc(now.year, now.month, now.day - 1);
      return Holiday(
        holidayId: 'vac',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'y26',
        date: start,
        endDate: start.add(const Duration(days: 4)),
        name: 'Summer vacation',
        type: HolidayType.vacation,
        status: ActivationStatus.active,
      );
    }

    Future<void> openHolidays(
      WidgetTester tester,
      FakeCalendarRepository calendar,
    ) async {
      await _pump(tester, calendar);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(App)),
      );
      container.read(appRouterProvider).go(AppRoutes.settingsHolidays);
      await tester.pumpAndSettle();
    }

    testWidgets('a vacation is listed with its range and length', (
      tester,
    ) async {
      await openHolidays(
        tester,
        FakeCalendarRepository(
          workingDays: _sundayOff(),
          holidays: [vacation()],
        ),
      );
      expect(find.text('Summer vacation'), findsOneWidget);
      expect(find.textContaining('5 days'), findsOneWidget);
      expect(find.textContaining('Vacation'), findsWidgets);
    });

    testWidgets('removing asks first, then keeps the record as inactive', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(
        workingDays: _sundayOff(),
        holidays: [vacation()],
      );
      await openHolidays(tester, calendar);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove this holiday?'), findsOneWidget);
      expect(calendar.updatedHolidays, isEmpty); // nothing yet
      await tester.tap(find.widgetWithText(TextButton, 'Keep it'));
      await tester.pumpAndSettle();
      expect(calendar.updatedHolidays, isEmpty);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(calendar.updatedHolidays, hasLength(1));
      final kept = calendar.updatedHolidays.single;
      expect(kept.status, ActivationStatus.inactive);
      expect(kept.name, 'Summer vacation'); // never deleted
      expect(kept.date, vacation().date); // untouched but for its status
      expect(find.text('Holiday removed.'), findsOneWidget);
    });

    testWidgets('a new holiday that overlaps an existing one asks first', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(
        workingDays: _sundayOff(),
        holidays: [vacation()],
      );
      await openHolidays(tester, calendar);
      await tester.tap(find.text('Add holiday'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Holiday name'),
        'Sports day',
      );
      // the dialog starts on today, which the vacation covers
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('This overlaps other holidays'), findsOneWidget);
      expect(find.textContaining('Summer vacation'), findsWidgets);
      expect(calendar.createdHolidays, isEmpty);

      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(calendar.createdHolidays, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();
      expect(calendar.createdHolidays, hasLength(1));
      expect(calendar.createdHolidays.single.name, 'Sports day');
      expect(calendar.holidays, hasLength(2)); // both records kept
    });

    testWidgets('a multi-day holiday asks for a last day', (tester) async {
      final calendar = FakeCalendarRepository(workingDays: _sundayOff());
      await openHolidays(tester, calendar);
      await tester.tap(find.text('Add holiday'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lastDay')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('multiDay')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lastDay')), findsOneWidget);
      expect(find.textContaining('First day'), findsWidgets);
    });

    testWidgets('the calendar marks weekly offs and holidays with a legend', (
      tester,
    ) async {
      final calendar = FakeCalendarRepository(
        workingDays: _sundayOff(),
        holidays: [vacation()],
      );
      await openHolidays(tester, calendar);
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendarLegend')), findsOneWidget);
      for (final label in const [
        'Working day',
        'Weekly off',
        'Public holiday',
        'Festival',
        'School holiday',
        'Vacation',
        'Special working day',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // month navigation
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
