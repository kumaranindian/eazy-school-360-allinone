import 'package:eazy_school_360/features/students/domain/placement_precondition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> student({String section = 'a', int stamp = 1}) => {
    'currentAcademicYearId': 'y1',
    'currentClassId': 'c1',
    'currentSectionId': section,
    'updatedAt': stamp,
  };

  test('holds while the student is unchanged', () {
    final planned = PlacementPrecondition.of(student());
    expect(planned.holdsFor(PlacementPrecondition.of(student())), isTrue);
  });

  test('fails after a concurrent placement change', () {
    final planned = PlacementPrecondition.of(student());
    expect(
      planned.holdsFor(
        PlacementPrecondition.of(student(section: 'b', stamp: 2)),
      ),
      isFalse,
    );
  });

  test('fails after any other write to the student record', () {
    final planned = PlacementPrecondition.of(student());
    expect(
      planned.holdsFor(PlacementPrecondition.of(student(stamp: 2))),
      isFalse,
    );
  });
}
