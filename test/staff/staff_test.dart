import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/staff/domain/employment_type.dart';
import 'package:eazy_school_360/features/staff/domain/staff.dart';
import 'package:eazy_school_360/features/staff/domain/staff_search_field.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/students/domain/blood_group.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:flutter_test/flutter_test.dart';

Staff _staff({
  String? middleName,
  String? email,
  StaffStatus status = StaffStatus.active,
  String? userId,
  String? photoUrl,
  bool isTeacher = true,
}) {
  return Staff(
    staffId: 'staff-1',
    schoolId: 'school-1',
    branchId: 'main',
    employeeCode: 'EMP-0001',
    firstName: 'Priya',
    middleName: middleName,
    lastName: 'Sharma',
    photoUrl: photoUrl,
    dateOfBirth: DateTime(1990, 5, 1),
    gender: Gender.female,
    bloodGroup: BloodGroup.oPositive,
    phone: '9876543210',
    email: email,
    joiningDate: DateTime(2020, 6, 1),
    employmentType: EmploymentType.fullTime,
    departmentId: 'academic',
    designationId: 'senior-teacher',
    status: status,
    isTeacher: isTeacher,
    userId: userId,
  );
}

void main() {
  group('names and codes', () {
    test(
      'displayName joins first/middle/last, skipping an empty middle name',
      () {
        expect(
          Staff.computeDisplayName('Priya', null, 'Sharma'),
          'Priya Sharma',
        );
        expect(
          Staff.computeDisplayName('Priya', '  ', 'Sharma'),
          'Priya Sharma',
        );
        expect(_staff(middleName: 'K').displayName, 'Priya K Sharma');
      },
    );

    test(
      'employee codes compare case-insensitively and ignore surrounding spaces',
      () {
        expect(Staff.normalizeEmployeeCode(' EMP-0001 '), 'emp-0001');
        expect(
          Staff.normalizeEmployeeCode('Emp-0001'),
          Staff.normalizeEmployeeCode('EMP-0001'),
        );
      },
    );

    test('employee code pattern accepts safe ids and rejects the rest', () {
      for (final ok in ['EMP-0001', 'T_12', 'ab', 'A' * 20]) {
        expect(Staff.employeeCodePattern.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'A', 'has space', 'a/b', 'x.y', 'A' * 21, 'ünï']) {
        expect(Staff.employeeCodePattern.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });

  group('toFirestoreCreate', () {
    test(
      'derives searchable fields and writes wire values firestore.rules expects',
      () {
        final data = _staff(
          email: 'Priya@School.org',
        ).toFirestoreCreate(createdBy: 'admin-1');

        expect(data['schoolId'], 'school-1');
        expect(data['branchId'], 'main');
        expect(data['employeeCode'], 'EMP-0001');
        expect(data['employeeCodeLower'], 'emp-0001');
        expect(data['displayName'], 'Priya Sharma');
        expect(data['displayNameLower'], 'priya sharma');
        expect(data['emailLower'], 'priya@school.org');
        expect(data['gender'], 'FEMALE');
        expect(data['bloodGroup'], 'O_POSITIVE');
        expect(data['employmentType'], 'FULL_TIME');
        expect(data['isTeacher'], isTrue);
        expect(data['createdBy'], 'admin-1');
        expect(data['updatedBy'], 'admin-1');
        expect(data['createdAt'], isA<FieldValue>());
      },
    );

    test(
      'a new member always starts ACTIVE, unlinked and without a photo, whatever the instance says',
      () {
        final data = _staff(
          status: StaffStatus.retired,
          userId: 'u-1',
          photoUrl: 'https://x/y.png',
        ).toFirestoreCreate(createdBy: 'admin-1');
        expect(data['status'], 'ACTIVE');
        expect(data['userId'], isNull);
        expect(data['photoUrl'], isNull);
      },
    );

    test('a missing email stores null for both email fields', () {
      final data = _staff().toFirestoreCreate(createdBy: 'a');
      expect(data['email'], isNull);
      expect(data['emailLower'], isNull);
    });
  });

  group('toFirestoreProfileUpdate', () {
    test(
      'never writes status, photo, account link, tenant ids or creation audit',
      () {
        final data = _staff(
          status: StaffStatus.resigned,
          userId: 'u-1',
          photoUrl: 'https://x/y.png',
        ).toFirestoreProfileUpdate(updatedBy: 'admin-2');

        for (final protectedKey in [
          'status',
          'photoUrl',
          'userId',
          'schoolId',
          'branchId',
          'createdAt',
          'createdBy',
          'statusChangeReason',
        ]) {
          expect(
            data.containsKey(protectedKey),
            isFalse,
            reason: '$protectedKey must not be writable from a profile edit',
          );
        }
        expect(data['updatedBy'], 'admin-2');
        expect(data['updatedAt'], isA<FieldValue>());
      },
    );

    test(
      'every key it writes is one the firestore.rules update allow-list permits',
      () {
        // Mirrors the changedOnly([...]) list for /staff/{staffId} update.
        const allowed = {
          'employeeCode',
          'employeeCodeLower',
          'firstName',
          'middleName',
          'lastName',
          'displayName',
          'displayNameLower',
          'photoUrl',
          'dateOfBirth',
          'gender',
          'bloodGroup',
          'phone',
          'alternatePhone',
          'email',
          'emailLower',
          'address',
          'city',
          'state',
          'country',
          'postalCode',
          'joiningDate',
          'employmentType',
          'departmentId',
          'designationId',
          'isTeacher',
          'userId',
          'status',
          'statusChangeReason',
          'statusChangeDate',
          'statusChangeNotes',
          'updatedAt',
          'updatedBy',
        };
        final keys = _staff()
            .toFirestoreProfileUpdate(updatedBy: 'a')
            .keys
            .toSet();
        expect(
          allowed.containsAll(keys),
          isTrue,
          reason: 'unexpected: ${keys.difference(allowed)}',
        );
      },
    );
  });

  test(
    'firestoreStatusChange carries status, effective date, reason and notes only',
    () {
      final data = Staff.firestoreStatusChange(
        status: StaffStatus.onNotice,
        effectiveDate: DateTime(2026, 9, 1),
        reason: 'Relocating',
        notes: '30 days',
        updatedBy: 'admin-1',
      );
      expect(data['status'], 'ON_NOTICE');
      expect(
        (data['statusChangeDate'] as Timestamp).toDate(),
        DateTime(2026, 9, 1),
      );
      expect(data['statusChangeReason'], 'Relocating');
      expect(data['statusChangeNotes'], '30 days');
      expect(data.keys.toSet(), {
        'status',
        'statusChangeReason',
        'statusChangeDate',
        'statusChangeNotes',
        'updatedAt',
        'updatedBy',
      });
    },
  );

  test('fromFirestore round-trips what toFirestoreCreate writes', () {
    final original = _staff(middleName: 'K', email: 'p@s.org');
    final written = original.toFirestoreCreate(createdBy: 'admin-1')
      ..['createdAt'] = Timestamp.fromDate(DateTime(2026, 1, 1))
      ..['updatedAt'] = Timestamp.fromDate(DateTime(2026, 1, 1));
    final read = Staff.fromFirestore('school-1', 'main', 'staff-1', written);

    expect(read.employeeCode, original.employeeCode);
    expect(read.displayName, original.displayName);
    expect(read.dateOfBirth, original.dateOfBirth);
    expect(read.gender, Gender.female);
    expect(read.bloodGroup, BloodGroup.oPositive);
    expect(read.employmentType, EmploymentType.fullTime);
    expect(read.departmentId, 'academic');
    expect(read.isTeacher, isTrue);
    expect(read.status, StaffStatus.active);
    expect(read.createdBy, 'admin-1');
  });

  test(
    'a document without isTeacher (an older record) reads as not a teacher',
    () {
      final data = _staff().toFirestoreCreate(createdBy: 'a')
        ..['createdAt'] = Timestamp.now()
        ..['updatedAt'] = Timestamp.now()
        ..remove('isTeacher');
      expect(Staff.fromFirestore('s', 'b', 'id', data).isTeacher, isFalse);
    },
  );

  test('copyWith keeps identity, tenant and audit fields', () {
    final changed = _staff().copyWith(phone: '1', isTeacher: false);
    expect(changed.staffId, 'staff-1');
    expect(changed.schoolId, 'school-1');
    expect(changed.branchId, 'main');
    expect(changed.phone, '1');
    expect(changed.isTeacher, isFalse);
  });

  test('only an ACTIVE teacher can receive assignments', () {
    expect(_staff().canReceiveAssignments, isTrue);
    expect(_staff(isTeacher: false).canReceiveAssignments, isFalse);
    expect(_staff(status: StaffStatus.onNotice).canReceiveAssignments, isFalse);
    expect(_staff(status: StaffStatus.inactive).canReceiveAssignments, isFalse);
  });

  group('EmploymentType', () {
    test('wire values round-trip and match the documented set', () {
      expect(EmploymentType.values.map((e) => e.wireValue), [
        'FULL_TIME',
        'PART_TIME',
        'CONTRACT',
        'TEMPORARY',
        'INTERN',
        'OTHER',
      ]);
      for (final type in EmploymentType.values) {
        expect(EmploymentType.fromWireValue(type.wireValue), type);
        expect(type.displayName, isNotEmpty);
      }
    });
  });

  group('StaffSearchField', () {
    test('maps to indexed, normalized fields', () {
      expect(StaffSearchField.name.firestoreField, 'displayNameLower');
      expect(StaffSearchField.employeeCode.firestoreField, 'employeeCodeLower');
      expect(StaffSearchField.phone.firestoreField, 'phone');
      expect(StaffSearchField.email.firestoreField, 'emailLower');
    });

    test('normalizes the query the way the stored field is normalized', () {
      expect(StaffSearchField.name.normalize('  Priya S '), 'priya s');
      expect(StaffSearchField.employeeCode.normalize('EMP-0'), 'emp-0');
      expect(StaffSearchField.email.normalize('P@S.ORG'), 'p@s.org');
      expect(
        StaffSearchField.phone.normalize(' +91 98 '),
        '+91 98',
      ); // stored as typed
    });
  });
}
