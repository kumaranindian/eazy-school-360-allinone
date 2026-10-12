import 'exam_enums.dart';
import 'examination.dart';
import 'grading_scheme.dart';
import 'marks.dart';

/// What a subject came to for one student.
enum SubjectOutcome {
  passed('PASSED'),
  failed('FAILED'),
  absent('ABSENT'),
  exempted('EXEMPTED'),
  pending('PENDING');

  final String wireValue;
  const SubjectOutcome(this.wireValue);

  static SubjectOutcome fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

class SubjectResultLine {
  final String subjectId;
  final String subjectName;
  final double maxMarks;
  final double passMarks;
  final double weightage;
  final double? obtained;
  final double? theory;
  final double? practical;
  final MarkStatus markStatus;
  final SubjectOutcome outcome;
  final double? percent;
  final String? grade;
  final double? gradePoint;
  final String remark;

  /// Counted in the totals (entered, or absent under the ZERO policy).
  final bool counted;

  const SubjectResultLine({
    required this.subjectId,
    required this.subjectName,
    required this.maxMarks,
    required this.passMarks,
    required this.weightage,
    this.obtained,
    this.theory,
    this.practical,
    required this.markStatus,
    required this.outcome,
    this.percent,
    this.grade,
    this.gradePoint,
    this.remark = '',
    this.counted = false,
  });

  Map<String, dynamic> toMap() => {
    'subjectId': subjectId,
    'subjectName': subjectName,
    'maxMarks': maxMarks,
    'passMarks': passMarks,
    'weightage': weightage,
    'obtained': obtained,
    'theory': theory,
    'practical': practical,
    'markStatus': markStatus.wireValue,
    'outcome': outcome.wireValue,
    'percent': percent,
    'grade': grade,
    'gradePoint': gradePoint,
    'remark': remark,
    'counted': counted,
  };

  factory SubjectResultLine.fromMap(Map<String, dynamic> m) =>
      SubjectResultLine(
        subjectId: m['subjectId'] as String,
        subjectName: m['subjectName'] as String? ?? '',
        maxMarks: (m['maxMarks'] as num).toDouble(),
        passMarks: (m['passMarks'] as num).toDouble(),
        weightage: (m['weightage'] as num?)?.toDouble() ?? 1,
        obtained: (m['obtained'] as num?)?.toDouble(),
        theory: (m['theory'] as num?)?.toDouble(),
        practical: (m['practical'] as num?)?.toDouble(),
        markStatus: MarkStatus.fromWireValue(m['markStatus'] as String),
        outcome: SubjectOutcome.fromWireValue(m['outcome'] as String),
        percent: (m['percent'] as num?)?.toDouble(),
        grade: m['grade'] as String?,
        gradePoint: (m['gradePoint'] as num?)?.toDouble(),
        remark: m['remark'] as String? ?? '',
        counted: m['counted'] as bool? ?? false,
      );
}

/// Overall outcome of a student in an examination.
enum OverallResult {
  pass('PASS', 'Pass'),
  fail('FAIL', 'Fail'),

  /// Nothing was assessed (every subject exempted or absent and excluded).
  notApplicable('NOT_APPLICABLE', 'Not applicable');

  final String wireValue;
  final String displayName;
  const OverallResult(this.wireValue, this.displayName);

  static OverallResult fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

class StudentResult {
  final String studentId;
  final String studentName;
  final String? admissionNumber;
  final String? rollNumber;
  final String sectionId;
  final List<SubjectResultLine> lines;
  final double totalObtained;
  final double totalMax;
  final double? percentage;
  final double? weightedPercentage;

  /// The percentage the grade and result are based on (per the scheme's
  /// aggregation method).
  final double? overallPercentage;
  final String? overallGrade;
  final double? gpa;
  final OverallResult result;
  final bool hasAbsence;
  final int? rank;
  final int? classSize;

  /// Subjects with no usable marks (pending / never entered). A result with
  /// any of these is **incomplete** and cannot be finalised.
  final List<String> incompleteSubjectIds;

  const StudentResult({
    required this.studentId,
    required this.studentName,
    this.admissionNumber,
    this.rollNumber,
    required this.sectionId,
    required this.lines,
    required this.totalObtained,
    required this.totalMax,
    this.percentage,
    this.weightedPercentage,
    this.overallPercentage,
    this.overallGrade,
    this.gpa,
    required this.result,
    this.hasAbsence = false,
    this.rank,
    this.classSize,
    this.incompleteSubjectIds = const [],
  });

  bool get isComplete => incompleteSubjectIds.isEmpty;

  StudentResult withRank(int? rank, int? size) => StudentResult(
    studentId: studentId,
    studentName: studentName,
    admissionNumber: admissionNumber,
    rollNumber: rollNumber,
    sectionId: sectionId,
    lines: lines,
    totalObtained: totalObtained,
    totalMax: totalMax,
    percentage: percentage,
    weightedPercentage: weightedPercentage,
    overallPercentage: overallPercentage,
    overallGrade: overallGrade,
    gpa: gpa,
    result: result,
    hasAbsence: hasAbsence,
    rank: rank,
    classSize: size,
    incompleteSubjectIds: incompleteSubjectIds,
  );

  Map<String, dynamic> toMap() => {
    'studentId': studentId,
    'studentName': studentName,
    'admissionNumber': admissionNumber,
    'rollNumber': rollNumber,
    'sectionId': sectionId,
    'lines': [for (final l in lines) l.toMap()],
    'totalObtained': totalObtained,
    'totalMax': totalMax,
    'percentage': percentage,
    'weightedPercentage': weightedPercentage,
    'overallPercentage': overallPercentage,
    'overallGrade': overallGrade,
    'gpa': gpa,
    'result': result.wireValue,
    'hasAbsence': hasAbsence,
    'rank': rank,
    'classSize': classSize,
  };

  factory StudentResult.fromMap(Map<String, dynamic> m) => StudentResult(
    studentId: m['studentId'] as String,
    studentName: m['studentName'] as String? ?? '',
    admissionNumber: m['admissionNumber'] as String?,
    rollNumber: m['rollNumber'] as String?,
    sectionId: m['sectionId'] as String? ?? '',
    lines: [
      for (final l in m['lines'] as List? ?? [])
        SubjectResultLine.fromMap(Map<String, dynamic>.from(l as Map)),
    ],
    totalObtained: (m['totalObtained'] as num).toDouble(),
    totalMax: (m['totalMax'] as num).toDouble(),
    percentage: (m['percentage'] as num?)?.toDouble(),
    weightedPercentage: (m['weightedPercentage'] as num?)?.toDouble(),
    overallPercentage: (m['overallPercentage'] as num?)?.toDouble(),
    overallGrade: m['overallGrade'] as String?,
    gpa: (m['gpa'] as num?)?.toDouble(),
    result: OverallResult.fromWireValue(m['result'] as String),
    hasAbsence: m['hasAbsence'] as bool? ?? false,
    rank: (m['rank'] as num?)?.toInt(),
    classSize: (m['classSize'] as num?)?.toInt(),
  );
}

/// The **only** place marks become percentages, grades and results. Pure and
/// deterministic: the same marks and scheme always give the same result, and
/// recalculation is therefore safe.
///
/// Rules (also in `docs/milestone-10-…md`):
/// 1. `ENTERED` marks → percent = obtained ÷ max × 100, rounded to the
///    scheme's precision; the grade is looked up from the **rounded**
///    percent; the subject passes when obtained ≥ passing marks.
/// 2. `EXEMPTED` is out of every total and cannot fail.
/// 3. `ABSENT` follows the scheme's policy: excluded from totals, or counted
///    as 0 of the maximum and failed.
/// 4. `PENDING` (or no entry) makes the result **incomplete**.
/// 5. Overall percentage = Σ obtained ÷ Σ max, or the weightage-weighted mean
///    of subject percentages, per the scheme; the overall grade uses the same
///    bands. GPA only when every band carries a grade point.
abstract final class ResultCalculator {
  static double roundTo(double v, int decimals, RoundingMode mode) {
    final f = _pow10(decimals);
    final scaled = v * f;
    final r = switch (mode) {
      RoundingMode.halfUp => (scaled + 1e-9).roundToDouble(),
      RoundingMode.down => (scaled + 1e-9).floorToDouble(),
    };
    return r / f;
  }

  static double _pow10(int n) {
    var f = 1.0;
    for (var i = 0; i < n; i++) {
      f *= 10;
    }
    return f;
  }

  /// The grade band for [percent] (already rounded).
  static GradeBand? bandFor(GradingScheme scheme, double percent) {
    for (final b in scheme.sortedBands) {
      if (percent >= b.minPercent) return b;
    }
    return null;
  }

  static StudentResult calculate({
    required GradingScheme scheme,
    required List<ExaminationSubject> subjects,
    required Map<String, MarksEntry?> entries,
    required String studentId,
    required String studentName,
    String? admissionNumber,
    String? rollNumber,
    required String sectionId,
  }) {
    final lines = <SubjectResultLine>[];
    final incomplete = <String>[];
    var totalObtained = 0.0;
    var totalMax = 0.0;
    var weightedSum = 0.0;
    var weightSum = 0.0;
    var pointSum = 0.0;
    var pointWeight = 0.0;
    var anyFailed = false;
    var hasAbsence = false;
    var counted = 0;

    for (final s in subjects) {
      final e = entries[s.subjectId];
      final pass = s.effectivePassMarks(scheme.passPercent);
      SubjectResultLine line(
        SubjectOutcome outcome,
        MarkStatus status, {
        double? obtained,
        double? percent,
        String? grade,
        double? point,
        bool isCounted = false,
      }) => SubjectResultLine(
        subjectId: s.subjectId,
        subjectName: s.subjectName,
        maxMarks: s.maxMarks,
        passMarks: pass,
        weightage: s.weightage,
        obtained: obtained,
        theory: e?.theory,
        practical: e?.practical,
        markStatus: status,
        outcome: outcome,
        percent: percent,
        grade: grade,
        gradePoint: point,
        remark: e?.remark ?? '',
        counted: isCounted,
      );

      if (e == null ||
          e.status == MarkStatus.pending ||
          (e.status == MarkStatus.entered && e.effectiveMarks == null)) {
        incomplete.add(s.subjectId);
        lines.add(line(SubjectOutcome.pending, MarkStatus.pending));
        continue;
      }
      switch (e.status) {
        case MarkStatus.exempted:
          lines.add(line(SubjectOutcome.exempted, MarkStatus.exempted));
        case MarkStatus.absent:
          hasAbsence = true;
          if (scheme.absentPolicy == AbsentPolicy.zero) {
            anyFailed = true;
            counted++;
            totalMax += s.maxMarks;
            weightedSum += 0 * s.weightage;
            weightSum += s.weightage;
            final band = bandFor(scheme, 0);
            if (band?.gradePoint != null) {
              pointSum += band!.gradePoint! * s.weightage;
              pointWeight += s.weightage;
            }
            lines.add(
              line(
                SubjectOutcome.absent,
                MarkStatus.absent,
                obtained: 0,
                percent: 0,
                grade: band?.grade,
                point: band?.gradePoint,
                isCounted: true,
              ),
            );
          } else {
            lines.add(line(SubjectOutcome.absent, MarkStatus.absent));
          }
        case MarkStatus.entered:
          final obtained = e.effectiveMarks!;
          final pct = roundTo(
            obtained / s.maxMarks * 100,
            scheme.decimals,
            scheme.rounding,
          );
          final band = bandFor(scheme, pct);
          final passed = obtained >= pass;
          if (!passed) anyFailed = true;
          counted++;
          totalObtained += obtained;
          totalMax += s.maxMarks;
          weightedSum += pct * s.weightage;
          weightSum += s.weightage;
          if (band?.gradePoint != null) {
            pointSum += band!.gradePoint! * s.weightage;
            pointWeight += s.weightage;
          }
          lines.add(
            line(
              passed ? SubjectOutcome.passed : SubjectOutcome.failed,
              MarkStatus.entered,
              obtained: obtained,
              percent: pct,
              grade: band?.grade,
              point: band?.gradePoint,
              isCounted: true,
            ),
          );
        case MarkStatus.pending:
          break; // handled above
      }
    }

    double? percentage;
    double? weighted;
    double? overall;
    String? grade;
    double? gpa;
    var result = OverallResult.notApplicable;

    if (counted > 0 && totalMax > 0) {
      percentage = roundTo(
        totalObtained / totalMax * 100,
        scheme.decimals,
        scheme.rounding,
      );
      weighted = weightSum > 0
          ? roundTo(weightedSum / weightSum, scheme.decimals, scheme.rounding)
          : null;
      overall = scheme.aggregate == AggregateMethod.weighted
          ? weighted
          : percentage;
      if (overall != null) grade = bandFor(scheme, overall)?.grade;
      if (scheme.gpaEnabled && pointWeight > 0) {
        gpa = roundTo(pointSum / pointWeight, 2, scheme.rounding);
      }
      var failed = anyFailed;
      if (scheme.overallPassPercent != null &&
          overall != null &&
          overall < scheme.overallPassPercent!) {
        failed = true;
      }
      result = failed ? OverallResult.fail : OverallResult.pass;
    }

    return StudentResult(
      studentId: studentId,
      studentName: studentName,
      admissionNumber: admissionNumber,
      rollNumber: rollNumber,
      sectionId: sectionId,
      lines: lines,
      totalObtained: roundTo(totalObtained, 2, RoundingMode.halfUp),
      totalMax: totalMax,
      percentage: percentage,
      weightedPercentage: weighted,
      overallPercentage: overall,
      overallGrade: grade,
      gpa: gpa,
      result: result,
      hasAbsence: hasAbsence,
      incompleteSubjectIds: incomplete,
    );
  }

  /// Competition ranking (1, 2, 2, 4) by overall percentage, among students
  /// with a computed percentage. Only call when the scheme enables ranking.
  static List<StudentResult> assignRanks(List<StudentResult> results) {
    final ranked = [
      for (final r in results)
        if (r.overallPercentage != null) r,
    ]..sort((a, b) => b.overallPercentage!.compareTo(a.overallPercentage!));
    final rankOf = <String, int>{};
    for (var i = 0; i < ranked.length; i++) {
      if (i > 0 &&
          ranked[i].overallPercentage == ranked[i - 1].overallPercentage) {
        rankOf[ranked[i].studentId] = rankOf[ranked[i - 1].studentId]!;
      } else {
        rankOf[ranked[i].studentId] = i + 1;
      }
    }
    return [
      for (final r in results) r.withRank(rankOf[r.studentId], ranked.length),
    ];
  }
}

/// Summary figures for dashboards. Computed from stored results only.
class ExamStats {
  final int students;
  final int passed;
  final int failed;
  final double? averagePercentage;
  final Map<String, int> gradeDistribution;
  final Map<String, SubjectStats> bySubject;

  const ExamStats({
    required this.students,
    required this.passed,
    required this.failed,
    this.averagePercentage,
    required this.gradeDistribution,
    required this.bySubject,
  });

  /// Pass percentage among students with a pass/fail outcome.
  double? get passRate {
    final judged = passed + failed;
    return judged == 0 ? null : passed / judged * 100;
  }

  static ExamStats of(Iterable<StudentResult> results) {
    var passed = 0, failed = 0, n = 0;
    var sum = 0.0;
    var withPct = 0;
    final grades = <String, int>{};
    final subjects = <String, _SubjectAcc>{};
    for (final r in results) {
      n++;
      if (r.result == OverallResult.pass) passed++;
      if (r.result == OverallResult.fail) failed++;
      if (r.overallPercentage != null) {
        sum += r.overallPercentage!;
        withPct++;
      }
      if (r.overallGrade != null) {
        grades[r.overallGrade!] = (grades[r.overallGrade!] ?? 0) + 1;
      }
      for (final l in r.lines) {
        final a = subjects.putIfAbsent(
          l.subjectId,
          () => _SubjectAcc(l.subjectName),
        );
        switch (l.outcome) {
          case SubjectOutcome.passed:
            a.passed++;
            a.pctSum += l.percent ?? 0;
            a.scored++;
          case SubjectOutcome.failed:
            a.failed++;
            a.pctSum += l.percent ?? 0;
            a.scored++;
          case SubjectOutcome.absent:
            a.absent++;
          case SubjectOutcome.exempted:
          case SubjectOutcome.pending:
            break;
        }
      }
    }
    return ExamStats(
      students: n,
      passed: passed,
      failed: failed,
      averagePercentage: withPct == 0 ? null : sum / withPct,
      gradeDistribution: grades,
      bySubject: {
        for (final e in subjects.entries)
          e.key: SubjectStats(
            name: e.value.name,
            passed: e.value.passed,
            failed: e.value.failed,
            absent: e.value.absent,
            averagePercentage: e.value.scored == 0
                ? null
                : e.value.pctSum / e.value.scored,
          ),
      },
    );
  }
}

class _SubjectAcc {
  final String name;
  int passed = 0, failed = 0, absent = 0, scored = 0;
  double pctSum = 0;

  _SubjectAcc(this.name);
}

class SubjectStats {
  final String name;
  final int passed;
  final int failed;
  final int absent;
  final double? averagePercentage;

  const SubjectStats({
    required this.name,
    required this.passed,
    required this.failed,
    required this.absent,
    this.averagePercentage,
  });

  double? get passRate {
    final judged = passed + failed;
    return judged == 0 ? null : passed / judged * 100;
  }
}
