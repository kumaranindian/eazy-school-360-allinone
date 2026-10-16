import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/students/data/branch_transfer_writes.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/parent_student_link.dart';
import 'package:eazy_school_360/features/students/domain/relationship_type.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exports the exact documents a student move between branches writes to
/// `firestore-tests/fixtures/branch-transfer-write-plans.json`;
/// `branch-transfer-contract.test.mjs` replays them under the real rules.
const _school = '__SCHOOL__';

Object? _encode(Object? v) {
  if (v is FieldValue) return {r'$serverTimestamp': true};
  if (v is Timestamp) return {r'$time': v.toDate().toUtc().toIso8601String()};
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _encode(e.value)};
  }
  if (v is List) return [for (final e in v) _encode(e)];
  return v;
}

Student _student({StudentStatus status = StudentStatus.active}) => Student(
  studentId: 'stu-1',
  schoolId: _school,
  branchId: 'north',
  admissionNumber: 'N-001',
  studentCode: 'STU-STU-1',
  firstName: 'Anil',
  lastName: 'Kumar',
  dateOfBirth: DateTime.utc(2014, 5, 4),
  gender: Gender.male,
  admissionDate: DateTime.utc(2020, 6, 1),
  status: status,
  currentAcademicYearId: 'y1',
  currentClassId: 'c5',
  currentSectionId: 'sa',
  currentRollNumber: '7',
);

ParentStudentLink _link(String parentId, {bool portal = true}) =>
    ParentStudentLink(
      relationshipId: parentId,
      schoolId: _school,
      branchId: 'north',
      studentId: 'stu-1',
      parentId: parentId,
      relationshipType: RelationshipType.father,
      isPrimary: true,
      canAccessPortal: portal,
      status: ActivationStatus.active,
    );

BranchTransferInput _input({
  List<TransferGuardian>? guardians,
  String? activeRecord = 'rec-old',
  String to = 'south',
  String admission = 'S-100',
  Student? source,
}) => BranchTransferInput(
  source: source ?? _student(),
  toBranchId: to,
  admissionNumber: admission,
  academicYearId: 'y1',
  classId: 'c6',
  sectionId: 'sb',
  rollNumber: '12',
  reason: 'Family moved',
  effectiveDate: DateTime.utc(2026, 7, 1),
  actorId: 'bt-admin',
  activeSourceRecordId: activeRecord,
  destinationRecordId: 'rec-new',
  transferId: 'tr-1',
  guardians:
      guardians ??
      [
        // already has a record in the new branch
        TransferGuardian(
          parentId: 'par-existing',
          parentData: null,
          existsInDestination: true,
          link: _link('par-existing'),
        ),
        // needs a copy
        TransferGuardian(
          parentId: 'par-new',
          parentData: {
            'schoolId': _school,
            'branchId': 'north',
            'firstName': 'Ravi',
            'lastName': 'Kumar',
            'displayName': 'Ravi Kumar',
            'displayNameLower': 'ravi kumar',
            'email': 'ravi@example.com',
            'phone': '+919876543210',
            'status': 'ACTIVE',
            'linkedUserId': 'user-par',
            'createdAt': Timestamp.fromDate(DateTime.utc(2020, 6, 1)),
            'updatedAt': Timestamp.fromDate(DateTime.utc(2020, 6, 1)),
            'createdBy': 'old-admin',
            'updatedBy': 'old-admin',
          },
          existsInDestination: false,
          link: _link('par-new'),
        ),
      ],
);

void main() {
  group('validate', () {
    test('accepts a normal move', () {
      expect(BranchTransferWrites.validate(_input()), isNull);
    });
    test('refuses the same branch, inactive students, missing details', () {
      expect(
        BranchTransferWrites.validate(_input(to: 'north')),
        contains('already'),
      );
      expect(
        BranchTransferWrites.validate(_input(to: '')),
        contains('Choose the branch'),
      );
      expect(
        BranchTransferWrites.validate(
          _input(source: _student(status: StudentStatus.left)),
        ),
        contains('active student'),
      );
      expect(
        BranchTransferWrites.validate(_input(admission: '  ')),
        contains('admission number'),
      );
      expect(
        () => BranchTransferWrites.plan(_input(to: 'north')),
        throwsArgumentError,
      );
    });
  });

  group('plan', () {
    final writes = BranchTransferWrites.plan(_input());
    PlannedWrite at(String suffix) =>
        writes.singleWhere((w) => w.path.endsWith(suffix));

    test('new branch: same id, new admission, placed, pointing back', () {
      final d = at('branches/south/students/stu-1').data;
      expect(d['branchId'], 'south');
      expect(d['admissionNumber'], 'S-100');
      expect(d['status'], 'ACTIVE');
      expect(d['currentClassId'], 'c6');
      expect(d['currentSectionId'], 'sb');
      expect(d['currentRollNumber'], '12');
      expect(d['photoUrl'], isNull);
      expect(d['transferredFrom'], {
        'branchId': 'north',
        'studentId': 'stu-1',
        'admissionNumber': 'N-001',
      });
      expect(at('branches/south/students/stu-1').isCreate, isTrue);
      expect(
        at('students/stu-1/academicRecords/rec-new').data['status'],
        'ACTIVE',
      );
    });

    test('old branch: transferred, pointing forward, placement closed', () {
      final old = at('branches/north/students/stu-1');
      expect(old.isCreate, isFalse);
      expect(old.data['status'], 'TRANSFERRED');
      expect(old.data['statusChangeReason'], 'TRANSFERRED_TO_BRANCH');
      expect(old.data['transferredTo'], {
        'branchId': 'south',
        'studentId': 'stu-1',
        'admissionNumber': 'S-100',
      });
      final rec = at('north/students/stu-1/academicRecords/rec-old');
      expect(rec.data['status'], 'TRANSFERRED');
      expect(rec.isCreate, isFalse);
    });

    test('guardians: links for all, a record copy only where missing', () {
      expect(
        at('south/students/stu-1/parentLinks/par-existing').isCreate,
        isTrue,
      );
      expect(
        at('south/students/stu-1/parentLinks/par-new').data['canAccessPortal'],
        isTrue,
      );
      expect(
        writes.where((w) => w.path.endsWith('south/parents/par-existing')),
        isEmpty,
      );
      final copy = at('south/parents/par-new').data;
      expect(copy['branchId'], 'south');
      expect(copy['linkedUserId'], 'user-par'); // the login follows the family
      expect(copy['createdBy'], 'bt-admin');
      expect(copy['email'], 'ravi@example.com');
    });

    test('audit entry names who moved whom, where and why', () {
      final a = at('studentTransfers/tr-1').data;
      expect(a['fromBranchId'], 'north');
      expect(a['toBranchId'], 'south');
      expect(a['studentName'], 'Anil Kumar');
      expect(a['reason'], 'Family moved');
      expect(a['createdBy'], 'bt-admin');
      expect(
        a.containsKey('updatedAt'),
        isFalse,
      ); // rules allow exactly these keys
    });

    test('nothing is deleted and the old history is not rewritten', () {
      expect(
        writes.every((w) => w.isCreate || !w.path.contains('/south/')),
        isTrue,
      );
      expect(
        writes
            .where((w) => w.path.contains('/north/') && !w.isCreate)
            .map((w) => w.path.split('/north/').last),
        unorderedEquals([
          'students/stu-1',
          'students/stu-1/academicRecords/rec-old',
        ]),
      );
    });
  });

  test('exports the plan for the rules contract test', () {
    final writes = BranchTransferWrites.plan(_input());
    final ops = [
      for (final w in writes)
        {
          'op': w.isCreate ? 'set' : 'update',
          'path': w.path,
          'data': _encode(w.data),
        },
    ];
    final file = File(
      'firestore-tests/fixtures/branch-transfer-write-plans.json',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'scenarios': [
          {
            'name': 'move an active student with two guardians',
            'batches': [
              {'as': 'bt-admin', 'label': 'transfer', 'ops': ops},
            ],
          },
        ],
      }),
    );
    expect(ops, hasLength(writes.length));
    expect((ops.first['data'] as Map)['createdAt'], {
      r'$serverTimestamp': true,
    });
  });
}
