import 'package:eazy_school_360/features/students/domain/admission_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a clean admission says so', () {
    expect(
      AdmissionOutcome.message(studentName: 'Asha Nair', guardianLinked: true),
      'Asha Nair admitted successfully.',
    );
  });

  test('a failed guardian step is never reported as plain success', () {
    final m = AdmissionOutcome.message(
      studentName: 'Asha Nair',
      guardianLinked: false,
      guardianError: 'Permission denied',
    );
    expect(m, isNot(contains('successfully')));
    expect(m, contains('admitted'));
    expect(m, contains('could not be linked'));
    expect(m, contains('Permission denied'));
  });
}
