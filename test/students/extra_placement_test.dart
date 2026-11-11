import 'package:eazy_school_360/features/students/domain/extra_placement.dart';
import 'package:flutter_test/flutter_test.dart';

ExtraPlacement _p(String cls, {String year = 'y1', String sec = 's1'}) =>
    ExtraPlacement(
      recordId: 'r-$cls',
      academicYearId: year,
      classId: cls,
      sectionId: sec,
    );

void main() {
  test('keys cover the whole class and the exact section', () {
    expect(ExtraPlacement.keysOf([_p('dc', sec: 'd1')]), ['y1|dc', 'y1|dc|d1']);
  });

  test('round-trips through the stored map', () {
    const p = ExtraPlacement(
      recordId: 'r',
      academicYearId: 'y1',
      classId: 'dc',
      sectionId: 'd1',
      label: 'Afternoon',
      rollNumber: '4',
    );
    final back = ExtraPlacement.fromMap(p.toMap());
    expect(back.label, 'Afternoon');
    expect(back.rollNumber, '4');
    expect(back.sectionKey, 'y1|dc|d1');
    expect(ExtraPlacement.listFrom(null), isEmpty);
    expect(ExtraPlacement.listFrom([p.toMap()]), hasLength(1));
  });

  group('checkAdd', () {
    String? check(
      ExtraPlacement c, {
      List<ExtraPlacement> existing = const [],
    }) => ExtraPlacement.checkAdd(
      candidate: c,
      mainYearId: 'y1',
      mainClassId: 'pre',
      existing: existing,
    );

    test('a different class is fine', () => expect(check(_p('dc')), isNull));

    test('the main class is refused', () {
      expect(check(_p('pre')), contains('main class'));
    });

    test('the same class twice is refused, even in another section', () {
      expect(check(_p('dc', sec: 's2'), existing: [_p('dc')]), isNotNull);
    });

    test('a class of another year is not the main class', () {
      expect(check(_p('pre', year: 'y2')), isNull);
    });

    test('at most three extra classes', () {
      final full = [_p('a'), _p('b'), _p('c')];
      expect(check(_p('d'), existing: full), contains('at most 3'));
    });

    test('a long label is refused', () {
      final c = ExtraPlacement(
        recordId: '',
        academicYearId: 'y1',
        classId: 'dc',
        sectionId: 's1',
        label: 'x' * 31,
      );
      expect(check(c), contains('label'));
    });
  });
}
