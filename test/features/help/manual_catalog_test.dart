import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/help/content/manual_content.dart';
import 'package:flutter_test/flutter_test.dart';

bool Function(Permission) _can(UserRole r) =>
    (p) => RolePermissions.roleHas(r, p);

Set<String> _ids(UserRole r) => {
  for (final g in manualCatalog.visibleTo(_can(r))) g.id,
};

void main() {
  test('guide ids are unique and every category and related id exists', () {
    final ids = manualCatalog.guides.map((g) => g.id).toList();
    expect(ids.toSet().length, ids.length);
    final cats = manualCatalog.categories.map((c) => c.id).toSet();
    for (final g in manualCatalog.guides) {
      expect(cats, contains(g.categoryId), reason: g.id);
      for (final r in g.related) {
        expect(ids, contains(r), reason: '${g.id} -> $r');
      }
    }
  });

  test('every step link is a real route the app can gate', () {
    // A linked screen must be permission-gated by the router, or be one of the
    // few deliberately open screens.
    const open = {AppRoutes.dashboard, AppRoutes.help, AppRoutes.deleteAccount};
    for (final g in manualCatalog.guides) {
      for (final s in g.steps) {
        if (s.route == null) continue;
        expect(
          open.contains(s.route) ||
              AppRoutes.requiredPermissions.containsKey(s.route),
          isTrue,
          reason: '${g.id}: ${s.route}',
        );
        expect(s.route, isNot(contains(':')), reason: 'needs parameters');
      }
      for (final r in g.contextRoutes) {
        expect(r, isNot(contains(':')), reason: '${g.id}: $r never matches');
      }
    }
  });

  test('reference pages have questions; step guides have steps', () {
    for (final g in manualCatalog.guides) {
      expect(
        g.steps.isNotEmpty || g.troubleshooting.isNotEmpty,
        isTrue,
        reason: g.id,
      );
    }
  });

  test('the main areas of the app each have a guide', () {
    final ids = manualCatalog.guides.map((g) => g.id).toSet();
    expect(
      ids,
      containsAll([
        'bell-schedule',
        'timetable-build',
        'substitution',
        'staff-add',
        'teacher-assign',
        'attendance-mark',
        'homework-publish',
        'homework-review',
        'grading-scheme',
        'exam-create',
        'marks-entry',
        'exam-results',
        'announcements',
        'messages-guide',
        'reports-guide',
        'parent-start',
        'parent-fees',
        'faq',
        'troubleshooting',
      ]),
    );
  });

  test('roles see only the guides their permissions allow', () {
    final teacher = _ids(UserRole.teacher);
    expect(teacher, contains('getting-started'));
    expect(teacher, contains('leave-apply'));
    expect(teacher, isNot(contains('invoices')));
    expect(teacher, isNot(contains('parent-login')));
    expect(teacher, isNot(contains('fee-structure')));
    expect(
      teacher,
      containsAll([
        'attendance-mark',
        'homework-publish',
        'marks-entry',
        'my-timetable',
      ]),
    );
    expect(teacher, isNot(contains('timetable-build')));

    final finance = _ids(UserRole.finance);
    expect(
      finance,
      containsAll(['fee-structure', 'fee-assign', 'invoices', 'payments']),
    );
    expect(finance, isNot(contains('admit-student')));

    final admin = _ids(UserRole.schoolAdmin);
    expect(
      admin,
      containsAll([
        'school-setup',
        'admit-student',
        'parent-login',
        'invoices',
      ]),
    );

    final parent = _ids(UserRole.parent);
    expect(parent, contains('getting-started'));
    expect(parent, isNot(contains('admit-student')));
    expect(parent, isNot(contains('invoices')));
    expect(
      parent,
      containsAll([
        'parent-start',
        'parent-fees',
        'parent-homework',
        'parent-results',
        'parent-attendance',
      ]),
    );
    expect(parent, isNot(contains('attendance-mark')));
  });

  test('search finds tasks by plain words, within the role', () {
    final admin = _can(UserRole.schoolAdmin);
    expect(
      manualCatalog.search('how to generate invoices', admin).first.id,
      'invoices',
    );
    expect(
      manualCatalog.search('create parent login', admin).first.id,
      'parent-login',
    );
    expect(manualCatalog.search('collect payment', admin).first.id, 'payments');
    expect(
      manualCatalog.search('bell timings period', admin).first.id,
      'bell-schedule',
    );
    expect(
      manualCatalog.search('enter marks', admin).map((g) => g.id),
      contains('marks-entry'),
    );
    expect(
      manualCatalog.search('substitute teacher', admin).first.id,
      'substitution',
    );
    expect(
      manualCatalog.search('invoices', _can(UserRole.teacher)).map((g) => g.id),
      isNot(contains('invoices')),
    );
    expect(manualCatalog.search('   ', admin), isEmpty);
  });

  test('a screen opens its own guide, and only if the user may see it', () {
    final admin = _can(UserRole.schoolAdmin);
    expect(
      manualCatalog.forPath(AppRoutes.generateInvoices, admin)?.id,
      'invoices',
    );
    expect(manualCatalog.forPath(AppRoutes.invoices, admin)?.id, 'invoices');
    expect(
      manualCatalog.forPath('/fees/invoices/abc123', admin)?.id,
      'invoices',
    );
    expect(
      manualCatalog.forPath(AppRoutes.newStudent, admin)?.id,
      'admit-student',
    );
    expect(
      manualCatalog.forPath(AppRoutes.invoices, _can(UserRole.teacher)),
      isNull,
    );
  });

  test('no guide promises features the app does not have', () {
    final text = [
      for (final g in manualCatalog.guides) ...[
        g.title,
        g.summary,
        for (final s in g.steps) s.instruction,
      ],
    ].join(' ').toLowerCase();
    expect(text, isNot(contains('razorpay')));
    expect(text, isNot(contains('pay online now')));
  });
}
