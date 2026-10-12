import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const school = School(
    schoolId: 'school-1',
    name: 'Rosewood High',
    email: 'office@rosewood.example',
    status: SchoolStatus.active,
  );

  test(
    'fromFirestore parses every profile field, including the new Milestone 2 ones',
    () {
      final parsed = School.fromFirestore('school-1', {
        'name': 'Rosewood High',
        'shortName': 'RH',
        'code': 'RWD',
        'email': 'office@rosewood.example',
        'alternatePhone': '999',
        'website': 'https://rosewood.example',
        'addressLine1': '1 Main St',
        'postalCode': '12345',
        'defaultBranchId': 'main',
        'status': 'ACTIVE',
      });

      expect(parsed.shortName, 'RH');
      expect(parsed.code, 'RWD');
      expect(parsed.website, 'https://rosewood.example');
      expect(parsed.postalCode, '12345');
      expect(parsed.defaultBranchId, 'main');
    },
  );

  test(
    'copyWith only changes the fields passed, leaving the rest (and status) untouched',
    () {
      final updated = school.copyWith(name: 'New Name', city: 'Springfield');
      expect(updated.name, 'New Name');
      expect(updated.city, 'Springfield');
      expect(updated.email, school.email);
      expect(updated.status, school.status);
    },
  );

  test(
    'toFirestoreProfileUpdate never includes status — that is a platform-only field',
    () {
      final data = school.toFirestoreProfileUpdate(updatedBy: 'uid-1');
      expect(data.containsKey('status'), isFalse);
      expect(data.containsKey('createdAt'), isFalse);
      expect(data.containsKey('createdBy'), isFalse);
    },
  );
}
