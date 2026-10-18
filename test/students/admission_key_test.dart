import 'package:eazy_school_360/features/students/domain/admission_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the same number in any case or spacing is the same key', () {
    expect(AdmissionKey.of('ADM-001'), 'adm-001');
    expect(AdmissionKey.of('  Adm-001 '), AdmissionKey.of('adm-001'));
  });

  test('a slash cannot reach a document id', () {
    expect(AdmissionKey.of('2024/001'), '2024~001');
    expect(AdmissionKey.of('2024/001').contains('/'), isFalse);
  });

  test('validation', () {
    expect(AdmissionKey.validate('ADM-1'), isNull);
    expect(AdmissionKey.validate('   '), isNotNull);
    expect(AdmissionKey.validate('.hidden'), isNotNull);
    expect(AdmissionKey.validate('_x'), isNotNull);
    expect(AdmissionKey.validate('a' * 61), isNotNull);
    expect(AdmissionKey.validate('a' * 60), isNull);
  });
}
