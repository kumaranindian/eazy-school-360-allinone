import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_csv.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_date.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_day.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_history_entry.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_reports.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_tally.dart';
import 'package:eazy_school_360/features/attendance/domain/staff_attendance.dart';
import 'package:eazy_school_360/features/attendance/domain/student_attendance.dart';
import 'package:flutter_test/flutter_test.dart';

StudentAttendance _record({
  AttendanceStatus status = AttendanceStatus.present,
  int revision = 1,
  String? reason,
}) => StudentAttendance(
  attendanceId: StudentAttendance.idFor('2026-06-10', 'stu-1'),
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  dateKey: '2026-06-10',
  studentId: 'stu-1',
  academicRecordId: 'rec-1',
  classId: 'c5',
  sectionId: 'a',
  status: status,
  revision: revision,
  lastChangeReason: reason,
);

void main() {
  group('AttendanceDate — civil dates, no timezone surprises', () {
    test('key uses the date\'s own fields, whatever the time of day', () {
      expect(AttendanceDate.key(DateTime(2026, 6, 10, 0, 0)), '2026-06-10');
      expect(
        AttendanceDate.key(DateTime(2026, 6, 10, 23, 59, 59)),
        '2026-06-10',
      );
      expect(AttendanceDate.key(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('parse is UTC midnight and round-trips through key', () {
      final parsed = AttendanceDate.parse('2026-06-10');
      expect(parsed, DateTime.utc(2026, 6, 10));
      expect(AttendanceDate.key(parsed), '2026-06-10');
    });

    test('timestamps are UTC midnight of the civil date', () {
      expect(
        AttendanceDate.timestampFor('2026-06-10').toDate().toUtc(),
        DateTime.utc(2026, 6, 10),
      );
    });

    test(
      'keys sort chronologically as strings, across month and year ends',
      () {
        final keys = ['2027-01-01', '2026-12-31', '2026-02-09', '2026-02-10']
          ..sort();
        expect(keys, ['2026-02-09', '2026-02-10', '2026-12-31', '2027-01-01']);
      },
    );

    test('month bounds, including February and leap years', () {
      expect(AttendanceDate.firstOfMonthKey(2026, 6), '2026-06-01');
      expect(AttendanceDate.lastOfMonthKey(2026, 6), '2026-06-30');
      expect(AttendanceDate.lastOfMonthKey(2026, 2), '2026-02-28');
      expect(AttendanceDate.lastOfMonthKey(2028, 2), '2028-02-29');
      expect(AttendanceDate.lastOfMonthKey(2026, 12), '2026-12-31');
    });

    test('keysBetween is inclusive and survives a month boundary', () {
      expect(AttendanceDate.keysBetween('2026-06-29', '2026-07-02'), [
        '2026-06-29',
        '2026-06-30',
        '2026-07-01',
        '2026-07-02',
      ]);
      expect(AttendanceDate.keysBetween('2026-06-10', '2026-06-10'), [
        '2026-06-10',
      ]);
      expect(AttendanceDate.keysBetween('2026-06-11', '2026-06-10'), isEmpty);
    });

    test('keyPattern accepts only yyyy-MM-dd', () {
      expect(AttendanceDate.keyPattern.hasMatch('2026-06-10'), isTrue);
      for (final bad in ['2026-6-10', '10/06/2026', '2026-06-10T00:00', '']) {
        expect(AttendanceDate.keyPattern.hasMatch(bad), isFalse, reason: bad);
      }
    });
  });

  group('AttendanceStatus', () {
    test(
      'exactly present / absent / late / half day — leave is not a status',
      () {
        expect(AttendanceStatus.values.map((s) => s.wireValue), [
          'PRESENT',
          'ABSENT',
          'LATE',
          'HALF_DAY',
        ]);
        expect(
          AttendanceStatus.values.any((s) => s.wireValue.contains('LEAVE')),
          isFalse,
        );
        for (final s in AttendanceStatus.values) {
          expect(AttendanceStatus.fromWireValue(s.wireValue), s);
        }
      },
    );

    test('weights: present 1, late 1, half day 0.5, absent 0', () {
      expect(AttendanceStatus.present.attendanceWeight, 1);
      expect(AttendanceStatus.late.attendanceWeight, 1);
      expect(AttendanceStatus.halfDay.attendanceWeight, 0.5);
      expect(AttendanceStatus.absent.attendanceWeight, 0);
    });
  });

  group('AttendanceTally and attendance percentage', () {
    test('counts every status and the unmarked', () {
      final t = AttendanceTally.of([
        AttendanceStatus.present,
        AttendanceStatus.present,
        AttendanceStatus.absent,
        AttendanceStatus.late,
        AttendanceStatus.halfDay,
        null,
      ]);
      expect(
        (t.present, t.absent, t.late, t.halfDay, t.notMarked),
        (2, 1, 1, 1, 1),
      );
      expect(t.marked, 5);
      expect(t.total, 6);
    });

    test('percentage = (present + late + 0.5 × half day) ÷ days marked', () {
      // 6 present, 2 absent, 1 late, 2 half-day  => attended 6 + 1 + 1 = 8 of 11
      final t = AttendanceTally(present: 6, absent: 2, late: 1, halfDay: 2);
      expect(t.attendedDays, 8);
      expect(t.percentage, closeTo(8 / 11 * 100, 1e-9));
    });

    test('all present is 100%, all absent is 0%, only half days is 50%', () {
      expect(const AttendanceTally(present: 10).percentage, 100);
      expect(const AttendanceTally(absent: 10).percentage, 0);
      expect(const AttendanceTally(halfDay: 4).percentage, 50);
    });

    test('late counts as attended', () {
      expect(const AttendanceTally(late: 5).percentage, 100);
    });

    test(
      'unmarked days are NOT in the denominator; nothing marked has no percentage',
      () {
        expect(
          const AttendanceTally(
            present: 5,
            absent: 5,
            notMarked: 20,
          ).percentage,
          50,
        );
        expect(const AttendanceTally(notMarked: 20).percentage, isNull);
        expect(const AttendanceTally().percentage, isNull);
      },
    );

    test('tallies add up, so a class total is the sum of its students', () {
      final sum =
          const AttendanceTally(present: 1, absent: 2) +
          const AttendanceTally(present: 3, late: 1, notMarked: 1);
      expect((sum.present, sum.absent, sum.late, sum.notMarked), (4, 2, 1, 1));
    });
  });

  group('AttendanceDay (register) serialization', () {
    test(
      'a student session carries scope, counts, DRAFT status and revision 1',
      () {
        final day = AttendanceDay(
          dayId: AttendanceDay.studentSessionId(
            dateKey: '2026-06-10',
            academicYearId: 'y1',
            classId: 'c5',
            sectionId: 'a',
          ),
          schoolId: 'school-1',
          branchId: 'main',
          academicYearId: 'y1',
          classId: 'c5',
          sectionId: 'a',
          dateKey: '2026-06-10',
          status: AttendanceDayStatus.draft,
          tally: const AttendanceTally(present: 2, absent: 1, notMarked: 1),
        );
        final data = day.toFirestoreCreate(createdBy: 'u1');
        expect(day.dayId, '2026-06-10__y1__c5__a');
        expect(data['status'], 'DRAFT');
        expect(data['enrolled'], 4);
        expect(data['present'], 2);
        expect(data['notMarked'], 1);
        expect(data['revision'], 1);
        expect(data['finalizedAt'], isNull);
        expect(data['createdBy'], 'u1');
      },
    );

    test('finalizing stamps finalizedBy and a server timestamp', () {
      final data = AttendanceDay(
        dayId: 'd',
        schoolId: 's',
        branchId: 'b',
        dateKey: '2026-06-10',
        status: AttendanceDayStatus.finalized,
        tally: const AttendanceTally(present: 1),
        revision: 3,
      ).toFirestoreUpdate(updatedBy: 'u2');
      expect(data['status'], 'FINALIZED');
      expect(data['finalizedBy'], 'u2');
      expect(data['finalizedAt'], isA<FieldValue>());
      expect(data['revision'], 3);
    });

    test('updates only touch the fields the rules allow', () {
      const allowed = {
        'dateKey',
        'attendanceDate',
        'status',
        'enrolled',
        'present',
        'absent',
        'late',
        'halfDay',
        'notMarked',
        'dayKind',
        'overrideReason',
        'revision',
        'finalizedAt',
        'finalizedBy',
        'updatedAt',
        'updatedBy',
      };
      final keys = AttendanceDay(
        dayId: 'd',
        schoolId: 's',
        branchId: 'b',
        dateKey: '2026-06-10',
        status: AttendanceDayStatus.draft,
        tally: const AttendanceTally(),
      ).toFirestoreUpdate(updatedBy: 'u').keys.toSet();
      expect(
        allowed.containsAll(keys),
        isTrue,
        reason: '${keys.difference(allowed)}',
      );
    });

    test('fromFirestore reads counts and status', () {
      final day = AttendanceDay.fromFirestore('s', 'b', 'd', {
        'status': 'FINALIZED',
        'dateKey': '2026-06-10',
        'present': 5,
        'absent': 1,
        'late': 0,
        'halfDay': 1,
        'notMarked': 0,
        'revision': 4,
      });
      expect(day.isFinalized, isTrue);
      expect(day.tally.marked, 7);
      expect(day.revision, 4);
    });
  });

  group('Student / staff attendance records', () {
    test(
      'the id is date + subject, so there can be only one per student per day',
      () {
        expect(
          StudentAttendance.idFor('2026-06-10', 'stu-1'),
          '2026-06-10_stu-1',
        );
        expect(
          StaffAttendance.idFor('2026-06-10', 'staff-1'),
          '2026-06-10_staff-1',
        );
        expect(
          StudentAttendance.idFor('2026-06-10', 'stu-1'),
          isNot(StudentAttendance.idFor('2026-06-11', 'stu-1')),
        );
      },
    );

    test(
      'create starts at revision 1 with the placement snapshot and server audit',
      () {
        final data = _record(revision: 7).toFirestoreCreate(createdBy: 'u1');
        expect(data['revision'], 1);
        expect(data['dateKey'], '2026-06-10');
        expect(
          (data['attendanceDate'] as Timestamp).toDate().toUtc(),
          DateTime.utc(2026, 6, 10),
        );
        expect(
          [
            data['academicYearId'],
            data['classId'],
            data['sectionId'],
            data['academicRecordId'],
          ],
          ['y1', 'c5', 'a', 'rec-1'],
        );
        expect(data['status'], 'PRESENT');
        expect(data['createdAt'], isA<FieldValue>());
      },
    );

    test(
      'update writes only the mutable fields and the new revision — never identity or placement',
      () {
        final data = _record(
          status: AttendanceStatus.absent,
          revision: 2,
          reason: 'Parent called',
        ).toFirestoreUpdate(updatedBy: 'u2');
        expect(data.keys.toSet(), {
          'status',
          'remarks',
          'revision',
          'lastChangeReason',
          'updatedAt',
          'updatedBy',
        });
        expect(data['revision'], 2);
        expect(data['lastChangeReason'], 'Parent called');
      },
    );

    test(
      'staff records have no class/section/year and no pay-related fields',
      () {
        final data = const StaffAttendance(
          attendanceId: '2026-06-10_s1',
          schoolId: 's',
          branchId: 'b',
          dateKey: '2026-06-10',
          staffId: 's1',
          status: AttendanceStatus.late,
        ).toFirestoreCreate(createdBy: 'u');
        for (final k in [
          'classId',
          'sectionId',
          'academicYearId',
          'overtime',
          'shift',
          'salary',
        ]) {
          expect(data.containsKey(k), isFalse, reason: k);
        }
        expect(data['status'], 'LATE');
      },
    );

    test('fromFirestore round-trips', () {
      final read = StudentAttendance.fromFirestore(
        'school-1',
        'main',
        '2026-06-10_stu-1',
        {
          'academicYearId': 'y1',
          'dateKey': '2026-06-10',
          'studentId': 'stu-1',
          'academicRecordId': 'rec-1',
          'classId': 'c5',
          'sectionId': 'a',
          'status': 'HALF_DAY',
          'remarks': 'left at noon',
          'revision': 3,
        },
      );
      expect(read.status, AttendanceStatus.halfDay);
      expect(read.remarks, 'left at noon');
      expect(read.revision, 3);
    });
  });

  test('history entries read previous and new status with the reason', () {
    final e = AttendanceHistoryEntry.fromFirestore({
      'revision': 2,
      'previousStatus': 'PRESENT',
      'newStatus': 'ABSENT',
      'reason': 'Correction',
      'changedBy': 'u',
      'changedAt': Timestamp.fromDate(DateTime(2026, 6, 11)),
    });
    expect(
      (e.previousStatus, e.newStatus, e.reason),
      (AttendanceStatus.present, AttendanceStatus.absent, 'Correction'),
    );
    expect(
      AttendanceHistoryEntry.fromFirestore({
        'newStatus': 'PRESENT',
        'changedBy': 'u',
      }).previousStatus,
      isNull,
    );
  });

  group('AttendanceCsv — quoting and formula injection', () {
    test(
      'plain values pass through; commas, quotes and newlines are quoted',
      () {
        expect(AttendanceCsv.cell('Arun'), 'Arun');
        expect(AttendanceCsv.cell('Kumar, Arun'), '"Kumar, Arun"');
        expect(AttendanceCsv.cell('say "hi"'), '"say ""hi"""');
        expect(AttendanceCsv.cell('a\nb'), '"a\nb"');
      },
    );

    test('text that a spreadsheet would run as a formula is neutralized', () {
      for (final evil in [
        '=SUM(A1:A9)',
        '+1+1',
        '-2+3',
        '@cmd',
        '=HYPERLINK("http://x","y")',
        '\t=1',
      ]) {
        final cell = AttendanceCsv.cell(evil);
        expect(cell.replaceAll('"', ''), startsWith("'"), reason: evil);
      }
      expect(AttendanceCsv.sanitizeText('Normal = text'), 'Normal = text');
    });

    test(
      'numbers are not altered, nulls are empty, doubles use two decimals',
      () {
        expect(AttendanceCsv.cell(-5), '-5');
        expect(AttendanceCsv.cell(null), '');
        expect(AttendanceCsv.cell(72.7272), '72.73');
      },
    );

    test('encode writes header + rows with CRLF line endings', () {
      expect(
        AttendanceCsv.encode(
          ['A', 'B'],
          [
            [1, 'x'],
            [2, null],
          ],
        ),
        'A,B\r\n1,x\r\n2,\r\n',
      );
    });
  });

  group('AttendanceReports', () {
    test('tallyBySubject groups per student', () {
      final t = AttendanceReports.tallyBySubject([
        (subjectId: 's1', status: AttendanceStatus.present),
        (subjectId: 's1', status: AttendanceStatus.absent),
        (subjectId: 's2', status: AttendanceStatus.late),
      ]);
      expect(t['s1']!.marked, 2);
      expect(t['s1']!.percentage, 50);
      expect(t['s2']!.percentage, 100);
    });

    test(
      'summary CSV has the documented header, empty percentage when nothing marked, and sanitized names',
      () {
        final csv = AttendanceReports.summaryCsv([
          const AttendanceSummaryRow(
            subjectId: '1',
            name: '=cmd|calc',
            detail: '12',
            tally: AttendanceTally(present: 3, absent: 1),
          ),
          const AttendanceSummaryRow(
            subjectId: '2',
            name: 'Meera',
            tally: AttendanceTally(),
          ),
        ]);
        final lines = csv.trim().split('\r\n');
        expect(
          lines.first,
          'Name,Detail,Present,Absent,Late,Half day,Days marked,Attendance %',
        );
        expect(lines[1], "'=cmd|calc,12,3,1,0,0,4,75.00");
        expect(lines[2], 'Meera,,0,0,0,0,0,');
      },
    );

    test('percentLabel', () {
      expect(AttendanceReports.percentLabel(const AttendanceTally()), '—');
      expect(
        AttendanceReports.percentLabel(
          const AttendanceTally(present: 2, absent: 1),
        ),
        '66.7%',
      );
    });

    test('daily CSV lists date, status label and remarks', () {
      final csv = AttendanceReports.dailyCsv('Arun', [
        (
          dateKey: '2026-06-10',
          status: AttendanceStatus.halfDay,
          remarks: null,
        ),
      ]);
      expect(csv, 'Name,Date,Status,Remarks\r\nArun,2026-06-10,Half day,\r\n');
    });
  });
}
