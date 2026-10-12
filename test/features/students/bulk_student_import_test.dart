import 'package:eazy_school_360/features/students/data/bulk_student_importer.dart';
import 'package:eazy_school_360/features/students/domain/bulk_student_import.dart';
import 'package:eazy_school_360/features/students/domain/parent.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/domain/relationship_type.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _placements = PlacementLookup({
  'grade 1': ClassPlacement(
    'c1',
    'Grade 1',
    {'a': 's1a', 'b': 's1b'},
    ['A', 'B'],
  ),
  'grade 2': ClassPlacement('c2', 'Grade 2', {}, []),
});

final _today = DateTime(2026, 10, 11);
final _header = bulkStudentColumns.map((c) => c.key).join(',');

BulkStudentParseResult _parse(String body) => parseBulkStudentCsv(
  '$_header\n$body',
  placements: _placements,
  today: _today,
);

// admission,first,middle,last,dob,gender,blood,email,phone,address,city,
// adm date,class,section,roll,pfirst,plast,pphone,prel
const _good =
    'ADM-1,Asha,,Kumar,2015-06-30,Female,O+,,,,,2026-06-01,Grade 1,A,1,Ravi,Kumar,98765 43210,Father';

void main() {
  group('csv codec', () {
    test('round-trips quotes, commas, newlines and BOM', () {
      final rows = [
        ['a', 'b,c', 'say "hi"', 'x\ny'],
        ['1', '', '3', '4'],
      ];
      final back = parseCsv('﻿${encodeCsv(rows)}');
      expect(back, rows);
    });

    test('handles CRLF and skips blank lines', () {
      expect(parseCsv('a,b\r\n\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });
  });

  group('template', () {
    test('header lists every column and its own example row is valid', () {
      final csv = bulkStudentTemplateCsv();
      expect(csv.startsWith('﻿'), isTrue);
      final r = parseBulkStudentCsv(
        csv,
        placements: const PlacementLookup({
          'grade 1': ClassPlacement('c1', 'Grade 1', {'a': 's1a'}),
        }),
        today: _today,
      );
      expect(r.fileError, isNull);
      expect(r.rows, hasLength(1));
      expect(r.rows.single.errors, isEmpty);
    });
  });

  group('validation', () {
    test('a good row resolves ids and parses fields', () {
      final r = _parse(_good);
      final d = r.rows.single.data!;
      expect(d.classId, 'c1');
      expect(d.sectionId, 's1a');
      expect(d.dateOfBirth, DateTime(2015, 6, 30));
      expect(d.parent!.relationship, RelationshipType.father);
      expect(d.parent!.key, '9876543210');
    });

    test('accepts day-first dates and rejects impossible ones', () {
      expect(parseSheetDate('30/06/2015'), DateTime(2015, 6, 30));
      expect(parseSheetDate('2015-02-30'), isNull);
      expect(parseSheetDate('31/04/2015'), isNull);
      expect(parseSheetDate('June 30'), isNull);
    });

    test('reports every problem on a row with the sheet line number', () {
      final r = _parse(
        ',Asha,,,2999-01-01,Robot,Z+,not-mail,12,,,,Grade 9,A,,Ravi,,,Aunt',
      );
      final row = r.rows.single;
      expect(row.line, 2);
      expect(row.isValid, isFalse);
      final all = row.errors.join('|');
      for (final s in [
        'Admission number: is empty',
        'Last name: is empty',
        'Date of birth: "2999-01-01" is in the future',
        'Gender: "Robot" is not recognised',
        'Blood group: "Z+"',
        'Email: "not-mail"',
        'Phone: "12"',
        'No class named "Grade 9" exists',
        'Parent last name: is empty',
        'Parent phone: is empty',
        'Parent relationship: "Aunt"',
      ]) {
        expect(all, contains(s));
      }
    });

    test('unknown section and in-file duplicate admission numbers', () {
      final r = _parse(
        '$_good\n${_good.replaceFirst(',A,1,', ',Z,2,')}\n$_good',
      );
      expect(r.rows[0].isValid, isTrue);
      expect(
        r.rows[1].errors.join(),
        contains('Class Grade 1 has no section named "Z"'),
      );
      expect(r.rows[2].errors.join(), contains('already used on line 2'));
    });

    test('unknown class/section errors list what exists and suggest a fix', () {
      final r = _parse(
        '$_good\n'
        '${_good.replaceFirst('ADM-1', 'ADM-5').replaceFirst('Grade 1,A', 'Grade1,A')}\n'
        '${_good.replaceFirst('ADM-1', 'ADM-6').replaceFirst('Grade 1,A', 'Grade 1,C')}\n'
        '${_good.replaceFirst('ADM-1', 'ADM-7').replaceFirst('Grade 1,A', 'Grade 7,A')}\n'
        '${_good.replaceFirst('ADM-1', 'ADM-8').replaceFirst('Grade 1,A', 'Grade 2,A')}',
      );
      final typo = r.rows[1].errors.single;
      expect(typo.column, 'class');
      expect(typo.fix, contains('Did you mean "Grade 1"?'));
      expect(typo.fix, contains('Classes available: Grade 1, Grade 2'));

      final noSection = r.rows[2].errors.single;
      expect(noSection.column, 'section');
      expect(noSection.fix, contains('Sections of Grade 1: A, B'));

      final far = r.rows[3].errors.single;
      expect(far.fix, isNot(contains('Did you mean')));

      final emptyClass = r.rows[4].errors.single;
      expect(emptyClass.fix, contains('(none set up)'));
      expect(r.rows[4].who, 'ADM-8 · Asha Kumar');
    });

    test('names match regardless of case and extra spaces', () {
      final r = _parse(_good.replaceFirst('Grade 1,A', '  GRADE   1 , a '));
      expect(r.rows.single.errors, isEmpty);
    });

    test(
      'a year with no classes still lists every row with a clear reason',
      () {
        final r = parseBulkStudentCsv(
          '$_header\n$_good\n${_good.replaceFirst('ADM-1', 'ADM-2')}',
          placements: const PlacementLookup({}),
          academicYearName: 'academic year "2026-27"',
          today: _today,
        );
        expect(r.fileError, isNull);
        expect(r.rows, hasLength(2));
        final e = r.rows.first.errors.single;
        expect(e.column, 'class');
        expect(e.message, contains('has no classes set up yet'));
        expect(e.fix, contains('Academic setup'));
      },
    );

    test('inline edit of one cell or all equal values re-validates', () {
      final csv =
          '$_header\n${_good.replaceFirst('Grade 1', 'Grade9')}\n'
          '${_good.replaceFirst('ADM-1', 'ADM-2').replaceFirst('Grade 1', 'Grade9')}';
      final fixedOne = editCsvCells(
        csv,
        columnKey: 'class',
        newValue: 'Grade 1',
        line: 3,
      );
      var r = parseBulkStudentCsv(
        fixedOne,
        placements: _placements,
        today: _today,
      );
      expect(r.rows[0].isValid, isFalse);
      expect(r.rows[1].isValid, isTrue);

      final fixedAll = editCsvCells(
        csv,
        columnKey: 'class',
        newValue: 'Grade 1',
        oldValue: 'Grade9',
      );
      r = parseBulkStudentCsv(fixedAll, placements: _placements, today: _today);
      expect(r.rows.every((x) => x.isValid), isTrue);
    });

    test('class and section problems carry pickable choices', () {
      final r = _parse(_good.replaceFirst('Grade 1,A', 'Grade 1,Q'));
      expect(r.rows.single.errors.single.choices, ['A', 'B']);
      final c = _parse(_good.replaceFirst('Grade 1,A', 'Grade 9,A'));
      expect(c.rows.single.errors.single.choices, ['Grade 1', 'Grade 2']);
    });

    test('file-level errors: missing columns, empty, too many rows', () {
      expect(
        parseBulkStudentCsv('first_name\nA', placements: _placements).fileError,
        contains('missing these required columns'),
      );
      expect(
        parseBulkStudentCsv('', placements: _placements).fileError,
        isNotNull,
      );
      final many = List.filled(bulkStudentMaxRows + 1, _good).join('\n');
      expect(_parse(many).fileError, contains('limit'));
    });

    test('blank optional cells and missing trailing cells are fine', () {
      final r = _parse('ADM-2,Bo,,Lee,2014-01-02,m,,,,,,,Grade 1,B');
      expect(r.rows.single.errors, isEmpty);
      expect(r.rows.single.data!.parent, isNull);
      expect(r.rows.single.data!.admissionDate, DateTime(2026, 10, 11));
    });
  });

  group('errors csv', () {
    test('keeps original cells and appends the error column', () {
      final r = _parse(',Asha,,Kumar,2015-06-30,Female,,,,,,,Grade 1,A');
      final out = bulkStudentErrorsCsv(r.header, [
        (row: r.rows.single, error: 'admission_number is required'),
      ]);
      final table = parseCsv(out);
      expect(table.first.last, 'error');
      expect(table[1].last, 'admission_number is required');
      expect(table[1][1], 'Asha');
    });
  });

  group('importer', () {
    test('shares one parent per phone; isolates a failing row', () async {
      final students = _FakeStudents(failAdmission: 'ADM-2');
      final parents = _FakeParents();
      final rows = _parse(
        [
          _good,
          _good.replaceFirst('ADM-1,Asha', 'ADM-2,Bela'),
          _good.replaceFirst('ADM-1,Asha', 'ADM-3,Chitra'),
        ].join('\n'),
      ).rows;

      final progress = <int>[];
      final results = await BulkStudentImporter(students, parents).import(
        schoolId: 's',
        branchId: 'b',
        academicYearId: 'y',
        createdBy: 'u',
        rows: rows,
        onProgress: (d, t) => progress.add(d),
      );

      expect(results.map((r) => r.status), [
        BulkImportStatus.imported,
        BulkImportStatus.failed,
        BulkImportStatus.imported,
      ]);
      expect(parents.created, 1, reason: 'same phone -> one parent record');
      expect(students.linked, 2);
      expect(progress, [1, 2, 3]);
    });

    test(
      'parent email is read, validated and stored once for siblings',
      () async {
        final ok = _parse('$_good,ravi@example.com').rows.single;
        expect(ok.isValid, isTrue);
        expect(ok.data!.parent!.email, 'ravi@example.com');

        final bad = _parse('$_good,not-an-email').rows.single;
        expect(bad.isValid, isFalse);
        expect(bad.errors.map((e) => e.column), contains('parent_email'));

        // Older files without the column still import.
        expect(_parse(_good).rows.single.data!.parent!.email, isNull);
      },
    );

    test('a parent failure keeps the admitted student', () async {
      final rows = _parse(_good).rows;
      final results =
          await BulkStudentImporter(
            _FakeStudents(),
            _FakeParents(fail: true),
          ).import(
            schoolId: 's',
            branchId: 'b',
            academicYearId: 'y',
            createdBy: 'u',
            rows: rows,
          );
      expect(results.single.status, BulkImportStatus.importedParentFailed);
    });

    test('flags admission numbers that already exist', () async {
      final rows = _parse(_good).rows;
      final out = await BulkStudentImporter(
        _FakeStudents(existing: {'ADM-1'}),
        _FakeParents(),
      ).flagExistingAdmissionNumbers(schoolId: 's', branchId: 'b', rows: rows);
      expect(out.single.isValid, isFalse);
      expect(
        out.single.errors.single.message,
        contains('already belongs to a student'),
      );
    });
  });
}

class _FakeStudents implements StudentRepository {
  final String? failAdmission;
  final Set<String> existing;
  int linked = 0;
  int _n = 0;

  _FakeStudents({this.failAdmission, this.existing = const {}});

  @override
  Future<String> admitStudent({
    required Student student,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    required String createdBy,
  }) async {
    if (student.admissionNumber == failAdmission) {
      throw StateError('boom');
    }
    return 'stu${_n++}';
  }

  @override
  Future<bool> isAdmissionNumberAvailable(
    String schoolId,
    String branchId,
    String admissionNumber, {
    String? excludingStudentId,
  }) async => !existing.contains(admissionNumber);

  @override
  Future<void> linkParentToStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String parentId,
    required RelationshipType relationshipType,
    bool isPrimary = false,
    bool isEmergencyContact = false,
    bool canAccessPortal = false,
    required String createdBy,
  }) async => linked++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeParents implements ParentRepository {
  final bool fail;
  int created = 0;
  _FakeParents({this.fail = false});

  @override
  Future<String> createParent(
    Parent parent, {
    required String createdBy,
  }) async {
    if (fail) throw StateError('parent boom');
    return 'par${created++}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
