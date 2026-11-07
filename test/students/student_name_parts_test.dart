import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_name_parts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one word is a first name only', () {
    final n = StudentNameParts.split('Arun');
    expect((n.first, n.middle, n.last), ('Arun', null, ''));
    expect(n.isComplete, isFalse); // the form asks for a last name too
    expect(StudentNameParts.split('Arun Kumar').isComplete, isTrue);
  });

  test('two words: first and last', () {
    final n = StudentNameParts.split('Arun Kumar');
    expect((n.first, n.middle, n.last), ('Arun', null, 'Kumar'));
  });

  test('three or more: everything between is the middle name', () {
    final n = StudentNameParts.split('Mary Anne  Elizabeth Smith');
    expect(n.first, 'Mary');
    expect(n.middle, 'Anne Elizabeth');
    expect(n.last, 'Smith');
  });

  test('spaces are ignored; empty input is empty', () {
    expect(StudentNameParts.split('   ').isEmpty, isTrue);
    expect(StudentNameParts.split('  Arun   Kumar ').full, 'Arun Kumar');
  });

  test('the stored display name is the same as the typed name', () {
    for (final typed in ['Arun Kumar', 'Mary Anne Smith']) {
      final n = StudentNameParts.split(typed);
      expect(Student.computeDisplayName(n.first, n.middle, n.last), typed);
    }
  });
}
