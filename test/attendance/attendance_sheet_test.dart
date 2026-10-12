import 'package:eazy_school_360/features/attendance/domain/attendance_save_planner.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_sheet.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceEntry _new(String id) => AttendanceEntry(
  subjectId: id,
  name: 'Student $id',
  academicRecordId: 'rec-$id',
);

AttendanceEntry _saved(
  String id,
  AttendanceStatus status, {
  int revision = 1,
  String? remarks,
  String sectionId = 'a',
}) => AttendanceEntry(
  subjectId: id,
  name: 'Student $id',
  academicRecordId: 'rec-$id',
  savedStatus: status,
  savedRemarks: remarks,
  savedRevision: revision,
  savedSectionId: sectionId,
);

AttendanceSheet _sheet(
  List<AttendanceEntry> entries, {
  AttendanceDayStatus? day,
}) => AttendanceSheet(entries: entries, savedDayStatus: day);

void main() {
  group('marking', () {
    test(
      'a fresh register starts with everybody "not marked" — never silently present or absent',
      () {
        final sheet = _sheet([_new('1'), _new('2'), _new('3')]);
        expect(sheet.tally.notMarked, 3);
        expect(sheet.tally.present + sheet.tally.absent, 0);
        expect(sheet.isDirty, isFalse);
        expect(sheet.hasUnmarked, isTrue);
      },
    );

    test(
      'present, absent, late and half day can each be set on one student',
      () {
        final sheet = _sheet([_new('1'), _new('2'), _new('3'), _new('4')]);
        sheet.setStatus('1', AttendanceStatus.present);
        sheet.setStatus('2', AttendanceStatus.absent);
        sheet.setStatus('3', AttendanceStatus.late);
        sheet.setStatus('4', AttendanceStatus.halfDay);
        final t = sheet.tally;
        expect(
          (t.present, t.absent, t.late, t.halfDay, t.notMarked),
          (1, 1, 1, 1, 0),
        );
        expect(sheet.hasUnmarked, isFalse);
      },
    );

    test(
      'mark all present fills the unmarked only and keeps exceptions already chosen',
      () {
        final sheet = _sheet([_new('1'), _new('2'), _new('3')]);
        sheet.setStatus('2', AttendanceStatus.absent);
        sheet.markAllPresent();
        expect(sheet.entryFor('1')!.status, AttendanceStatus.present);
        expect(sheet.entryFor('2')!.status, AttendanceStatus.absent);
        expect(sheet.entryFor('3')!.status, AttendanceStatus.present);
      },
    );

    test(
      'mark all present does not overwrite statuses that are already saved',
      () {
        final sheet = _sheet([_saved('1', AttendanceStatus.absent), _new('2')]);
        sheet.markAllPresent();
        expect(sheet.entryFor('1')!.status, AttendanceStatus.absent);
        expect(sheet.entryFor('2')!.status, AttendanceStatus.present);
      },
    );

    test('reset returns a student to what is stored (or to not marked)', () {
      final sheet = _sheet([
        _saved('1', AttendanceStatus.present, remarks: 'ok'),
        _new('2'),
      ]);
      sheet.setStatus('1', AttendanceStatus.absent);
      sheet.setRemarks('1', 'changed');
      sheet.setStatus('2', AttendanceStatus.late);
      sheet.reset('1');
      sheet.reset('2');
      expect(sheet.entryFor('1')!.status, AttendanceStatus.present);
      expect(sheet.entryFor('1')!.remarks, 'ok');
      expect(sheet.entryFor('2')!.status, isNull);
      expect(sheet.isDirty, isFalse);
    });

    test('setting a status that is already stored is not a change', () {
      final sheet = _sheet([_saved('1', AttendanceStatus.present)]);
      sheet.setStatus('1', AttendanceStatus.present);
      expect(sheet.isDirty, isFalse);
    });

    test('empty and missing remarks are the same; real edits are changes', () {
      final sheet = _sheet([_saved('1', AttendanceStatus.present)]);
      sheet.setRemarks('1', '   ');
      expect(sheet.isDirty, isFalse);
      sheet.setRemarks('1', 'late bus');
      expect(sheet.isDirty, isTrue);
      expect(sheet.changedEntries.map((e) => e.subjectId), ['1']);
    });

    test('unknown ids are ignored rather than crashing', () {
      final sheet = _sheet([_new('1')]);
      sheet.setStatus('nope', AttendanceStatus.present);
      sheet.reset('nope');
      expect(sheet.tally.notMarked, 1);
    });
  });

  group('validateSave — no accidental partial submission', () {
    test('refuses an empty register and an unchanged one', () {
      expect(_sheet([]).validateSave(), contains('nobody'));
      expect(
        _sheet([_saved('1', AttendanceStatus.present)]).validateSave(),
        contains('no changes'),
      );
    });

    test(
      'refuses while anyone is unmarked unless partial saving is explicitly confirmed',
      () {
        final sheet = _sheet([_new('1'), _new('2')]);
        sheet.setStatus('1', AttendanceStatus.present);
        expect(sheet.validateSave(), contains('1 not marked'));
        expect(sheet.validateSave(allowPartial: true), isNull);
      },
    );

    test('a fully marked register saves without confirmation', () {
      final sheet = _sheet([_new('1'), _new('2')])..markAllPresent();
      expect(sheet.validateSave(), isNull);
    });
  });

  group('finalization', () {
    test('finalizing needs everyone marked', () {
      final sheet = _sheet([_new('1'), _new('2')]);
      sheet.setStatus('1', AttendanceStatus.present);
      expect(sheet.validateFinalize(), contains('Mark every entry'));
      sheet.setStatus('2', AttendanceStatus.absent);
      expect(sheet.validateFinalize(), isNull);
    });

    test(
      'a finalized register cannot be changed by someone without correction rights',
      () {
        final sheet = _sheet([
          _saved('1', AttendanceStatus.present),
        ], day: AttendanceDayStatus.finalized);
        sheet.setStatus('1', AttendanceStatus.absent);
        expect(sheet.isFinalized, isTrue);
        expect(sheet.validateSave(reason: 'because'), contains('finalized'));
      },
    );

    test('a manager correcting a finalized register must give a reason', () {
      final sheet = _sheet([
        _saved('1', AttendanceStatus.present),
      ], day: AttendanceDayStatus.finalized);
      sheet.setStatus('1', AttendanceStatus.absent);
      expect(sheet.validateSave(canEditFinalized: true), contains('reason'));
      expect(
        sheet.validateSave(canEditFinalized: true, reason: '  '),
        contains('reason'),
      );
      expect(
        sheet.validateSave(canEditFinalized: true, reason: 'Parent confirmed'),
        isNull,
      );
    });

    test('a draft register needs no reason', () {
      final sheet = _sheet([
        _saved('1', AttendanceStatus.present),
      ], day: AttendanceDayStatus.draft);
      sheet.setStatus('1', AttendanceStatus.absent);
      expect(sheet.validateSave(), isNull);
    });
  });

  group(
    'AttendanceSavePlanner — optimistic concurrency, idempotency, minimal writes',
    () {
      CurrentAttendance stored(
        int revision,
        AttendanceStatus status, {
        String? remarks,
        String sectionId = 'a',
      }) => CurrentAttendance(
        revision: revision,
        status: status,
        remarks: remarks,
        sectionId: sectionId,
      );

      test('new marks become revision-1 creates; nothing else is written', () {
        final entries = [_new('1'), _new('2')];
        entries[0].status = AttendanceStatus.present;
        entries[1].status = AttendanceStatus.absent;
        final plan = AttendanceSavePlanner.plan(
          entries: entries,
          current: {'1': null, '2': null},
          sectionId: 'a',
        );
        expect(plan.hasConflicts, isFalse);
        expect(
          plan.writes.map(
            (w) =>
                (w.entry.subjectId, w.newRevision, w.isNew, w.previousStatus),
          ),
          [('1', 1, true, null), ('2', 1, true, null)],
        );
        expect(plan.resultingTally.present, 1);
        expect(plan.resultingTally.absent, 1);
      });

      test(
        'students who were not marked are not written and stay "not marked" (partial attendance)',
        () {
          final entries = [_new('1'), _new('2')];
          entries[0].status = AttendanceStatus.present;
          final plan = AttendanceSavePlanner.plan(
            entries: entries,
            current: {'1': null, '2': null},
            sectionId: 'a',
          );
          expect(plan.writes, hasLength(1));
          expect(plan.resultingTally.notMarked, 1);
        },
      );

      test(
        'an edit bumps the revision by one and remembers the previous status for the history',
        () {
          final entry = _saved('1', AttendanceStatus.present, revision: 3);
          entry.status = AttendanceStatus.late;
          final plan = AttendanceSavePlanner.plan(
            entries: [entry],
            current: {'1': stored(3, AttendanceStatus.present)},
            sectionId: 'a',
          );
          final w = plan.writes.single;
          expect(
            (w.newRevision, w.isNew, w.previousStatus, w.newStatus),
            (4, false, AttendanceStatus.present, AttendanceStatus.late),
          );
        },
      );

      test(
        'unchanged students are skipped, so a class save only writes the exceptions',
        () {
          final entries = [
            for (var i = 1; i <= 30; i++)
              _saved('$i', AttendanceStatus.present),
          ];
          entries[4].status = AttendanceStatus.absent;
          final plan = AttendanceSavePlanner.plan(
            entries: entries,
            current: {
              for (final e in entries)
                e.subjectId: stored(1, AttendanceStatus.present),
            },
            sectionId: 'a',
          );
          expect(plan.writes.map((w) => w.entry.subjectId), ['5']);
          expect(plan.resultingTally.present, 29);
        },
      );

      test(
        'CONFLICT: someone else saved this student after it was loaded — nothing may be written',
        () {
          final entry = _saved('1', AttendanceStatus.present, revision: 1);
          entry.status = AttendanceStatus.absent;
          final plan = AttendanceSavePlanner.plan(
            entries: [entry],
            current: {'1': stored(2, AttendanceStatus.late)},
            sectionId: 'a',
          );
          expect(plan.hasConflicts, isTrue);
          expect(plan.conflicts, ['Student 1']);
        },
      );

      test(
        'CONFLICT: two teachers marking the same class at once — the second sees the first one\'s revisions',
        () {
          final teacherB = [_new('1'), _new('2')]
            ..forEach((e) => e.status = AttendanceStatus.present);
          // Teacher A has already saved both while B was editing.
          final plan = AttendanceSavePlanner.plan(
            entries: teacherB,
            current: {
              '1': stored(1, AttendanceStatus.absent),
              '2': stored(1, AttendanceStatus.present),
            },
            sectionId: 'a',
          );
          expect(plan.hasConflicts, isTrue);
          expect(plan.conflicts, hasLength(2));
        },
      );

      test(
        'RETRY / double-click safety: replaying a save that already succeeded conflicts instead of duplicating',
        () {
          final entry = _new('1')..status = AttendanceStatus.present;
          // the first attempt committed (revision 1 now exists); the retry still believes revision 0
          final plan = AttendanceSavePlanner.plan(
            entries: [entry],
            current: {'1': stored(1, AttendanceStatus.present)},
            sectionId: 'a',
          );
          expect(plan.hasConflicts, isTrue);
          expect(plan.writes, isEmpty);
        },
      );

      test(
        'a record that vanished since it was loaded is a conflict, not a silent re-create',
        () {
          final entry = _saved('1', AttendanceStatus.present);
          entry.status = AttendanceStatus.absent;
          final plan = AttendanceSavePlanner.plan(
            entries: [entry],
            current: {'1': null},
            sectionId: 'a',
          );
          expect(plan.hasConflicts, isTrue);
        },
      );

      test(
        'a student already recorded in ANOTHER section on this date cannot be marked here (one record per day)',
        () {
          final entry = _new('1')..status = AttendanceStatus.present;
          final plan = AttendanceSavePlanner.plan(
            entries: [entry],
            current: {'1': stored(1, AttendanceStatus.absent, sectionId: 'b')},
            sectionId: 'a',
          );
          expect(plan.hasConflicts, isTrue);
          expect(plan.writes, isEmpty);
        },
      );

      test(
        'one conflicting student blocks the whole save (all-or-nothing)',
        () {
          final ok = _new('1')..status = AttendanceStatus.present;
          final stale = _saved('2', AttendanceStatus.present, revision: 1)
            ..status = AttendanceStatus.absent;
          final plan = AttendanceSavePlanner.plan(
            entries: [ok, stale],
            current: {'1': null, '2': stored(5, AttendanceStatus.late)},
            sectionId: 'a',
          );
          expect(plan.hasConflicts, isTrue);
        },
      );

      test(
        'remarks-only changes are written (and history-logged), empty remarks are normalized to null',
        () {
          final entry = _saved('1', AttendanceStatus.present, remarks: 'old')
            ..remarks = '  ';
          final plan = AttendanceSavePlanner.plan(
            entries: [entry],
            current: {'1': stored(1, AttendanceStatus.present, remarks: 'old')},
            sectionId: 'a',
          );
          expect(plan.writes.single.newRemarks, isNull);
          expect(plan.writes.single.previousRemarks, 'old');
        },
      );

      test('staff registers (no section) plan the same way', () {
        final a = _new('s1')..status = AttendanceStatus.late;
        final plan = AttendanceSavePlanner.plan(
          entries: [a],
          current: {'s1': null},
        );
        expect(plan.writes.single.isNew, isTrue);
      });
    },
  );
}
