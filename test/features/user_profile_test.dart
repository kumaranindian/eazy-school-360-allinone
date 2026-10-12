import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromFirestore parses role/status enums from their wire values', () {
    final profile = UserProfile.fromFirestore('uid-1', {
      'schoolId': 'school-1',
      'branchId': 'main',
      'name': 'Ada Lovelace',
      'email': 'ada@example.com',
      'phone': null,
      'photoUrl': null,
      'role': 'TEACHER',
      'status': 'ACTIVE',
    });

    expect(profile.userId, 'uid-1');
    expect(profile.schoolId, 'school-1');
    expect(profile.branchId, 'main');
    expect(profile.role, UserRole.teacher);
    expect(profile.status, UserStatus.active);
    expect(profile.isActive, isTrue);
  });

  test(
    'toFirestoreCreate writes the exact wire values firestore.rules expects',
    () {
      const profile = UserProfile(
        userId: 'uid-1',
        schoolId: 'school-1',
        branchId: 'main',
        name: 'Ada Lovelace',
        email: 'ada@example.com',
        role: UserRole.schoolAdmin,
        status: UserStatus.active,
      );

      final data = profile.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['role'], 'SCHOOL_ADMIN');
      expect(data['status'], 'ACTIVE');
      expect(data['schoolId'], 'school-1');
      expect(data['branchId'], 'main');
      expect(data['createdBy'], 'uid-1');
      expect(data['updatedBy'], 'uid-1');
    },
  );

  test('platformAdmin profile allows a null schoolId/branchId', () {
    const profile = UserProfile(
      userId: 'uid-platform',
      schoolId: null,
      branchId: null,
      name: 'Platform Owner',
      email: 'owner@example.com',
      role: UserRole.platformAdmin,
      status: UserStatus.active,
    );

    expect(profile.schoolId, isNull);
    expect(profile.branchId, isNull);
    expect(profile.role.isSchoolScoped, isFalse);
  });

  test(
    'toFirestoreSelfUpdate never includes role/schoolId/branchId/status',
    () {
      const profile = UserProfile(
        userId: 'uid-1',
        schoolId: 'school-1',
        branchId: 'main',
        name: 'Ada Lovelace',
        email: 'ada@example.com',
        role: UserRole.teacher,
        status: UserStatus.active,
      );

      final data = profile.toFirestoreSelfUpdate(updatedBy: 'uid-1');

      expect(data.containsKey('role'), isFalse);
      expect(data.containsKey('schoolId'), isFalse);
      expect(data.containsKey('branchId'), isFalse);
      expect(data.containsKey('status'), isFalse);
    },
  );
}
