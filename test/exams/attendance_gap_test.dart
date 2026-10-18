import 'package:eazy_school_360/features/exams/domain/attendance_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no warning when every attendance read succeeded', () {
    expect(AttendanceGap.warning(failed: 0, total: 30), isNull);
  });

  test('a partial failure names how many students are affected', () {
    final w = AttendanceGap.warning(failed: 3, total: 30)!;
    expect(w, contains('3 of 30 students'));
  });

  test('a total failure says so', () {
    expect(AttendanceGap.warning(failed: 30, total: 30), contains('all 30'));
  });
}
