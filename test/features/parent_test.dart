import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/students/domain/parent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('displayName omits an absent middle name', () {
    const parent = Parent(
      parentId: 'p1',
      schoolId: 's1',
      branchId: 'main',
      firstName: 'Rekha',
      lastName: 'Kumar',
      phone: '9999999999',
      status: ActivationStatus.active,
    );
    expect(parent.displayName, 'Rekha Kumar');
  });

  test('hasPortalAccess reflects linkedUserId, not status', () {
    const withLink = Parent(
      parentId: 'p1',
      schoolId: 's1',
      branchId: 'main',
      firstName: 'Rekha',
      lastName: 'Kumar',
      phone: '9999999999',
      status: ActivationStatus.active,
      linkedUserId: 'uid-1',
    );
    const withoutLink = Parent(
      parentId: 'p1',
      schoolId: 's1',
      branchId: 'main',
      firstName: 'Rekha',
      lastName: 'Kumar',
      phone: '9999999999',
      status: ActivationStatus.active,
    );

    expect(withLink.hasPortalAccess, isTrue);
    expect(withoutLink.hasPortalAccess, isFalse);
  });

  test(
    'toFirestoreCreate derives displayNameLower for prefix search and starts unlinked',
    () {
      const parent = Parent(
        parentId: '',
        schoolId: 's1',
        branchId: 'main',
        firstName: 'Rekha',
        lastName: 'Kumar',
        phone: '9999999999',
        status: ActivationStatus.active,
      );
      final data = parent.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['displayNameLower'], 'rekha kumar');
      expect(data['linkedUserId'], isNull);
      expect(data['status'], 'ACTIVE');
    },
  );

  test(
    'toFirestoreUpdate does not reset linkedUserId — portal-access linking is a separate operation',
    () {
      const parent = Parent(
        parentId: 'p1',
        schoolId: 's1',
        branchId: 'main',
        firstName: 'Rekha',
        lastName: 'Kumar',
        phone: '9999999999',
        status: ActivationStatus.active,
      );
      final data = parent.toFirestoreUpdate(updatedBy: 'uid-1');

      expect(data.containsKey('linkedUserId'), isFalse);
    },
  );

  test('fromFirestore round-trips contact fields and status', () {
    final parent = Parent.fromFirestore('s1', 'main', 'p1', {
      'firstName': 'Rekha',
      'lastName': 'Kumar',
      'phone': '9999999999',
      'status': 'ACTIVE',
      'linkedUserId': 'uid-1',
    });

    expect(parent.displayName, 'Rekha Kumar');
    expect(parent.status, ActivationStatus.active);
    expect(parent.linkedUserId, 'uid-1');
  });
}
