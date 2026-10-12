import 'package:eazy_school_360/features/exams/domain/exam_enums.dart';
import 'package:eazy_school_360/features/exams/domain/exam_rules.dart';
import 'package:eazy_school_360/features/exams/domain/examination.dart';
import 'package:eazy_school_360/features/exams/domain/grading_scheme.dart';
import 'package:eazy_school_360/features/exams/domain/marks.dart';
import 'package:eazy_school_360/features/exams/domain/result_calculator.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_status.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_tally.dart';
import 'package:eazy_school_360/features/exams/domain/result_summary.dart';
import 'package:eazy_school_360/features/exams/presentation/widgets/report_card_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

GradingScheme _scheme({
  List<GradeBand>? bands,
  double pass = 33,
  double? overall,
  int decimals = 2,
  RoundingMode rounding = RoundingMode.halfUp,
  AbsentPolicy absent = AbsentPolicy.exclude,
  AggregateMethod aggregate = AggregateMethod.total,
}) => GradingScheme(
  schemeId: 's',
  schoolId: 'sc',
  branchId: 'b',
  name: 'Test scheme',
  bands:
      bands ??
      const [
        GradeBand(grade: 'A', minPercent: 80),
        GradeBand(grade: 'B', minPercent: 60),
        GradeBand(grade: 'C', minPercent: 33),
        GradeBand(grade: 'D', minPercent: 0),
      ],
  passPercent: pass,
  overallPassPercent: overall,
  decimals: decimals,
  rounding: rounding,
  absentPolicy: absent,
  aggregate: aggregate,
);

ExaminationSubject _sub(
  String id, {
  double max = 100,
  double? pass,
  double weight = 1,
  double? theory,
  double? practical,
}) => ExaminationSubject(
  examId: 'e',
  subjectId: id,
  schoolId: 'sc',
  branchId: 'b',
  academicYearId: 'y',
  classId: 'c',
  subjectName: id,
  maxMarks: max,
  passMarks: pass,
  weightage: weight,
  theoryMax: theory,
  practicalMax: practical,
);

MarksEntry _e(
  String subject,
  MarkStatus status, {
  double? marks,
  double? theory,
  double? practical,
}) => MarksEntry(
  sheetId: 'e__${subject}__sa',
  examId: 'e',
  subjectId: subject,
  studentId: 'stu',
  studentName: 'Stu',
  classId: 'c',
  sectionId: 'sa',
  academicYearId: 'y',
  schoolId: 'sc',
  branchId: 'b',
  status: status,
  marks: marks,
  theory: theory,
  practical: practical,
  revision: 1,
);

StudentResult _calc(
  GradingScheme scheme,
  List<ExaminationSubject> subjects,
  Map<String, MarksEntry?> entries,
) => ResultCalculator.calculate(
  scheme: scheme,
  subjects: subjects,
  entries: entries,
  studentId: 'stu',
  studentName: 'Stu',
  sectionId: 'sa',
);

void main() {
  group('Grading scheme validation', () {
    test('accepts a complete, unambiguous scheme', () {
      expect(_scheme().validate(), isNull);
    });
    test('refuses overlapping (duplicate) boundaries', () {
      final s = _scheme(
        bands: const [
          GradeBand(grade: 'A', minPercent: 80),
          GradeBand(grade: 'B', minPercent: 80),
          GradeBand(grade: 'C', minPercent: 0),
        ],
      );
      expect(s.validate(), contains('overlap'));
    });
    test('requires the lowest band to start at zero (no ungraded scores)', () {
      final s = _scheme(
        bands: const [
          GradeBand(grade: 'A', minPercent: 80),
          GradeBand(grade: 'B', minPercent: 40),
        ],
      );
      expect(s.validate(), contains('0%'));
    });
    test(
      'refuses duplicate grades, out-of-range boundaries, bad precision',
      () {
        expect(
          _scheme(
            bands: const [
              GradeBand(grade: 'A', minPercent: 50),
              GradeBand(grade: 'a', minPercent: 0),
            ],
          ).validate(),
          isNotNull,
        );
        expect(
          _scheme(
            bands: const [
              GradeBand(grade: 'A', minPercent: 101),
              GradeBand(grade: 'B', minPercent: 0),
            ],
          ).validate(),
          isNotNull,
        );
        expect(_scheme(decimals: 4).validate(), isNotNull);
        expect(_scheme(pass: 120).validate(), isNotNull);
      },
    );
    test('grade points are all-or-none, and monotonic', () {
      expect(
        _scheme(
          bands: const [
            GradeBand(grade: 'A', minPercent: 50, gradePoint: 4),
            GradeBand(grade: 'B', minPercent: 0),
          ],
        ).validate(),
        isNotNull,
      );
      expect(
        _scheme(
          bands: const [
            GradeBand(grade: 'A', minPercent: 50, gradePoint: 2),
            GradeBand(grade: 'B', minPercent: 0, gradePoint: 3),
          ],
        ).validate(),
        isNotNull,
      );
      final ok = _scheme(
        bands: const [
          GradeBand(grade: 'A', minPercent: 50, gradePoint: 4),
          GradeBand(grade: 'B', minPercent: 0, gradePoint: 2),
        ],
      );
      expect(ok.validate(), isNull);
      expect(ok.gpaEnabled, isTrue);
      expect(_scheme().gpaEnabled, isFalse);
    });
  });

  group('Examination configuration validation', () {
    Examination exam({
      String name = 'Half-yearly',
      String start = '2026-09-01',
      String end = '2026-09-10',
      String scheme = 's',
    }) => Examination(
      examId: 'x',
      schoolId: 'sc',
      branchId: 'b',
      academicYearId: 'y',
      classId: 'c',
      name: name,
      schemeId: scheme,
      startDateKey: start,
      endDateKey: end,
    );

    test('valid and invalid configurations', () {
      expect(exam().validate(), isNull);
      expect(exam(name: 'ab').validate(), isNotNull);
      expect(exam(end: '2026-08-01').validate(), isNotNull);
      expect(exam(start: 'soon').validate(), isNotNull);
      expect(exam(scheme: '').validate(), isNotNull);
    });
    test('the id is deterministic, so a duplicate scope + name collides', () {
      String id(String n, {String? section}) => Examination.idFor(
        academicYearId: 'y',
        classId: 'c',
        sectionId: section,
        name: n,
      );
      expect(id('Half-Yearly 2026'), id('half yearly 2026'));
      expect(id('Half-yearly'), isNot(id('Half-yearly', section: 'sa')));
    });
    test('subject bounds: max positive, pass ≤ max, components add up', () {
      expect(_sub('m').validate(), isNull);
      expect(_sub('m', max: 0).validate(), isNotNull);
      expect(_sub('m', pass: 101).validate(), isNotNull);
      expect(_sub('m', weight: 0).validate(), isNotNull);
      expect(_sub('m', theory: 60, practical: 30).validate(), isNotNull);
      expect(_sub('m', theory: 70, practical: 30).validate(), isNull);
      expect(_sub('m', theory: 70).validate(), isNotNull);
    });
    test('subject date must fall inside the examination dates', () {
      final s = ExaminationSubject(
        examId: 'x',
        subjectId: 'm',
        schoolId: 'sc',
        branchId: 'b',
        academicYearId: 'y',
        classId: 'c',
        subjectName: 'm',
        maxMarks: 50,
        dateKey: '2026-10-01',
      );
      expect(
        s.validate(examStartKey: '2026-09-01', examEndKey: '2026-09-10'),
        isNotNull,
      );
    });
  });

  group('Marks entry validation', () {
    final math = _sub('math');
    final sci = _sub('sci', theory: 70, practical: 30);
    test('zero is a valid score; absent/exempted/pending carry none', () {
      expect(_e('math', MarkStatus.entered, marks: 0).validate(math), isNull);
      expect(_e('math', MarkStatus.absent).validate(math), isNull);
      expect(_e('math', MarkStatus.exempted).validate(math), isNull);
      expect(_e('math', MarkStatus.entered).validate(math), isNotNull);
    });
    test('marks may not exceed the maximum or be negative', () {
      expect(
        _e('math', MarkStatus.entered, marks: 101).validate(math),
        isNotNull,
      );
      expect(
        _e('math', MarkStatus.entered, marks: -1).validate(math),
        isNotNull,
      );
      expect(_e('math', MarkStatus.entered, marks: 100).validate(math), isNull);
      expect(
        _e('math', MarkStatus.entered, marks: 33.456).validate(math),
        isNotNull,
      );
    });
    test('components are bounded separately and sum to the total', () {
      expect(
        _e('sci', MarkStatus.entered, theory: 71, practical: 10).validate(sci),
        isNotNull,
      );
      expect(
        _e('sci', MarkStatus.entered, theory: 50, practical: 31).validate(sci),
        isNotNull,
      );
      final ok = _e('sci', MarkStatus.entered, theory: 50, practical: 25);
      expect(ok.validate(sci), isNull);
      expect(ok.effectiveMarks, 75);
    });
  });

  group('Result calculation', () {
    final subjects = [_sub('math'), _sub('eng'), _sub('sci')];

    test('totals, percentage, grade and pass for entered marks', () {
      final r = _calc(_scheme(), subjects, {
        'math': _e('math', MarkStatus.entered, marks: 90),
        'eng': _e('eng', MarkStatus.entered, marks: 70),
        'sci': _e('sci', MarkStatus.entered, marks: 80),
      });
      expect(r.totalObtained, 240);
      expect(r.totalMax, 300);
      expect(r.percentage, 80);
      expect(r.overallGrade, 'A');
      expect(r.result, OverallResult.pass);
      expect(r.isComplete, isTrue);
      expect(r.lines.map((l) => l.grade), ['A', 'B', 'A']);
    });

    test('zero marks is a scored zero that fails, not an absence', () {
      final r = _calc(
        _scheme(),
        [_sub('math')],
        {'math': _e('math', MarkStatus.entered, marks: 0)},
      );
      expect(r.lines.single.outcome, SubjectOutcome.failed);
      expect(r.totalMax, 100);
      expect(r.result, OverallResult.fail);
      expect(r.hasAbsence, isFalse);
    });

    test('absent is excluded from totals under the EXCLUDE policy', () {
      final r = _calc(_scheme(), subjects, {
        'math': _e('math', MarkStatus.entered, marks: 60),
        'eng': _e('eng', MarkStatus.absent),
        'sci': _e('sci', MarkStatus.entered, marks: 40),
      });
      expect(r.totalMax, 200);
      expect(r.percentage, 50);
      expect(r.hasAbsence, isTrue);
      expect(r.lines[1].outcome, SubjectOutcome.absent);
      expect(r.result, OverallResult.pass);
    });

    test('absent counts as zero and fails under the ZERO policy', () {
      final r = _calc(_scheme(absent: AbsentPolicy.zero), subjects, {
        'math': _e('math', MarkStatus.entered, marks: 60),
        'eng': _e('eng', MarkStatus.absent),
        'sci': _e('sci', MarkStatus.entered, marks: 60),
      });
      expect(r.totalMax, 300);
      expect(r.percentage, 40);
      expect(r.result, OverallResult.fail);
    });

    test('exempted is out of every total and cannot fail', () {
      final r = _calc(_scheme(), subjects, {
        'math': _e('math', MarkStatus.entered, marks: 50),
        'eng': _e('eng', MarkStatus.exempted),
        'sci': _e('sci', MarkStatus.entered, marks: 50),
      });
      expect(r.totalMax, 200);
      expect(r.percentage, 50);
      expect(r.result, OverallResult.pass);
      expect(r.hasAbsence, isFalse);
    });

    test('pending or missing entries make the result incomplete', () {
      final r = _calc(_scheme(), subjects, {
        'math': _e('math', MarkStatus.entered, marks: 50),
        'eng': _e('eng', MarkStatus.pending),
      });
      expect(r.isComplete, isFalse);
      expect(r.incompleteSubjectIds, ['eng', 'sci']);
    });

    test('everything exempted is not applicable, never a pass', () {
      final r = _calc(
        _scheme(),
        [_sub('math')],
        {'math': _e('math', MarkStatus.exempted)},
      );
      expect(r.result, OverallResult.notApplicable);
      expect(r.percentage, isNull);
      expect(r.overallGrade, isNull);
    });

    test('explicit passing marks beat the scheme percentage', () {
      final r = _calc(
        _scheme(pass: 33),
        [_sub('math', pass: 50)],
        {'math': _e('math', MarkStatus.entered, marks: 45)},
      );
      expect(r.lines.single.outcome, SubjectOutcome.failed);
      final r2 = _calc(
        _scheme(pass: 33),
        [_sub('math')],
        {'math': _e('math', MarkStatus.entered, marks: 33)},
      );
      expect(r2.lines.single.outcome, SubjectOutcome.passed);
    });

    test(
      'an overall pass percentage can fail a student with no failed subject',
      () {
        final r = _calc(_scheme(overall: 50), subjects, {
          'math': _e('math', MarkStatus.entered, marks: 40),
          'eng': _e('eng', MarkStatus.entered, marks: 40),
          'sci': _e('sci', MarkStatus.entered, marks: 40),
        });
        expect(
          r.lines.every((l) => l.outcome == SubjectOutcome.passed),
          isTrue,
        );
        expect(r.result, OverallResult.fail);
      },
    );

    test('weighted aggregate uses weightage; total uses marks', () {
      final weighted = [
        _sub('math', weight: 3),
        _sub('eng', weight: 1, max: 50),
      ];
      final entries = {
        'math': _e('math', MarkStatus.entered, marks: 90),
        'eng': _e('eng', MarkStatus.entered, marks: 25),
      };
      final total = _calc(_scheme(), weighted, entries);
      expect(total.percentage, closeTo(76.67, 0.01));
      expect(total.overallPercentage, total.percentage);
      final w = _calc(
        _scheme(aggregate: AggregateMethod.weighted),
        weighted,
        entries,
      );
      // (90×3 + 50×1) ÷ 4 = 80
      expect(w.weightedPercentage, 80);
      expect(w.overallPercentage, 80);
      expect(w.overallGrade, 'A');
    });

    test('rounding and precision are configured, and deterministic', () {
      final entries = {'math': _e('math', MarkStatus.entered, marks: 66.666)};
      final up = _calc(_scheme(decimals: 1), [_sub('math')], entries);
      final down = _calc(_scheme(decimals: 1, rounding: RoundingMode.down), [
        _sub('math'),
      ], entries);
      expect(up.percentage, 66.7);
      expect(down.percentage, 66.6);
      // half-up on an exact half
      expect(ResultCalculator.roundTo(2.5, 0, RoundingMode.halfUp), 3);
      expect(ResultCalculator.roundTo(1.005, 2, RoundingMode.halfUp), 1.01);
      // recalculation is identical
      final again = _calc(_scheme(decimals: 1), [_sub('math')], entries);
      expect(again.toMap(), up.toMap());
    });

    test('the grade comes from the rounded percentage', () {
      // 79.996% rounds to 80.00 → A with 2 decimals; stays B at 0 decimals? no: 80 → A
      final r = _calc(
        _scheme(decimals: 2),
        [_sub('math', max: 10000)],
        {
          'math': _e(
            'math',
            MarkStatus.entered,
            marks: 7999.6 > 10000 ? 0 : 7999.6,
          ),
        },
      );
      expect(r.percentage, 80);
      expect(r.overallGrade, 'A');
      final r0 = _calc(
        _scheme(decimals: 0),
        [_sub('math')],
        {'math': _e('math', MarkStatus.entered, marks: 79.5)},
      );
      expect(r0.percentage, 80);
      expect(r0.overallGrade, 'A');
    });

    test('GPA exists only when the scheme defines grade points', () {
      final points = _scheme(
        bands: const [
          GradeBand(grade: 'A', minPercent: 50, gradePoint: 4),
          GradeBand(grade: 'B', minPercent: 0, gradePoint: 2),
        ],
      );
      final entries = {
        'math': _e('math', MarkStatus.entered, marks: 90),
        'eng': _e('eng', MarkStatus.entered, marks: 20),
      };
      final r = _calc(points, [_sub('math'), _sub('eng')], entries);
      expect(r.gpa, 3);
      expect(
        _calc(_scheme(), [_sub('math'), _sub('eng')], entries).gpa,
        isNull,
      );
    });

    test('components produce the subject total', () {
      final r = _calc(
        _scheme(),
        [_sub('sci', theory: 70, practical: 30)],
        {'sci': _e('sci', MarkStatus.entered, theory: 50, practical: 25)},
      );
      expect(r.totalObtained, 75);
      expect(r.lines.single.theory, 50);
      expect(r.lines.single.practical, 25);
    });
  });

  group('Ranking and statistics', () {
    StudentResult r(String id, double pct, {OverallResult? result}) =>
        StudentResult(
          studentId: id,
          studentName: id,
          sectionId: 'sa',
          lines: const [],
          totalObtained: pct,
          totalMax: 100,
          percentage: pct,
          overallPercentage: pct,
          overallGrade: pct >= 50 ? 'A' : 'B',
          result:
              result ?? (pct >= 33 ? OverallResult.pass : OverallResult.fail),
        );

    test('competition ranking gives ties the same rank', () {
      final ranked = ResultCalculator.assignRanks([
        r('a', 90),
        r('b', 80),
        r('c', 80),
        r('d', 70),
      ]);
      expect(ranked.map((x) => x.rank), [1, 2, 2, 4]);
      expect(ranked.first.classSize, 4);
    });

    test('students without a percentage are not ranked', () {
      final ranked = ResultCalculator.assignRanks([
        r('a', 90),
        StudentResult(
          studentId: 'x',
          studentName: 'x',
          sectionId: 'sa',
          lines: const [],
          totalObtained: 0,
          totalMax: 0,
          result: OverallResult.notApplicable,
        ),
      ]);
      expect(ranked.last.rank, isNull);
    });

    test('statistics', () {
      final stats = ExamStats.of([r('a', 90), r('b', 40), r('c', 10)]);
      expect(stats.students, 3);
      expect(stats.passed, 2);
      expect(stats.failed, 1);
      expect(stats.passRate, closeTo(66.67, 0.01));
      expect(stats.averagePercentage, closeTo(46.67, 0.01));
      expect(stats.gradeDistribution['A'], 1);
    });
  });

  group('Workflow rules', () {
    Examination ex(
      ExamStatus s, {
      int subjects = 2,
      int sheets = 2,
      int approved = 2,
      int written = 0,
      int count = 0,
    }) => Examination(
      examId: 'x',
      schoolId: 'sc',
      branchId: 'b',
      academicYearId: 'y',
      classId: 'c',
      name: 'Half-yearly',
      schemeId: 's',
      startDateKey: '2026-09-01',
      endDateKey: '2026-09-02',
      status: s,
      subjectCount: subjects,
      sheetCount: sheets,
      approvedSheets: approved,
      resultCount: count,
      resultsWritten: written,
    );

    test('scheduling needs a draft with subjects', () {
      expect(ExamRules.checkSchedule(ex(ExamStatus.draft)), isNull);
      expect(
        ExamRules.checkSchedule(ex(ExamStatus.draft, subjects: 0)),
        isNotNull,
      );
      expect(ExamRules.checkSchedule(ex(ExamStatus.scheduled)), isNotNull);
    });
    test('finalisation needs every sheet approved', () {
      expect(ExamRules.checkFinalize(ex(ExamStatus.inProgress)), isNull);
      expect(
        ExamRules.checkFinalize(ex(ExamStatus.inProgress, approved: 1)),
        contains('1 of 2'),
      );
      expect(ExamRules.checkFinalize(ex(ExamStatus.scheduled)), isNotNull);
    });
    test('publishing needs every result written', () {
      expect(
        ExamRules.checkPublish(ex(ExamStatus.completed, written: 5, count: 5)),
        isNull,
      );
      expect(
        ExamRules.checkPublish(ex(ExamStatus.completed, written: 3, count: 5)),
        isNotNull,
      );
      expect(ExamRules.checkPublish(ex(ExamStatus.inProgress)), isNotNull);
    });
    test('withdraw / reopen / cancel need a reason and the right state', () {
      expect(ExamRules.checkWithdraw(ex(ExamStatus.published), 'x'), isNotNull);
      expect(
        ExamRules.checkWithdraw(ex(ExamStatus.published), 'Marks misread'),
        isNull,
      );
      expect(
        ExamRules.checkWithdraw(ex(ExamStatus.completed), 'Marks misread'),
        isNotNull,
      );
      expect(
        ExamRules.checkReopen(ex(ExamStatus.withdrawn), 'Correct maths'),
        isNull,
      );
      expect(
        ExamRules.checkReopen(ex(ExamStatus.published), 'Correct maths'),
        isNotNull,
      );
      expect(
        ExamRules.checkCancel(ex(ExamStatus.published), 'Because'),
        isNotNull,
      );
      expect(
        ExamRules.checkCancel(ex(ExamStatus.scheduled), 'Postponed'),
        isNull,
      );
    });
    test(
      'the submitter cannot approve their own sheet unless school admin',
      () {
        final sheet = MarksSheet(
          examId: 'x',
          subjectId: 'm',
          sectionId: 'sa',
          classId: 'c',
          academicYearId: 'y',
          schoolId: 'sc',
          branchId: 'b',
          status: SheetStatus.submitted,
          submittedBy: 'u1',
        );
        expect(
          ExamRules.checkApprove(
            sheet: sheet,
            approverUserId: 'u1',
            approverIsSchoolAdmin: false,
          ),
          isNotNull,
        );
        expect(
          ExamRules.checkApprove(
            sheet: sheet,
            approverUserId: 'u2',
            approverIsSchoolAdmin: false,
          ),
          isNull,
        );
        expect(
          ExamRules.checkApprove(
            sheet: sheet,
            approverUserId: 'u1',
            approverIsSchoolAdmin: true,
          ),
          isNull,
        );
      },
    );
    test('a sheet is submitted only when every student is decided', () {
      final math = _sub('math');
      final ok = [
        _e('math', MarkStatus.entered, marks: 0),
        _e('math', MarkStatus.absent),
      ];
      expect(
        ExamRules.checkSubmitSheet(sheet: null, subject: math, roster: ok),
        isNull,
      );
      expect(
        ExamRules.checkSubmitSheet(
          sheet: null,
          subject: math,
          roster: [...ok, _e('math', MarkStatus.pending)],
        ),
        contains('1 student'),
      );
      expect(
        ExamRules.checkSubmitSheet(
          sheet: null,
          subject: math,
          roster: [_e('math', MarkStatus.entered, marks: 500)],
        ),
        isNotNull,
      );
    });
  });

  group('Attendance snapshot (uses the attendance module\'s definition)', () {
    test('present + late + half a half-day, over marked days only', () {
      final tally = AttendanceTally.of([
        AttendanceStatus.present,
        AttendanceStatus.present,
        AttendanceStatus.late,
        AttendanceStatus.halfDay,
        AttendanceStatus.absent,
        null, // not marked: not in the denominator
      ]);
      final s = AttendanceSnapshot.fromTally(
        tally,
        fromKey: '2026-06-01',
        toKey: '2026-09-01',
      );
      expect(s.markedDays, 5);
      expect(s.attendedDays, 3.5);
      expect(s.percentage, closeTo(70, 0.0001));
    });
    test('no marked days gives no percentage, not 0%', () {
      final s = AttendanceSnapshot.fromTally(
        AttendanceTally.of(const [null, null]),
        fromKey: 'a',
        toKey: 'b',
      );
      expect(s.percentage, isNull);
    });
  });

  group('Report card', () {
    ResultSummary summary({bool absent = false}) {
      final scheme = _scheme();
      final result = _calc(
        scheme,
        [_sub('math'), _sub('sci', theory: 70, practical: 30)],
        {
          'math': absent
              ? _e('math', MarkStatus.absent)
              : _e('math', MarkStatus.entered, marks: 72),
          'sci': _e('sci', MarkStatus.entered, theory: 55, practical: 25),
        },
      );
      return ResultSummary(
        examId: 'e',
        examName: 'Half-yearly',
        studentId: 'stu',
        version: 2,
        schoolId: 'sc',
        branchId: 'b',
        academicYearId: 'y',
        classId: 'c',
        sectionId: 'sa',
        result: result,
        schemeSnapshot: scheme.policyMap(),
        attendance: const AttendanceSnapshot(
          attendedDays: 90,
          markedDays: 100,
          percentage: 90,
          fromKey: '2026-06-01',
          toKey: '2026-09-01',
        ),
        teacherRemark: 'Good progress',
        principalRemark: 'Well done',
      );
    }

    test('is produced from the stored result as a real PDF', () async {
      final bytes = await ReportCardPdf.build(
        ReportCardData(
          schoolName: 'Rosewood High',
          branchName: 'Main',
          academicYearName: '2026-27',
          className: 'Class 5',
          sectionName: 'A',
          summary: summary(),
          publishedAt: DateTime(2026, 9, 20),
        ),
      );
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test(
      'handles an absent subject, no attendance and a provisional mark',
      () async {
        final s = summary(absent: true);
        final bytes = await ReportCardPdf.build(
          ReportCardData(
            schoolName: 'Rosewood High',
            branchName: '',
            academicYearName: '2026-27',
            className: 'Class 5',
            sectionName: 'A',
            summary: ResultSummary(
              examId: s.examId,
              examName: s.examName,
              studentId: s.studentId,
              version: 0,
              schoolId: s.schoolId,
              branchId: s.branchId,
              academicYearId: s.academicYearId,
              classId: s.classId,
              sectionId: s.sectionId,
              result: s.result,
              schemeSnapshot: s.schemeSnapshot,
            ),
            provisional: true,
          ),
        );
        expect(bytes, isNotEmpty);
        expect(
          ReportCardPdf.outcomeLabel(s.result.lines.first.outcome),
          'Absent',
        );
      },
    );

    test('a stored result round-trips through its document form', () {
      final s = summary();
      final back = StudentResult.fromMap(s.result.toMap());
      expect(back.toMap(), s.result.toMap());
      expect(back.lines.last.theory, 55);
      expect(back.overallGrade, s.result.overallGrade);
    });
  });
}
