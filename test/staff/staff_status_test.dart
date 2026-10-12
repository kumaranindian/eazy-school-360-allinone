import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wire values match firestore.rules and round-trip', () {
    expect(StaffStatus.values.map((s) => s.wireValue), [
      'ACTIVE',
      'INACTIVE',
      'ON_NOTICE',
      'RESIGNED',
      'TERMINATED',
      'RETIRED',
    ]);
    for (final status in StaffStatus.values) {
      expect(StaffStatus.fromWireValue(status.wireValue), status);
    }
  });

  test('resigned, terminated and retired are terminal and allow no moves', () {
    for (final status in [
      StaffStatus.resigned,
      StaffStatus.terminated,
      StaffStatus.retired,
    ]) {
      expect(status.isTerminal, isTrue);
      expect(status.allowedTransitions, isEmpty);
      expect(status.transitionError(StaffStatus.active), isNotNull);
    }
    expect(StaffStatus.terminal, {
      StaffStatus.resigned,
      StaffStatus.terminated,
      StaffStatus.retired,
    });
  });

  test('ACTIVE can move to every other status', () {
    expect(
      StaffStatus.active.allowedTransitions,
      StaffStatus.values.toSet()..remove(StaffStatus.active),
    );
  });

  test('ACTIVE -> ON_NOTICE -> RESIGNED is a valid path', () {
    expect(StaffStatus.active.canTransitionTo(StaffStatus.onNotice), isTrue);
    expect(StaffStatus.onNotice.canTransitionTo(StaffStatus.resigned), isTrue);
  });

  test(
    'ACTIVE <-> INACTIVE is reversible; INACTIVE cannot jump to a terminal status',
    () {
      expect(StaffStatus.active.canTransitionTo(StaffStatus.inactive), isTrue);
      expect(StaffStatus.inactive.canTransitionTo(StaffStatus.active), isTrue);
      expect(
        StaffStatus.inactive.canTransitionTo(StaffStatus.resigned),
        isFalse,
      );
      expect(
        StaffStatus.inactive.canTransitionTo(StaffStatus.retired),
        isFalse,
      );
    },
  );

  test('a notice period can be withdrawn but cannot end as retired', () {
    expect(StaffStatus.onNotice.canTransitionTo(StaffStatus.active), isTrue);
    expect(StaffStatus.onNotice.canTransitionTo(StaffStatus.retired), isFalse);
  });

  test('no status can transition to itself', () {
    for (final status in StaffStatus.values) {
      expect(status.canTransitionTo(status), isFalse);
    }
  });

  test(
    'transitionError is null for a legal move and explains an illegal one',
    () {
      expect(StaffStatus.active.transitionError(StaffStatus.inactive), isNull);
      expect(
        StaffStatus.resigned.transitionError(StaffStatus.active),
        contains('resigned'),
      );
      expect(
        StaffStatus.resigned.transitionError(StaffStatus.active),
        contains('active'),
      );
    },
  );

  test('only ACTIVE staff can receive new assignments', () {
    expect(StaffStatus.values.where((s) => s.canReceiveAssignments), [
      StaffStatus.active,
    ]);
  });

  test('leaving the workforce ends assignments; going on notice does not', () {
    expect(StaffStatus.onNotice.endsActiveAssignments, isFalse);
    expect(StaffStatus.active.endsActiveAssignments, isFalse);
    for (final status in [
      StaffStatus.inactive,
      StaffStatus.resigned,
      StaffStatus.terminated,
      StaffStatus.retired,
    ]) {
      expect(status.endsActiveAssignments, isTrue, reason: status.name);
    }
  });
}
