import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/students/domain/parent.dart';
import 'package:eazy_school_360/features/students/domain/parent_duplicates.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/domain/relationship_type.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_repository.dart';
import 'package:eazy_school_360/features/students/domain/admission_number_format.dart';
import 'package:eazy_school_360/features/students/presentation/pages/student_admission_page.dart';
import 'package:eazy_school_360/features/students/presentation/providers/parent_providers.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/students/presentation/widgets/parent_form_dialog.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_provisioning_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/shared/dialogs/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';

const _uid = 'admin-1';

Parent _parent(
  String id, {
  String first = 'Lakshmi',
  String last = 'Nair',
  String phone = '+91 98765 43210',
  String? email = 'lakshmi@example.com',
  String? linkedUserId,
}) => Parent(
  parentId: id,
  schoolId: 'school-1',
  branchId: 'main',
  firstName: first,
  lastName: last,
  phone: phone,
  email: email,
  status: ActivationStatus.active,
  linkedUserId: linkedUserId,
);

class _Parents implements ParentRepository {
  final List<Parent> created = [];
  List<Parent> searchable = const [];
  Object? createError;

  @override
  Future<String> createParent(
    Parent parent, {
    required String createdBy,
  }) async {
    if (createError != null) throw createError!;
    created.add(parent);
    return 'new-parent-${created.length}';
  }

  @override
  Future<PagedResult<Parent>> searchParentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async => PagedResult(items: searchable, nextCursor: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Link = ({String studentId, String parentId, bool canAccessPortal});

class _Students implements StudentRepository {
  final List<Student> admitted = [];
  final List<_Link> links = [];

  @override
  Future<String> admitStudent({
    required Student student,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    required String createdBy,
  }) async {
    admitted.add(student);
    return 'student-1';
  }

  @override
  Future<void> linkParentToStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String parentId,
    required RelationshipType relationshipType,
    bool isPrimary = false,
    bool isEmergencyContact = false,
    bool canAccessPortal = false,
    required String createdBy,
  }) async {
    links.add((
      studentId: studentId,
      parentId: parentId,
      canAccessPortal: canAccessPortal,
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Finder implements ParentDuplicateFinder {
  List<Parent> existing = const [];
  Object? error;
  int calls = 0;

  @override
  Future<List<ParentMatch>> find({
    required String schoolId,
    required String branchId,
    required String? email,
    required String? phone,
    required String displayName,
    String? excludeParentId,
  }) async {
    calls++;
    if (error != null) throw error!;
    return ParentContact.matches(
      email: email,
      phone: phone,
      candidates: existing,
      excludeParentId: excludeParentId,
    );
  }
}

class _Provisioner implements LoginProvisioner {
  final List<List<String>> calls = [];
  bool? enablePortal;
  ProvisionOutcome outcome = ProvisionOutcome.created;

  @override
  Future<List<ProvisionResult>> provision({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    UserRole? staffRole,
    bool enablePortal = false,
    Map<String, String> emails = const {},
    PasswordSetup? passwordSetup,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    calls.add(ids);
    this.enablePortal = enablePortal;
    return [
      for (final id in ids)
        ProvisionResult(
          id: id,
          outcome: outcome,
          name: 'Parent',
          email: emails[id] ?? 'priya@example.com',
          newAccount: outcome == ProvisionOutcome.created,
        ),
    ];
  }
}

class _Auth extends FakeAuthRepository {
  _Auth()
    : super(
        signedInAs: const AppUser(uid: _uid, email: 'admin@example.com'),
      );
  final List<String> resetTo = [];
  @override
  Future<void> sendPasswordResetEmail(String email) async => resetTo.add(email);
}

class _Harness {
  final parents = _Parents();
  final students = _Students();
  final finder = _Finder();
  final provisioner = _Provisioner();
  final auth = _Auth();

  List<Override> get overrides => [
    envConfigProvider.overrideWithValue(
      EnvConfig.forEnvironment(AppEnvironment.test),
    ),
    authRepositoryProvider.overrideWithValue(auth),
    userRepositoryProvider.overrideWithValue(
      FakeUserRepository({
        _uid: const UserProfile(
          userId: _uid,
          schoolId: 'school-1',
          branchId: 'main',
          name: 'Grace Hopper',
          email: 'admin@example.com',
          role: UserRole.branchAdmin,
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
    parentRepositoryProvider.overrideWithValue(parents),
    studentRepositoryProvider.overrideWithValue(students),
    parentDuplicateFinderProvider.overrideWithValue(finder),
    admissionNumberSourceProvider.overrideWithValue(_FakeNumbers()),
    loginProvisionerProvider.overrideWithValue(provisioner),
    academicYearsProvider.overrideWith(
      (ref, key) => Stream.value([
        AcademicYear(
          academicYearId: 'y1',
          schoolId: 'school-1',
          branchId: 'main',
          name: '2026-27',
          startDate: DateTime(2026, 6),
          endDate: DateTime(2027, 3, 31),
          status: AcademicYearStatus.active,
        ),
      ]),
    ),
    classesProvider.overrideWith(
      (ref, key) => Stream.value([
        const SchoolClass(
          classId: 'c1',
          schoolId: 'school-1',
          branchId: 'main',
          academicYearId: 'y1',
          name: 'Grade 1',
          displayOrder: 1,
          status: ActivationStatus.active,
        ),
      ]),
    ),
    sectionsProvider.overrideWith(
      (ref, key) => Stream.value([
        const Section(
          sectionId: 's1',
          schoolId: 'school-1',
          branchId: 'main',
          academicYearId: 'y1',
          classId: 'c1',
          name: 'A',
          status: ActivationStatus.active,
        ),
      ]),
    ),
  ];
}

Future<void> _setSize(WidgetTester tester, Size size, double textScale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
}

Future<void> _pumpAdmission(
  WidgetTester tester,
  _Harness h, {
  Size size = const Size(1000, 1600),
  double textScale = 1,
}) async {
  await _setSize(tester, size, textScale);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const StudentAdmissionPage()),
      GoRoute(
        path: '/students/:id',
        builder: (_, s) =>
            Scaffold(body: Text('Profile ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// The wizard shows one step at a time with a single Next / Admit button.
Future<void> _next(WidgetTester tester) async {
  final next = find.widgetWithText(FilledButton, 'Next');
  await tester.ensureVisible(next);
  await tester.pumpAndSettle();
  await tester.tap(next);
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillBasics(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, "Enter student's full name"),
    'Asha Nair',
  );
  await _tapVisible(tester, find.text('Select date'));
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  await _next(tester);
}

Future<void> _fillNewParent(
  WidgetTester tester, {
  String phone = '9988776655',
  String email = 'Priya@Example.com',
}) async {
  await _tapVisible(tester, find.text('New'));
  await tester.enterText(
    find.widgetWithText(TextFormField, 'First name').last,
    'Priya',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Last name').last,
    'Nair',
  );
  await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), phone);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email (optional)').last,
    email,
  );
  await tester.pumpAndSettle();
}

Future<void> _placeAndReview(WidgetTester tester) async {
  Future<void> pick(String label, String value) async {
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, label),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  await pick('Academic year', '2026-27');
  await pick('Class', 'Grade 1');
  await pick('Section', 'A');
  await _next(tester);
}

/// No pumpAndSettle here: the save button shows a spinner until the page
/// navigates away, and the login dialog opens on top of it.
Future<void> _admit(WidgetTester tester) async {
  final admit = find.widgetWithText(FilledButton, 'Admit student');
  await tester.ensureVisible(admit);
  await tester.pump();
  await tester.tap(admit);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// After the login dialog closes the page navigates; settle from there.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openParentForm(
  WidgetTester tester,
  _Harness h, {
  Size size = const Size(1000, 1400),
  double textScale = 1,
}) async {
  await _setSize(tester, size, textScale);
  await tester.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAdaptiveAppDialog<ParentFormResult>(
                  context: context,
                  builder: (_) => const ParentFormDialog(
                    schoolId: 'school-1',
                    branchId: 'main',
                    currentUserId: _uid,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _fillParentForm(
  WidgetTester tester, {
  String phone = '9988776655',
  String email = 'priya@example.com',
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'First name'),
    'Priya',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Last name'),
    'Nair',
  );
  await tester.enterText(find.widgetWithText(TextFormField, 'Phone'), phone);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email (optional)'),
    email,
  );
}

void main() {
  group('ParentContact (duplicate rules)', () {
    test('emails match case-insensitively and block a second record', () {
      final m = ParentContact.matches(
        email: ' LAKSHMI@example.com ',
        phone: '1111111',
        candidates: [_parent('p1')],
      );
      expect(m.single.reasons, {ParentMatchReason.email});
      expect(m.single.blocksCreate, isTrue);
    });

    test('phones match on digits and on the last ten digits', () {
      expect(ParentContact.samePhone('98765 43210', '+91-9876543210'), isTrue);
      expect(ParentContact.samePhone('(044) 2345-678', '0442345678'), isTrue);
      expect(ParentContact.samePhone('9876543210', '9876543211'), isFalse);
      expect(ParentContact.samePhone('12345', '12345'), isFalse); // too short
      final m = ParentContact.matches(
        email: null,
        phone: '9876543210',
        candidates: [_parent('p1')],
      );
      expect(m.single.reasons, {ParentMatchReason.phone});
      expect(m.single.blocksCreate, isFalse);
    });

    test('the record being edited is not its own duplicate', () {
      expect(
        ParentContact.matches(
          email: 'lakshmi@example.com',
          phone: '9876543210',
          candidates: [_parent('p1')],
          excludeParentId: 'p1',
        ),
        isEmpty,
      );
    });

    test('a record found by several queries is listed once, email first', () {
      final m = ParentContact.matches(
        email: 'priya@example.com',
        phone: '9876543210',
        candidates: [
          _parent('p1'),
          _parent('p1'),
          _parent('p2', first: 'Priya', email: 'priya@example.com', phone: '1'),
        ],
      );
      expect(m.map((x) => x.parent.parentId), ['p2', 'p1']);
    });

    test('normalisation used for the stored email and the queries', () {
      expect(ParentContact.normalizeEmail('  A@B.COM '), 'a@b.com');
      expect(ParentContact.normalizeEmail('  '), isNull);
      expect(ParentContact.phoneVariants(' +91 98765 43210 '), [
        '+91 98765 43210',
        '919876543210',
        '+919876543210',
      ]);
      expect(ParentContact.phoneVariants('n/a'), isEmpty);
    });
  });

  group('Admission wizard: guardian and parent login', () {
    testWidgets('new parent + login: saved lowercase, linked with portal on, '
        'and the server-backed login dialog runs for that parent once', (
      tester,
    ) async {
      final h = _Harness();
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester);
      await _tapVisible(
        tester,
        find.text('Give this parent a login after admission'),
      );
      await _next(tester);
      expect(h.finder.calls, 1);
      await _placeAndReview(tester);
      expect(
        find.text('Parent login: will be set up after admission'),
        findsOneWidget,
      );
      await _admit(tester);

      expect(h.students.admitted.single.firstName, 'Asha');
      expect(h.parents.created.single.email, 'priya@example.com');
      expect(h.students.links.single.parentId, 'new-parent-1');
      expect(h.students.links.single.canAccessPortal, isTrue);

      // The existing "Give login access" dialog, for this one parent.
      expect(
        find.text('Allow portal access to their children'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create login'));
      await _settle(tester);
      expect(h.provisioner.calls, [
        ['new-parent-1'],
      ]);
      expect(h.provisioner.enablePortal, isTrue);
      expect(find.text('Sign-in details'), findsOneWidget);
      expect(find.text('Sign-in email: priya@example.com'), findsOneWidget);
      expect(h.auth.resetTo, ['priya@example.com']); // activation email
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.text('Profile student-1'), findsOneWidget);
    });

    testWidgets('same email as an existing parent: no second record; the '
        'existing parent (already signed in) is linked, no new login', (
      tester,
    ) async {
      final h = _Harness();
      h.finder.existing = [_parent('p1', linkedUserId: 'uid-parent')];
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester, email: 'LAKSHMI@example.com');
      await _next(tester);

      expect(find.text('This parent may already exist'), findsOneWidget);
      expect(find.text('Create new anyway'), findsNothing);
      await tester.tap(find.text('Use this parent'));
      await tester.pumpAndSettle();
      // The wizard moved on to placement; the review states the login.
      expect(
        find.text('Give this parent a login after admission'),
        findsNothing,
      );
      await _placeAndReview(tester);
      expect(find.text('Parent login: already has one'), findsOneWidget);
      await _admit(tester);

      expect(h.parents.created, isEmpty);
      expect(h.students.links.single.parentId, 'p1');
      // A second child of a signed-in parent is visible to them.
      expect(h.students.links.single.canAccessPortal, isTrue);
      expect(h.provisioner.calls, isEmpty);
      expect(find.text('Profile student-1'), findsOneWidget);
    });

    testWidgets('same phone only: may still create a separate record', (
      tester,
    ) async {
      final h = _Harness();
      h.finder.existing = [_parent('p1', email: null)];
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester, phone: '98765 43210');
      await _next(tester);
      await tester.tap(find.text('Create new anyway'));
      await tester.pumpAndSettle();
      await _placeAndReview(tester);
      await _admit(tester);
      expect(h.parents.created, hasLength(1));
      expect(h.students.links.single.canAccessPortal, isFalse);
    });

    testWidgets('invalid email / missing phone are shown on the fields and '
        'nothing is checked or saved', (tester) async {
      final h = _Harness();
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester, phone: '', email: 'not-an-email');
      await _next(tester);
      expect(find.text('Phone number is required.'), findsOneWidget);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(h.finder.calls, 0);
      expect(h.parents.created, isEmpty);
    });

    testWidgets('the duplicate check failing blocks the step with a message', (
      tester,
    ) async {
      final h = _Harness();
      h.finder.error = const NetworkFailure();
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester);
      await _next(tester);
      expect(
        find.textContaining('Could not check for an existing parent'),
        findsOneWidget,
      );
      expect(find.text('Academic year'), findsNothing);
    });

    testWidgets('parent save failing: the student is kept, the message says '
        'so, and no login is attempted', (tester) async {
      final h = _Harness();
      h.parents.createError = const NetworkFailure();
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester);
      await _tapVisible(
        tester,
        find.text('Give this parent a login after admission'),
      );
      await _next(tester);
      await _placeAndReview(tester);
      await _admit(tester);
      expect(h.students.admitted, hasLength(1));
      expect(h.provisioner.calls, isEmpty);
      expect(
        find.textContaining('guardian could not be linked'),
        findsOneWidget,
      );
      expect(find.text('Profile student-1'), findsOneWidget);
    });

    testWidgets('login dialog cancelled: the student is saved and the '
        'message points to Parents for later', (tester) async {
      final h = _Harness();
      await _pumpAdmission(tester, h);
      await _fillBasics(tester);
      await _fillNewParent(tester);
      await _tapVisible(
        tester,
        find.text('Give this parent a login after admission'),
      );
      await _next(tester);
      await _placeAndReview(tester);
      await _admit(tester);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(h.provisioner.calls, isEmpty);
      expect(find.textContaining('No parent login was given'), findsOneWidget);
      expect(find.text('Profile student-1'), findsOneWidget);
    });

    for (final (name, size, scale) in [
      ('phone', const Size(360, 740), 1.5),
      ('tablet', const Size(800, 1100), 1.0),
    ]) {
      testWidgets('guardian step lays out without overflow: $name', (
        tester,
      ) async {
        final h = _Harness();
        await _pumpAdmission(tester, h, size: size, textScale: scale);
        await _fillBasics(tester);
        await _tapVisible(tester, find.text('New'));
        expect(tester.takeException(), isNull);
        h.finder.existing = [_parent('p1')];
        await _fillNewParent(tester, email: 'lakshmi@example.com');
        await _next(tester);
        expect(find.text('This parent may already exist'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Admission wizard: layout and student details', () {
    testWidgets('shows the banner, the four-step tracker and Bulk upload', (
      tester,
    ) async {
      await _pumpAdmission(tester, _Harness(), size: const Size(1000, 1200));
      expect(find.text('Admit Student'), findsOneWidget);
      expect(find.text('Add a new student to the school'), findsOneWidget);
      for (final l in [
        'Student Details',
        'Parent / Guardian',
        'Academic Placement',
        'Review',
      ]) {
        expect(find.text(l), findsWidgets, reason: l);
      }
      expect(find.text('Admission Number'), findsOneWidget);
      expect(find.text('ADM-0001'), findsOneWidget);
      expect(find.text('Generated automatically'), findsOneWidget);
      expect(find.text('Bulk upload'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Back'), findsNothing); // nothing before step 1
    });

    testWidgets('Bulk upload is a visible button that opens the import', (
      tester,
    ) async {
      await _setSize(tester, const Size(1000, 1200), 1);
      var opened = false;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const StudentAdmissionPage()),
          GoRoute(
            path: '/students/import',
            builder: (_, _) {
              opened = true;
              return const Scaffold(body: Text('import page'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _Harness().overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bulk upload'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets('the full name needs a first and a last name', (tester) async {
      await _pumpAdmission(tester, _Harness(), size: const Size(1000, 1400));
      await tester.enterText(
        find.widgetWithText(TextFormField, "Enter student's full name"),
        'Asha',
      );
      await _next(tester);
      expect(find.text('Enter the first and last name'), findsOneWidget);
      expect(find.text('Select the date of birth'), findsOneWidget);
      // still on step 1
      expect(find.text('Basic information of the student'), findsOneWidget);
    });

    testWidgets('the typed full name is stored as first, middle and last', (
      tester,
    ) async {
      final h = _Harness();
      await _pumpAdmission(tester, h, size: const Size(1000, 1400));
      await tester.enterText(
        find.widgetWithText(TextFormField, "Enter student's full name"),
        'Mary  Anne Elizabeth Smith',
      );
      await _tapVisible(tester, find.text('Select date'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await _next(tester); // guardian: add later
      await _next(tester);
      await _placeAndReview(tester);
      expect(find.text('Mary Anne Elizabeth Smith'), findsOneWidget);
      await _admit(tester);
      await _settle(tester);
      final s = h.students.admitted.single;
      expect(s.firstName, 'Mary');
      expect(s.middleName, 'Anne Elizabeth');
      expect(s.lastName, 'Smith');
      expect(s.displayName, 'Mary Anne Elizabeth Smith');
    });

    testWidgets('Back returns to the earlier step with what was typed', (
      tester,
    ) async {
      await _pumpAdmission(tester, _Harness(), size: const Size(1000, 1400));
      await _fillBasics(tester);
      expect(find.text('Link a guardian now or add one later'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Asha Nair'), findsOneWidget);
    });

    for (final (name, size) in [
      ('phone', const Size(360, 740)),
      ('tablet', const Size(820, 1180)),
      ('desktop', const Size(1440, 900)),
    ]) {
      testWidgets('step one lays out without overflow: $name, text x1.5', (
        tester,
      ) async {
        await _pumpAdmission(tester, _Harness(), size: size, textScale: 1.5);
        expect(tester.takeException(), isNull);
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -2500),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Add parent form', () {
    testWidgets('valid new parent: saved lowercase, login requested', (
      tester,
    ) async {
      final h = _Harness();
      ParentFormResult? result;
      await _setSize(tester, const Size(1000, 1400), 1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showAdaptiveAppDialog<ParentFormResult>(
                      context: context,
                      builder: (_) => const ParentFormDialog(
                        schoolId: 'school-1',
                        branchId: 'main',
                        currentUserId: _uid,
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _fillParentForm(tester, email: 'Priya@Example.com');
      await tester.tap(find.text('Give login access after saving'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(h.parents.created.single.email, 'priya@example.com');
      expect(result?.parentId, 'new-parent-1');
      expect(result?.created, isTrue);
      expect(result?.giveLogin, isTrue);
      expect(result?.email, 'priya@example.com');
    });

    testWidgets('same email: refused; choosing the existing parent returns it '
        'without creating anything', (tester) async {
      final h = _Harness();
      h.finder.existing = [_parent('p1')];
      ParentFormResult? result;
      await _setSize(tester, const Size(1000, 1400), 1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await showAdaptiveAppDialog<ParentFormResult>(
                      context: context,
                      builder: (_) => const ParentFormDialog(
                        schoolId: 'school-1',
                        branchId: 'main',
                        currentUserId: _uid,
                      ),
                    ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _fillParentForm(tester, email: 'lakshmi@example.com');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Create new anyway'), findsNothing);
      await tester.tap(find.text('Use this parent'));
      await tester.pumpAndSettle();

      expect(h.parents.created, isEmpty);
      expect(result?.parentId, 'p1');
      expect(result?.created, isFalse);
      expect(result?.giveLogin, isFalse);
    });

    testWidgets('"Change details" keeps the form open and saves nothing', (
      tester,
    ) async {
      final h = _Harness();
      h.finder.existing = [_parent('p1', email: null)];
      await _openParentForm(tester, h);
      await _fillParentForm(tester, phone: '9876543210');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change details'));
      await tester.pumpAndSettle();
      expect(h.parents.created, isEmpty);
      expect(find.text('Add parent / guardian'), findsOneWidget);
    });

    testWidgets('invalid email is refused before any lookup', (tester) async {
      final h = _Harness();
      await _openParentForm(tester, h);
      await _fillParentForm(tester, email: 'priya@');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(h.finder.calls, 0);
    });

    testWidgets('lays out on a phone at large text', (tester) async {
      final h = _Harness();
      await _openParentForm(
        tester,
        h,
        size: const Size(360, 740),
        textScale: 1.5,
      );
      expect(find.text('Give login access after saving'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FakeNumbers extends AdmissionNumberSource {
  @override
  Future<int> highestSequence({
    required String schoolId,
    required String branchId,
  }) async => 0;
}
