import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/core/regional/school_time.dart';
import 'dart:convert';

import 'package:eazy_school_360/features/admission/domain/admission_activity.dart';
import 'package:eazy_school_360/features/admission/domain/admission_application.dart';
import 'package:eazy_school_360/features/admission/presentation/providers/document_picker.dart';
import 'package:eazy_school_360/features/admission/domain/admission_enquiry.dart';
import 'package:eazy_school_360/features/admission/domain/admission_fee.dart';
import 'package:eazy_school_360/features/admission/domain/admission_settings.dart';
import 'package:eazy_school_360/features/admission/domain/admission_status.dart';
import 'package:eazy_school_360/features/admission/presentation/providers/admission_providers.dart';
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

import '../support/admission_fakes.dart';
import '../support/fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';

/// A phone-width window tall enough to show a whole form without scrolling.
const _tall = Size(390, 3400);

final _year = AcademicYear(
  academicYearId: 'y1',
  schoolId: 'school-1',
  branchId: 'main',
  name: '2026-27',
  startDate: DateTime(2026, 6, 1),
  endDate: DateTime(2027, 3, 31),
  status: AcademicYearStatus.active,
);

const _class5 = SchoolClass(
  classId: 'c5',
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  name: 'Class 5',
  displayOrder: 1,
  status: ActivationStatus.active,
);

Future<FakeAdmissionRepository> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.branchAdmin,
  String path = '/admissions',
  Size size = const Size(390, 844),
  double textScale = 1.0,
  FakeAdmissionRepository? repo,
  FakeDocumentStore? store,
  DocumentPicker? picker,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final fake = repo ?? FakeAdmissionRepository();
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
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood High',
              email: 'office@rosewood.example',
              status: SchoolStatus.active,
            ),
          },
          branches: {
            'school-1/main': const Branch(
              branchId: 'main',
              schoolId: 'school-1',
              name: 'Main',
              status: BranchStatus.active,
            ),
          },
        ),
      ),
      academicStructureRepositoryProvider.overrideWithValue(
        FakeAcademicStructureRepository(years: [_year], classes: [_class5]),
      ),
      admissionRepositoryProvider.overrideWithValue(fake),
      admissionDocumentStoreProvider.overrideWithValue(
        store ?? FakeDocumentStore(),
      ),
      if (picker != null) documentPickerProvider.overrideWithValue(picker),
      assigneesProvider.overrideWith(
        (ref, key) async => [(userId: 'u-staff', name: 'Ravi Menon')],
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(path);
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _fillValidForm(WidgetTester tester) async {
  Future<void> type(String label, String text) async {
    final f = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(f);
    await tester.enterText(f, text);
  }

  await type('First name *', 'Asha');
  await type('Last name', 'Nair');
  await type('Name *', 'Meena Nair');
  await type('Mobile *', '98765 43210');

  Future<void> pick(String label, String option) async {
    final f = find.widgetWithText(DropdownButtonFormField<String>, label);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  await pick('Academic year *', '2026-27');
  await pick('Interested class *', 'Class 5');
  await pick('Source *', 'Walk-in');
}

/// A school date [days] from today (the page uses the same clock).
String _day(int days) {
  final t = SchoolTime.today();
  return SchoolTime.keyOf(DateTime(t.year, t.month, t.day + days));
}

/// Chooses a fixed file (or nothing) without a platform dialog.
class _FakePicker implements DocumentPicker {
  PickedDocument? next;
  final List<bool> asked = [];
  @override
  Future<PickedDocument?> pick({required bool photoOnly}) async {
    asked.add(photoOnly);
    return next;
  }
}

List<int> _bytes(int n) => List<int>.filled(n, 7);

/// A button of any style (filled, tonal, outlined, text) carrying [label].
Finder _btn(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

void main() {
  group('dashboard', () {
    testWidgets(
      'shows the numbers and the way in; no settings for a branch admin',
      (tester) async {
        await _pump(tester);
        expect(find.text('Total enquiries'), findsOneWidget);
        expect(find.text('9'), findsOneWidget, reason: '3+2+1+2+1 enquiries');
        expect(find.text('All enquiries'), findsOneWidget);
        expect(find.text('New enquiry'), findsOneWidget);
        expect(find.text('Admission settings'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('conversion is confirmed ÷ all enquiries', (tester) async {
      await _pump(tester);
      expect(find.text('22%'), findsOneWidget, reason: '2 of 9');
    });

    testWidgets('a school admin also sees Admission settings', (tester) async {
      await _pump(tester, role: UserRole.schoolAdmin);
      expect(find.text('Admission settings'), findsOneWidget);
    });

    testWidgets('when the module is off: explained, no New enquiry', (
      tester,
    ) async {
      await _pump(
        tester,
        role: UserRole.schoolAdmin,
        repo: FakeAdmissionRepository(
          settings: const AdmissionSettings(enabled: false),
        ),
      );
      expect(find.text('Admissions are not switched on'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
      expect(find.text('New enquiry'), findsNothing);
      expect(find.text('Total enquiries'), findsNothing);
    });

    testWidgets('a branch admin is told who can switch it on', (tester) async {
      await _pump(
        tester,
        repo: FakeAdmissionRepository(
          settings: const AdmissionSettings(enabled: false),
        ),
      );
      expect(find.text('Admissions are not switched on'), findsOneWidget);
      expect(find.text('Open settings'), findsNothing);
    });
  });

  group('who can open it', () {
    for (final role in [UserRole.teacher, UserRole.finance, UserRole.parent]) {
      testWidgets('${role.name} has no Admissions entry and is turned away', (
        tester,
      ) async {
        await _pump(tester, role: role);
        expect(find.text('All enquiries'), findsNothing);
        expect(find.text('Total enquiries'), findsNothing);
        expect(find.byIcon(Icons.contact_phone_outlined), findsNothing);
      });
    }

    testWidgets('a branch admin cannot open the school-wide settings', (
      tester,
    ) async {
      await _pump(tester, path: '/admissions/settings');
      expect(find.text('Save settings'), findsNothing);
    });
  });

  group('enquiry list', () {
    testWidgets('lists enquiries as cards with status and contact', (
      tester,
    ) async {
      await _pump(
        tester,
        path: '/admissions/enquiries',
        repo: FakeAdmissionRepository(
          enquiries: [
            fakeEnquiry('1'),
            fakeEnquiry(
              '2',
              first: 'Ravi',
              last: 'Menon',
              status: AdmissionStatus.interested,
              duplicateOf: const ['1'],
            ),
          ],
        ),
      );
      expect(find.text('Asha Nair'), findsOneWidget);
      expect(find.text('Ravi Menon'), findsOneWidget);
      expect(find.text('New'), findsWidgets);
      expect(find.text('Interested'), findsWidgets);
      expect(find.text('Possible duplicate'), findsOneWidget);
      expect(find.textContaining('9876543210'), findsWidgets);
      expect(find.text('2 enquiries'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty list says how to start', (tester) async {
      await _pump(
        tester,
        path: '/admissions/enquiries',
        repo: FakeAdmissionRepository(enquiries: []),
      );
      expect(find.textContaining('No enquiries yet'), findsOneWidget);
    });

    testWidgets('search waits for a pause and is classified', (tester) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries',
        repo: FakeAdmissionRepository(
          enquiries: [
            fakeEnquiry('1'),
            fakeEnquiry('2', first: 'Ravi', last: 'Menon'),
          ],
        ),
      );
      final before = repo.fetchedSearches.length;
      await tester.enterText(find.byType(TextField).first, 'rav');
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.fetchedSearches.length, before, reason: 'debounced');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.fetchedSearches.last!.value, 'rav');
      expect(find.text('Ravi Menon'), findsOneWidget);
      expect(find.text('Asha Nair'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '+91 98765 43210');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.fetchedSearches.last!.value, '9876543210');
    });

    testWidgets('a status filter reaches the repository', (tester) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries',
        repo: FakeAdmissionRepository(
          enquiries: [
            fakeEnquiry('1'),
            fakeEnquiry(
              '2',
              first: 'Ravi',
              last: 'Menon',
              status: AdmissionStatus.interested,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<AdmissionStatus?>,
          'All statuses',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested').last);
      await tester.pumpAndSettle();
      expect(repo.fetchedFilters.last.status, AdmissionStatus.interested);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Nair'), findsNothing);
      expect(find.text('Ravi Menon'), findsOneWidget);
    });
  });

  group('new enquiry form', () {
    testWidgets('required fields are checked before anything is sent', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/new',
        size: _tall,
      );
      await tester.ensureVisible(find.text('Save enquiry'));
      await tester.tap(find.text('Save enquiry'));
      await tester.pumpAndSettle();
      expect(find.text('First name is required'), findsOneWidget);
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('Mobile is required'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('a filled form sends the details and nothing the server owns', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/new',
        size: _tall,
        repo: FakeAdmissionRepository(
          settings: const AdmissionSettings(enabled: true, version: 1),
        ),
      );
      await _fillValidForm(tester);

      await tester.ensureVisible(find.text('Save enquiry'));
      await tester.tap(find.text('Save enquiry'));
      await tester.pumpAndSettle();

      expect(repo.created, hasLength(1));
      final sent = repo.created.single.input;
      expect(sent.firstName, 'Asha');
      expect(sent.academicYearId, 'y1');
      expect(sent.interestedClassId, 'c5');
      expect(sent.source, 'Walk-in');
      expect(sent.guardians.single.phone, '98765 43210');
      expect(sent.toWire().containsKey('status'), isFalse);
    });

    testWidgets('a server refusal is shown and the form stays', (tester) async {
      final repo = FakeAdmissionRepository()
        ..failWith = StateError('not allowed');
      await _pump(
        tester,
        path: '/admissions/enquiries/new',
        size: _tall,
        repo: repo,
      );
      await _fillValidForm(tester);
      await tester.ensureVisible(find.text('Save enquiry'));
      await tester.tap(find.text('Save enquiry'));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      expect(find.text('Save enquiry'), findsOneWidget, reason: 'still here');
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('enquiry details', () {
    testWidgets('overview, duplicate warning and actions', (tester) async {
      await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [
            fakeEnquiry('1', duplicateOf: const ['7'], remarks: 'Call after 5'),
          ],
        ),
      );
      expect(find.text('Asha Nair'), findsWidgets);
      expect(find.text('ENQ-2026-00001'), findsWidgets);
      expect(find.text('Possible duplicate'), findsOneWidget);
      expect(find.text('Change status'), findsOneWidget);
      expect(find.text('Assign'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
      await tester.tap(find.text('Internal notes'));
      await tester.pumpAndSettle();
      expect(find.text('Call after 5'), findsOneWidget);
    });

    testWidgets('rejecting needs a reason, then sends it with the revision', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [fakeEnquiry('1', revision: 4)],
        ),
      );
      await tester.tap(find.text('Change status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rejected'));
      await tester.pumpAndSettle();
      FilledButton update() =>
          tester.widget(find.widgetWithText(FilledButton, 'Update'));
      expect(update().onPressed, isNull, reason: 'no reason yet');
      await tester.enterText(find.byType(TextField).last, 'Seats are full');
      await tester.pumpAndSettle();
      expect(update().onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      expect(repo.statusChanges, hasLength(1));
      final c = repo.statusChanges.single;
      expect(
        [c.id, c.status, c.reason, c.base],
        ['1', 'REJECTED', 'Seats are full', 4],
      );
    });

    testWidgets('only lead-stage options are offered; no jump to Approved', (
      tester,
    ) async {
      await _pump(tester, path: '/admissions/enquiries/1', size: _tall);
      await tester.tap(find.text('Change status'));
      await tester.pumpAndSettle();
      expect(find.text('Contacted'), findsOneWidget);
      expect(find.text('Approved'), findsNothing);
      expect(find.text('Admission confirmed'), findsNothing);
      expect(find.text('Visit scheduled'), findsNothing);
    });

    testWidgets('an enquiry on hold offers Resume back to where it was', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [
            fakeEnquiry(
              '1',
              status: AdmissionStatus.onHold,
              heldFrom: 'INTERESTED',
            ),
          ],
        ),
      );
      await tester.tap(find.text('Change status'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Resume (back to Interested)'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Resume'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Update'));
      await tester.pumpAndSettle();
      expect(repo.statusChanges.single.status, 'RESUME');
    });

    testWidgets('a closed enquiry cannot be changed, edited or reassigned', (
      tester,
    ) async {
      await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [fakeEnquiry('1', status: AdmissionStatus.rejected)],
        ),
      );
      expect(find.byTooltip('Edit'), findsNothing);
      FilledButton change() => tester.widget(
        find.ancestor(
          of: find.text('Change status'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(change().onPressed, isNull);
    });

    testWidgets('assigning picks a staff member', (tester) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
      );
      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ravi Menon'));
      await tester.pumpAndSettle();
      expect(repo.assigned.single, (id: '1', to: 'u-staff'));
    });

    testWidgets('status history is listed newest first', (tester) async {
      await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          history: const [
            StatusHistoryEntry(
              revision: 1,
              to: AdmissionStatus.newEnquiry,
              actorId: 'a',
            ),
            StatusHistoryEntry(
              revision: 2,
              from: AdmissionStatus.newEnquiry,
              to: AdmissionStatus.rejected,
              reason: 'Seats full',
              actorId: 'a',
            ),
          ],
        ),
      );
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.text('New → Rejected'), findsOneWidget);
      expect(find.textContaining('Reason: Seats full'), findsOneWidget);
      expect(find.text('Enquiry created (New)'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('a school admin saves the module switch and prefixes', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        path: '/admissions/settings',
        size: _tall,
        repo: FakeAdmissionRepository(
          settings: const AdmissionSettings(enabled: false, version: 2),
        ),
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enquiry prefix'),
        'adm',
      );
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(repo.savedSettings, hasLength(1));
      expect(repo.savedSettings.single.enabled, isTrue);
      expect(repo.savedSettings.single.enquiryPrefix, 'ADM');
      expect(repo.savedSettings.single.version, 2, reason: 'base version sent');
    });

    testWidgets('equal prefixes are refused before saving', (tester) async {
      final repo = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        path: '/admissions/settings',
        size: _tall,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Application prefix'),
        'ENQ',
      );
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(find.text('The two prefixes must differ'), findsWidgets);
      expect(repo.savedSettings, isEmpty);
    });

    testWidgets('sources can be added and removed', (tester) async {
      final repo = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        path: '/admissions/settings',
        size: _tall,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Add a source'),
        'Open day',
      );
      await tester.tap(find.byTooltip('Add source'));
      await tester.pumpAndSettle();
      expect(find.text('Open day'), findsOneWidget);
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(repo.savedSettings.single.sources, contains('Open day'));
    });
  });

  group('follow-ups dashboard', () {
    List<AdmissionActivity> sample() => [
      fakeActivity('a1', date: _day(0), time: '10:30', assignedTo: 'u-staff'),
      fakeActivity(
        'a2',
        date: _day(-2),
        type: ActivityType.whatsapp,
        student: 'Ravi Menon',
        enquiryId: '2',
      ),
      fakeActivity(
        'a3',
        date: _day(5),
        type: ActivityType.schoolVisit,
        student: 'Meena Pillai',
        enquiryId: '3',
      ),
      fakeActivity(
        'a4',
        date: _day(-9),
        status: ActivityStatus.completed,
        outcome: 'Visited',
        enquiryId: '4',
      ),
    ];

    testWidgets('the admission home summarises follow-ups and opens them', (
      tester,
    ) async {
      await _pump(tester, size: _tall);
      expect(find.text('Follow-ups'), findsOneWidget);
      expect(find.text('2 today'), findsOneWidget);
      expect(find.text('1 overdue'), findsOneWidget);
      await tester.tap(find.text('Follow-ups'));
      await tester.pumpAndSettle();
      expect(find.text('Today 2'), findsOneWidget);
    });

    testWidgets('chips show counts; today lists today\'s activities only', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/follow-ups',
        repo: FakeAdmissionRepository(activities: sample()),
      );
      for (final chip in [
        'Today 2',
        'Overdue 1',
        'Upcoming 3',
        'Mine 0',
        'Unassigned 0',
        'Completed 0',
        'No follow-up 0',
      ]) {
        expect(find.text(chip), findsOneWidget, reason: chip);
      }
      expect(repo.fetchedBuckets.last, FollowUpBucket.today);
      expect(find.text('Phone call'), findsOneWidget);
      expect(find.textContaining('10:30 AM'), findsOneWidget);
      expect(find.text('Meena Pillai · ENQ-2026-00003'), findsNothing);
    });

    testWidgets(
      'overdue, upcoming, unassigned and completed each show their own',
      (tester) async {
        final repo = await _pump(
          tester,
          path: '/admissions/follow-ups',
          repo: FakeAdmissionRepository(activities: sample()),
        );
        await tester.tap(find.text('Overdue 1'));
        await tester.pumpAndSettle();
        expect(repo.fetchedBuckets.last, FollowUpBucket.overdue);
        expect(find.text('Ravi Menon · ENQ-2026-00002'), findsOneWidget);
        expect(find.text('Overdue'), findsWidgets, reason: 'badge on the card');

        await tester.tap(find.text('Upcoming 3'));
        await tester.pumpAndSettle();
        expect(find.text('Meena Pillai · ENQ-2026-00003'), findsOneWidget);
        expect(find.text('School visit'), findsOneWidget);

        await tester.tap(find.text('Unassigned 0'));
        await tester.pumpAndSettle();
        expect(repo.fetchedBuckets.last, FollowUpBucket.unassigned);
        expect(find.text('Ravi Menon · ENQ-2026-00002'), findsOneWidget);

        await tester.tap(find.text('Completed 0'));
        await tester.pumpAndSettle();
        expect(find.text('Outcome'), findsOneWidget);
        expect(find.text('Visited'), findsOneWidget);
      },
    );

    testWidgets('an empty bucket says so', (tester) async {
      await _pump(
        tester,
        path: '/admissions/follow-ups',
        repo: FakeAdmissionRepository(activities: const []),
      );
      expect(find.text('Nothing is due today.'), findsOneWidget);
    });

    testWidgets('open enquiries with no follow-up are listed separately', (
      tester,
    ) async {
      await _pump(
        tester,
        path: '/admissions/follow-ups',
        repo: FakeAdmissionRepository(
          enquiries: [
            fakeEnquiry('1'),
            fakeEnquiry(
              '2',
              first: 'Ravi',
              last: 'Menon',
              nextFollowUp: _day(3),
            ),
            fakeEnquiry(
              '3',
              first: 'Closed',
              last: 'One',
              status: AdmissionStatus.rejected,
            ),
          ],
        ),
      );
      await tester.tap(find.text('No follow-up 0'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Nair'), findsOneWidget);
      expect(find.text('Ravi Menon'), findsNothing, reason: 'has a follow-up');
      expect(
        find.text('Closed One'),
        findsNothing,
        reason: 'closed enquiries are not chased',
      );
    });

    testWidgets('a card opens its enquiry', (tester) async {
      await _pump(
        tester,
        path: '/admissions/follow-ups',
        repo: FakeAdmissionRepository(activities: sample()),
      );
      await tester.tap(find.text('Phone call'));
      await tester.pumpAndSettle();
      expect(find.text('Change status'), findsOneWidget);
    });
  });

  group('activities on an enquiry', () {
    Future<FakeAdmissionRepository> open(
      WidgetTester tester, {
      List<AdmissionActivity>? activities,
      AdmissionStatus status = AdmissionStatus.newEnquiry,
    }) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [fakeEnquiry('1', status: status)],
          activities: activities ?? [],
        ),
      );
      await tester.tap(find.text('Activities'));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> pickToday(WidgetTester tester, String field) async {
      await tester.tap(find.text(field));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('no activities yet: an invitation and the schedule button', (
      tester,
    ) async {
      await open(tester);
      expect(find.textContaining('No follow-ups yet'), findsOneWidget);
      expect(find.text('Schedule follow-up'), findsOneWidget);
    });

    testWidgets(
      'scheduling needs a date, then sends type, date and an idempotency key',
      (tester) async {
        final repo = await open(tester);
        await tester.tap(find.text('Schedule follow-up'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
        await tester.pumpAndSettle();
        expect(find.text('Pick a date'), findsOneWidget);
        expect(repo.scheduled, isEmpty);

        await pickToday(tester, 'Select date');
        await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
        await tester.pumpAndSettle();
        expect(repo.scheduled, hasLength(1));
        final s = repo.scheduled.single;
        expect(s.enquiryId, '1');
        expect(s.input.type, ActivityType.phoneCall);
        expect(s.input.scheduledDate, _day(0));
        expect(
          s.input.toWire().containsKey('assignedTo'),
          isFalse,
          reason: 'defaults to the enquiry assignee on the server',
        );
        expect(s.requestId, hasLength(20));
      },
    );

    testWidgets('every save gets its own idempotency key', (tester) async {
      final repo = await open(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Schedule follow-up'));
        await tester.pumpAndSettle();
        await pickToday(tester, 'Select date');
        await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
        await tester.pumpAndSettle();
      }
      expect(repo.scheduled.map((s) => s.requestId).toSet(), hasLength(2));
    });

    testWidgets(
      'an open activity offers all four actions; a finished one none',
      (tester) async {
        await open(
          tester,
          activities: [
            fakeActivity('a1', date: _day(2)),
            fakeActivity(
              'a2',
              date: _day(-3),
              status: ActivityStatus.completed,
              outcome: 'Spoke to mother',
            ),
            fakeActivity(
              'a3',
              date: _day(-4),
              status: ActivityStatus.cancelled,
            ),
          ],
        );
        for (final a in ['Complete', 'Reschedule', 'Reassign', 'Cancel']) {
          expect(_btn(a), findsOneWidget, reason: a);
        }
        expect(find.text('Spoke to mother'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
        expect(find.text('Cancelled'), findsWidgets);
      },
    );

    testWidgets('completing needs an outcome', (tester) async {
      final repo = await open(
        tester,
        activities: [fakeActivity('a1', date: _day(1), revision: 3)],
      );
      await tester.tap(_btn('Complete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark completed'));
      await tester.pumpAndSettle();
      expect(find.text('Please describe the outcome'), findsOneWidget);
      expect(repo.completed, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Outcome *'),
        'Wants to visit on Friday',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Parent feedback (optional)'),
        'Liked the labs',
      );
      await tester.tap(find.text('Mark completed'));
      await tester.pumpAndSettle();
      final c = repo.completed.single;
      expect(c.id, 'a1');
      expect(c.completion.outcome, 'Wants to visit on Friday');
      expect(c.completion.parentFeedback, 'Liked the labs');
      expect(c.next, isNull);
    });

    testWidgets('completing can plan the next contact in the same step', (
      tester,
    ) async {
      final repo = await open(
        tester,
        activities: [fakeActivity('a1', date: _day(1))],
      );
      await tester.tap(_btn('Complete'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Outcome *'),
        'Asked to call back',
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark completed'));
      await tester.pumpAndSettle();
      expect(
        find.text('Pick a date'),
        findsOneWidget,
        reason: 'the next date is required',
      );
      expect(repo.completed, isEmpty);
      await pickToday(tester, 'Select date');
      await tester.tap(find.text('Mark completed'));
      await tester.pumpAndSettle();
      expect(repo.completed.single.next!.scheduledDate, _day(0));
    });

    testWidgets(
      'rescheduling asks for a date and sends the activity revision',
      (tester) async {
        final repo = await open(
          tester,
          activities: [fakeActivity('a1', date: _day(1), revision: 4)],
        );
        await tester.tap(_btn('Reschedule'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Reschedule'));
        await tester.pumpAndSettle();
        expect(repo.rescheduled, isEmpty);
        await pickToday(tester, 'Select date');
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason (optional)'),
          'Parent travelling',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Reschedule'));
        await tester.pumpAndSettle();
        final r = repo.rescheduled.single;
        expect(
          [r.id, r.date, r.reason, r.base],
          ['a1', _day(0), 'Parent travelling', 4],
        );
      },
    );

    testWidgets('reassigning picks a person or nobody', (tester) async {
      final repo = await open(
        tester,
        activities: [fakeActivity('a1', date: _day(1))],
      );
      await tester.tap(_btn('Reassign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ravi Menon'));
      await tester.pumpAndSettle();
      expect(repo.reassigned.single, (id: 'a1', to: 'u-staff'));
    });

    testWidgets('cancelling requires a reason', (tester) async {
      final repo = await open(
        tester,
        activities: [fakeActivity('a1', date: _day(1))],
      );
      await tester.tap(_btn('Cancel'));
      await tester.pumpAndSettle();
      FilledButton go() =>
          tester.widget(find.widgetWithText(FilledButton, 'Cancel follow-up'));
      expect(go().onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'Family withdrew');
      await tester.pumpAndSettle();
      expect(go().onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel follow-up'));
      await tester.pumpAndSettle();
      expect(repo.cancelled.single, (id: 'a1', reason: 'Family withdrew'));
    });

    testWidgets(
      'a closed enquiry cannot be given new follow-ups or have them changed',
      (tester) async {
        await open(
          tester,
          status: AdmissionStatus.rejected,
          activities: [fakeActivity('a1', date: _day(1))],
        );
        FilledButton schedule() => tester.widget(
          find.ancestor(
            of: find.text('Schedule follow-up'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          ),
        );
        expect(schedule().onPressed, isNull);
        expect(_btn('Complete'), findsNothing);
      },
    );

    testWidgets('a server refusal is reported and nothing is claimed done', (
      tester,
    ) async {
      final repo = await open(
        tester,
        activities: [fakeActivity('a1', date: _day(1))],
      );
      repo.failWith = StateError('nope');
      await tester.tap(_btn('Reassign'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ravi Menon'));
      await tester.pumpAndSettle();
      expect(repo.reassigned, isEmpty);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Follow-up reassigned.'), findsNothing);
    });
  });

  group('school visits', () {
    Future<FakeAdmissionRepository> openVisits(
      WidgetTester tester, {
      List<AdmissionActivity>? activities,
      AdmissionStatus status = AdmissionStatus.newEnquiry,
      List<ActivityHistoryEntry> history = const [],
    }) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [fakeEnquiry('1', status: status)],
          activities: activities ?? [],
        )..activityHistory = [...history],
      );
      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<void> pickToday(WidgetTester tester, String field) async {
      await tester.tap(find.text(field));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('an enquiry with no visits invites booking one', (
      tester,
    ) async {
      await openVisits(tester);
      expect(find.textContaining('No school visits yet'), findsOneWidget);
      expect(find.text('Book visit'), findsOneWidget);
    });

    testWidgets(
      'booking asks for a purpose and a date, then sends a visit with a key',
      (tester) async {
        final repo = await openVisits(tester);
        await tester.tap(find.text('Book visit'));
        await tester.pumpAndSettle();
        expect(find.text('Book a school visit'), findsOneWidget);
        expect(find.text('Purpose *'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Book visit'));
        await tester.pumpAndSettle();
        expect(find.text('Pick a date'), findsOneWidget);
        expect(repo.visitsBooked, isEmpty);

        await tester.tap(find.text('Campus tour'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Meet the principal').last);
        await tester.pumpAndSettle();
        await pickToday(tester, 'Select date');
        await tester.tap(find.widgetWithText(FilledButton, 'Book visit'));
        await tester.pumpAndSettle();

        expect(repo.visitsBooked, hasLength(1));
        final v = repo.visitsBooked.single;
        expect(v.enquiryId, '1');
        expect(v.input.type, ActivityType.schoolVisit);
        expect(v.input.purpose, VisitPurpose.meetPrincipal);
        expect(v.input.scheduledDate, _day(0));
        expect(v.requestId, hasLength(20));
        expect(
          repo.scheduled,
          isEmpty,
          reason: 'not through the generic follow-up call',
        );
      },
    );

    testWidgets('visits and other follow-ups are listed on their own tabs', (
      tester,
    ) async {
      final repo = await openVisits(
        tester,
        activities: [
          fakeActivity(
            'v1',
            type: ActivityType.schoolVisit,
            purpose: VisitPurpose.assessment,
            date: _day(3),
          ),
          fakeActivity('c1', type: ActivityType.email, date: _day(1)),
        ],
      );
      expect(find.text('School visit · Assessment'), findsOneWidget);
      expect(find.text('Email'), findsNothing);
      await tester.tap(find.text('Activities'));
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('School visit · Assessment'), findsNothing);
      expect(repo.scheduled, isEmpty);
    });

    testWidgets('the follow-up dialog does not offer School visit as a type', (
      tester,
    ) async {
      await openVisits(tester);
      await tester.tap(find.text('Activities'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule follow-up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phone call'));
      await tester.pumpAndSettle();
      expect(find.text('Email'), findsWidgets);
      expect(find.text('School visit'), findsNothing);
    });

    testWidgets(
      'completing a visit asks for visit notes and sends them with parent feedback',
      (tester) async {
        final repo = await openVisits(
          tester,
          activities: [
            fakeActivity(
              'v1',
              type: ActivityType.schoolVisit,
              purpose: VisitPurpose.campusTour,
              date: _day(1),
              revision: 2,
            ),
          ],
        );
        await tester.tap(_btn('Complete'));
        await tester.pumpAndSettle();
        expect(find.text('Complete visit'), findsOneWidget);
        await tester.tap(find.text('Mark completed'));
        await tester.pumpAndSettle();
        expect(find.text('Please describe the outcome'), findsOneWidget);
        expect(repo.completed, isEmpty);
        await tester.enterText(
          find.widgetWithText(TextField, 'Visit notes *'),
          'Saw labs and the library',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Parent feedback (optional)'),
          'Very impressed',
        );
        await tester.tap(find.text('Mark completed'));
        await tester.pumpAndSettle();
        final c = repo.completed.single;
        expect(
          [c.id, c.completion.outcome, c.completion.parentFeedback],
          ['v1', 'Saw labs and the library', 'Very impressed'],
        );
      },
    );

    testWidgets('a visit can be rescheduled and cancelled with a reason', (
      tester,
    ) async {
      final repo = await openVisits(
        tester,
        activities: [
          fakeActivity(
            'v1',
            type: ActivityType.schoolVisit,
            purpose: VisitPurpose.counselling,
            date: _day(2),
            revision: 3,
          ),
        ],
      );
      await tester.tap(_btn('Reschedule'));
      await tester.pumpAndSettle();
      await pickToday(tester, 'Select date');
      await tester.tap(find.widgetWithText(FilledButton, 'Reschedule'));
      await tester.pumpAndSettle();
      expect(repo.rescheduled.single.base, 3);

      await tester.tap(_btn('Cancel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Family cannot attend',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel follow-up'));
      await tester.pumpAndSettle();
      expect(repo.cancelled.single, (id: 'v1', reason: 'Family cannot attend'));
    });

    testWidgets(
      'a finished visit shows its notes and feedback; a closed enquiry books no more',
      (tester) async {
        await openVisits(
          tester,
          status: AdmissionStatus.rejected,
          activities: [
            fakeActivity(
              'v1',
              type: ActivityType.schoolVisit,
              purpose: VisitPurpose.campusTour,
              status: ActivityStatus.completed,
              date: _day(-3),
              outcome: 'Toured the campus',
            ),
          ],
        );
        expect(find.text('Toured the campus'), findsOneWidget);
        FilledButton book() => tester.widget(
          find.ancestor(
            of: find.text('Book visit'),
            matching: find.byWidgetPredicate((w) => w is FilledButton),
          ),
        );
        expect(book().onPressed, isNull);
      },
    );

    testWidgets(
      'a server refusal (wrong status) is shown and nothing is claimed booked',
      (tester) async {
        final repo = await openVisits(tester);
        repo.failWith = StateError('no');
        await tester.tap(find.text('Book visit'));
        await tester.pumpAndSettle();
        await pickToday(tester, 'Select date');
        await tester.tap(find.widgetWithText(FilledButton, 'Book visit'));
        await tester.pumpAndSettle();
        expect(repo.visitsBooked, isEmpty);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Visit booked.'), findsNothing);
      },
    );

    testWidgets('the timeline lists status changes and visit events together', (
      tester,
    ) async {
      DateTime t(int m) => DateTime(2026, 11, 7, 10, m);
      await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo:
            FakeAdmissionRepository(
                enquiries: [
                  fakeEnquiry('1', status: AdmissionStatus.visitScheduled),
                ],
                history: [
                  StatusHistoryEntry(
                    revision: 1,
                    to: AdmissionStatus.newEnquiry,
                    actorId: 'a',
                    at: t(0),
                  ),
                  StatusHistoryEntry(
                    revision: 2,
                    from: AdmissionStatus.newEnquiry,
                    to: AdmissionStatus.visitScheduled,
                    reason: 'Visit scheduled',
                    actorId: 'a',
                    at: t(5),
                  ),
                ],
              )
              ..activityHistory = [
                ActivityHistoryEntry(
                  activityId: 'v1',
                  revision: 1,
                  event: ActivityEvent.created,
                  type: ActivityType.schoolVisit,
                  purpose: VisitPurpose.campusTour,
                  toDate: '2026-11-10',
                  toTime: '10:30',
                  actorId: 'a',
                  at: t(5),
                ),
                ActivityHistoryEntry(
                  activityId: 'v1',
                  revision: 2,
                  event: ActivityEvent.rescheduled,
                  type: ActivityType.schoolVisit,
                  purpose: VisitPurpose.campusTour,
                  fromDate: '2026-11-10',
                  toDate: '2026-11-18',
                  reason: 'Travelling',
                  actorId: 'a',
                  at: t(9),
                ),
              ],
      );
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.text('Enquiry created (New)'), findsOneWidget);
      expect(find.text('New → Visit scheduled'), findsOneWidget);
      expect(
        find.textContaining('School visit (campus tour) scheduled for'),
        findsOneWidget,
      );
      expect(find.textContaining('10:30 AM'), findsOneWidget);
      expect(find.textContaining('rescheduled from'), findsOneWidget);
      expect(find.textContaining('Reason: Travelling'), findsOneWidget);
    });

    testWidgets('the follow-up dashboard has a Visits list', (tester) async {
      final repo = await _pump(
        tester,
        path: '/admissions/follow-ups',
        repo: FakeAdmissionRepository(
          followUpCounts: const FollowUpCounts(today: 1, visits: 2),
          activities: [
            fakeActivity(
              'v1',
              type: ActivityType.schoolVisit,
              purpose: VisitPurpose.assessment,
              date: _day(2),
              student: 'Ravi Menon',
              enquiryId: '2',
            ),
            fakeActivity(
              'c1',
              type: ActivityType.email,
              date: _day(2),
              enquiryId: '3',
            ),
          ],
        ),
      );
      await tester.tap(find.text('Visits 2'));
      await tester.pumpAndSettle();
      expect(repo.fetchedBuckets.last, FollowUpBucket.visits);
      expect(find.text('School visit · Assessment'), findsOneWidget);
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('the admission home counts visits scheduled and completed', (
      tester,
    ) async {
      await _pump(
        tester,
        size: _tall,
        repo: FakeAdmissionRepository(
          counts: const {
            AdmissionStatus.visitScheduled: 4,
            AdmissionStatus.visitCompleted: 3,
            AdmissionStatus.newEnquiry: 1,
          },
        ),
      );
      expect(find.text('Visits scheduled'), findsOneWidget);
      expect(find.text('Visits completed'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });
  });

  group('applications', () {
    Future<FakeAdmissionRepository> open(
      WidgetTester tester, {
      AdmissionApplication? application,
      AdmissionStatus status = AdmissionStatus.interested,
      UserRole role = UserRole.schoolAdmin,
      AdmissionSettings settings = const AdmissionSettings(
        enabled: true,
        version: 1,
      ),
      List<ApplicationEvent> events = const [],
    }) async {
      final repo = await _pump(
        tester,
        role: role,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo:
            FakeAdmissionRepository(
                settings: settings,
                enquiries: [fakeEnquiry('1', status: status)],
              )
              ..application = application
              ..applicationEvents = [...events],
      );
      await tester.tap(find.text('Application'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('no application yet: it can be started from Interested', (
      tester,
    ) async {
      final repo = await open(tester);
      expect(find.text('No application yet'), findsOneWidget);
      await tester.tap(find.text('Start application'));
      await tester.pumpAndSettle();
      expect(repo.applicationCalls, ['create:1']);
    });

    testWidgets('from New it explains what must happen first', (tester) async {
      await open(tester, status: AdmissionStatus.newEnquiry);
      FilledButton start() => tester.widget(
        find.ancestor(
          of: find.text('Start application'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(start().onPressed, isNull);
      expect(
        find.textContaining('once the enquiry is Interested'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a draft shows its number and can be edited or submitted after confirming',
      (tester) async {
        final repo = await open(
          tester,
          application: fakeApplication('1', revision: 3),
        );
        expect(find.text('APP-2026-00001'), findsOneWidget);
        expect(find.text('Draft'), findsOneWidget);
        expect(find.text('Edit details'), findsOneWidget);
        await tester.tap(find.text('Submit application'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(
          repo.applicationCalls,
          isEmpty,
          reason: 'backing out sends nothing',
        );
        await tester.tap(find.text('Submit application'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
        await tester.pumpAndSettle();
        expect(repo.applicationCalls, ['submit:1:3']);
      },
    );

    testWidgets(
      'a submitted application is taken into review, and can be commented on',
      (tester) async {
        final repo = await open(
          tester,
          application: fakeApplication(
            '1',
            status: ApplicationStatus.submitted,
          ),
        );
        await tester.tap(find.text('Start review'));
        await tester.pumpAndSettle();
        expect(repo.reviews.single.action, 'START');
        await tester.tap(find.text('Add comment'));
        await tester.pumpAndSettle();
        FilledButton add() =>
            tester.widget(find.widgetWithText(FilledButton, 'Add comment'));
        expect(add().onPressed, isNull);
        await tester.enterText(find.byType(TextField).last, 'Parent called');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Add comment'));
        await tester.pumpAndSettle();
        expect(repo.reviews.last, (
          action: 'COMMENT',
          comment: 'Parent called',
        ));
      },
    );

    testWidgets(
      'a school admin approves after confirming, or rejects with a reason',
      (tester) async {
        final repo = await open(
          tester,
          application: fakeApplication(
            '1',
            status: ApplicationStatus.underReview,
            revision: 6,
          ),
        );
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
        await tester.pumpAndSettle();
        expect(repo.decisions.single.decision, 'APPROVE');

        await tester.tap(_btn('Reject'));
        await tester.pumpAndSettle();
        FilledButton go() => tester.widget(
          find.widgetWithText(FilledButton, 'Reject application'),
        );
        expect(go().onPressed, isNull, reason: 'a reason is required');
        await tester.enterText(find.byType(TextField).last, 'Seats are full');
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Reject application'),
        );
        await tester.pumpAndSettle();
        expect(repo.decisions.last, (
          decision: 'REJECT',
          comment: 'Seats are full',
        ));
      },
    );

    testWidgets('a branch admin cannot decide unless the school allows it', (
      tester,
    ) async {
      await open(
        tester,
        role: UserRole.branchAdmin,
        application: fakeApplication(
          '1',
          status: ApplicationStatus.underReview,
        ),
      );
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(
        find.textContaining('A school administrator decides'),
        findsOneWidget,
      );
      expect(
        find.text('Add comment'),
        findsOneWidget,
        reason: 'comments are still open to them',
      );
    });

    testWidgets(
      'where the school allows it a branch admin can approve and reject',
      (tester) async {
        await open(
          tester,
          role: UserRole.branchAdmin,
          settings: const AdmissionSettings(
            enabled: true,
            version: 1,
            branchAdminsMayApprove: true,
          ),
          application: fakeApplication(
            '1',
            status: ApplicationStatus.underReview,
          ),
        );
        expect(find.text('Approve'), findsOneWidget);
        expect(find.text('Reject'), findsOneWidget);
        expect(
          find.textContaining('A school administrator decides'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a decided application offers no further actions and shows the decision note',
      (tester) async {
        await open(
          tester,
          application: fakeApplication(
            '1',
            status: ApplicationStatus.rejected,
            decisionComment: 'Seats are full',
          ),
        );
        expect(find.text('Rejected'), findsOneWidget);
        expect(find.textContaining('Seats are full'), findsOneWidget);
        for (final a in [
          'Approve',
          'Reject',
          'Submit application',
          'Start review',
          'Add comment',
          'Edit details',
        ]) {
          expect(find.text(a), findsNothing, reason: a);
        }
      },
    );

    testWidgets('a server refusal is shown and nothing is claimed done', (
      tester,
    ) async {
      final repo = await open(tester, application: fakeApplication('1'));
      repo.failWith = StateError('no');
      await tester.tap(find.text('Submit application'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Application submitted.'), findsNothing);
    });

    testWidgets('the timeline shows application and document events in words', (
      tester,
    ) async {
      DateTime t(int m) => DateTime(2026, 11, 7, 10, m);
      await open(
        tester,
        application: fakeApplication(
          '1',
          status: ApplicationStatus.submitted,
          revision: 4,
        ),
        events: [
          ApplicationEvent(
            revision: 1,
            event: 'CREATED',
            actorId: 'a',
            at: t(0),
          ),
          ApplicationEvent(
            revision: 2,
            event: 'DOCUMENT_UPLOADED',
            documentType: 'BIRTH_CERTIFICATE',
            actorId: 'a',
            at: t(2),
          ),
          ApplicationEvent(
            revision: 3,
            event: 'DOCUMENT_REJECTED',
            documentType: 'BIRTH_CERTIFICATE',
            comment: 'Blurred',
            actorId: 'a',
            at: t(3),
          ),
          ApplicationEvent(
            revision: 4,
            event: 'SUBMITTED',
            actorId: 'a',
            at: t(4),
          ),
        ],
      );
      await tester.tap(find.text('Timeline'));
      await tester.pumpAndSettle();
      expect(find.text('Application started'), findsOneWidget);
      expect(find.text('Birth certificate uploaded'), findsOneWidget);
      expect(find.text('Birth certificate rejected'), findsOneWidget);
      expect(find.textContaining('Note: Blurred'), findsOneWidget);
      expect(find.text('Application submitted'), findsOneWidget);
    });
  });

  group('application list and edit form', () {
    testWidgets(
      'the list shows counts per status, filters, and opens the enquiry',
      (tester) async {
        final repo = await _pump(
          tester,
          path: '/admissions/applications',
          repo: FakeAdmissionRepository()
            ..application = fakeApplication(
              '1',
              status: ApplicationStatus.underReview,
            )
            ..applicationCounts = {
              ApplicationStatus.underReview: 1,
              ApplicationStatus.draft: 2,
            },
        );
        expect(find.text('All 3'), findsOneWidget);
        expect(find.text('Draft 2'), findsOneWidget);
        expect(find.text('Under review 1'), findsOneWidget);
        expect(find.text('Asha Nair'), findsOneWidget);
        expect(find.text('APP-2026-00001 · ENQ-2026-00001'), findsOneWidget);
        await tester.tap(find.text('Draft 2'));
        await tester.pumpAndSettle();
        expect(repo.fetchedApplicationStatuses.last, ApplicationStatus.draft);
        expect(find.text('No applications here yet.'), findsOneWidget);
      },
    );

    testWidgets('the admission home links to the applications', (tester) async {
      await _pump(tester, size: _tall);
      await tester.tap(find.text('Applications'));
      await tester.pumpAndSettle();
      expect(find.textContaining('All'), findsWidgets);
    });

    testWidgets('editing a draft sends the changed details with the revision', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1/application/edit',
        size: _tall,
        repo: FakeAdmissionRepository()
          ..application = fakeApplication('1', revision: 5),
      );
      expect(find.text('Edit application APP-2026-00001'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'First name *'),
        'Asha Rose',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes for the reviewer'),
        'Sibling in Class 7',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.applicationCalls, ['update:1:5']);
      final sent = repo.applicationUpdates.single;
      expect(sent.details.firstName, 'Asha Rose');
      expect(sent.details.guardians.first.phone, '9876543210');
      expect(sent.submissionNotes, 'Sibling in Class 7');
      expect(sent.toWire().containsKey('status'), isFalse);
    });

    testWidgets('required fields are checked before anything is sent', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1/application/edit',
        size: _tall,
        repo: FakeAdmissionRepository()..application = fakeApplication('1'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'First name *'),
        '',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('First name is required'), findsOneWidget);
      expect(repo.applicationUpdates, isEmpty);
    });

    testWidgets('a submitted application cannot be edited', (tester) async {
      await _pump(
        tester,
        path: '/admissions/enquiries/1/application/edit',
        size: _tall,
        repo: FakeAdmissionRepository()
          ..application = fakeApplication(
            '1',
            status: ApplicationStatus.submitted,
          ),
      );
      expect(
        find.text('Only a draft application can be edited.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
    });
  });

  group('documents', () {
    setUp(() => AdmissionWriteController.uploadRetryDelay = Duration.zero);
    tearDown(
      () => AdmissionWriteController.uploadRetryDelay = const Duration(
        seconds: 2,
      ),
    );

    Future<
      ({
        FakeAdmissionRepository repo,
        FakeDocumentStore store,
        _FakePicker picker,
      })
    >
    open(
      WidgetTester tester, {
      AdmissionApplication? application,
      List<AdmissionDocument> documents = const [],
      UserRole role = UserRole.schoolAdmin,
      AdmissionSettings settings = const AdmissionSettings(
        enabled: true,
        version: 1,
      ),
      Size size = _tall,
    }) async {
      final store = FakeDocumentStore();
      final picker = _FakePicker();
      final repo = await _pump(
        tester,
        role: role,
        path: '/admissions/enquiries/1',
        size: size,
        store: store,
        picker: picker,
        repo:
            FakeAdmissionRepository(
                settings: settings,
                enquiries: [
                  fakeEnquiry(
                    '1',
                    status: AdmissionStatus.applicationSubmitted,
                  ),
                ],
              )
              ..application =
                  application ??
                  fakeApplication('1', status: ApplicationStatus.underReview)
              ..documents = [...documents],
      );
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      return (repo: repo, store: store, picker: picker);
    }

    testWidgets('documents belong to the application', (tester) async {
      final repo = await _pump(
        tester,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo: FakeAdmissionRepository(enquiries: [fakeEnquiry('1')]),
      );
      expect(repo.application, isNull);
      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Start the application first'),
        findsOneWidget,
      );
    });

    testWidgets(
      'every document type is listed, required ones marked, with the progress line',
      (tester) async {
        await open(tester);
        for (final label in builtInDocumentTypes.values) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        expect(find.text('Required'), findsNWidgets(2));
        expect(
          find.textContaining('0 of 2 required documents verified'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Still needed: Birth certificate, Student photograph',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('progress follows verification; all verified says so', (
      tester,
    ) async {
      await open(
        tester,
        documents: [
          fakeDocument('d1', status: DocumentStatus.verified),
          fakeDocument(
            'd2',
            type: 'STUDENT_PHOTO',
            fileName: 'p.png',
            contentType: 'image/png',
            status: DocumentStatus.uploaded,
          ),
        ],
      );
      expect(
        find.textContaining('1 of 2 required documents verified'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Still needed: Student photograph'),
        findsOneWidget,
      );
    });

    testWidgets('all required verified', (tester) async {
      await open(
        tester,
        documents: [
          fakeDocument('d1', status: DocumentStatus.verified),
          fakeDocument(
            'd2',
            type: 'STUDENT_PHOTO',
            fileName: 'p.png',
            contentType: 'image/png',
            status: DocumentStatus.verified,
          ),
        ],
      );
      expect(
        find.text('All 2 required documents are verified.'),
        findsOneWidget,
      );
    });

    testWidgets('the school can require nothing, or its own types', (
      tester,
    ) async {
      await open(
        tester,
        settings: const AdmissionSettings(
          enabled: true,
          version: 1,
          requiredDocumentTypes: [],
        ),
      );
      expect(find.text('This school requires no documents.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a school-defined type appears with its label', (tester) async {
      await open(
        tester,
        settings: const AdmissionSettings(
          enabled: true,
          version: 1,
          customDocumentTypes: [
            CustomDocumentType(id: 'CASTE_CERT', label: 'Caste certificate'),
          ],
          requiredDocumentTypes: ['CASTE_CERT'],
        ),
      );
      expect(find.text('Caste certificate'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });

    testWidgets(
      'uploading: ask, put the bytes at the approved path, then confirm',
      (tester) async {
        final w = await open(tester);
        w.picker.next = PickedDocument('birth.pdf', _bytes(1000));
        await tester.tap(_btn('Upload').first);
        await tester.pumpAndSettle();
        final r = w.repo.uploadRequests.single;
        expect(
          [r.type, r.fileName, r.contentType, r.size],
          ['BIRTH_CERTIFICATE', 'birth.pdf', 'application/pdf', 1000],
        );
        expect(r.requestId, hasLength(20));
        expect(
          w.store.uploads.single.path,
          'schools/school-1/branches/main/admissionDocs/1/doc-new/document.pdf',
        );
        expect(
          [w.store.uploads.single.size, w.store.uploads.single.contentType],
          [1000, 'application/pdf'],
        );
        expect(w.repo.confirmedDocuments, ['doc-new']);
        expect(w.picker.asked, [false]);
        expect(find.text('Document uploaded.'), findsOneWidget);
      },
    );

    testWidgets('a photograph is picked as an image only', (tester) async {
      final w = await open(tester);
      w.picker.next = PickedDocument('child.png', _bytes(500));
      await tester.tap(_btn('Upload').at(1));
      await tester.pumpAndSettle();
      expect(w.picker.asked, [true]);
      expect(w.repo.uploadRequests.single.type, 'STUDENT_PHOTO');
      expect(w.repo.uploadRequests.single.contentType, 'image/png');
    });

    testWidgets('a flaky network is retried before giving up', (tester) async {
      final w = await open(tester);
      w.store.failUploads = 2;
      w.picker.next = PickedDocument('birth.pdf', _bytes(100));
      await tester.tap(_btn('Upload').first);
      await tester.pumpAndSettle();
      expect(w.store.attempts, 3);
      expect(w.repo.confirmedDocuments, ['doc-new']);
      expect(
        w.repo.uploadRequests,
        hasLength(1),
        reason: 'one request, the same approved path every time',
      );
    });

    testWidgets(
      'if every attempt fails the document is not confirmed and the error is shown',
      (tester) async {
        final w = await open(tester);
        w.store.failUploads = 5;
        w.picker.next = PickedDocument('birth.pdf', _bytes(100));
        await tester.tap(_btn('Upload').first);
        await tester.pumpAndSettle();
        expect(w.store.attempts, 3);
        expect(w.repo.confirmedDocuments, isEmpty);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Document uploaded.'), findsNothing);
      },
    );

    testWidgets('a file the server cannot confirm is reported', (tester) async {
      final w = await open(tester);
      w.repo.confirmFailsWith = StateError('mismatch');
      w.picker.next = PickedDocument('birth.pdf', _bytes(100));
      await tester.tap(_btn('Upload').first);
      await tester.pumpAndSettle();
      expect(w.store.uploads, hasLength(1));
      expect(find.text('Document uploaded.'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets(
      'files that break the limits are stopped before anything is sent',
      (tester) async {
        final w = await open(tester);
        for (final f in [
          PickedDocument('big.pdf', _bytes(DocumentLimits.maxBytes + 1)),
          PickedDocument('empty.pdf', const []),
          PickedDocument('virus.exe', _bytes(10)),
        ]) {
          w.picker.next = f;
          await tester.tap(_btn('Upload').first);
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsOneWidget, reason: f.name);
          ScaffoldMessenger.of(
            tester.element(find.byType(Scaffold).first),
          ).clearSnackBars();
          await tester.pumpAndSettle();
        }
        w.picker.next = PickedDocument('photo.pdf', _bytes(10));
        await tester.tap(_btn('Upload').at(1));
        await tester.pumpAndSettle();
        expect(w.repo.uploadRequests, isEmpty);
        expect(w.store.attempts, 0);
      },
    );

    testWidgets('closing the picker uploads nothing', (tester) async {
      final w = await open(tester);
      await tester.tap(_btn('Upload').first);
      await tester.pumpAndSettle();
      expect(w.repo.uploadRequests, isEmpty);
    });

    testWidgets('verify, reject (with a reason) and remove', (tester) async {
      final w = await open(
        tester,
        documents: [
          fakeDocument('d1', revision: 4),
          fakeDocument('d2', type: 'ADDRESS_PROOF', fileName: 'bill.pdf'),
          fakeDocument(
            'd3',
            type: 'PREVIOUS_RECORDS',
            fileName: 'marks.pdf',
            status: DocumentStatus.verified,
          ),
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Verify').first);
      await tester.pumpAndSettle();
      expect(w.repo.documentDecisions.single, (
        id: 'd1',
        decision: 'VERIFY',
        reason: null,
        base: 4,
      ));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').last);
      await tester.pumpAndSettle();
      FilledButton go() =>
          tester.widget(find.widgetWithText(FilledButton, 'Reject document'));
      expect(go().onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'Not legible');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject document'));
      await tester.pumpAndSettle();
      expect(w.repo.documentDecisions.last, (
        id: 'd2',
        decision: 'REJECT',
        reason: 'Not legible',
        base: 2,
      ));

      expect(
        find.widgetWithText(FilledButton, 'Verify'),
        findsNWidgets(2),
        reason: 'a verified document has no Verify',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Remove').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove document'));
      await tester.pumpAndSettle();
      expect(w.repo.removedDocuments.single.id, 'd1');
    });

    testWidgets(
      'a rejected document shows its reason; removed and abandoned records are not listed',
      (tester) async {
        await open(
          tester,
          documents: [
            fakeDocument(
              'd1',
              status: DocumentStatus.rejected,
              rejectionReason: 'Blurred',
            ),
            fakeDocument(
              'd2',
              type: 'ADDRESS_PROOF',
              fileName: 'gone.pdf',
              status: DocumentStatus.removed,
            ),
            fakeDocument(
              'd3',
              type: 'ADDRESS_PROOF',
              fileName: 'failed.pdf',
              status: DocumentStatus.abandoned,
            ),
          ],
        );
        expect(find.text('Reason: Blurred'), findsOneWidget);
        expect(find.text('gone.pdf'), findsNothing);
        expect(find.text('failed.pdf'), findsNothing);
        expect(
          find.textContaining('0 of 2'),
          findsOneWidget,
          reason: 'a rejected document does not count',
        );
      },
    );

    testWidgets('once decided, documents can be viewed but not changed', (
      tester,
    ) async {
      await open(
        tester,
        application: fakeApplication('1', status: ApplicationStatus.approved),
        documents: [fakeDocument('d1', status: DocumentStatus.verified)],
      );
      expect(find.text('View'), findsOneWidget);
      for (final a in ['Upload', 'Verify', 'Reject', 'Remove']) {
        expect(find.text(a), findsNothing, reason: a);
      }
    });

    testWidgets(
      'viewing reads the bytes through the store (no link) and shows an image',
      (tester) async {
        final w = await open(
          tester,
          documents: [
            fakeDocument(
              'd1',
              type: 'STUDENT_PHOTO',
              fileName: 'child.png',
              contentType: 'image/png',
            ),
          ],
        );
        w.store.files['schools/school-1/branches/main/admissionDocs/1/d1/document.pdf'] =
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAHdRLkQAAAABJRU5ErkJggg==',
            );
        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();
        expect(find.text('Student photograph · child.png'), findsOneWidget);
        Finder shown() => find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Image),
        );
        expect(shown(), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(shown(), findsNothing);
      },
    );

    testWidgets('a file that cannot be read says so', (tester) async {
      final w = await open(tester, documents: [fakeDocument('d1')]);
      w.store.failReadWith = StateError('denied');
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
    });
  });

  group('application settings', () {
    testWidgets(
      'required documents, a new type and the approval switch are saved',
      (tester) async {
        final repo = await _pump(
          tester,
          role: UserRole.schoolAdmin,
          path: '/admissions/settings',
          size: const Size(390, 5200),
          repo: FakeAdmissionRepository(
            settings: const AdmissionSettings(enabled: true, version: 4),
          ),
        );
        await tester.tap(
          find.widgetWithText(CheckboxListTile, 'Address proof'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckboxListTile, 'Student photograph'),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Add a document type'),
          'Caste certificate',
        );
        await tester.tap(find.byTooltip('Add document type'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(CheckboxListTile, 'Caste certificate'),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            SwitchListTile,
            'Branch administrators may approve applications',
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save settings'));
        await tester.tap(find.text('Save settings'));
        await tester.pumpAndSettle();
        final saved = repo.savedSettings.single;
        expect(saved.requiredDocumentTypes, [
          'BIRTH_CERTIFICATE',
          'ADDRESS_PROOF',
          'CASTE_CERTIFICATE',
        ]);
        expect(saved.customDocumentTypes.single.id, 'CASTE_CERTIFICATE');
        expect(saved.customDocumentTypes.single.label, 'Caste certificate');
        expect(saved.branchAdminsMayApprove, isTrue);
        expect(saved.version, 4);
      },
    );
  });

  group('follow-up settings and the form', () {
    testWidgets('reminders can be switched off and the time chosen', (
      tester,
    ) async {
      final repo = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        path: '/admissions/settings',
        size: _tall,
        repo: FakeAdmissionRepository(
          settings: const AdmissionSettings(enabled: true, version: 5),
        ),
      );
      expect(find.text('Reminder time'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Daily follow-up reminders'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reminder time'), findsNothing);
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(repo.savedSettings.single.remindersEnabled, isFalse);
    });

    testWidgets('the reminder time is saved', (tester) async {
      final repo = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        path: '/admissions/settings',
        size: _tall,
      );
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Reminder time'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('18:00').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save settings'));
      await tester.tap(find.text('Save settings'));
      await tester.pumpAndSettle();
      expect(repo.savedSettings.single.reminderTime, '18:00');
    });

    testWidgets(
      'once follow-ups exist the edit form shows the derived date read-only',
      (tester) async {
        final repo = await _pump(
          tester,
          path: '/admissions/enquiries/1/edit',
          size: _tall,
          repo: FakeAdmissionRepository(
            enquiries: [
              fakeEnquiry(
                '1',
                nextFollowUp: '2026-11-20',
                activityCount: 2,
                openActivityCount: 1,
              ),
            ],
          ),
        );
        expect(
          find.textContaining('From the scheduled follow-ups'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(
          repo.updated.single.input.nextFollowUpDate,
          isNull,
          reason: 'the form does not send a date it does not own',
        );
      },
    );

    testWidgets('without follow-ups the manual date stays editable', (
      tester,
    ) async {
      await _pump(
        tester,
        path: '/admissions/enquiries/1/edit',
        size: _tall,
        repo: FakeAdmissionRepository(
          enquiries: [fakeEnquiry('1', nextFollowUp: '2026-11-20')],
        ),
      );
      expect(
        find.textContaining('From the scheduled follow-ups'),
        findsNothing,
      );
      expect(find.text('Next follow-up'), findsOneWidget);
    });
  });

  group('responsive layout', () {
    final pages = {
      'dashboard': '/admissions',
      'list': '/admissions/enquiries',
      'form': '/admissions/enquiries/new',
      'details': '/admissions/enquiries/1',
      'follow-ups': '/admissions/follow-ups',
      'applications': '/admissions/applications',
    };
    for (final (name, size, scale) in [
      ('small phone', const Size(320, 640), 1.0),
      ('small phone, large text', const Size(320, 640), 1.5),
      ('phone', const Size(390, 844), 1.0),
      ('tablet', const Size(820, 1180), 1.0),
      ('desktop', const Size(1440, 900), 1.0),
    ]) {
      for (final entry in pages.entries) {
        testWidgets('${entry.key} fits on $name', (tester) async {
          await _pump(
            tester,
            path: entry.value,
            size: size,
            textScale: scale,
            repo: FakeAdmissionRepository(
              enquiries: [
                fakeEnquiry(
                  '1',
                  first: 'Venkatasubramanian',
                  last: 'Ramachandran-Iyer',
                  duplicateOf: const ['2'],
                  nextFollowUp: '2026-11-20',
                ),
              ],
            ),
          );
          expect(tester.takeException(), isNull);
        });
      }
      testWidgets('settings fit on $name', (tester) async {
        await _pump(
          tester,
          role: UserRole.schoolAdmin,
          path: '/admissions/settings',
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('admission fees', () {
    AdmissionFee fee(
      FeeCategory c, {
      int amount = 100000,
      int paid = 0,
      int refunded = 0,
      AdmissionFeeStatus status = AdmissionFeeStatus.due,
    }) => AdmissionFee(
      id: '1__${c.wire}',
      category: c,
      currency: 'INR',
      amountMinor: amount,
      paidMinor: paid,
      refundedMinor: refunded,
      status: status,
    );

    Future<FakeAdmissionRepository> open(
      WidgetTester tester, {
      List<AdmissionFee> fees = const [],
      List<AdmissionFeePayment> payments = const [],
      UserRole role = UserRole.schoolAdmin,
      AdmissionStatus status = AdmissionStatus.interested,
    }) async {
      final repo = await _pump(
        tester,
        role: role,
        path: '/admissions/enquiries/1',
        size: _tall,
        repo:
            FakeAdmissionRepository(
                enquiries: [fakeEnquiry('1', status: status)],
              )
              ..fees = [...fees]
              ..feePayments = [...payments],
      );
      await tester.tap(find.text('Fees'));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('an enquiry with no fees shows every category as not set', (
      tester,
    ) async {
      await open(tester);
      for (final c in FeeCategory.values) {
        expect(find.text(c.label), findsOneWidget);
      }
      expect(find.text('Not set'), findsNWidgets(4));
      expect(_btn('Set amount'), findsNWidgets(4));
      expect(find.text('No payments recorded yet.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('setting an amount sends minor units', (tester) async {
      final repo = await open(tester);
      await tester.tap(_btn('Set amount').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '500');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.feeCalls, ['set APPLICATION 50000']);
    });

    testWidgets('a bad amount is refused before anything is sent', (
      tester,
    ) async {
      final repo = await open(tester);
      await tester.tap(_btn('Set amount').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'abc');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
      expect(repo.feeCalls, isEmpty);
    });

    testWidgets(
      'recording a payment sends one request id and shows the receipt',
      (tester) async {
        final repo = await open(tester, fees: [fee(FeeCategory.application)]);
        await tester.tap(_btn('Record payment'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '400');
        await tester.tap(find.text('Record').last);
        await tester.pumpAndSettle();
        expect(repo.recordedPayments, hasLength(1));
        expect(repo.recordedPayments.single['amountMinor'], 40000);
        expect(repo.recordedPayments.single['method'], 'CASH');
        expect(
          (repo.recordedPayments.single['requestId'] as String).length,
          greaterThan(8),
        );
        expect(find.textContaining('RCT-2026-000001'), findsOneWidget);
      },
    );

    testWidgets(
      'a payment above the balance or without a needed reference is refused',
      (tester) async {
        final repo = await open(
          tester,
          fees: [
            fee(
              FeeCategory.application,
              amount: 100000,
              paid: 60000,
              status: AdmissionFeeStatus.partial,
            ),
          ],
        );
        await tester.tap(_btn('Record payment'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '500');
        await tester.tap(find.text('Record').last);
        await tester.pumpAndSettle();
        expect(find.text('That is more than the balance due.'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, '100');
        await tester.tap(
          find.byType(DropdownButtonFormField<AdmissionPaymentMethod>),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('UPI').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Record').last);
        await tester.pumpAndSettle();
        expect(find.text('A reference is needed for UPI.'), findsOneWidget);
        expect(repo.recordedPayments, isEmpty);
      },
    );

    testWidgets(
      'a paid fee offers no payment; the payment list shows the receipt',
      (tester) async {
        await open(
          tester,
          fees: [
            fee(
              FeeCategory.application,
              paid: 100000,
              status: AdmissionFeeStatus.paid,
            ),
          ],
          payments: [
            const AdmissionFeePayment(
              id: 'p1',
              feeId: '1__APPLICATION',
              category: FeeCategory.application,
              isRefund: false,
              amountMinor: 100000,
              currency: 'INR',
              method: AdmissionPaymentMethod.cash,
              paymentDate: '2026-11-07',
              receiptNumber: 'RCT-2026-000009',
            ),
          ],
        );
        expect(find.text('Paid'), findsWidgets);
        expect(_btn('Record payment'), findsNothing);
        expect(find.textContaining('Receipt RCT-2026-000009'), findsOneWidget);
        expect(_btn('Refund'), findsOneWidget);
      },
    );

    testWidgets('only the approval authority can waive or refund', (
      tester,
    ) async {
      await open(
        tester,
        role: UserRole.branchAdmin,
        fees: [
          fee(
            FeeCategory.application,
            paid: 20000,
            status: AdmissionFeeStatus.partial,
          ),
        ],
      );
      expect(_btn('Record payment'), findsOneWidget);
      expect(_btn('Waive balance'), findsNothing);
      expect(_btn('Refund'), findsNothing);
    });

    testWidgets('a refund needs a reason and is sent once confirmed', (
      tester,
    ) async {
      final repo = await open(
        tester,
        fees: [
          fee(
            FeeCategory.application,
            paid: 100000,
            status: AdmissionFeeStatus.paid,
          ),
        ],
      );
      await tester.tap(_btn('Refund'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '300');
      await tester.tap(find.text('Refund').last);
      await tester.pumpAndSettle();
      expect(find.text('Give a reason for the refund.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'family moved');
      await tester.tap(find.text('Refund').last);
      await tester.pumpAndSettle();
      expect(repo.feeCalls, ['refund APPLICATION 30000 family moved']);
    });

    testWidgets('a closed enquiry cannot take fees or payments, only refunds', (
      tester,
    ) async {
      await open(
        tester,
        status: AdmissionStatus.notInterested,
        fees: [
          fee(
            FeeCategory.application,
            paid: 50000,
            status: AdmissionFeeStatus.partial,
          ),
        ],
      );
      expect(_btn('Set amount'), findsNothing);
      expect(_btn('Change amount'), findsNothing);
      expect(_btn('Record payment'), findsNothing);
      expect(_btn('Refund'), findsOneWidget);
    });

    testWidgets('a server refusal is shown and nothing is claimed as saved', (
      tester,
    ) async {
      final repo = await open(tester, fees: [fee(FeeCategory.application)]);
      repo.failWith = const ValidationFailure('no');
      await tester.tap(_btn('Record payment'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.tap(find.text('Record').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Payment recorded'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('lays out on a phone and a desktop', (tester) async {
      await open(
        tester,
        fees: [
          fee(
            FeeCategory.application,
            paid: 20000,
            status: AdmissionFeeStatus.partial,
          ),
        ],
      );
      for (final size in const [Size(360, 800), Size(1280, 900)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });
  });
}
