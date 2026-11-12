import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/admission/domain/admission_enquiry.dart';
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
      await tester.tap(find.byType(Switch));
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

  group('responsive layout', () {
    final pages = {
      'dashboard': '/admissions',
      'list': '/admissions/enquiries',
      'form': '/admissions/enquiries/new',
      'details': '/admissions/enquiries/1',
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
}
