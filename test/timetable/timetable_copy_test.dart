import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/timetable/domain/period_set.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_copy.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_enums.dart';
import 'package:flutter_test/flutter_test.dart';

PeriodSlot _p(String id, int n, int s, int e) => PeriodSlot(
  slotId: id,
  number: n,
  kind: SlotKind.teaching,
  label: '',
  startMin: s,
  endMin: e,
);

PeriodSet _set(String id, List<PeriodSlot> slots) => PeriodSet(
  periodSetId: id,
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  name: id,
  slots: slots,
);

Timetable _tt(String section, Map<String, String> days) => Timetable(
  timetableId: 'y1__c5__${section}__v1',
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: section,
  className: 'Class 5',
  sectionName: section.toUpperCase(),
  name: 'T',
  version: 1,
  status: TimetableStatus.draft,
  dayPeriodSets: days,
  effectiveFromKey: '2026-06-01',
);

TimetableEntry _e(
  Timetable t,
  Weekday d,
  String slot,
  int n,
  int s,
  int e,
  String subject,
  String teacher,
) => TimetableEntry(
  entryId: TimetableEntry.idFor(t.timetableId, d, slot),
  timetableId: t.timetableId,
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  classId: t.classId,
  sectionId: t.sectionId,
  weekday: d,
  slotId: slot,
  periodNumber: n,
  startMin: s,
  endMin: e,
  subjectId: subject,
  subjectName: subject,
  teacherStaffId: teacher,
  teacherName: 'T $teacher',
  room: 'Room 1',
);

void main() {
  final regular = _set('reg', [_p('p1', 1, 540, 580), _p('p2', 2, 590, 630)]);
  final short = _set('short', [_p('a', 1, 540, 570), _p('b', 2, 570, 600)]);
  final onlyOne = _set('one', [_p('x', 1, 540, 580)]);

  group('copy a day', () {
    final t = _tt('sa', {
      'MONDAY': 'reg',
      'TUESDAY': 'reg',
      'WEDNESDAY': 'short',
      'THURSDAY': 'one',
    });
    final entries = [
      _e(t, Weekday.monday, 'p1', 1, 540, 580, 'math', 't1'),
      _e(t, Weekday.monday, 'p2', 2, 590, 630, 'eng', 't2'),
    ];
    final sets = {'reg': regular, 'short': short, 'one': onlyOne};

    test('same schedule: slots map by id, cells replaced on the target', () {
      final r = TimetableCopier.copyDay(
        timetable: t,
        entries: entries,
        day: Weekday.monday,
        targets: [Weekday.tuesday],
        periodSets: sets,
      );
      expect(r.skipped, isEmpty);
      expect(r.entries.map((e) => (e.weekday, e.slotId)), [
        (Weekday.tuesday, 'p1'),
        (Weekday.tuesday, 'p2'),
      ]);
      expect(r.entries.every((e) => e.live == false), isTrue);
      expect(
        r.entries.first.entryId,
        'y1__c5__sa__v1__TUESDAY__p1',
        reason: 'ids follow weekday + slot',
      );
    });

    test('a different schedule maps by period number and takes its times', () {
      final r = TimetableCopier.copyDay(
        timetable: t,
        entries: entries,
        day: Weekday.monday,
        targets: [Weekday.wednesday],
        periodSets: sets,
      );
      expect(
        r.entries.map((e) => (e.slotId, e.periodNumber, e.startMin, e.endMin)),
        [('a', 1, 540, 570), ('b', 2, 570, 600)],
      );
    });

    test('periods with no counterpart are skipped and reported', () {
      final r = TimetableCopier.copyDay(
        timetable: t,
        entries: entries,
        day: Weekday.monday,
        targets: [Weekday.thursday],
        periodSets: sets,
      );
      expect(r.entries, hasLength(1));
      expect(r.skipped.single, contains('no period 2'));
    });

    test(
      'a target day without a schedule is skipped; the source day is not a target',
      () {
        final r = TimetableCopier.copyDay(
          timetable: t,
          entries: entries,
          day: Weekday.monday,
          targets: [Weekday.friday, Weekday.monday],
          periodSets: sets,
        );
        expect(r.entries, isEmpty);
        expect(r.skipped.single, contains('Friday'));
      },
    );

    test('room and teacher travel with a day copy', () {
      final r = TimetableCopier.copyDay(
        timetable: t,
        entries: entries,
        day: Weekday.monday,
        targets: [Weekday.tuesday],
        periodSets: sets,
      );
      expect(r.entries.first.room, 'Room 1');
      expect(r.entries.first.teacherStaffId, 't1');
    });
  });

  group('copy to another section', () {
    final src = _tt('sa', {'MONDAY': 'reg'});
    final target = _tt('sb', {'MONDAY': 'reg'});
    final entries = [
      _e(src, Weekday.monday, 'p1', 1, 540, 580, 'math', 't1'),
      _e(src, Weekday.monday, 'p2', 2, 590, 630, 'eng', 't2'),
    ];

    test('teachers become the target section\'s; rooms are cleared', () {
      final r = TimetableCopier.toSection(
        entries: entries,
        target: target,
        teacherBySubject: {
          'math': const SectionTeacher('t9', 'Mr Nine'),
          'eng': const SectionTeacher('t8', 'Ms Eight'),
        },
      );
      expect(r.skipped, isEmpty);
      expect(r.entries.map((e) => e.teacherStaffId), ['t9', 't8']);
      expect(r.entries.every((e) => e.sectionId == 'sb'), isTrue);
      expect(r.entries.every((e) => e.room == null), isTrue);
      expect(r.entries.first.timetableId, target.timetableId);
      expect(r.entries.first.entryId, startsWith('y1__c5__sb__v1__MONDAY'));
    });

    test('a subject the target does not teach is skipped, never guessed', () {
      final r = TimetableCopier.toSection(
        entries: entries,
        target: target,
        teacherBySubject: {'math': const SectionTeacher('t9', 'Mr Nine')},
      );
      expect(r.entries, hasLength(1));
      expect(r.skipped.single, allOf(contains('Class 5 SB'), contains('eng')));
    });
  });
}
