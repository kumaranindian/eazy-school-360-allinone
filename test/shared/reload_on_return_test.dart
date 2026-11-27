import 'package:eazy_school_360/shared/paging/reload_on_return.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// STU-01-DEF-02 / HW-01-DEF-01 / COM-01-DEF-01: a list that fetched once
// reloads when its route is current again after a child page (create).
int reloads = 0;

class _List extends StatefulWidget {
  const _List();
  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with ReloadOnReturn {
  @override
  void onReturn() => reloads++;

  @override
  Widget build(BuildContext context) => const Text('list');
}

void main() {
  testWidgets('reloads after a child route closes, not before', (tester) async {
    reloads = 0;
    final router = GoRouter(
      initialLocation: '/students',
      routes: [
        GoRoute(
          path: '/students',
          builder: (_, __) => const Scaffold(body: _List()),
          routes: [
            GoRoute(
              path: 'new',
              builder: (_, __) => const Scaffold(body: Text('admit')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(reloads, 0);

    router.push('/students/new');
    await tester.pumpAndSettle();
    expect(reloads, 0);

    router.pop();
    await tester.pumpAndSettle();
    expect(reloads, 1);

    router.go('/students/new');
    await tester.pumpAndSettle();
    router.go('/students');
    await tester.pumpAndSettle();
    expect(reloads, 2);
  });
}
