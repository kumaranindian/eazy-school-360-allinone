import 'package:eazy_school_360/features/students/domain/admission_key.dart';
import 'package:eazy_school_360/features/students/domain/admission_number_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('numbers are ADM- plus a zero-padded sequence', () {
    expect(AdmissionNumberFormat.format(1), 'ADM-0001');
    expect(AdmissionNumberFormat.format(42), 'ADM-0042');
    expect(AdmissionNumberFormat.format(12345), 'ADM-12345');
  });

  test('only plain ADM-<digits> numbers count towards the sequence', () {
    expect(AdmissionNumberFormat.sequenceOf('ADM-1001'), 1001);
    expect(AdmissionNumberFormat.sequenceOf('ADM-0007'), 7);
    expect(AdmissionNumberFormat.sequenceOf('ADM-2026-0007'), isNull);
    expect(AdmissionNumberFormat.sequenceOf('S-100'), isNull);
    expect(AdmissionNumberFormat.sequenceOf(null), isNull);
  });

  test('highest ignores other styles; none gives 0', () {
    expect(
      AdmissionNumberFormat.highest(['ADM-0009', 'ADM-2026-0500', 'x', null]),
      9,
    );
    expect(AdmissionNumberFormat.highest(const []), 0);
  });

  test('generated numbers are valid admission numbers', () {
    expect(AdmissionKey.validate(AdmissionNumberFormat.format(1)), isNull);
  });
}
