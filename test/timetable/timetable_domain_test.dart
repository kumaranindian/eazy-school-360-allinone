import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/leave/domain/leave_application.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/timetable/domain/period_set.dart';
import 'package:eazy_school_360/features/timetable/domain/substitution.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_enums.dart';
import 'package:eazy_school_360/features/timetable/domain/timetable_validation.dart';
import 'package:flutter_test/flutter_test.dart';

PeriodSlot _p(String id, int n, int s, int e) => PeriodSlot(
  slotId: id,
  number: n,
  kind: SlotKind.teaching,
  label: '',
  startMin: s,
  endMin: e,
);

PeriodSet _set({List<PeriodSlot>? slots, String name = 'Regular'}) => PeriodSet(
  periodSetId: 'y1__regular',
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  name: name,
  slots:
      slots ??
      [
        _p('p1', 1, 540, 580),
        const PeriodSlot(
          slotId: 'brk',
          kind: SlotKind.breakSlot,
          label: 'Break',
          startMin: 580,
          endMin: 590,
        ),
        _p('p2', 2, 590, 630),
        _p('p3', 3, 630, 670),
      ],
);

Timetable _tt(
  String section, {
  int version = 1,
  String from = '2026-06-01',
  String? to,
  TimetableStatus status = TimetableStatus.published,
  String cls = 'c5',
  Map<String, String>? days,
}) => Timetable(
  timetableId: Timetable.idFor('y1__${cls}__$section', version),
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  classId: cls,
  sectionId: section,
  className: 'Class 5',
  sectionName: section.toUpperCase(),
  name: 'Term 1',
  version: version,
  status: status,
  dayPeriodSets:
      days ?? const {'MONDAY': 'y1__regular', 'TUESDAY': 'y1__regular'},
  effectiveFromKey: from,
  effectiveToKey: to,
);

TimetableEntry _e(
  Timetable t,
  String slot,
  int period,
  int start,
  int end,
  String subject,
  String teacher, {
  Weekday day = Weekday.monday,
  String? room,
}) => TimetableEntry(
  entryId: TimetableEntry.idFor(t.timetableId, day, slot),
  timetableId: t.timetableId,
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  classId: t.classId,
  sectionId: t.sectionId,
  weekday: day,
  slotId: slot,
  periodNumber: period,
  startMin: start,
  endMin: end,
  subjectId: subject,
  subjectName: subject,
  teacherStaffId: teacher,
  teacherName: 'Teacher $teacher',
  room: room,
  live: true,
);

AssignmentFact _a(
  String teacher,
  String section,
  String subject, {
  String cls = 'c5',
  bool classTeacher = false,
}) => AssignmentFact(
  teacherStaffId: teacher,
  classId: cls,
  sectionId: section,
  subjectId: classTeacher ? null : subject,
  isClassTeacher: classTeacher,
);

final _working = {
  for (final d in Weekday.values)
    if (d != Weekday.saturday && d != Weekday.sunday) d.wireValue,
};

List<TimetableIssue> _validate(
  TimetableBundle candidate, {
  List<TimetableBundle> others = const [],
  List<AssignmentFact>? assignments,
  Set<String>? active,
  Map<String, PeriodSet>? sets,
  Set<String>? working,
  List<LeaveCalendarEntry> leave = const [],
}) => TimetableValidator.validate(
  candidate: candidate,
  periodSets: sets ?? {'y1__regular': _set()},
  workingWeekdays: working ?? _working,
  otherPublished: others,
  sectionAssignments:
      assignments ?? [_a('t1', 'sa', 'math'), _a('t2', 'sa', 'eng')],
  activeTeacherIds: active ?? {'t1', 't2', 't3'},
  staffLeave: leave,
);

Iterable<IssueKind> _kinds(List<TimetableIssue> i, {bool errors = true}) =>
    i.where((x) => !errors || x.isError).map((x) => x.kind);

void main() {
  group('period sets', () {
    test('a valid schedule', () => expect(_set().validate(), isNull));

    test('end must be after start; times stay within a day', () {
      expect(
        _set(slots: [_p('p1', 1, 600, 600)]).validate(),
        contains('after the start'),
      );
      expect(
        _set(slots: [_p('p1', 1, 1400, 1500)]).validate(),
        contains('within one day'),
      );
      expect(_set(slots: [_p('p1', 1, 700, 650)]).validate(), isNotNull);
    });

    test('overlapping slots are named', () {
      final msg = _set(
        slots: [_p('p1', 1, 540, 590), _p('p2', 2, 580, 630)],
      ).validate();
      expect(msg, contains('overlaps'));
    });

    test('back-to-back is fine; ids unique; numbering 1..n in time order', () {
      expect(
        _set(slots: [_p('p1', 1, 540, 580), _p('p2', 2, 580, 620)]).validate(),
        isNull,
      );
      expect(
        _set(slots: [_p('p1', 1, 540, 580), _p('p1', 2, 590, 630)]).validate(),
        contains('unique'),
      );
      expect(
        _set(slots: [_p('p1', 2, 540, 580), _p('p2', 1, 590, 630)]).validate(),
        contains('numbered'),
      );
    });

    test('needs a teaching period and a name for non-teaching slots', () {
      expect(
        _set(
          slots: const [
            PeriodSlot(
              slotId: 'lunch',
              kind: SlotKind.lunch,
              label: 'Lunch',
              startMin: 700,
              endMin: 740,
            ),
          ],
        ).validate(),
        contains('teaching'),
      );
      expect(
        _set(
          slots: [
            _p('p1', 1, 540, 580),
            const PeriodSlot(
              slotId: 'b',
              kind: SlotKind.breakSlot,
              label: ' ',
              startMin: 580,
              endMin: 590,
            ),
          ],
        ).validate(),
        contains('Name'),
      );
    });

    test('normalized renumbers teaching slots in time order', () {
      final n = _set(
        slots: [_p('b', 9, 600, 640), _p('a', 5, 540, 580)],
      ).normalized();
      expect(
        [for (final s in n.slots) (s.slotId, s.number)],
        [('a', 1), ('b', 2)],
      );
      expect(n.validate(), isNull);
    });

    test('non-teaching slots need no subject or teacher', () {
      final s = _set();
      expect(s.teachingSlots.map((x) => x.slotId), ['p1', 'p2', 'p3']);
      expect(s.slot('brk')!.isTeaching, isFalse);
    });

    test('minute-of-day parsing and display', () {
      expect(MinuteOfDay.parse('09:05'), 545);
      expect(MinuteOfDay.parse('24:00'), isNull);
      expect(MinuteOfDay.parse('9'), isNull);
      expect(MinuteOfDay.format(545), '09:05');
      expect(MinuteOfDay.overlaps(540, 580, 580, 620), isFalse);
      expect(MinuteOfDay.overlaps(540, 581, 580, 620), isTrue);
    });
  });

  group('timetable metadata and effective dates', () {
    test('valid', () => expect(_tt('sa').validateMeta(), isNull));

    test('range rules and the academic-year bounds', () {
      expect(
        _tt('sa', from: '2026-09-01', to: '2026-08-01').validateMeta(),
        contains('before the start'),
      );
      expect(
        _tt(
          'sa',
          from: '2026-05-01',
        ).validateMeta(yearStartKey: '2026-06-01', yearEndKey: '2027-03-31'),
        contains('before the academic year'),
      );
      expect(
        _tt(
          'sa',
          from: '2026-06-01',
          to: '2027-04-30',
        ).validateMeta(yearStartKey: '2026-06-01', yearEndKey: '2027-03-31'),
        contains('past the academic year'),
      );
      expect(_tt('sa', days: const {}).validateMeta(), isNotNull);
    });

    test('date coverage and overlap use civil keys', () {
      final t = _tt('sa', from: '2026-06-01', to: '2026-08-31');
      expect(t.coversDate('2026-06-01'), isTrue);
      expect(t.coversDate('2026-08-31'), isTrue);
      expect(t.coversDate('2026-09-01'), isFalse);
      expect(t.overlapsRange('2026-08-31', null), isTrue);
      expect(t.overlapsRange('2026-09-01', null), isFalse);
      expect(_tt('sa').overlapsRange('2030-01-01', null), isTrue);
    });

    test('ids and version keys are stable', () {
      expect(Timetable.idFor('y1__c5__sa', 3), 'y1__c5__sa__v3');
      expect(
        TimetableEntry.idFor('y1__c5__sa__v3', Weekday.monday, 'p1'),
        'y1__c5__sa__v3__MONDAY__p1',
      );
    });
  });

  group('validation: structure and assignments', () {
    test('an empty draft cannot be published', () {
      final t = _tt('sa', status: TimetableStatus.draft);
      final issues = _validate(TimetableBundle(t, const []));
      expect(_kinds(issues), contains(IssueKind.empty));
      expect(TimetablePublication.checkPublish(t, issues), isNotNull);
    });

    test('a clean draft can be published; only drafts can be', () {
      final t = _tt('sa', status: TimetableStatus.draft);
      final issues = _validate(
        TimetableBundle(t, [
          _e(t, 'p1', 1, 540, 580, 'math', 't1'),
          _e(t, 'p2', 2, 590, 630, 'eng', 't2'),
        ]),
      );
      expect(issues.where((i) => i.isError), isEmpty);
      expect(TimetablePublication.checkPublish(t, issues), isNull);
      expect(
        TimetablePublication.checkPublish(_tt('sa'), issues),
        contains('Only a draft'),
      );
    });

    test(
      'a teacher who is not the assigned teacher for the subject is refused',
      () {
        final t = _tt('sa', status: TimetableStatus.draft);
        final issues = _validate(
          TimetableBundle(t, [_e(t, 'p1', 1, 540, 580, 'math', 't2')]),
        );
        expect(_kinds(issues), contains(IssueKind.notAssigned));
        expect(
          issues.first.message,
          allOf(contains('Teacher t2'), contains('math')),
        );
      },
    );

    test('an inactive teacher is refused even if still assigned', () {
      final t = _tt('sa', status: TimetableStatus.draft);
      final issues = _validate(
        TimetableBundle(t, [_e(t, 'p1', 1, 540, 580, 'math', 't1')]),
        active: {'t2'},
      );
      expect(_kinds(issues), contains(IssueKind.notAssigned));
    });

    test(
      'a class-teacher assignment alone does not allow a subject period',
      () {
        final t = _tt('sa', status: TimetableStatus.draft);
        final issues = _validate(
          TimetableBundle(t, [_e(t, 'p1', 1, 540, 580, 'math', 't1')]),
          assignments: [_a('t1', 'sa', 'x', classTeacher: true)],
        );
        expect(_kinds(issues), contains(IssueKind.notAssigned));
      },
    );

    test('slots: unknown, non-teaching and stale times are refused', () {
      final t = _tt('sa', status: TimetableStatus.draft);
      final issues = _validate(
        TimetableBundle(t, [
          _e(t, 'zz', 1, 540, 580, 'math', 't1'),
          _e(t, 'brk', 1, 580, 590, 'eng', 't2'),
          _e(t, 'p3', 3, 600, 640, 'math', 't1'),
        ]),
        assignments: [_a('t1', 'sa', 'math'), _a('t2', 'sa', 'eng')],
      );
      expect(
        _kinds(issues),
        containsAll([IssueKind.invalidSlot, IssueKind.stalePeriods]),
      );
    });

    test('non-working days and missing schedules are refused', () {
      final t = _tt(
        'sa',
        status: TimetableStatus.draft,
        days: const {'SATURDAY': 'y1__regular', 'MONDAY': 'gone'},
      );
      final issues = _validate(
        TimetableBundle(t, [
          _e(t, 'p1', 1, 540, 580, 'math', 't1', day: Weekday.saturday),
        ]),
      );
      expect(
        _kinds(issues),
        containsAll([IssueKind.nonWorkingDay, IssueKind.missingPeriodSet]),
      );
    });

    test('an entry on a day the timetable does not cover is refused', () {
      final t = _tt(
        'sa',
        status: TimetableStatus.draft,
        days: const {'MONDAY': 'y1__regular'},
      );
      final issues = _validate(
        TimetableBundle(t, [
          _e(t, 'p1', 1, 540, 580, 'math', 't1', day: Weekday.wednesday),
        ]),
      );
      expect(_kinds(issues), contains(IssueKind.nonWorkingDay));
    });
  });

  group('validation: conflicts across timetables', () {
    final draft = _tt('sa', status: TimetableStatus.draft);
    final other = _tt('sb');

    test(
      'TEACHER double-booking across sections names day, period and class',
      () {
        final issues = _validate(
          TimetableBundle(draft, [_e(draft, 'p1', 1, 540, 580, 'math', 't1')]),
          others: [
            TimetableBundle(other, [
              _e(other, 'p1', 1, 540, 580, 'math', 't1'),
            ]),
          ],
        );
        final c = issues.firstWhere((i) => i.kind == IssueKind.teacherConflict);
        expect(c.isError, isTrue);
        expect(
          c.message,
          allOf(
            contains('Teacher t1'),
            contains('Class 5 SB'),
            contains('Monday'),
          ),
        );
      },
    );

    test('partially overlapping periods conflict; back-to-back do not', () {
      final partial = _validate(
        TimetableBundle(draft, [_e(draft, 'p1', 1, 540, 580, 'math', 't1')]),
        others: [
          TimetableBundle(other, [_e(other, 'p2', 2, 570, 610, 'math', 't1')]),
        ],
      );
      expect(_kinds(partial), contains(IssueKind.teacherConflict));
      final adjacent = _validate(
        TimetableBundle(draft, [_e(draft, 'p1', 1, 540, 580, 'math', 't1')]),
        others: [
          TimetableBundle(other, [_e(other, 'p2', 2, 580, 620, 'math', 't1')]),
        ],
      );
      expect(_kinds(adjacent), isNot(contains(IssueKind.teacherConflict)));
    });

    test('same time on a different weekday is not a conflict', () {
      final issues = _validate(
        TimetableBundle(draft, [_e(draft, 'p1', 1, 540, 580, 'math', 't1')]),
        others: [
          TimetableBundle(other, [
            _e(other, 'p1', 1, 540, 580, 'math', 't1', day: Weekday.tuesday),
          ]),
        ],
      );
      expect(_kinds(issues), isNot(contains(IssueKind.teacherConflict)));
    });

    test('disjoint effective dates do not conflict', () {
      final later = _tt(
        'sa',
        status: TimetableStatus.draft,
        from: '2026-09-01',
      );
      final earlier = _tt('sb', from: '2026-06-01', to: '2026-08-31');
      final issues = _validate(
        TimetableBundle(later, [_e(later, 'p1', 1, 540, 580, 'math', 't1')]),
        others: [
          TimetableBundle(earlier, [
            _e(earlier, 'p1', 1, 540, 580, 'math', 't1'),
          ]),
        ],
      );
      expect(_kinds(issues), isNot(contains(IssueKind.teacherConflict)));
    });

    test(
      'ROOM double-booking is detected case-insensitively; unset rooms never clash',
      () {
        final issues = _validate(
          TimetableBundle(draft, [
            _e(draft, 'p1', 1, 540, 580, 'math', 't1', room: 'Lab 2'),
          ]),
          others: [
            TimetableBundle(other, [
              _e(other, 'p1', 1, 540, 580, 'sci', 't3', room: ' lab 2'),
            ]),
          ],
        );
        expect(_kinds(issues), contains(IssueKind.roomConflict));
        final none = _validate(
          TimetableBundle(draft, [_e(draft, 'p1', 1, 540, 580, 'math', 't1')]),
          others: [
            TimetableBundle(other, [_e(other, 'p1', 1, 540, 580, 'sci', 't3')]),
          ],
        );
        expect(_kinds(none), isNot(contains(IssueKind.roomConflict)));
      },
    );

    test(
      'another version of the SAME section is a warning that it will be replaced',
      () {
        final old = _tt('sa', version: 1);
        final next = _tt('sa', version: 2, status: TimetableStatus.draft);
        final issues = _validate(
          TimetableBundle(next, [_e(next, 'p1', 1, 540, 580, 'math', 't1')]),
          others: [
            TimetableBundle(old, [_e(old, 'p1', 1, 540, 580, 'math', 't1')]),
          ],
        );
        final w = issues.firstWhere((i) => i.kind == IssueKind.sectionOverlap);
        expect(w.severity, IssueSeverity.warning);
        expect(_kinds(issues), isNot(contains(IssueKind.teacherConflict)));
      },
    );

    test('approved leave in the range produces a warning, never an error', () {
      final leave = LeaveCalendarEntry(
        applicationId: 'l1',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.staff,
        subjectId: 't1',
        subjectName: 'T1',
        startDateKey: '2026-08-03',
        endDateKey: '2026-08-04',
        countedDateKeys: const ['2026-08-03', '2026-08-04'],
      );
      final issues = _validate(
        TimetableBundle(draft, [_e(draft, 'p1', 1, 540, 580, 'math', 't1')]),
        leave: [leave],
      );
      final w = issues.firstWhere((i) => i.kind == IssueKind.teacherOnLeave);
      expect(w.severity, IssueSeverity.warning);
      expect(w.message, contains('03/08/2026'));
      expect(issues.where((i) => i.isError), isEmpty);
      // Tuesday leave on a Monday-only teacher: nothing to warn about
      final tue = LeaveCalendarEntry(
        applicationId: 'l2',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.staff,
        subjectId: 't1',
        subjectName: 'T1',
        startDateKey: '2026-08-04',
        endDateKey: '2026-08-04',
        countedDateKeys: const ['2026-08-04'],
      );
      expect(
        _kinds(
          _validate(
            TimetableBundle(draft, [
              _e(draft, 'p1', 1, 540, 580, 'math', 't1'),
            ]),
            leave: [tue],
          ),
          errors: false,
        ),
        isNot(contains(IssueKind.teacherOnLeave)),
      );
    });
  });

  group('publication: which version applies, and what a new one replaces', () {
    test('resolver picks the version in force on a date, newest first', () {
      final v1 = _tt('sa', version: 1, to: '2026-08-31');
      final v2 = _tt('sa', version: 2, from: '2026-09-01');
      final all = [v1, v2];
      final key = v1.sectionKeyValue;
      expect(
        TimetableResolver.forSectionOn(all, key, '2026-08-15')!.version,
        1,
      );
      expect(
        TimetableResolver.forSectionOn(all, key, '2026-09-01')!.version,
        2,
      );
      expect(TimetableResolver.forSectionOn(all, key, '2026-05-01'), isNull);
      expect(
        TimetableResolver.forSectionOn(
          [_tt('sa', status: TimetableStatus.archived)],
          key,
          '2026-08-01',
        ),
        isNull,
      );
    });

    test(
      'a later-starting version TRUNCATES the old; an earlier one REPLACES it',
      () {
        final old = _tt('sa', version: 1, from: '2026-06-01');
        final later = _tt(
          'sa',
          version: 2,
          from: '2026-09-01',
          status: TimetableStatus.draft,
        );
        final plan = TimetablePublication.planSupersession(later, [old]);
        expect(plan.archive, isEmpty);
        expect(plan.truncate.single.newEndKey, '2026-08-31');

        final earlier = _tt(
          'sa',
          version: 3,
          from: '2026-05-01',
          status: TimetableStatus.draft,
        );
        final replace = TimetablePublication.planSupersession(earlier, [old]);
        expect(replace.archive.single.timetableId, old.timetableId);
        expect(replace.truncate, isEmpty);
      },
    );

    test('other sections and non-overlapping versions are untouched', () {
      final cand = _tt(
        'sa',
        version: 2,
        from: '2026-09-01',
        status: TimetableStatus.draft,
      );
      final plan = TimetablePublication.planSupersession(cand, [
        _tt('sb'),
        _tt('sa', version: 1, from: '2026-06-01', to: '2026-08-31'),
      ]);
      expect(plan.isEmpty, isTrue);
    });

    test('truncation crosses month and year ends', () {
      final cand = _tt(
        'sa',
        version: 2,
        from: '2027-01-01',
        status: TimetableStatus.draft,
      );
      final plan = TimetablePublication.planSupersession(cand, [_tt('sa')]);
      expect(plan.truncate.single.newEndKey, '2026-12-31');
    });
  });

  group('substitution planning', () {
    final wd = WorkingDays.defaults(schoolId: 's', branchId: 'b');
    // Class 5 A: Monday p1 maths (t1), p2 english (t2). Class 5 B: Monday p1 science (t3).
    final sa = _tt('sa');
    final sb = _tt('sb');
    final saEntries = [
      _e(sa, 'p1', 1, 540, 580, 'math', 't1'),
      _e(sa, 'p2', 2, 590, 630, 'eng', 't2'),
    ];
    final sbEntries = [_e(sb, 'p1', 1, 540, 580, 'sci', 't3')];
    final bundles = [
      TimetableBundle(sa, saEntries),
      TimetableBundle(sb, sbEntries),
    ];
    final assignments = [
      _a('t1', 'sa', 'math'),
      _a('t2', 'sa', 'eng'),
      _a('t3', 'sb', 'sci'),
      _a('t4', 'sb', 'math'), // teaches maths elsewhere, free on Monday p1
    ];
    final teachers = [
      for (final id in ['t1', 't2', 't3', 't4', 't5'])
        StaffLite(staffId: id, name: 'Teacher $id', userId: 'u-$id'),
    ];

    // 2026-08-03 is a Monday
    List<AffectedPeriod> affected({
      String from = '2026-08-03',
      String to = '2026-08-03',
      List<Substitution> subs = const [],
      List<Holiday> holidays = const [],
    }) => SubstitutionPlanner.affected(
      teacherId: 't1',
      fromKey: from,
      toKey: to,
      published: bundles,
      workingDays: wd,
      calendarEntries: holidays,
      substitutions: subs,
    );

    test('finds the teacher\'s periods on school days only', () {
      final a = affected(from: '2026-08-03', to: '2026-08-10');
      expect(a.map((p) => p.dateKey), ['2026-08-03', '2026-08-10']);
      expect(a.first.entry.slotId, 'p1');
      // a weekend and a Tuesday (no entries) contribute nothing
      expect(affected(from: '2026-08-08', to: '2026-08-09'), isEmpty);
    });

    test('a holiday removes the periods of that day', () {
      final h = Holiday(
        holidayId: 'h',
        schoolId: 's',
        branchId: 'b',
        academicYearId: 'y1',
        date: DateTime.utc(2026, 8, 3),
        name: 'Holiday',
        type: HolidayType.school,
        status: ActivationStatus.active,
      );
      expect(affected(holidays: [h]), isEmpty);
    });

    test('uses the version in force on each date', () {
      final v1 = _tt('sa', version: 1, to: '2026-08-31');
      final v2 = _tt('sa', version: 2, from: '2026-09-01');
      final e2 = _e(v2, 'p3', 3, 630, 670, 'math', 't1');
      final a = SubstitutionPlanner.affected(
        teacherId: 't1',
        fromKey: '2026-08-31',
        toKey: '2026-09-07',
        published: [
          TimetableBundle(v1, [_e(v1, 'p1', 1, 540, 580, 'math', 't1')]),
          TimetableBundle(v2, [e2]),
        ],
        workingDays: wd,
        calendarEntries: const [],
        substitutions: const [],
      );
      expect(a.map((p) => '${p.dateKey}:${p.timetable.version}'), [
        '2026-08-31:1',
        '2026-09-07:2',
      ]);
    });

    test(
      'an existing cover is attached; the original timetable is not touched',
      () {
        final p = affected().single;
        final sub = Substitution(
          substitutionId: p.substitutionId,
          schoolId: 's',
          branchId: 'b',
          academicYearId: 'y1',
          dateKey: p.dateKey,
          timetableId: p.timetable.timetableId,
          timetableVersion: 1,
          entryId: p.entry.entryId,
          slotId: 'p1',
          weekday: Weekday.monday,
          periodNumber: 1,
          startMin: 540,
          endMin: 580,
          classId: 'c5',
          sectionId: 'sa',
          subjectId: 'math',
          subjectName: 'math',
          originalTeacherId: 't1',
          originalTeacherName: 'T1',
          substituteTeacherId: 't4',
          substituteTeacherName: 'T4',
          reasonKind: SubstitutionReasonKind.leave,
          reason: 'Leave',
        );
        final withSub = affected(subs: [sub]).single;
        expect(withSub.isCovered, isTrue);
        expect(withSub.entry.teacherStaffId, 't1');
      },
    );

    List<SubstituteCandidate> candidates({
      List<Substitution> subs = const [],
      List<LeaveCalendarEntry> leave = const [],
    }) => SubstitutionPlanner.candidates(
      period: affected().single,
      activeTeachers: teachers,
      yearAssignments: assignments,
      published: bundles,
      substitutionsOnDate: subs,
      staffLeave: leave,
    );

    SubstituteCandidate of(List<SubstituteCandidate> c, String id) =>
        c.firstWhere((x) => x.staff.staffId == id);

    test(
      'eligibility: free and qualified is eligible; the original is not',
      () {
        final c = candidates();
        expect(of(c, 't4').eligible, isTrue);
        expect(of(c, 't4').teachesSubject, isTrue);
        expect(of(c, 't1').eligible, isFalse);
        expect(of(c, 't1').reasons.first, contains('being replaced'));
      },
    );

    test('a teacher with a regular period at that time is not eligible', () {
      final c = candidates();
      expect(of(c, 't3').eligible, isFalse);
      expect(of(c, 't3').reasons.join(), contains('Class 5 SB'));
    });

    test('a period that someone else already covers frees its teacher', () {
      final p = affected().single;
      final coverOfT3 = Substitution(
        substitutionId: Substitution.idFor('2026-08-03', sb.timetableId, 'p1'),
        schoolId: 's',
        branchId: 'b',
        academicYearId: 'y1',
        dateKey: '2026-08-03',
        timetableId: sb.timetableId,
        timetableVersion: 1,
        entryId: sbEntries.first.entryId,
        slotId: 'p1',
        weekday: Weekday.monday,
        periodNumber: 1,
        startMin: 540,
        endMin: 580,
        classId: 'c5',
        sectionId: 'sb',
        subjectId: 'sci',
        subjectName: 'sci',
        originalTeacherId: 't3',
        originalTeacherName: 'T3',
        substituteTeacherId: 't5',
        substituteTeacherName: 'T5',
        reasonKind: SubstitutionReasonKind.absence,
        reason: 'Absent',
      );
      final c = SubstitutionPlanner.candidates(
        period: p,
        activeTeachers: teachers,
        yearAssignments: [
          ...assignments,
          _a('t5', 'sb', 'x', cls: 'c5'),
        ],
        published: bundles,
        substitutionsOnDate: [coverOfT3],
        staffLeave: const [],
      );
      expect(
        of(c, 't3').eligible,
        isTrue,
        reason: 't3 is free: t5 covers them',
      );
      // ...and t5 is now busy covering that period at the same time
      expect(of(c, 't5').eligible, isFalse);
      expect(of(c, 't5').reasons.join(), contains('Already covering'));
    });

    test('approved leave that day makes a candidate ineligible', () {
      final leave = LeaveCalendarEntry(
        applicationId: 'l',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.staff,
        subjectId: 't4',
        subjectName: 'T4',
        startDateKey: '2026-08-03',
        endDateKey: '2026-08-03',
        countedDateKeys: const ['2026-08-03'],
      );
      final c = candidates(leave: [leave]);
      expect(of(c, 't4').eligible, isFalse);
      expect(of(c, 't4').reasons.join(), contains('approved leave'));
    });

    test('a cancelled leave no longer blocks', () {
      final cancelled = LeaveCalendarEntry(
        applicationId: 'l',
        schoolId: 's',
        branchId: 'b',
        kind: LeaveKind.staff,
        subjectId: 't4',
        subjectName: 'T4',
        startDateKey: '2026-08-03',
        endDateKey: '2026-08-03',
        countedDateKeys: const ['2026-08-03'],
        active: false,
      );
      expect(of(candidates(leave: [cancelled]), 't4').eligible, isTrue);
    });

    test(
      'qualification: must teach the subject or the class; ranked best first',
      () {
        final c = candidates();
        // t5 teaches nothing in this class or this subject
        expect(of(c, 't5').eligible, isFalse);
        expect(of(c, 't5').reasons.join(), contains('Does not teach'));
        final eligible = c.where((x) => x.eligible).toList();
        expect(eligible.first.staff.staffId, 't4');
      },
    );

    test(
      'suggestions never include an ineligible person as eligible, and rank them last',
      () {
        final c = candidates();
        final firstIneligible = c.indexWhere((x) => !x.eligible);
        expect(c.sublist(firstIneligible).every((x) => !x.eligible), isTrue);
      },
    );
  });

  group('re-validation when leave or the timetable changes', () {
    final t = _tt('sa');
    final cell = _e(t, 'p1', 1, 540, 580, 'math', 't1');
    Substitution sub({String? leaveId = 'L1', String substitute = 't4'}) =>
        Substitution(
          substitutionId: 'x',
          schoolId: 's',
          branchId: 'b',
          academicYearId: 'y1',
          dateKey: '2026-08-03',
          timetableId: t.timetableId,
          timetableVersion: 1,
          entryId: cell.entryId,
          slotId: 'p1',
          weekday: Weekday.monday,
          periodNumber: 1,
          startMin: 540,
          endMin: 580,
          classId: 'c5',
          sectionId: 'sa',
          subjectId: 'math',
          subjectName: 'math',
          originalTeacherId: 't1',
          originalTeacherName: 'T1',
          substituteTeacherId: substitute,
          substituteTeacherName: substitute,
          reasonKind: SubstitutionReasonKind.leave,
          reason: 'Leave',
          leaveApplicationId: leaveId,
        );

    LeaveCalendarEntry leave(String id, String who, {bool active = true}) =>
        LeaveCalendarEntry(
          applicationId: id,
          schoolId: 's',
          branchId: 'b',
          kind: LeaveKind.staff,
          subjectId: who,
          subjectName: who,
          startDateKey: '2026-08-03',
          endDateKey: '2026-08-03',
          countedDateKeys: const ['2026-08-03'],
          active: active,
        );

    test('a healthy cover has no warnings', () {
      expect(
        SubstitutionHealth.check(
          substitution: sub(),
          staffLeave: [leave('L1', 't1')],
          published: [t],
        ),
        isEmpty,
      );
    });

    test('LEAVE CANCELLED after the cover was arranged is reported', () {
      final w = SubstitutionHealth.check(
        substitution: sub(),
        staffLeave: [leave('L1', 't1', active: false)],
        published: [t],
      );
      expect(w, contains(SubstitutionWarning.leaveNoLongerApproved));
    });

    test('the substitute getting approved leave later is reported', () {
      final w = SubstitutionHealth.check(
        substitution: sub(),
        staffLeave: [leave('L1', 't1'), leave('L2', 't4')],
        published: [t],
      );
      expect(w, contains(SubstitutionWarning.substituteOnLeave));
    });

    test(
      'a replaced timetable is reported; a cancelled cover reports nothing',
      () {
        expect(
          SubstitutionHealth.check(
            substitution: sub(),
            staffLeave: [leave('L1', 't1')],
            published: const [],
          ),
          contains(SubstitutionWarning.timetableChanged),
        );
        final cancelled = Substitution.fromFirestore({
          'schoolId': 's',
          'branchId': 'b',
          'academicYearId': 'y1',
          'dateKey': '2026-08-03',
          'timetableId': t.timetableId,
          'entryId': cell.entryId,
          'slotId': 'p1',
          'weekday': 'MONDAY',
          'periodNumber': 1,
          'startMin': 540,
          'endMin': 580,
          'classId': 'c5',
          'sectionId': 'sa',
          'subjectId': 'math',
          'originalTeacherId': 't1',
          'substituteTeacherId': 't4',
          'status': 'CANCELLED',
        }, 'x');
        expect(
          SubstitutionHealth.check(
            substitution: cancelled,
            staffLeave: const [],
            published: const [],
          ),
          isEmpty,
        );
      },
    );

    test('a change of the regular teacher on the cell is reported', () {
      final changed = cell.copyWith(teacherStaffId: 't2');
      final w = SubstitutionHealth.check(
        substitution: sub(),
        staffLeave: [leave('L1', 't1')],
        published: [t],
        bundles: [
          TimetableBundle(t, [changed]),
        ],
      );
      expect(w, contains(SubstitutionWarning.teacherChanged));
    });
  });
}
