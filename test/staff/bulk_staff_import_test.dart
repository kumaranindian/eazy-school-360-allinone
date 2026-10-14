import 'dart:io';

import 'package:eazy_school_360/features/staff/data/bulk_staff_importer.dart';
import 'package:eazy_school_360/features/staff/domain/bulk_staff_import.dart';
import 'package:eazy_school_360/features/users/domain/email_lookup.dart';
import 'package:eazy_school_360/features/staff/domain/employment_type.dart';
import 'package:eazy_school_360/features/staff/domain/staff.dart';
import 'package:eazy_school_360/features/staff/domain/staff_repository.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/students/domain/blood_group.dart';
import 'package:eazy_school_360/features/students/domain/bulk_student_import.dart'
    show editCsvCells, parseCsv;
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:flutter_test/flutter_test.dart';

const _refs = StaffReferenceLookup(
  departmentIds: {'academics': 'd1', 'acd': 'd1', 'admin': 'd2'},
  departmentNames: ['Academics', 'Admin'],
  designationIds: {'teacher': 'g1', 'clerk': 'g2'},
  designationNames: ['Teacher', 'Clerk'],
);

final _today = DateTime(2026, 10, 11);
final _header = bulkStaffColumns.map((c) => c.key).join(',');

BulkStaffParseResult _parse(String body, {bool teachers = false}) =>
    parseBulkStaffCsv(
      '$_header\n$body',
      references: _refs,
      defaultIsTeacher: teachers,
      today: _today,
    );

// code,first,middle,last,dob,gender,blood,phone,altphone,email,addr,city,
// state,country,postal,joining,employment,department,designation,is_teacher
const _good =
    'EMP-1,Meena,,Iyer,1988-04-12,Female,B+,9876500001,,m@x.com,,,,,,2024-06-01,Part time,Academics,Teacher,Yes';

void main() {
  group('email', () {
    test('is normalised to lowercase and validated strictly', () {
      final r = _parse(_good.replaceFirst('m@x.com', '  Meena@School.ORG '));
      expect(r.rows.single.isValid, isTrue);
      expect(r.rows.single.data!.email, 'meena@school.org');
      for (final bad in ['nope', 'a@b', 'a@b.c', 'a b@c.com', '@x.com']) {
        final x = _parse(_good.replaceFirst('m@x.com', bad));
        expect(x.rows.single.errors.single.column, 'email', reason: bad);
      }
    });

    test('is optional; blank is stored as no email', () {
      final r = _parse(_good.replaceFirst('m@x.com', ''));
      expect(r.rows.single.isValid, isTrue);
      expect(r.rows.single.data!.email, isNull);
    });

    test('a repeat inside the file is flagged, in any letter case', () {
      final r = _parse(
        [
          _good,
          _good
              .replaceFirst('EMP-1', 'EMP-2')
              .replaceFirst('m@x.com', 'M@X.com'),
          _good
              .replaceFirst('EMP-1', 'EMP-3')
              .replaceFirst('m@x.com', 'other@x.com'),
        ].join('\n'),
      );
      expect(r.rows.map((x) => x.isValid), [true, false, true]);
      expect(
        r.rows[1].errors.single.message,
        contains('already used on line 2'),
      );
    });

    test(
      'rows already holding an email in the branch are flagged, not merged',
      () async {
        final importer = BulkStaffImporter(_FakeStaff(), _Emails({'m@x.com'}));
        final rows = _parse(
          [
            _good,
            _good
                .replaceFirst('EMP-1', 'EMP-2')
                .replaceFirst('m@x.com', 'new@x.com'),
          ].join('\n'),
        ).rows;
        final checked = await importer.flagExistingEmails(
          schoolId: 's',
          branchId: 'b',
          rows: rows,
        );
        expect(checked.map((r) => r.isValid), [false, true]);
        expect(checked[0].errors.single.message, contains('already belongs'));
      },
    );

    test(
      'the same file twice: every email is reported, nothing is imported blindly',
      () async {
        final importer = BulkStaffImporter(_FakeStaff(), _Emails({'m@x.com'}));
        final rows = _parse(_good).rows;
        final checked = await importer.flagExistingEmails(
          schoolId: 's',
          branchId: 'b',
          rows: rows,
        );
        final results = await importer.import(
          schoolId: 's',
          branchId: 'b',
          createdBy: 'u',
          rows: checked,
        );
        expect(results, isEmpty);
      },
    );
  });

  group('template', () {
    test('its own example row is valid', () {
      final r = parseBulkStaffCsv(
        bulkStaffTemplateCsv(),
        references: _refs,
        today: _today,
      );
      expect(r.fileError, isNull);
      expect(r.rows.single.errors, isEmpty);
    });

    test('teacher template pre-fills is_teacher = Yes', () {
      final r = parseCsv(bulkStaffTemplateCsv(teachers: true));
      expect(r[1][r[0].indexOf('is_teacher')], 'Yes');
    });
  });

  group('validation', () {
    test('a good row resolves department/designation ids', () {
      final d = _parse(_good).rows.single.data!;
      expect(d.departmentId, 'd1');
      expect(d.designationId, 'g1');
      expect(d.employmentType, EmploymentType.partTime);
      expect(d.isTeacher, isTrue);
      expect(d.bloodGroup, BloodGroup.bPositive);
    });

    test('department/designation also match by code, any case', () {
      final r = _parse(_good.replaceFirst('Academics', ' ACD '));
      expect(r.rows.single.data!.departmentId, 'd1');
    });

    test('unknown department lists what exists and suggests a fix', () {
      final r = _parse(
        _good
            .replaceFirst('Academics', 'Academic')
            .replaceFirst('Teacher,Yes', 'Principal,Yes'),
      );
      final dept = r.rows.single.errors.firstWhere(
        (e) => e.column == 'department',
      );
      expect(dept.fix, contains('Did you mean "Academics"?'));
      expect(dept.fix, contains('Departments available: Academics, Admin'));
      final desig = r.rows.single.errors.firstWhere(
        (e) => e.column == 'designation',
      );
      expect(desig.fix, contains('Designations available: Teacher, Clerk'));
    });

    test('reports each problem with column, value and fix', () {
      final r = _parse(
        ',,,,31/02/2000,Robot,Z+,12,,bad,,,,,,not-a-date,Casual,Academics,Teacher,Maybe',
      );
      final all = r.rows.single.errors.join('|');
      for (final s in [
        'Employee code: is empty',
        'First name: is empty',
        'Last name: is empty',
        'Date of birth: "31/02/2000" is not a valid date',
        'Gender: "Robot"',
        'Blood group: "Z+"',
        'Phone: "12"',
        'Email: "bad"',
        'Joining date: "not-a-date"',
        'Employment type: "Casual"',
        'Is teacher: "Maybe"',
      ]) {
        expect(all, contains(s));
      }
      expect(r.rows.single.isValid, isFalse);
    });

    test('invalid and duplicate employee codes', () {
      final r = _parse(
        '$_good\n${_good.replaceFirst('EMP-1', 'emp-1')}\n'
        '${_good.replaceFirst('EMP-1', 'E M')}',
      );
      expect(r.rows[0].isValid, isTrue);
      expect(
        r.rows[1].errors.single.message,
        contains('already used on line 2'),
      );
      expect(
        r.rows[2].errors.single.message,
        contains('not a valid employee code'),
      );
    });

    test('blank is_teacher follows the screen default', () {
      final blank = _good.replaceFirst(',Yes', ',');
      expect(_parse(blank).rows.single.data!.isTeacher, isFalse);
      expect(_parse(blank, teachers: true).rows.single.data!.isTeacher, isTrue);
    });

    test('file-level errors', () {
      expect(
        parseBulkStaffCsv('first_name\nA', references: _refs).fileError,
        contains('missing these required columns'),
      );
      final many = List.filled(bulkStaffMaxRows + 1, _good).join('\n');
      expect(_parse(many).fileError, contains('limit'));
    });
  });

  group('nothing set up yet', () {
    const empty = StaffReferenceLookup(
      departmentIds: {},
      departmentNames: [],
      designationIds: {},
      designationNames: [],
    );

    test('still returns every row, with a create-it hint per row', () {
      final r = parseBulkStaffCsv(
        '$_header\n$_good\n${_good.replaceFirst('EMP-1', 'EMP-2')}',
        references: empty,
        today: _today,
      );
      expect(r.fileError, isNull);
      expect(r.rows, hasLength(2));
      for (final row in r.rows) {
        final dept = row.errors.firstWhere((e) => e.column == 'department');
        expect(dept.message, contains('no departments set up yet'));
        expect(dept.fix, contains('Create "Academics"'));
        expect(row.errors.any((e) => e.column == 'designation'), isTrue);
      }
    });
  });

  group('inline fixes', () {
    test('editCsvCells fixes one line or every matching value', () {
      final csv =
          '$_header\n${_good.replaceFirst('Academics', 'Academc')}\n'
          '${_good.replaceFirst('EMP-1', 'EMP-2').replaceFirst('m@x.com', 'm2@x.com').replaceFirst('Academics', 'Academc')}';
      final one = editCsvCells(
        csv,
        columnKey: 'department',
        newValue: 'Academics',
        line: 2,
      );
      var r = parseBulkStaffCsv(one, references: _refs, today: _today);
      expect(r.rows[0].isValid, isTrue);
      expect(r.rows[1].isValid, isFalse);

      final all = editCsvCells(
        csv,
        columnKey: 'department',
        newValue: 'Academics',
        oldValue: 'Academc',
      );
      r = parseBulkStaffCsv(all, references: _refs, today: _today);
      expect(r.rows.every((x) => x.isValid), isTrue);
    });

    test('problems with a fixed set of values carry the choices', () {
      final r = _parse(_good.replaceFirst('Female', 'Robot'));
      expect(r.rows.single.errors.single.choices, ['Male', 'Female', 'Other']);
      final d = _parse(_good.replaceFirst('Academics', 'Acad')).rows.single;
      expect(d.errors.single.choices, ['Academics', 'Admin']);
    });
  });

  group('export', () {
    final staff = Staff(
      staffId: 's1',
      schoolId: 'sc',
      branchId: 'b',
      employeeCode: 'EMP-9',
      firstName: 'Ravi',
      lastName: '=HYPERLINK("x")',
      dateOfBirth: DateTime(1980, 1, 2),
      gender: Gender.male,
      phone: '+919876500002',
      joiningDate: DateTime(2020, 7, 1),
      employmentType: EmploymentType.contract,
      departmentId: 'd2',
      designationId: 'g2',
      status: StaffStatus.onNotice,
      isTeacher: false,
      address: 'Flat 1, "Rose" Apts',
    );

    test('writes names, ISO dates, status, and neutralises formulas', () {
      final csv = staffExportCsv(
        [staff],
        departmentNames: const {'d2': 'Admin'},
        designationNames: const {'g2': 'Clerk'},
      );
      expect(csv.startsWith('﻿'), isTrue);
      final t = parseCsv(csv);
      final h = t[0];
      final row = t[1];
      String col(String k) => row[h.indexOf(k)];
      expect(h.last, 'status');
      expect(col('date_of_birth'), '1980-01-02');
      expect(col('department'), 'Admin');
      expect(col('designation'), 'Clerk');
      expect(col('employment_type'), 'Contract');
      expect(col('is_teacher'), 'No');
      expect(col('status'), 'On notice');
      expect(col('phone'), '+919876500002');
      expect(col('last_name'), "'=HYPERLINK(\"x\")");
      expect(col('address'), 'Flat 1, "Rose" Apts');
    });
  });

  group('importer', () {
    test('isolates a failing row; flags existing codes', () async {
      final repo = _FakeStaff(failCode: 'EMP-2', existing: {'EMP-3'});
      final rows = _parse(
        [
          _good,
          _good.replaceFirst('EMP-1', 'EMP-2').replaceFirst('m@x', 'm2@x'),
          _good.replaceFirst('EMP-1', 'EMP-3').replaceFirst('m@x', 'm3@x'),
        ].join('\n'),
      ).rows;
      final importer = BulkStaffImporter(repo);

      final checked = await importer.flagExistingCodes(
        schoolId: 's',
        branchId: 'b',
        rows: rows,
      );
      expect(checked.map((r) => r.isValid), [true, true, false]);
      expect(
        checked[2].errors.single.message,
        contains('already belongs to a staff member'),
      );

      final progress = <int>[];
      final results = await importer.import(
        schoolId: 's',
        branchId: 'b',
        createdBy: 'u',
        rows: checked,
        onProgress: (d, t) => progress.add(d),
      );
      expect(results.map((r) => r.status), [
        BulkStaffImportStatus.imported,
        BulkStaffImportStatus.failed,
      ]);
      expect(repo.created.single.employeeCode, 'EMP-1');
      expect(repo.created.single.isTeacher, isTrue);
      expect(repo.created.single.status, StaffStatus.active);
      expect(progress, [1, 2]);
    });
  });

  test('fee placement assignments are paged, never one limit above 10,000', () {
    final src = File(
      'lib/features/fees/data/firebase_fee_config_repository.dart',
    ).readAsStringSync();
    // Firestore rejects limit() > 10000; the old code used
    // limit(maxPlacementStudents * 8) = 16000.
    expect(src, isNot(contains('limit(maxPlacementStudents * 8)')));
    expect(src, contains('const pageSize = 500;'));
  });
}

class _FakeStaff implements StaffRepository {
  final String? failCode;
  final Set<String> existing;
  final created = <Staff>[];

  _FakeStaff({this.failCode, this.existing = const {}});

  @override
  Future<bool> isEmployeeCodeAvailable(
    String schoolId,
    String branchId,
    String employeeCode, {
    String? excludingStaffId,
  }) async => !existing.contains(employeeCode);

  @override
  Future<String> createStaff({
    required Staff staff,
    required String createdBy,
  }) async {
    if (staff.employeeCode == failCode) throw StateError('boom');
    created.add(staff);
    return 'id${created.length}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Emails implements EmailLookup {
  final Set<String> staff;
  _Emails(this.staff);

  @override
  Future<bool> staffEmailInUse(String s, String b, String email) async =>
      staff.contains(email);

  @override
  Future<bool> parentEmailInUse(String s, String b, String email) async =>
      false;
}
