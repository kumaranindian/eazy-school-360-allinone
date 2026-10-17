import 'dart:async';

import 'package:eazy_school_360/features/fees/domain/invoice.dart';
import 'package:eazy_school_360/shared/branding/page_hero.dart';
import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_settings.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_settings_repository.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_settings_providers.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/fees/domain/fee_dates.dart';
import 'package:eazy_school_360/features/fees/domain/fee_enums.dart';
import 'package:eazy_school_360/features/fees/domain/fee_planners.dart';
import 'package:eazy_school_360/features/fees/domain/fee_repositories.dart';
import 'package:eazy_school_360/features/fees/domain/fee_summary.dart';
import 'package:eazy_school_360/features/fees/domain/student_fee_assignment.dart';
import 'package:eazy_school_360/features/fees/presentation/providers/fee_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/presentation/providers/parent_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/attendance_fakes.dart';
import '../support/fakes.dart';
import '../support/fee_fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';

final _year = AcademicYear(
  academicYearId: 'y1',
  schoolId: 'school-1',
  branchId: 'main',
  name: '2026-27',
  startDate: DateTime(2026, 6, 1),
  endDate: DateTime(2027, 3, 31),
  status: AcademicYearStatus.active,
);

class _FakeSettings implements AcademicSettingsRepository {
  @override
  Future<AcademicSettings> getSettings(
    String schoolId,
    String branchId,
  ) async => AcademicSettings(schoolId: schoolId, branchId: branchId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeParentRepository implements ParentRepository {
  final List<Student> children;

  _FakeParentRepository(this.children);

  @override
  Future<List<Student>> getChildrenForParent({
    required String schoolId,
    required String parentId,
    String? branchId,
  }) async => children;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _World {
  final ProviderContainer container;
  final FakeInvoiceRepository invoices;
  final FakePaymentRepository payments;
  final FakeFeeConfigRepository config;
  final FakeFeeReportRepository reports;

  _World(
    this.container,
    this.invoices,
    this.payments,
    this.config,
    this.reports,
  );

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();

  Future<void> go(WidgetTester tester, String path) async {
    container.read(appRouterProvider).go(path);
    await tester.pumpAndSettle();
  }
}

FeeSummary _summary() => const FeeSummary(
  invoiceCount: 12,
  grossMinor: 1300000,
  discountMinor: 100000,
  payableMinor: 1200000,
  waivedMinor: 50000,
  collectedMinor: 700000,
  outstandingMinor: 450000,
  overdueMinor: 150000,
  overdueInvoiceCount: 3,
  partiallyPaidCount: 2,
  paidCount: 6,
);

Future<_World> _pump(
  WidgetTester tester, {
  required UserRole role,
  FakeFeeConfigRepository? config,
  FakeInvoiceRepository? invoiceRepo,
  FakePaymentRepository? paymentRepo,
  FakeFeeReportRepository? reportRepo,
  List<Student> children = const [],
  String? linkedParentId,
  Size size = const Size(1400, 1000),
  Map<String, Branch>? branches,
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final inv = invoiceRepo ?? FakeInvoiceRepository();
  final pay = paymentRepo ?? FakePaymentRepository();
  final cfg = config ?? FakeFeeConfigRepository();
  final rep = reportRepo ?? FakeFeeReportRepository(summary: _summary());

  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'u@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Fin Officer',
            email: 'u@example.com',
            role: role,
            status: UserStatus.active,
            linkedParentId: linkedParentId,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood High',
              email: 'o@r.example',
              status: SchoolStatus.active,
            ),
          },
          branches:
              branches ??
              {
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
          years: [_year],
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
              sectionId: 'sa',
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
      academicSettingsRepositoryProvider.overrideWithValue(_FakeSettings()),
      parentRepositoryProvider.overrideWithValue(
        _FakeParentRepository(children),
      ),
      invoiceRepositoryProvider.overrideWithValue(inv),
      paymentRepositoryProvider.overrideWithValue(pay),
      feeConfigRepositoryProvider.overrideWithValue(cfg),
      feeReportRepositoryProvider.overrideWithValue(rep),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, inv, pay, cfg, rep);
}

Finder _filled(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    )
    .first;
Finder _outlined(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    )
    .first;

void main() {
  group('route and navigation permissions', () {
    testWidgets('a parent reaches only /my-fees', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
      );
      await w.go(tester, '/my-fees');
      expect(w.location, '/my-fees');
      for (final p in [
        '/fees',
        '/fees/structures',
        '/fees/assign',
        '/fees/invoices',
        '/fees/invoices/generate',
        '/fees/invoices/x',
        '/fees/payments',
        '/fees/receipts/x',
        '/fees/reports',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
    });

    testWidgets('a teacher has no fee access of any kind', (tester) async {
      final w = await _pump(tester, role: UserRole.teacher);
      for (final p in [
        '/fees',
        '/fees/structures',
        '/fees/invoices',
        '/fees/payments',
        '/fees/reports',
        '/my-fees',
      ]) {
        await w.go(tester, p);
        expect(w.location, '/dashboard', reason: p);
      }
      expect(find.text('Fees'), findsNothing);
      expect(find.text('My Fees'), findsNothing);
    });

    testWidgets(
      'finance can run day-to-day fees (assign, issue, collect, report) and cannot reach parent pages',
      (tester) async {
        final w = await _pump(tester, role: UserRole.finance);
        for (final p in [
          '/fees',
          '/fees/structures',
          '/fees/assign',
          '/fees/invoices',
          '/fees/invoices/generate',
          '/fees/payments',
          '/fees/reports',
        ]) {
          await w.go(tester, p);
          expect(w.location, p);
        }
        await w.go(tester, '/my-fees');
        expect(w.location, '/dashboard');
      },
    );

    testWidgets('a branch admin can open every fees screen', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      for (final p in [
        '/fees',
        '/fees/structures',
        '/fees/assign',
        '/fees/invoices',
        '/fees/invoices/generate',
        '/fees/payments',
        '/fees/reports',
      ]) {
        await w.go(tester, p);
        expect(w.location, p);
      }
    });

    testWidgets(
      'on a phone the bottom bar stays usable: extra destinations go under "More", including Fees',
      (tester) async {
        final w = await _pump(
          tester,
          role: UserRole.schoolAdmin,
          size: const Size(390, 844),
        );
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('More'), findsOneWidget);
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        // The dashboard also has a "Fees" quick link; scope to the sheet.
        final inSheet = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Fees'),
        );
        expect(inSheet, findsOneWidget);
        await tester.tap(inSheet);
        await tester.pumpAndSettle();
        expect(w.location, '/fees');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'with every destination, the desktop rail neither overflows nor hides items on a short window',
      (tester) async {
        await _pump(
          tester,
          role: UserRole.schoolAdmin,
          size: const Size(1000, 520),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('compact layout', () {
    testWidgets('the hero is one slim strip and the year picker follows it', (
      tester,
    ) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/fees');
      final hero = tester.getRect(find.byType(PageHero));
      expect(hero.height, lessThan(95)); // was a ~140px banner
      final year = tester.getRect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Academic year'),
      );
      expect(year.top - hero.bottom, lessThan(30));
      expect(year.left, hero.left); // one shared gutter
      expect(tester.takeException(), isNull);
    });

    testWidgets('branch and year are pickers in ONE row, not two stacked', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        branches: {
          'school-1/main': const Branch(
            branchId: 'main',
            schoolId: 'school-1',
            name: 'Main',
            status: BranchStatus.active,
          ),
          'school-1/south': const Branch(
            branchId: 'south',
            schoolId: 'school-1',
            name: 'South',
            status: BranchStatus.active,
          ),
        },
      );
      await w.go(tester, '/fees');
      final branch = tester.getRect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Branch'),
      );
      final year = tester.getRect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Academic year'),
      );
      expect(year.top, branch.top); // the same row
      expect(year.left, greaterThan(branch.right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a phone the two pickers wrap instead of overflowing', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        size: const Size(360, 800),
        branches: {
          'school-1/main': const Branch(
            branchId: 'main',
            schoolId: 'school-1',
            name: 'Main',
            status: BranchStatus.active,
          ),
          'school-1/south': const Branch(
            branchId: 'south',
            schoolId: 'school-1',
            name: 'South',
            status: BranchStatus.active,
          ),
        },
      );
      await w.go(tester, '/fees');
      expect(find.text('Academic year'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('collecting and printing straight from the lists', () {
    Future<(_World, FakePaymentRepository)> invoicesList(
      WidgetTester tester, {
      List<dynamic>? invoices,
      Size size = const Size(1400, 1000),
    }) async {
      final pay = FakePaymentRepository(payments: [fakePayment()]);
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        invoiceRepo: FakeInvoiceRepository(
          invoices: [...?invoices?.cast<Invoice>()],
        ),
        paymentRepo: pay,
        size: size,
      );
      await w.go(tester, '/fees/invoices');
      return (w, pay);
    }

    testWidgets('an invoice with a balance can be collected from its row', (
      tester,
    ) async {
      final (_, pay) = await invoicesList(
        tester,
        invoices: [fakeInvoice(payable: 100000)],
      );
      // in the first column, so it is on screen even though the table is
      // wider than the window
      expect(
        tester.getRect(_filled('Collect')).right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      await tester.tap(_filled('Collect'));
      await tester.pumpAndSettle();
      // the same dialog as the invoice page, with the balance filled in
      expect(find.text('Collect payment'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Amount (INR)'),
            )
            .controller!
            .text,
        '1000.00',
      );
      await tester.tap(_filled('Record payment'));
      await tester.pumpAndSettle();
      expect(pay.collected, hasLength(1));
      expect(pay.collected.single.invoiceId, 'stu-1__y1__M-2026-06');
      expect(pay.collected.single.amountMinor, 100000);
      // and it opens the receipt, as from the invoice page
      expect(find.text('Receipt'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a paid or void invoice offers no Collect', (tester) async {
      await invoicesList(
        tester,
        invoices: [
          fakeInvoice(
            number: 'INV-1',
            payable: 100000,
            paid: 100000,
            status: InvoiceStatus.paid,
          ),
          fakeInvoice(id: 'v', number: 'INV-2', status: InvoiceStatus.voided),
        ],
      );
      expect(find.text('INV-1'), findsOneWidget);
      expect(find.text('INV-2'), findsOneWidget);
      expect(find.text('Collect'), findsNothing);
    });

    testWidgets(
      'the invoice number opens the invoice, where it can be printed',
      (tester) async {
        await invoicesList(tester, invoices: [fakeInvoice()]);
        await tester.tap(find.text('INV-2026-000001'));
        await tester.pumpAndSettle();
        expect(find.text('Collect payment'), findsOneWidget);
        expect(find.text('Print'), findsOneWidget);
        expect(find.text('PDF'), findsOneWidget);
      },
    );

    testWidgets('a phone card has the same actions', (tester) async {
      await invoicesList(
        tester,
        invoices: [fakeInvoice()],
        size: const Size(390, 844),
      );
      expect(find.text('Collect'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'View'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a payment row opens its receipt, and can print it', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        paymentRepo: FakePaymentRepository(payments: [fakePayment()]),
      );
      await w.go(tester, '/fees/payments');
      expect(find.byTooltip('Print receipt'), findsOneWidget);
      expect(
        tester.getRect(find.byTooltip('Print receipt')).right,
        lessThanOrEqualTo(tester.view.physicalSize.width),
      );
      await tester.tap(find.text('RCT-2026-000001'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('printing a receipt that is gone says so, never silently', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        paymentRepo: FakePaymentRepository(payments: [fakePayment()]),
      );
      await w.go(tester, '/fees/payments');
      await tester.tap(find.byTooltip('Print receipt'));
      await tester.pumpAndSettle();
      expect(find.text('This receipt could not be found.'), findsOneWidget);
    });

    testWidgets('payments lay out on a phone and a tablet without overflow', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        paymentRepo: FakePaymentRepository(payments: [fakePayment()]),
        size: const Size(390, 844),
      );
      await w.go(tester, '/fees/payments');
      expect(find.byTooltip('Print receipt'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('fees hub', () {
    testWidgets(
      'shows totals from the aggregate summary and states what is excluded',
      (tester) async {
        final w = await _pump(tester, role: UserRole.branchAdmin);
        await w.go(tester, '/fees');
        expect(find.text('₹12,000.00'), findsOneWidget); // invoiced
        expect(find.text('₹7,000.00'), findsOneWidget); // collected
        expect(find.text('₹4,500.00'), findsOneWidget); // outstanding
        expect(find.text('₹1,500.00'), findsOneWidget); // overdue
        expect(
          find.textContaining(
            'Void invoices and reversed payments are excluded',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('do not balance'), findsNothing);
      },
    );

    testWidgets('a summary that does not balance is flagged, not hidden', (
      tester,
    ) async {
      const off = FeeSummary(
        invoiceCount: 1,
        grossMinor: 100000,
        discountMinor: 0,
        payableMinor: 100000,
        waivedMinor: 0,
        collectedMinor: 40000,
        outstandingMinor: 70000,
        overdueMinor: 0,
        overdueInvoiceCount: 0,
        partiallyPaidCount: 1,
        paidCount: 0,
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        reportRepo: FakeFeeReportRepository(summary: off),
      );
      await w.go(tester, '/fees');
      expect(find.textContaining('do not balance'), findsOneWidget);
    });

    testWidgets(
      'a failure shows a friendly message with retry — never the raw error',
      (tester) async {
        final repo = FakeFeeReportRepository(summary: _summary())
          ..error = StateError('PERMISSION_DENIED internal path /schools/x');
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          reportRepo: repo,
        );
        await w.go(tester, '/fees');
        expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
        repo.error = null;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('₹12,000.00'), findsOneWidget);
      },
    );

    testWidgets(
      'finance sees the totals; the action buttons match their permissions',
      (tester) async {
        final w = await _pump(tester, role: UserRole.finance);
        await w.go(tester, '/fees');
        expect(find.text('Generate invoices'), findsOneWidget);
        expect(find.text('Assign fees'), findsOneWidget);
        expect(find.text('Reports'), findsOneWidget);
      },
    );
  });

  group('fee structures', () {
    testWidgets('only an admin is offered Add/Edit; finance can read', (
      tester,
    ) async {
      final config = FakeFeeConfigRepository(structures: [fakeStructure()]);
      final admin = await _pump(
        tester,
        role: UserRole.branchAdmin,
        config: config,
      );
      await admin.go(tester, '/fees/structures');
      expect(find.text('Tuition'), findsWidgets);
      expect(find.text('Add fee'), findsOneWidget);
    });

    testWidgets('finance sees the list but no Add control', (tester) async {
      final config = FakeFeeConfigRepository(structures: [fakeStructure()]);
      final w = await _pump(tester, role: UserRole.finance, config: config);
      await w.go(tester, '/fees/structures');
      expect(find.text('Tuition'), findsWidgets);
      expect(find.text('Add fee'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets(
      'the form validates amount and code, and saves the amount as exact minor units',
      (tester) async {
        final config = FakeFeeConfigRepository();
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          config: config,
        );
        await w.go(tester, '/fees/structures');
        await tester.tap(find.text('Add fee'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('2-20 letters, digits, "-" or "_".'), findsOneWidget);
        expect(find.text('Enter a fee name.'), findsOneWidget);
        expect(
          find.text('Enter a valid amount, up to 2 decimals.'),
          findsOneWidget,
        );
        expect(config.created, isEmpty);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Code'),
          'TUITION-5',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Fee name'),
          'Tuition fee',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount (INR)'),
          '0',
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          find.text('The amount must be greater than zero.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount (INR)'),
          '1500.505',
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter a valid amount, up to 2 decimals.'),
          findsOneWidget,
        );

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount (INR)'),
          '1,500.50',
        );
        await tester.ensureVisible(find.text('Save'));
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(config.created, hasLength(1));
        expect(config.created.single.amountMinor, 150050);
        expect(config.created.single.code, 'TUITION-5');
        expect(config.created.single.frequency, FeeFrequency.monthly);
        expect(find.text('Fee created successfully.'), findsOneWidget);
      },
    );

    testWidgets('an empty year says so', (tester) async {
      final w = await _pump(tester, role: UserRole.branchAdmin);
      await w.go(tester, '/fees/structures');
      expect(find.textContaining('No fees configured'), findsOneWidget);
    });
  });

  group('invoice list', () {
    final invoices = [
      fakeInvoice(
        id: 'a',
        number: 'INV-2026-000001',
        due: '2020-01-01',
      ), // overdue
      fakeInvoice(
        id: 'b',
        number: 'INV-2026-000002',
        studentName: 'Bina Kumar',
        paid: 100000,
        due: '2020-01-01',
      ), // paid
      fakeInvoice(
        id: 'c',
        number: 'INV-2026-000003',
        studentName: 'Charu Kumar',
        paid: 40000,
        due: '2099-01-01',
      ), // partial, not due
    ];

    testWidgets('lists invoices with a derived Overdue status and balances', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: UserRole.finance,
        invoiceRepo: FakeInvoiceRepository(invoices: invoices),
      );
      await w.go(tester, '/fees/invoices');
      expect(find.text('INV-2026-000001'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Paid'), findsWidgets);
      expect(find.text('Partially paid'), findsWidgets);
      expect(
        find.text('₹600.00'),
        findsWidgets,
      ); // balance of the partial invoice
    });

    testWidgets(
      'the Overdue filter asks the repository for open invoices due before today',
      (tester) async {
        final repo = FakeInvoiceRepository(invoices: invoices);
        final w = await _pump(
          tester,
          role: UserRole.finance,
          invoiceRepo: repo,
        );
        await w.go(tester, '/fees/invoices');
        expect(repo.fetchFilters.last.overdueOnly, isFalse);
        expect(repo.fetchFilters.last.academicYearId, 'y1');

        await tester.tap(find.text('All statuses').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Overdue').last);
        await tester.pumpAndSettle();
        expect(repo.fetchFilters.last.overdueOnly, isTrue);
      },
    );

    testWidgets(
      'searching by number uses the number search and pauses the filters',
      (tester) async {
        final repo = FakeInvoiceRepository(invoices: invoices);
        final w = await _pump(
          tester,
          role: UserRole.finance,
          invoiceRepo: repo,
        );
        await w.go(tester, '/fees/invoices');
        await tester.enterText(find.byType(TextField).first, 'inv-2026-000003');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(repo.searches, ['inv-2026-000003']);
        expect(find.text('INV-2026-000003'), findsOneWidget);
        expect(find.text('INV-2026-000001'), findsNothing);
        expect(find.textContaining('Filters are paused'), findsOneWidget);
      },
    );

    testWidgets('empty and error states', (tester) async {
      final empty = await _pump(tester, role: UserRole.finance);
      await empty.go(tester, '/fees/invoices');
      expect(find.text('No invoices found.'), findsOneWidget);
    });

    testWidgets('an error is friendly', (tester) async {
      final repo = FakeInvoiceRepository()
        ..error = StateError('boom: raw detail');
      final w = await _pump(tester, role: UserRole.finance, invoiceRepo: repo);
      await w.go(tester, '/fees/invoices');
      expect(find.textContaining('raw detail'), findsNothing);
      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a student ledger header summarizes billed / paid / balance / overdue / upcoming and excludes void invoices',
      (tester) async {
        final repo = FakeInvoiceRepository(
          invoices: [
            fakeInvoice(id: 'a', number: 'INV-2026-000001', due: '2020-01-01'),
            fakeInvoice(
              id: 'c',
              number: 'INV-2026-000003',
              paid: 40000,
              due: '2099-01-01',
            ),
            fakeInvoice(
              id: 'v',
              number: 'INV-2026-000009',
              status: InvoiceStatus.voided,
            ),
          ],
        );
        final w = await _pump(
          tester,
          role: UserRole.finance,
          invoiceRepo: repo,
        );
        await w.go(tester, '/fees/invoices?studentId=stu-1');
        expect(find.text('Billed'), findsOneWidget);
        expect(
          find.text('₹2,000.00'),
          findsOneWidget,
        ); // 1000 + 1000, void excluded
        expect(find.text('₹400.00'), findsWidgets); // paid
        expect(find.text('₹1,600.00'), findsWidgets); // balance
      },
    );

    for (final size in [
      const Size(360, 800),
      const Size(800, 1000),
      const Size(1400, 900),
    ]) {
      testWidgets('lays out without overflow at ${size.width.toInt()}px', (
        tester,
      ) async {
        final w = await _pump(
          tester,
          role: UserRole.finance,
          invoiceRepo: FakeInvoiceRepository(invoices: invoices),
          size: size,
        );
        await w.go(tester, '/fees/invoices');
        expect(find.textContaining('INV-2026-000001'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('invoice detail actions follow the role', () {
    Future<_World> open(
      WidgetTester tester,
      UserRole role, {
      required dynamic invoice,
      FakePaymentRepository? payments,
    }) async {
      final w = await _pump(
        tester,
        role: role,
        invoiceRepo: FakeInvoiceRepository(invoices: [invoice]),
        paymentRepo: payments,
      );
      await w.go(tester, '/fees/invoices/${invoice.invoiceId}');
      return w;
    }

    testWidgets('finance can collect, but cannot waive or void', (
      tester,
    ) async {
      await open(tester, UserRole.finance, invoice: fakeInvoice());
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Waive'), findsNothing);
      expect(find.text('Void invoice'), findsNothing);
      expect(find.text('Print'), findsOneWidget);
    });

    testWidgets('an admin can collect, waive and void an unpaid invoice', (
      tester,
    ) async {
      await open(tester, UserRole.branchAdmin, invoice: fakeInvoice());
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Waive'), findsOneWidget);
      expect(find.text('Void invoice'), findsOneWidget);
    });

    testWidgets(
      'an invoice with a payment cannot be voided until it is reversed',
      (tester) async {
        await open(
          tester,
          UserRole.branchAdmin,
          invoice: fakeInvoice(paid: 30000),
        );
        expect(find.text('Void invoice'), findsNothing);
        expect(find.text('Collect payment'), findsOneWidget);
      },
    );

    testWidgets('a fully paid invoice offers no collection, waiver or void', (
      tester,
    ) async {
      await open(
        tester,
        UserRole.branchAdmin,
        invoice: fakeInvoice(paid: 100000),
      );
      expect(find.text('Collect payment'), findsNothing);
      expect(find.text('Waive'), findsNothing);
      expect(find.text('Void invoice'), findsNothing);
    });

    testWidgets(
      'a void invoice offers no money actions and says why it is void',
      (tester) async {
        await open(
          tester,
          UserRole.branchAdmin,
          invoice: fakeInvoice(status: InvoiceStatus.voided),
        );
        expect(find.text('Collect payment'), findsNothing);
        expect(find.text('Void invoice'), findsNothing);
        expect(find.text('Void'), findsWidgets);
      },
    );

    testWidgets('shows the fee lines, the totals and the balance', (
      tester,
    ) async {
      await open(
        tester,
        UserRole.finance,
        invoice: fakeInvoice(payable: 150000, paid: 50000),
      );
      expect(find.text('Tuition'), findsWidgets);
      expect(find.text('Payable'), findsOneWidget);
      expect(find.text('Balance due'), findsOneWidget);
      expect(find.text('₹1,000.00'), findsWidgets);
    });

    testWidgets(
      'finance does not see the reverse / refund control on an active payment',
      (tester) async {
        final pay = FakePaymentRepository(payments: [fakePayment()]);
        await open(
          tester,
          UserRole.finance,
          invoice: fakeInvoice(paid: 30000),
          payments: pay,
        );
        expect(find.byTooltip('Reverse or refund'), findsNothing);
      },
    );

    testWidgets(
      'an admin sees the reverse / refund control on an active payment',
      (tester) async {
        final pay = FakePaymentRepository(payments: [fakePayment()]);
        await open(
          tester,
          UserRole.branchAdmin,
          invoice: fakeInvoice(paid: 30000),
          payments: pay,
        );
        expect(find.byTooltip('Reverse or refund'), findsOneWidget);
      },
    );

    testWidgets(
      'a reversed payment stays listed, marked, with no further reverse control',
      (tester) async {
        final pay = FakePaymentRepository(
          payments: [fakePayment(status: PaymentStatus.reversed)],
        );
        await open(
          tester,
          UserRole.branchAdmin,
          invoice: fakeInvoice(),
          payments: pay,
        );
        expect(find.text('Reversed'), findsOneWidget);
        expect(find.byTooltip('Reverse or refund'), findsNothing);
      },
    );
  });

  group('collecting a payment', () {
    Future<(_World, FakePaymentRepository)> start(
      WidgetTester tester, {
      dynamic invoice,
      FakePaymentRepository? pay,
    }) async {
      final payments = pay ?? FakePaymentRepository();
      final w = await _pump(
        tester,
        role: UserRole.finance,
        invoiceRepo: FakeInvoiceRepository(
          invoices: [invoice ?? fakeInvoice(payable: 100000)],
        ),
        paymentRepo: payments,
      );
      await w.go(tester, '/fees/invoices/stu-1__y1__M-2026-06');
      await tester.tap(find.text('Collect payment'));
      await tester.pumpAndSettle();
      return (w, payments);
    }

    testWidgets(
      'the amount defaults to the balance and a full payment is recorded with all details',
      (tester) async {
        final (_, pay) = await start(tester);
        expect(
          find.widgetWithText(TextFormField, 'Amount (INR)'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Amount (INR)'),
              )
              .controller!
              .text,
          '1000.00',
        );

        await tester.tap(_filled('Record payment'));
        await tester.pumpAndSettle();

        expect(pay.collected, hasLength(1));
        final r = pay.collected.single;
        expect(r.amountMinor, 100000);
        expect(r.method, PaymentMethod.cash);
        expect(r.invoiceId, 'stu-1__y1__M-2026-06');
        expect(r.paymentDateKey, FeeDates.todayKey());
        expect(r.collectorId, _uid);
        expect(r.collectorName, 'Fin Officer');
        expect(r.paymentId, startsWith('pay_'));
        expect(
          r.info.academicYearStartYear,
          2026,
          reason: 'receipt numbering follows the invoice year',
        );
        expect(find.text('Payment recorded successfully.'), findsOneWidget);
      },
    );

    testWidgets('a partial payment is accepted', (tester) async {
      final (_, pay) = await start(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (INR)'),
        '250.50',
      );
      await tester.tap(_filled('Record payment'));
      await tester.pumpAndSettle();
      expect(pay.collected.single.amountMinor, 25050);
    });

    testWidgets('OVERPAYMENT is blocked in the form and nothing is sent', (
      tester,
    ) async {
      final (_, pay) = await start(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (INR)'),
        '1000.01',
      );
      await tester.tap(_filled('Record payment'));
      await tester.pumpAndSettle();
      expect(find.text('More than the balance due.'), findsOneWidget);
      expect(pay.collected, isEmpty);
    });

    testWidgets('zero, negative and malformed amounts are blocked', (
      tester,
    ) async {
      final (_, pay) = await start(tester);
      for (final bad in ['0', '-5', 'abc', '10.123', '']) {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount (INR)'),
          bad,
        );
        await tester.tap(_filled('Record payment'));
        await tester.pumpAndSettle();
        expect(pay.collected, isEmpty, reason: bad);
      }
    });

    testWidgets('UPI needs a reference number', (tester) async {
      final (_, pay) = await start(tester);
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<PaymentMethod>,
          'Payment method',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('UPI').last);
      await tester.pumpAndSettle();
      await tester.tap(_filled('Record payment'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the reference number.'), findsOneWidget);
      expect(pay.collected, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Transaction / reference number'),
        'UTR12345678',
      );
      await tester.tap(_filled('Record payment'));
      await tester.pumpAndSettle();
      expect(pay.collected.single.method, PaymentMethod.upi);
      expect(pay.collected.single.referenceNo, 'UTR12345678');
    });

    testWidgets(
      'DOUBLE-CLICK: pressing Record twice while the first is in flight sends exactly one request',
      (tester) async {
        final gate = Completer<void>();
        final pay = FakePaymentRepository()..gate = () => gate.future;
        await start(tester, pay: pay);
        await tester.tap(_filled('Record payment'));
        await tester.pump();
        await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
        await tester.pump();
        expect(pay.collected, hasLength(1));
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
          isNull,
          reason: 'disabled while saving',
        );
        gate.complete();
        await tester.pumpAndSettle();
        expect(pay.collected, hasLength(1));
      },
    );

    testWidgets(
      'IDEMPOTENCY KEY: after a failure, retrying reuses the SAME payment id',
      (tester) async {
        final pay = FakePaymentRepository()
          ..collectError = const NetworkFailure();
        await start(tester, pay: pay);
        await tester.tap(_filled('Record payment'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'No internet connection. Please check your network and try again.',
          ),
          findsOneWidget,
        );
        expect(pay.collected, hasLength(1));
        ScaffoldMessenger.of(
          tester.element(find.byType(Scaffold).first),
        ).clearSnackBars();
        await tester.pumpAndSettle();

        await tester.tap(_filled('Record payment'));
        await tester.pumpAndSettle();
        expect(pay.collected, hasLength(2));
        expect(pay.collected.first.paymentId, pay.collected.last.paymentId);
        expect(find.text('Payment recorded successfully.'), findsOneWidget);
      },
    );

    testWidgets('success is announced only after the write completes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final pay = FakePaymentRepository()..gate = () => gate.future;
      await start(tester, pay: pay);
      await tester.tap(_filled('Record payment'));
      await tester.pump();
      expect(find.text('Payment recorded successfully.'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Payment recorded successfully.'), findsOneWidget);
    });

    testWidgets(
      'a refused payment shows the reason, keeps the dialog, and leaks no raw error',
      (tester) async {
        final pay = FakePaymentRepository()
          ..collectError = const ValidationFailure(
            'The amount is more than the balance due (₹500.00). Overpayment is not accepted.',
          );
        await start(tester, pay: pay);
        await tester.tap(_filled('Record payment'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Overpayment is not accepted'),
          findsOneWidget,
        );
        expect(find.text('Collect payment'), findsWidgets);
      },
    );

    testWidgets('a partially paid invoice defaults to the remaining balance', (
      tester,
    ) async {
      await start(tester, invoice: fakeInvoice(payable: 100000, paid: 30000));
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Amount (INR)'),
            )
            .controller!
            .text,
        '700.00',
      );
    });
  });

  group('reversal, waiver and void need a reason', () {
    testWidgets(
      'reversing a payment requires a reason and sends the chosen kind',
      (tester) async {
        final pay = FakePaymentRepository(payments: [fakePayment()]);
        final w = await _pump(
          tester,
          role: UserRole.branchAdmin,
          invoiceRepo: FakeInvoiceRepository(
            invoices: [fakeInvoice(paid: 30000)],
          ),
          paymentRepo: pay,
        );
        await w.go(tester, '/fees/invoices/stu-1__y1__M-2026-06');
        await tester.tap(find.byTooltip('Reverse or refund'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(find.text('Give a reason.'), findsOneWidget);
        expect(pay.reversed, isEmpty);

        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<ReversalKind>, 'Type'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refund').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            'Reason (recorded in the audit log)',
          ),
          'Parent withdrew the child',
        );
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(pay.reversed.single.kind, ReversalKind.refund);
        expect(pay.reversed.single.reason, 'Parent withdrew the child');
      },
    );

    testWidgets('a waiver cannot exceed the balance and needs a reason', (
      tester,
    ) async {
      final repo = FakeInvoiceRepository(
        invoices: [fakeInvoice(payable: 100000, paid: 40000)],
      );
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        invoiceRepo: repo,
      );
      await w.go(tester, '/fees/invoices/stu-1__y1__M-2026-06');
      await tester.tap(find.text('Waive'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Waiver amount (INR)'),
        '600.01',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Reason (recorded in the audit log)',
        ),
        'Hardship',
      );
      await tester.tap(find.text('Approve waiver'));
      await tester.pumpAndSettle();
      expect(find.textContaining('More than'), findsOneWidget);
      expect(repo.waivers, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Waiver amount (INR)'),
        '250',
      );
      await tester.tap(find.text('Approve waiver'));
      await tester.pumpAndSettle();
      expect(repo.waivers.single.amount, 25000);
      expect(repo.waivers.single.reason, 'Hardship');
    });

    testWidgets('voiding asks for a reason first', (tester) async {
      final repo = FakeInvoiceRepository(invoices: [fakeInvoice()]);
      final w = await _pump(
        tester,
        role: UserRole.branchAdmin,
        invoiceRepo: repo,
      );
      await w.go(tester, '/fees/invoices/stu-1__y1__M-2026-06');
      await tester.tap(find.text('Void invoice'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Void invoice'));
      await tester.pumpAndSettle();
      expect(repo.voids, isEmpty);
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Reason (recorded in the audit log)',
        ),
        'Issued twice',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Void invoice'));
      await tester.pumpAndSettle();
      expect(repo.voids.single.reason, 'Issued twice');
    });
  });

  group('bulk invoice generation', () {
    BillingContext context({
      Set<String> invoices = const {},
      Set<String> charges = const {},
    }) {
      final s1 = fakeStructure(code: 'TUITION', amount: 100000);
      FeeStudent student(String id, {bool enrolled = true}) => FeeStudent(
        studentId: id,
        name: 'Student $id',
        admissionNumber: 'ADM-$id',
        classId: 'c5',
        className: 'Class 5',
        sectionId: 'sa',
        sectionName: 'A',
        isEnrolled: enrolled,
      );
      StudentFeeAssignment assignment(String id) => StudentFeeAssignment(
        assignmentId: StudentFeeAssignment.idFor(id, s1.structureId),
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'y1',
        studentId: id,
        structureId: s1.structureId,
        structureName: 'Tuition',
        classId: 'c5',
        sectionId: 'sa',
      );
      return BillingContext(
        students: [student('1'), student('2'), student('3', enrolled: false)],
        assignmentsByStudent: {
          for (final id in ['1', '2', '3'])
            id: [BillableAssignment(assignment(id), s1)],
        },
        existingChargeIds: charges,
        existingInvoiceIds: invoices,
      );
    }

    Future<_World> openGenerate(
      WidgetTester tester,
      FakeInvoiceRepository repo,
    ) async {
      final w = await _pump(tester, role: UserRole.finance, invoiceRepo: repo);
      await w.go(tester, '/fees/invoices/generate');
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Class'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 5').last);
      await tester.pumpAndSettle();
      return w;
    }

    testWidgets(
      'preview first: who is billed, the total, and who is skipped and why — nothing is written yet',
      (tester) async {
        final repo = FakeInvoiceRepository()..context = context();
        await openGenerate(tester, repo);
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Preview ·'), findsOneWidget);
        expect(find.text('2 invoices'), findsOneWidget);
        expect(find.text('Total ₹2,000.00'), findsOneWidget);
        expect(find.text('1 student(s) will not be invoiced'), findsOneWidget);
        expect(repo.generated, isEmpty);
        await tester.pumpAndSettle();
        expect(find.textContaining('Not currently enrolled'), findsOneWidget);
      },
    );

    testWidgets(
      'confirming generates exactly the previewed invoices and reports the result',
      (tester) async {
        final repo = FakeInvoiceRepository()..context = context();
        await openGenerate(tester, repo);
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        await tester.tap(_filled('Generate 2 invoices'));
        await tester.pumpAndSettle();
        expect(find.text('Generate invoices?'), findsOneWidget);
        expect(find.textContaining('2 invoices for'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Generate').last);
        await tester.pumpAndSettle();

        expect(repo.generated.single.count, 2);
        expect(repo.generated.single.period, startsWith('M-'));
        expect(find.text('2 invoices generated.'), findsOneWidget);
      },
    );

    testWidgets('cancelling the confirmation writes nothing', (tester) async {
      final repo = FakeInvoiceRepository()..context = context();
      await openGenerate(tester, repo);
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await tester.tap(_filled('Generate 2 invoices'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.generated, isEmpty);
    });

    testWidgets(
      'students already invoiced for the period are excluded from the preview (re-run safety)',
      (tester) async {
        final repo = FakeInvoiceRepository()
          ..context = context(invoices: {'1__y1__M-2026-06'}, charges: {});
        await openGenerate(tester, repo);
        // choose the same month the invoice id above encodes
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<int>, 'Month'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('June 2026').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        expect(find.text('1 invoices'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.textContaining('Already invoiced'), findsOneWidget);
      },
    );

    testWidgets('a custom or one-time run needs a name', (tester) async {
      final repo = FakeInvoiceRepository()..context = context();
      await openGenerate(tester, repo);
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<FeeFrequency>,
          'Billing period',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom period').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least 3 characters'), findsOneWidget);
      expect(repo.generated, isEmpty);
    });

    testWidgets('Preview is disabled until a class is chosen', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.finance,
        invoiceRepo: FakeInvoiceRepository()..context = context(),
      );
      await w.go(tester, '/fees/invoices/generate');
      expect(tester.widget<FilledButton>(_filled('Preview')).onPressed, isNull);
    });
  });

  group('bulk fee assignment', () {
    testWidgets(
      'preview shows the breakdown and skipped students; confirm assigns only the previewed ones',
      (tester) async {
        final config = FakeFeeConfigRepository(
          structures: [fakeStructure(code: 'TUITION', amount: 100000)],
          students: [
            for (final (id, enrolled) in [
              ('1', true),
              ('2', true),
              ('3', false),
            ])
              FeeStudent(
                studentId: id,
                name: 'Student $id',
                admissionNumber: 'A$id',
                classId: 'c5',
                className: 'Class 5',
                sectionId: 'sa',
                sectionName: 'A',
                isEnrolled: enrolled,
              ),
          ],
          assignments: [
            StudentFeeAssignment(
              assignmentId: StudentFeeAssignment.idFor('2', 'y1__tuition'),
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y1',
              studentId: '2',
              structureId: 'y1__tuition',
              structureName: 'Tuition',
              classId: 'c5',
              sectionId: 'sa',
            ),
          ],
        );
        final w = await _pump(tester, role: UserRole.finance, config: config);
        await w.go(tester, '/fees/assign');
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<String>, 'Class'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Class 5').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load students'));
        await tester.pumpAndSettle();

        expect(find.textContaining('all 3 students'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find
                    .ancestor(
                      of: find.text('Preview assignment'),
                      matching: find.byWidgetPredicate(
                        (w) => w is OutlinedButton,
                      ),
                    )
                    .first,
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byType(CheckboxListTile).first);
        await tester.pumpAndSettle();
        await tester.tap(_outlined('Preview assignment'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Tuition: 1 students'), findsOneWidget);
        expect(find.text('2 skipped'), findsOneWidget);
        expect(
          config.bulkCreated,
          isEmpty,
          reason: 'previewing writes nothing',
        );

        await tester.tap(_filled('Assign 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Assign').last);
        await tester.pumpAndSettle();
        expect(config.bulkCreated, [1]);
      },
    );
  });

  group('parent portal', () {
    final child = fakeStudent('stu-1', 'Anil');

    testWidgets(
      'a parent sees their linked child\'s billed / paid / due figures, invoices, payments — read only',
      (tester) async {
        final invoices = FakeInvoiceRepository(
          invoices: [
            fakeInvoice(payable: 100000, paid: 40000, due: '2020-01-01'),
            fakeInvoice(
              id: 'stu-1__y1__M-2026-07',
              number: 'INV-2026-000002',
              payable: 100000,
              due: '2099-01-01',
            ),
          ],
        );
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'parent-1',
          children: [child],
          invoiceRepo: invoices,
          paymentRepo: FakePaymentRepository(payments: [fakePayment()]),
        );
        await w.go(tester, '/my-fees');

        expect(find.text('Anil Kumar'), findsWidgets);
        expect(find.text('Total billed'), findsOneWidget);
        expect(find.text('₹2,000.00'), findsOneWidget);
        expect(find.text('Overdue'), findsWidgets);
        expect(find.text('INV-2026-000001 · June 2026'), findsOneWidget);
        expect(find.textContaining('RCT-2026-000001'), findsOneWidget);
        expect(find.text('Collect payment'), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets(
      'opening an invoice shows no financial actions (no collect / waive / void / reverse)',
      (tester) async {
        final invoices = FakeInvoiceRepository(
          invoices: [fakeInvoice(payable: 100000, paid: 30000)],
        );
        final w = await _pump(
          tester,
          role: UserRole.parent,
          linkedParentId: 'parent-1',
          children: [child],
          invoiceRepo: invoices,
          paymentRepo: FakePaymentRepository(payments: [fakePayment()]),
        );
        await w.go(tester, '/my-fees');
        await tester.tap(find.text('INV-2026-000001 · June 2026'));
        await tester.pumpAndSettle();
        expect(find.text('Balance due'), findsOneWidget);
        for (final forbidden in ['Collect payment', 'Waive', 'Void invoice']) {
          expect(find.text(forbidden), findsNothing, reason: forbidden);
        }
        expect(find.byTooltip('Reverse or refund'), findsNothing);
        expect(
          find.text('Print'),
          findsOneWidget,
          reason: 'a parent may print their own invoice',
        );
      },
    );

    testWidgets('with several children the parent can switch between them', (
      tester,
    ) async {
      final second = fakeStudent('stu-2', 'Bina');
      final invoices = FakeInvoiceRepository(
        invoices: [
          fakeInvoice(),
          fakeInvoice(
            id: 'stu-2__y1__M-2026-06',
            number: 'INV-2026-000002',
            studentId: 'stu-2',
            studentName: 'Bina Kumar',
          ),
        ],
      );
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: [child, second],
        invoiceRepo: invoices,
      );
      await w.go(tester, '/my-fees');
      expect(find.text('INV-2026-000001 · June 2026'), findsOneWidget);
      expect(find.text('INV-2026-000002 · June 2026'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bina Kumar'));
      await tester.pumpAndSettle();
      expect(find.text('INV-2026-000002 · June 2026'), findsOneWidget);
      expect(find.text('INV-2026-000001 · June 2026'), findsNothing);
    });

    testWidgets(
      'a parent account with no linked parent record, or no children, gets a clear explanation',
      (tester) async {
        final unlinked = await _pump(tester, role: UserRole.parent);
        await unlinked.go(tester, '/my-fees');
        expect(
          find.textContaining("isn't linked to a parent record"),
          findsOneWidget,
        );
      },
    );

    testWidgets('no children with fee access yet', (tester) async {
      final w = await _pump(
        tester,
        role: UserRole.parent,
        linkedParentId: 'parent-1',
        children: const [],
      );
      await w.go(tester, '/my-fees');
      expect(find.textContaining('No children are linked'), findsOneWidget);
    });

    for (final size in [const Size(360, 800), const Size(1400, 900)]) {
      testWidgets(
        'the parent screen has no overflow at ${size.width.toInt()}px',
        (tester) async {
          final w = await _pump(
            tester,
            role: UserRole.parent,
            linkedParentId: 'parent-1',
            children: [child],
            invoiceRepo: FakeInvoiceRepository(
              invoices: [fakeInvoice(paid: 30000)],
            ),
            paymentRepo: FakePaymentRepository(payments: [fakePayment()]),
            size: size,
          );
          await w.go(tester, '/my-fees');
          expect(find.text('Total billed'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('payments and receipts history', () {
    testWidgets('lists payments including reversed ones, marked', (
      tester,
    ) async {
      final pay = FakePaymentRepository(
        payments: [
          fakePayment(),
          fakePayment(id: 'pay-2', status: PaymentStatus.reversed),
        ],
      );
      final w = await _pump(tester, role: UserRole.finance, paymentRepo: pay);
      await w.go(tester, '/fees/payments');
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Reversed'), findsWidgets);
    });

    testWidgets('empty history', (tester) async {
      final w = await _pump(tester, role: UserRole.finance);
      await w.go(tester, '/fees/payments');
      expect(find.text('No payments found.'), findsOneWidget);
    });
  });
}
