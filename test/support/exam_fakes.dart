import 'dart:async';

import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/exams/domain/exam_enums.dart';
import 'package:eazy_school_360/features/exams/domain/exam_repositories.dart';
import 'package:eazy_school_360/features/exams/domain/exam_rules.dart';
import 'package:eazy_school_360/features/exams/domain/examination.dart';
import 'package:eazy_school_360/features/exams/domain/grading_scheme.dart';
import 'package:eazy_school_360/features/exams/domain/marks.dart';
import 'package:eazy_school_360/features/exams/domain/result_calculator.dart';
import 'package:eazy_school_360/features/exams/domain/result_summary.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';

class FakeGradingSchemeRepository implements GradingSchemeRepository {
  final Map<String, GradingScheme> schemes = {};
  final List<GradingScheme> saved = [];
  final _changes = StreamController<void>.broadcast();

  FakeGradingSchemeRepository({List<GradingScheme> schemes = const []}) {
    for (final s in schemes) {
      this.schemes[s.schemeId] = s;
    }
  }

  @override
  Stream<List<GradingScheme>> watch(String schoolId, String branchId) async* {
    yield schemes.values.toList();
    yield* _changes.stream.map((_) => schemes.values.toList());
  }

  @override
  Future<GradingScheme?> fetch(
    String schoolId,
    String branchId,
    String schemeId,
  ) async => schemes[schemeId];

  @override
  Future<String> save(GradingScheme scheme, {required ExamActor actor}) async {
    final problem = scheme.validate();
    if (problem != null) throw ValidationFailure(problem);
    final id = scheme.schemeId.isEmpty
        ? 'gs_${schemes.length + 1}'
        : scheme.schemeId;
    final stored = GradingScheme(
      schemeId: id,
      schoolId: scheme.schoolId,
      branchId: scheme.branchId,
      name: scheme.name,
      description: scheme.description,
      bands: scheme.bands,
      passPercent: scheme.passPercent,
      overallPassPercent: scheme.overallPassPercent,
      decimals: scheme.decimals,
      rounding: scheme.rounding,
      absentPolicy: scheme.absentPolicy,
      aggregate: scheme.aggregate,
      rankingEnabled: scheme.rankingEnabled,
      active: scheme.active,
      revision: scheme.revision + (scheme.schemeId.isEmpty ? 0 : 1),
    );
    schemes[id] = stored;
    saved.add(stored);
    _changes.add(null);
    return id;
  }
}

/// An in-memory examination store that applies the same workflow rules the
/// real repository does.
class FakeExamRepository implements ExamRepository {
  final Map<String, Examination> exams = {};
  final Map<String, Map<String, ExaminationSubject>> subjects = {};
  final List<ExamAuditEntry> audit = [];
  final _changes = StreamController<String>.broadcast();

  FakeExamRepository({
    List<Examination> exams = const [],
    List<ExaminationSubject> subjects = const [],
  }) {
    for (final e in exams) {
      this.exams[e.examId] = e;
    }
    for (final s in subjects) {
      this.subjects.putIfAbsent(s.examId, () => {})[s.subjectId] = s;
    }
  }

  void put(Examination e) {
    exams[e.examId] = e;
    _changes.add(e.examId);
  }

  Examination _get(String id) {
    final e = exams[id];
    if (e == null) throw const NotFoundFailure('missing');
    return e;
  }

  void _log(Examination e, ExamEvent event, ExamActor a, {String? note}) {
    audit.add(
      ExamAuditEntry(
        refId: e.examId,
        scope: 'EXAM',
        revision: e.revision,
        event: event.wireValue,
        toStatus: e.status.wireValue,
        actorId: a.userId,
        actorName: a.name,
        note: note,
        at: DateTime.now(),
      ),
    );
  }

  Examination _copy(
    Examination e, {
    ExamStatus? status,
    int? sheetCount,
    int? approvedSheets,
    int? resultVersion,
    int? resultCount,
    int? resultsWritten,
    Map<String, dynamic>? snapshot,
    int? subjectCount,
    String? name,
    String? description,
    String? schemeId,
    String? startDateKey,
    String? endDateKey,
    ExamType? type,
    String? instructions,
    DateTime? publishedAt,
  }) => Examination(
    examId: e.examId,
    schoolId: e.schoolId,
    branchId: e.branchId,
    academicYearId: e.academicYearId,
    classId: e.classId,
    sectionId: e.sectionId,
    classLabel: e.classLabel,
    name: name ?? e.name,
    description: description ?? e.description,
    type: type ?? e.type,
    schemeId: schemeId ?? e.schemeId,
    startDateKey: startDateKey ?? e.startDateKey,
    endDateKey: endDateKey ?? e.endDateKey,
    instructions: instructions ?? e.instructions,
    status: status ?? e.status,
    revision: e.revision + 1,
    subjectCount: subjectCount ?? e.subjectCount,
    sheetCount: sheetCount ?? e.sheetCount,
    approvedSheets: approvedSheets ?? e.approvedSheets,
    resultVersion: resultVersion ?? e.resultVersion,
    resultCount: resultCount ?? e.resultCount,
    resultsWritten: resultsWritten ?? e.resultsWritten,
    schemeSnapshot: snapshot ?? e.schemeSnapshot,
    publishedAt: publishedAt ?? e.publishedAt,
    createdBy: e.createdBy,
  );

  /// Used by the other fakes to move counters/status.
  void mutate(String id, Examination Function(Examination e) f) {
    exams[id] = f(_get(id));
    _changes.add(id);
  }

  Examination copyOf(
    Examination e, {
    int? approvedSheets,
    ExamStatus? status,
    int? resultVersion,
    int? resultCount,
    int? resultsWritten,
    Map<String, dynamic>? snapshot,
    DateTime? publishedAt,
  }) => _copy(
    e,
    approvedSheets: approvedSheets,
    status: status,
    resultVersion: resultVersion,
    resultCount: resultCount,
    resultsWritten: resultsWritten,
    snapshot: snapshot,
    publishedAt: publishedAt,
  );

  @override
  Future<PagedResult<Examination>> fetch({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    String? classId,
    ExamStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    final all = [
      for (final e in exams.values)
        if (e.academicYearId == academicYearId &&
            (classId == null || e.classId == classId) &&
            (status == null || e.status == status))
          e,
    ]..sort((a, b) => b.startDateKey.compareTo(a.startDateKey));
    final start = cursor as int? ?? 0;
    final next = start + pageSize;
    return PagedResult(
      items: all.skip(start).take(pageSize).toList(),
      nextCursor: next < all.length ? next : null,
    );
  }

  @override
  Stream<Examination?> watch(
    String schoolId,
    String branchId,
    String examId,
  ) async* {
    yield exams[examId];
    yield* _changes.stream
        .where((id) => id == examId)
        .map((_) => exams[examId]);
  }

  @override
  Stream<List<ExaminationSubject>> watchSubjects(
    String schoolId,
    String branchId,
    String examId,
  ) async* {
    List<ExaminationSubject> now() =>
        (subjects[examId]?.values.toList() ?? [])
          ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
    yield now();
    yield* _changes.stream.where((id) => id == examId).map((_) => now());
  }

  @override
  Future<void> create(Examination exam, {required ExamActor actor}) async {
    final problem = exam.validate();
    if (problem != null) throw ValidationFailure(problem);
    if (exams.containsKey(exam.examId)) {
      throw const ConflictFailure(
        'An examination with this name already exists for this class and '
        'section.',
      );
    }
    exams[exam.examId] = exam;
    _log(exam, ExamEvent.created, actor);
    _changes.add(exam.examId);
  }

  @override
  Future<void> update(Examination exam, {required ExamActor actor}) async {
    final cur = _get(exam.examId);
    if (!cur.status.isConfigurable) {
      throw const ConflictFailure(
        'Only a draft or scheduled examination can be edited.',
      );
    }
    exams[exam.examId] = _copy(
      cur,
      name: exam.name,
      description: exam.description,
      type: exam.type,
      schemeId: exam.schemeId,
      startDateKey: exam.startDateKey,
      endDateKey: exam.endDateKey,
      instructions: exam.instructions,
    );
    _log(exams[exam.examId]!, ExamEvent.edited, actor);
    _changes.add(exam.examId);
  }

  @override
  Future<void> saveSubject(
    Examination exam,
    ExaminationSubject subject, {
    required bool isNew,
    required ExamActor actor,
  }) async {
    final problem = subject.validate(
      examStartKey: exam.startDateKey,
      examEndKey: exam.endDateKey,
    );
    if (problem != null) throw ValidationFailure(problem);
    final cur = _get(exam.examId);
    if (!cur.status.isConfigurable) {
      throw const ConflictFailure(
        'Subjects can only change while configurable.',
      );
    }
    final map = subjects.putIfAbsent(exam.examId, () => {});
    if (isNew && map.containsKey(subject.subjectId)) {
      throw const ConflictFailure('That subject is already configured.');
    }
    map[subject.subjectId] = subject;
    exams[exam.examId] = Examination(
      examId: cur.examId,
      schoolId: cur.schoolId,
      branchId: cur.branchId,
      academicYearId: cur.academicYearId,
      classId: cur.classId,
      sectionId: cur.sectionId,
      classLabel: cur.classLabel,
      name: cur.name,
      description: cur.description,
      type: cur.type,
      schemeId: cur.schemeId,
      startDateKey: cur.startDateKey,
      endDateKey: cur.endDateKey,
      instructions: cur.instructions,
      status: cur.status,
      revision: cur.revision,
      subjectCount: map.length,
    );
    _changes.add(exam.examId);
  }

  @override
  Future<void> removeSubject(
    Examination exam,
    ExaminationSubject subject, {
    required ExamActor actor,
  }) async {
    subjects[exam.examId]?.remove(subject.subjectId);
    mutate(
      exam.examId,
      (e) => _copy(e, subjectCount: subjects[exam.examId]?.length ?? 0),
    );
  }

  Future<void> _go(
    Examination exam,
    ExamActor actor,
    ExamEvent event,
    String? problem,
    Examination Function(Examination) f, {
    String? note,
  }) async {
    final cur = _get(exam.examId);
    final p = problem;
    if (p != null) throw ConflictFailure(p);
    exams[cur.examId] = f(cur);
    _log(exams[cur.examId]!, event, actor, note: note);
    _changes.add(cur.examId);
  }

  @override
  Future<void> schedule(Examination exam, {required ExamActor actor}) => _go(
    exam,
    actor,
    ExamEvent.scheduled,
    ExamRules.checkSchedule(_get(exam.examId)),
    (e) => _copy(e, status: ExamStatus.scheduled),
  );

  @override
  Future<void> startMarksEntry(
    Examination exam, {
    required int sheetCount,
    required ExamActor actor,
  }) => _go(
    exam,
    actor,
    ExamEvent.started,
    ExamRules.checkStart(_get(exam.examId), sheetCount),
    (e) => _copy(
      e,
      status: ExamStatus.inProgress,
      sheetCount: sheetCount,
      approvedSheets: 0,
    ),
  );

  @override
  Future<void> cancel(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  }) => _go(
    exam,
    actor,
    ExamEvent.cancelled,
    ExamRules.checkCancel(_get(exam.examId), reason),
    (e) => _copy(e, status: ExamStatus.cancelled),
    note: reason,
  );

  @override
  Future<void> withdraw(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  }) => _go(
    exam,
    actor,
    ExamEvent.withdrawn,
    ExamRules.checkWithdraw(_get(exam.examId), reason),
    (e) => _copy(e, status: ExamStatus.withdrawn),
    note: reason,
  );

  @override
  Future<void> reopen(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  }) => _go(
    exam,
    actor,
    ExamEvent.reopened,
    ExamRules.checkReopen(_get(exam.examId), reason),
    (e) => _copy(
      e,
      status: ExamStatus.inProgress,
      resultsWritten: 0,
      resultCount: 0,
    ),
    note: reason,
  );

  @override
  Future<List<ExamAuditEntry>> fetchAudit(
    String schoolId,
    String branchId,
    String examId,
  ) async => [
    for (final a in audit)
      if (a.refId == examId || a.refId.startsWith(examId)) a,
  ];
}

class FakeMarksRepository implements MarksRepository {
  final FakeExamRepository exams;
  final Map<String, MarksSheet> sheets = {};
  final Map<String, MarksEntry> entries = {};
  final List<String> saves = [];
  final List<String> submits = [];
  final List<String> approvals = [];
  final List<String> returns = [];
  final Map<String, int> revisions = {};

  FakeMarksRepository(this.exams);

  @override
  Future<MarksSheet?> fetchSheet(
    Examination exam,
    String subjectId,
    String sectionId,
  ) async => sheets[MarksSheet.idFor(exam.examId, subjectId, sectionId)];

  @override
  Future<List<MarksSheet>> fetchSheets(Examination exam) async => [
    for (final s in sheets.values)
      if (s.examId == exam.examId) s,
  ];

  @override
  Future<List<MarksEntry>> fetchEntries(
    Examination exam,
    String subjectId,
    String sectionId,
  ) async => [
    for (final e in entries.values)
      if (e.examId == exam.examId &&
          e.subjectId == subjectId &&
          e.sectionId == sectionId)
        e,
  ];

  @override
  Future<List<MarksEntry>> fetchAllEntries(Examination exam) async => [
    for (final e in entries.values)
      if (e.examId == exam.examId) e,
  ];

  /// Seeds an approved sheet with entries, bypassing the workflow.
  void seed(
    Examination exam,
    String subjectId,
    String sectionId,
    List<MarksEntry> list, {
    SheetStatus status = SheetStatus.approved,
    String submittedBy = 'someone',
  }) {
    final id = MarksSheet.idFor(exam.examId, subjectId, sectionId);
    sheets[id] = MarksSheet(
      examId: exam.examId,
      subjectId: subjectId,
      sectionId: sectionId,
      classId: exam.classId,
      academicYearId: exam.academicYearId,
      schoolId: exam.schoolId,
      branchId: exam.branchId,
      status: status,
      rosterCount: list.length,
      submittedBy: submittedBy,
      submittedAt: DateTime.now(),
    );
    for (final e in list) {
      entries[e.id] = e;
    }
  }

  @override
  Future<int> saveEntries({
    required Examination exam,
    required ExaminationSubject subject,
    required String sectionId,
    required List<MarksEntry> changed,
    required int rosterCount,
    required ExamActor actor,
  }) async {
    final current = exams.exams[exam.examId]!;
    if (current.status != ExamStatus.inProgress) {
      throw const ConflictFailure('Marks entry is not open.');
    }
    final id = MarksSheet.idFor(exam.examId, subject.subjectId, sectionId);
    final sheet = sheets[id];
    if (sheet != null && !sheet.status.isEditable) {
      throw ConflictFailure(
        'This sheet is ${sheet.status.displayName.toLowerCase()}.',
      );
    }
    for (final e in changed) {
      final p = e.validate(subject);
      if (p != null) throw ValidationFailure(p);
    }
    sheets.putIfAbsent(
      id,
      () => MarksSheet(
        examId: exam.examId,
        subjectId: subject.subjectId,
        sectionId: sectionId,
        classId: exam.classId,
        academicYearId: exam.academicYearId,
        schoolId: exam.schoolId,
        branchId: exam.branchId,
        rosterCount: rosterCount,
      ),
    );
    for (final e in changed) {
      final rev = (revisions[e.id] ?? 0) + 1;
      revisions[e.id] = rev;
      final body = e.body(components: subject.hasComponents);
      entries[e.id] = MarksEntry(
        sheetId: e.sheetId,
        examId: e.examId,
        subjectId: e.subjectId,
        studentId: e.studentId,
        studentName: e.studentName,
        rollNumber: e.rollNumber,
        classId: e.classId,
        sectionId: e.sectionId,
        academicYearId: e.academicYearId,
        schoolId: e.schoolId,
        branchId: e.branchId,
        status: e.status,
        marks: body['marks'] as double?,
        theory: body['theory'] as double?,
        practical: body['practical'] as double?,
        remark: e.remark,
        revision: rev,
        updatedBy: actor.userId,
      );
    }
    saves.add('$id:${changed.length}');
    return changed.length;
  }

  MarksSheet _sheet(MarksSheet s, SheetStatus st, {String? by, String? note}) =>
      MarksSheet(
        examId: s.examId,
        subjectId: s.subjectId,
        sectionId: s.sectionId,
        classId: s.classId,
        academicYearId: s.academicYearId,
        schoolId: s.schoolId,
        branchId: s.branchId,
        status: st,
        revision: s.revision + 1,
        rosterCount: s.rosterCount,
        submittedBy: st == SheetStatus.submitted ? by : s.submittedBy,
        submittedAt: s.submittedAt,
        approvedBy: st == SheetStatus.approved ? by : null,
        reviewNote: note,
      );

  @override
  Future<void> submitSheet({
    required Examination exam,
    required MarksSheet sheet,
    required ExamActor actor,
  }) async {
    final s = sheets[sheet.id]!;
    if (!s.status.isEditable) throw const ConflictFailure('Already submitted.');
    sheets[s.id] = _sheet(s, SheetStatus.submitted, by: actor.userId);
    submits.add(s.id);
  }

  @override
  Future<void> approveSheet({
    required Examination exam,
    required MarksSheet sheet,
    required ExamActor actor,
  }) async {
    final s = sheets[sheet.id]!;
    final p = ExamRules.checkApprove(
      sheet: s,
      approverUserId: actor.userId,
      approverIsSchoolAdmin: actor.isSchoolAdmin,
    );
    if (p != null) throw ConflictFailure(p);
    sheets[s.id] = _sheet(s, SheetStatus.approved, by: actor.userId);
    exams.mutate(
      exam.examId,
      (e) => exams.copyOf(e, approvedSheets: e.approvedSheets + 1),
    );
    approvals.add(s.id);
  }

  @override
  Future<void> returnSheet({
    required Examination exam,
    required MarksSheet sheet,
    required String note,
    required ExamActor actor,
  }) async {
    final s = sheets[sheet.id]!;
    final p = ExamRules.checkReturn(s, note);
    if (p != null) throw ConflictFailure(p);
    if (s.status == SheetStatus.approved) {
      exams.mutate(
        exam.examId,
        (e) => exams.copyOf(e, approvedSheets: e.approvedSheets - 1),
      );
    }
    sheets[s.id] = _sheet(s, SheetStatus.returned, note: note);
    returns.add(s.id);
  }
}

class FakeResultRepository implements ResultRepository {
  final FakeExamRepository exams;
  final Map<String, ResultSummary> results = {};
  final Map<String, ExamRemark> remarks = {};
  final List<String> published = [];
  final List<int> finalizedVersions = [];

  /// When set, every single-result read fails with it (a denied or failed
  /// read, as opposed to a result that simply does not exist).
  Object? fetchError;

  FakeResultRepository(this.exams);

  @override
  Future<Map<String, ExamRemark>> fetchRemarks(Examination exam) async =>
      Map.of(remarks);

  @override
  Future<void> saveRemark({
    required Examination exam,
    required ExamRemark remark,
    required String sectionId,
    required ExamActor actor,
    required bool principal,
  }) async {
    remarks[remark.studentId] = remark;
  }

  ResultSummary _summary(
    Examination exam,
    GradingScheme scheme,
    StudentResult r,
    int version,
    Map<String, AttendanceSnapshot?> attendance,
    Map<String, ExamRemark> rem,
    String classLabel,
  ) => ResultSummary(
    examId: exam.examId,
    examName: exam.name,
    studentId: r.studentId,
    version: version,
    schoolId: exam.schoolId,
    branchId: exam.branchId,
    academicYearId: exam.academicYearId,
    classId: exam.classId,
    sectionId: r.sectionId,
    classLabel: classLabel,
    result: r,
    schemeSnapshot: scheme.policyMap(),
    attendance: attendance[r.studentId],
    teacherRemark: rem[r.studentId]?.teacherRemark ?? '',
    principalRemark: rem[r.studentId]?.principalRemark ?? '',
  );

  @override
  Future<int> finalize({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required Map<String, String> classLabels,
    required ExamActor actor,
  }) async {
    final cur = exams.exams[exam.examId]!;
    final p = ExamRules.checkFinalize(cur);
    if (p != null) throw ConflictFailure(p);
    if (results.any((r) => !r.isComplete)) {
      throw const ValidationFailure('Some marks are missing.');
    }
    final version = cur.resultVersion + 1;
    for (final r in results) {
      this.results['${exam.examId}__${r.studentId}__v$version'] = _summary(
        cur,
        scheme,
        r,
        version,
        attendance,
        remarks,
        classLabels[r.sectionId] ?? '',
      );
    }
    exams.mutate(
      exam.examId,
      (e) => exams.copyOf(
        e,
        status: ExamStatus.completed,
        resultVersion: version,
        resultCount: results.length,
        resultsWritten: results.length,
        snapshot: scheme.policyMap(),
      ),
    );
    finalizedVersions.add(version);
    return version;
  }

  @override
  Future<void> completeResults({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required String classLabel,
    required ExamActor actor,
  }) async {}

  @override
  Future<void> publish(Examination exam, {required ExamActor actor}) async {
    final cur = exams.exams[exam.examId]!;
    if (cur.status == ExamStatus.published) return;
    final p = ExamRules.checkPublish(cur);
    if (p != null) throw ConflictFailure(p);
    exams.mutate(
      exam.examId,
      (e) => exams.copyOf(
        e,
        status: ExamStatus.published,
        publishedAt: DateTime.now(),
      ),
    );
    published.add('${exam.examId}:v${cur.resultVersion}');
  }

  @override
  Future<PagedResult<ResultSummary>> fetchResults({
    required Examination exam,
    int pageSize = 50,
    Object? cursor,
  }) async => PagedResult(
    items: [
      for (final r in results.values)
        if (r.examId == exam.examId && r.version == exam.resultVersion) r,
    ],
    nextCursor: null,
  );

  @override
  Future<ResultSummary?> fetchResult({
    required String schoolId,
    required String branchId,
    required String examId,
    required String studentId,
    required int version,
  }) async {
    // Mirrors the rules: a family can read only the version in force of a
    // PUBLISHED examination. (Staff reads of unpublished results are the
    // staff screens' business.)
    if (fetchError != null) throw fetchError!;
    return results['${examId}__${studentId}__v$version'];
  }

  @override
  Future<List<Examination>> fetchPublishedForClass({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  }) async => [
    for (final e in exams.exams.values)
      if (e.status == ExamStatus.published &&
          e.classId == classId &&
          e.academicYearId == academicYearId &&
          (e.sectionId == null || e.sectionId == sectionId))
        e,
  ];
}
