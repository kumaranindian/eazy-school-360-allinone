import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/staff/domain/department.dart';
import 'package:eazy_school_360/features/staff/domain/designation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Department', () {
    test(
      'the document id is the lower-cased, trimmed code — so a code can exist once per branch',
      () {
        expect(Department.idForCode(' ADM '), 'adm');
        expect(Department.idForCode('Finance_2'), 'finance_2');
        expect(Department.idForCode('ADM'), Department.idForCode('adm'));
      },
    );

    test('code pattern: 2-20 letters, digits, - or _', () {
      for (final ok in ['AD', 'Finance', 'a-b_c', 'X' * 20]) {
        expect(Department.codePattern.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'A', 'two words', 'a/b', 'X' * 21]) {
        expect(Department.codePattern.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test(
      'create writes the audit and tenant fields rules require, with ACTIVE status',
      () {
        final data = const Department(
          departmentId: 'adm',
          schoolId: 'school-1',
          branchId: 'main',
          name: 'Administration',
          code: ' ADM ',
          status: ActivationStatus.active,
        ).toFirestoreCreate(createdBy: 'admin-1');

        expect(data['schoolId'], 'school-1');
        expect(data['branchId'], 'main');
        expect(data['code'], 'ADM');
        expect(data['status'], 'ACTIVE');
        expect(data['createdBy'], 'admin-1');
        expect(data['createdAt'], isA<FieldValue>());
      },
    );

    test(
      'update can change name, description and status but never the code',
      () {
        final data = const Department(
          departmentId: 'adm',
          schoolId: 'school-1',
          branchId: 'main',
          name: 'Admin & Ops',
          code: 'ADM',
          description: 'Front office',
          status: ActivationStatus.inactive,
        ).toFirestoreUpdate(updatedBy: 'admin-2');

        expect(data.keys.toSet(), {
          'name',
          'description',
          'status',
          'updatedAt',
          'updatedBy',
        });
        expect(data['status'], 'INACTIVE');
      },
    );

    test('fromFirestore reads the stored fields', () {
      final department = Department.fromFirestore('school-1', 'main', 'adm', {
        'name': 'Administration',
        'code': 'ADM',
        'description': null,
        'status': 'INACTIVE',
        'createdBy': 'a',
      });
      expect(department.departmentId, 'adm');
      expect(department.isActive, isFalse);
      expect(department.description, isNull);
    });
  });

  group('Designation', () {
    test(
      'mirrors Department: id from code, immutable code, status instead of delete',
      () {
        expect(Designation.idForCode('Senior-Teacher'), 'senior-teacher');
        final update = const Designation(
          designationId: 'principal',
          schoolId: 'school-1',
          branchId: 'main',
          name: 'Principal',
          code: 'PRINCIPAL',
          status: ActivationStatus.active,
        ).toFirestoreUpdate(updatedBy: 'u');
        expect(update.containsKey('code'), isFalse);
        expect(update['status'], 'ACTIVE');
      },
    );

    test(
      'is independent of any authorization role — it carries no role field at all',
      () {
        final data = const Designation(
          designationId: 'senior-teacher',
          schoolId: 's',
          branchId: 'b',
          name: 'Senior Teacher',
          code: 'SENIOR-TEACHER',
          status: ActivationStatus.active,
        ).toFirestoreCreate(createdBy: 'u');
        expect(data.containsKey('role'), isFalse);
      },
    );
  });
}
