import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_academic_year.dart';
import 'package:flutter_test/flutter_test.dart';

SchoolAcademicYear _y(
  String id,
  String name, {
  SchoolYearStatus status = SchoolYearStatus.active,
}) => SchoolAcademicYear(
  schoolYearId: id,
  schoolId: 's1',
  name: name,
  startDate: DateTime(2026, 6, 1),
  endDate: DateTime(2027, 3, 31),
  status: status,
);

void main() {
  group('SchoolYearRules.validate', () {
    String? v({
      String name = '2026-27',
      DateTime? start,
      DateTime? end,
      List<String> existing = const [],
    }) => SchoolYearRules.validate(
      name: name,
      start: start ?? DateTime(2026, 6, 1),
      end: end ?? DateTime(2027, 3, 31),
      existingNames: existing,
    );

    test('accepts a good definition', () => expect(v(), isNull));
    test('needs a name of sensible length', () {
      expect(v(name: '  '), contains('name'));
      expect(v(name: 'x' * 101), contains('too long'));
    });
    test('needs ordered dates', () {
      expect(
        SchoolYearRules.validate(
          name: 'a',
          start: null,
          end: DateTime(2027),
          existingNames: const [],
        ),
        contains('both'),
      );
      expect(v(end: DateTime(2026, 6, 1)), contains('after the start'));
      expect(v(end: DateTime(2026, 1, 1)), contains('after the start'));
    });
    test('names are unique ignoring case and padding', () {
      expect(v(existing: [' 2026-27 ']), contains('already exists'));
      expect(v(name: 'ABC', existing: ['abc']), contains('already exists'));
      expect(v(existing: ['2025-26']), isNull);
    });
  });

  test('openableIn: active years not yet open in the branch', () {
    final registry = [
      _y('a', 'A'),
      _y('b', 'B'),
      _y('c', 'C', status: SchoolYearStatus.archived),
    ];
    expect(
      SchoolYearRules.openableIn(registry, ['b']).map((y) => y.schoolYearId),
      ['a'],
    );
    expect(SchoolYearRules.openableIn(registry, const []).length, 2);
    expect(SchoolYearRules.openableIn(const [], ['a']), isEmpty);
  });

  test('the branch copy: same id, name and dates, a DRAFT, linked', () {
    final y = _y('y26', '2026-27');
    final b = y.forBranch('north');
    expect(b.academicYearId, 'y26');
    expect(b.schoolYearId, 'y26');
    expect(b.branchId, 'north');
    expect(b.schoolId, 's1');
    expect(b.name, '2026-27');
    expect(b.startDate, y.startDate);
    expect(b.endDate, y.endDate);
    expect(b.status, AcademicYearStatus.draft);
    final data = b.toFirestoreCreate(createdBy: 'u1');
    expect(data['schoolYearId'], 'y26');
    expect(data['status'], 'DRAFT');
    expect(data['branchId'], 'north');
  });

  test('a legacy branch year has no schoolYearId and writes none', () {
    final legacy = AcademicYear(
      academicYearId: 'old',
      schoolId: 's1',
      branchId: 'north',
      name: 'Old',
      startDate: DateTime(2020),
      endDate: DateTime(2021),
      status: AcademicYearStatus.closed,
    );
    expect(legacy.schoolYearId, isNull);
    expect(
      legacy.toFirestoreCreate(createdBy: 'u').containsKey('schoolYearId'),
      isFalse,
    );
  });

  test('the registry document carries exactly the fields the rules allow', () {
    final data = _y('', 'N').toFirestoreCreate(createdBy: 'u1');
    expect(data.keys.toSet(), {
      'schoolId',
      'name',
      'startDate',
      'endDate',
      'startDateKey',
      'endDateKey',
      'status',
      'createdAt',
      'updatedAt',
      'createdBy',
      'updatedBy',
    });
    expect(data['status'], 'ACTIVE');
  });
}
