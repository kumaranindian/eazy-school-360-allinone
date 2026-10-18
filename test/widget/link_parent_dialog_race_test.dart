import 'dart:async';
import 'package:eazy_school_360/core/constants/activation_status.dart';

import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/students/domain/parent.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/presentation/providers/parent_providers.dart';
import 'package:eazy_school_360/features/students/presentation/widgets/link_parent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Parent _parent(String id, String first) => Parent(
  parentId: id,
  schoolId: 's',
  branchId: 'b',
  firstName: first,
  lastName: 'Nair',
  phone: '9876543210',
  email: '$first@example.com',
  status: ActivationStatus.active,
);

/// Answers searches on demand so a test can make an older one finish last.
class _GatedParents implements ParentRepository {
  final gates = <String, Completer<void>>{};

  @override
  Future<PagedResult<Parent>> searchParentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    await gates[query]?.future;
    return PagedResult(items: [_parent('p-$query', query)], nextCursor: null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('STATE-2: a slow older search cannot overwrite a newer one', (
    tester,
  ) async {
    final repo = _GatedParents()..gates['Ab'] = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [parentRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          home: Scaffold(
            body: LinkParentDialog(
              schoolId: 's',
              branchId: 'b',
              studentId: 'st',
              currentUserId: 'u',
              alreadyLinkedParentIds: {},
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Ab'); // held open
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Raj'); // answers at once
    await tester.pumpAndSettle();
    expect(find.text('Raj Nair'), findsOneWidget);

    repo.gates['Ab']!.complete(); // the older request answers last
    await tester.pumpAndSettle();
    expect(find.text('Raj Nair'), findsOneWidget);
    expect(find.text('Ab Nair'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
