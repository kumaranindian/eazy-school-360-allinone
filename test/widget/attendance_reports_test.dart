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
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_date.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_registers.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/presentation/providers/attendance_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
import '../support/fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
final _today = AttendanceDate.dateOnly(DateTime.now());
final _key = AttendanceDate.key(_today);

Future<(ProviderContainer, FakeStudentAttendanceRepository)> _pump(
  WidgetTester tester,
  UserRole role,
) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;

  final students =
      FakeStudentAttendanceRepository(
          register: StudentRegister(
            roster: [
              for (final (id, name) in [('1', 'Anil'), ('2', '=Bina')])
                EnrolledStudent(
                  student: fakeStudent(id, name, roll: id),
                  academicRecordId: 'r$id',
                ),
            ],
            records: const {},
            day: null,
          ),
        )
        ..sectionRecords = [
          fakeStoredAttendance(
            '1',
            dateKey: _key,
            status: AttendanceStatus.present,
          ),
          fakeStoredAttendance(
            '1',
            dateKey: '${_today.year}-01-01',
            status: AttendanceStatus.present,
          ),
          fakeStoredAttendance(
            '1',
            dateKey: '${_today.year}-01-02',
            status: AttendanceStatus.absent,
          ),
          fakeStoredAttendance(
            '2',
            dateKey: _key,
            status: AttendanceStatus.halfDay,
          ),
        ];

  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'g@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace',
            email: 'g@example.com',
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
              name: 'R',
              email: 'o@r.example',
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
        FakeAcademicStructureRepository(
          years: [
            AcademicYear(
              academicYearId: 'y1',
              schoolId: 'school-1',
              branchId: 'main',
              name: '2026-27',
              startDate: DateTime(_today.year, 1, 1),
              endDate: DateTime(_today.year, 12, 31),
              status: AcademicYearStatus.active,
            ),
          ],
          classes: [
            const SchoolClass(
              classId: 'c5',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              name: 'Class 5',
              displayOrder: 1,
              status: ActivationStatus.active,
            ),
          ],
          sections: [
            const Section(
              sectionId: 'sec-a',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              classId: 'c5',
              name: 'A',
              status: ActivationStatus.active,
            ),
          ],
        ),
      ),
      staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
      studentAttendanceRepositoryProvider.overrideWithValue(students),
      staffAttendanceRepositoryProvider.overrideWithValue(
        FakeStaffAttendanceRepository(
          register: const StaffRegister(roster: [], records: {}, day: null),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/attendance/reports');
  await tester.pumpAndSettle();
  return (container, students);
}

Future<void> _pick(WidgetTester tester, String label, String option) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a manager generates a class report: totals, percentage per student, and the formula is shown',
    (tester) async {
      final (_, repo) = await _pump(tester, UserRole.branchAdmin);
      await _pick(tester, 'Class', 'Class 5');
      await _pick(tester, 'Section', 'A');

      // widen the range to the whole year so all four records are in scope
      await tester.tap(find.textContaining('From'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate report'));
      await tester.pumpAndSettle();

      expect(repo.rangeRequests, hasLength(1));
      expect(repo.rangeRequests.single['section'], 'sec-a');
      expect(find.text('Anil Kumar'), findsOneWidget);
      // Anil: 2 present + 1 absent  => 66.7%;   Bina: 1 half day => 50.0%
      expect(find.text('66.7%'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(
        find.textContaining('(present + late + ½ × half day) ÷ days marked'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a range that leaves the academic year is refused so years are never mixed',
    (tester) async {
      final (_, repo) = await _pump(tester, UserRole.branchAdmin);
      await _pick(tester, 'Class', 'Class 5');
      await _pick(tester, 'Section', 'A');

      // Last month on 1 January would reach into the previous year.
      await tester.tap(find.text('Last month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate report'));
      await tester.pumpAndSettle();

      if (_today.month == 1) {
        expect(find.textContaining('Keep the range inside'), findsOneWidget);
        expect(repo.rangeRequests, isEmpty);
      } else {
        expect(repo.rangeRequests, hasLength(1)); // inside the year: allowed
      }
    },
  );

  testWidgets(
    'CSV export copies a sanitized report to the clipboard (formula-looking names are neutralized)',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(tester, UserRole.branchAdmin);
      await _pick(tester, 'Class', 'Class 5');
      await _pick(tester, 'Section', 'A');
      await tester.tap(find.text('Generate report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy CSV'));
      await tester.pumpAndSettle();

      expect(copied, isNotNull);
      final lines = copied!.trim().split('\r\n');
      expect(
        lines.first,
        'Name,Detail,Present,Absent,Late,Half day,Days marked,Attendance %',
      );
      expect(lines.any((l) => l.startsWith('Anil Kumar,1,')), isTrue);
      expect(
        lines.any((l) => l.startsWith("'=Bina Kumar")),
        isTrue,
        reason: 'a name starting with = must not be left as a formula',
      );
      expect(
        find.text('Report copied as CSV. Paste it into a spreadsheet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('finance gets staff reports only — there is no student mode', (
    tester,
  ) async {
    await _pump(tester, UserRole.finance);
    expect(find.text('Class'), findsNothing);
    expect(find.text('Generate report'), findsOneWidget);
  });
}
