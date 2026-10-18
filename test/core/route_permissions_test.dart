import 'dart:io';

import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

/// ROUTE-1: every route is either listed in `requiredPermissions` or is
/// deliberately open to any signed-in user. A new route cannot be forgotten.
void main() {
  test('every AppRoutes path has a permission or is explicitly open', () {
    const open = {
      'login',
      'register',
      'forgotPassword',
      'accountInactive',
      'changePassword',
      'createSchool',
      'dashboard',
    };
    final src = File('lib/core/routing/app_routes.dart').readAsStringSync();
    final paths = {
      for (final m in RegExp(
        r"static const String (\w+) =\s*'([^']+)'",
      ).allMatches(src))
        m.group(1)!: m.group(2)!,
    };
    expect(paths.length, greaterThan(50));
    final missing = [
      for (final e in paths.entries)
        if (!open.contains(e.key) &&
            !AppRoutes.requiredPermissions.containsKey(e.value))
          '${e.key} (${e.value})',
    ];
    expect(missing, isEmpty);
  });
}
