import 'package:eazy_school_360/features/staff/domain/teacher_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the display list written by the function', () {
    final s = TeacherScope.fromData({
      'sectionKeys': ['c5__sa', 'c6__sb'],
      'scopes': [
        {'academicYearId': 'y1', 'classId': 'c5', 'sectionId': 'sa'},
        {'academicYearId': 'y1', 'classId': 'c6', 'sectionId': 'sb'},
      ],
    });
    expect(s.sections.length, 2);
    expect(s.sections.first.academicYearId, 'y1');
    expect(s.sections.first.key, 'c5__sa');
    expect(s.covers('c5', 'sa'), isTrue);
    expect(s.covers('c5', 'sb'), isFalse);
    expect(s.covers('c5', null), isFalse);
    expect(s.covers(null, 'sa'), isFalse);
  });

  test('falls back to the rules keys; ignores malformed entries', () {
    final s = TeacherScope.fromData({
      'sectionKeys': ['c5__sa', 'garbage', 5, '__x'],
    });
    expect(s.sections.map((e) => e.key), ['c5__sa']);
    expect(s.sections.single.academicYearId, isNull);
    final odd = TeacherScope.fromData({
      'scopes': [
        'nope',
        {'classId': 1, 'sectionId': 'x'},
        {'classId': 'c', 'sectionId': 's'},
      ],
    });
    expect(odd.sections.map((e) => e.key), ['c__s']);
  });

  test(
    'a document with nothing usable is an empty scope, never everything',
    () {
      expect(TeacherScope.fromData({}).isEmpty, isTrue);
      expect(TeacherScope.fromData({'sectionKeys': 'c5__sa'}).isEmpty, isTrue);
      expect(TeacherScope.empty.covers('c5', 'sa'), isFalse);
    },
  );
}
