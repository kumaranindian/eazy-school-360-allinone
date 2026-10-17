import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/exams/data/exam_writes.dart';
import 'package:eazy_school_360/features/exams/domain/exam_enums.dart';
import 'package:eazy_school_360/features/exams/domain/exam_repositories.dart';
import 'package:eazy_school_360/features/exams/domain/examination.dart';
import 'package:eazy_school_360/features/exams/domain/grading_scheme.dart';
import 'package:eazy_school_360/features/exams/domain/marks.dart';
import 'package:eazy_school_360/features/exams/domain/result_calculator.dart';
import 'package:eazy_school_360/features/exams/domain/result_summary.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exports the exact documents the Dart examination code writes, step by
/// step through the whole workflow, to
/// `firestore-tests/fixtures/exam-write-plans.json`. `exam-contract.test.mjs`
/// replays them under the real `firestore.rules`; every step must be accepted.
const _school = '__SCHOOL__';
const _branch = 'north';
const _admin = ExamActor(
  userId: 'ex-admin',
  name: 'Admin',
  role: 'SCHOOL_ADMIN',
);
const _t1 = ExamActor(userId: 'ex-t1', name: 'Maths teacher', role: 'TEACHER');
const _t2 = ExamActor(
  userId: 'ex-t2',
  name: 'Science teacher',
  role: 'TEACHER',
);
const _branchAdmin = ExamActor(
  userId: 'ex-badmin',
  name: 'Branch admin',
  role: 'BRANCH_ADMIN',
);

Object? _encode(Object? v) {
  if (v is FieldValue) return {r'$serverTimestamp': true};
  if (v is Timestamp) return {r'$time': v.toDate().toUtc().toIso8601String()};
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _encode(e.value)};
  }
  if (v is List) return [for (final e in v) _encode(e)];
  return v;
}

class _Batch {
  final String as;
  final String label;
  final List<Map<String, Object?>> ops = [];

  _Batch(this.as, this.label);

  void set(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'set', 'path': path, 'data': _encode(data)});
  void update(String path, Map<String, dynamic> data) =>
      ops.add({'op': 'update', 'path': path, 'data': _encode(data)});

  Map<String, Object?> toJson() => {'as': as, 'label': label, 'ops': ops};
}

String _p(String c, String id) => '$c/$id';

MarksEntry _entry(
  Examination e,
  String subject,
  String student,
  MarkStatus status, {
  double? marks,
  double? theory,
  double? practical,
  int revision = 0,
}) => MarksEntry(
  sheetId: MarksSheet.idFor(e.examId, subject, 'sa'),
  examId: e.examId,
  subjectId: subject,
  studentId: student,
  studentName: student,
  classId: 'c5',
  sectionId: 'sa',
  academicYearId: 'y1',
  schoolId: _school,
  branchId: _branch,
  status: status,
  marks: marks,
  theory: theory,
  practical: practical,
  revision: revision,
);

void main() {
  test('exports the examination write plan', () {
    final batches = <_Batch>[];
    var exam = const Examination(
      examId: 'y1__c5__sa__half-yearly',
      schoolId: _school,
      branchId: _branch,
      academicYearId: 'y1',
      classId: 'c5',
      sectionId: 'sa',
      classLabel: 'Class 5 – A',
      name: 'Half-yearly',
      type: ExamType.halfYearly,
      schemeId: 'scheme-1',
      startDateKey: '2026-09-01',
      endDateKey: '2026-09-10',
    );
    final id = exam.examId;
    ExaminationSubject subject(
      String sid,
      String name, {
      double? theory,
      double? practical,
    }) => ExaminationSubject(
      examId: id,
      subjectId: sid,
      schoolId: _school,
      branchId: _branch,
      academicYearId: 'y1',
      classId: 'c5',
      subjectName: name,
      maxMarks: 100,
      passMarks: 35,
      weightage: 2,
      dateKey: '2026-09-02',
      startMin: 540,
      endMin: 660,
      theoryMax: theory,
      practicalMax: practical,
    );
    final math = subject('math', 'Maths');
    final sci = subject('sci', 'Science', theory: 70, practical: 30);

    // ---- configuration ---------------------------------------------------
    final create = _Batch('ex-admin', 'create examination');
    create.set(
      _p('examinations', id),
      exam.toFirestoreCreate(actorId: 'ex-admin'),
    );
    create.set(
      _p('examHistory', ExamWrites.historyId(id, 1)),
      ExamWrites.history(
        exam: exam,
        revision: 1,
        event: ExamEvent.created,
        toStatus: ExamStatus.draft,
        actor: _admin,
      ),
    );
    batches.add(create);
    // Families filter examinations on this string; the rules require it to
    // agree with sectionId (a null filter cannot be proven on the live service).
    expect(
      exam.toFirestoreCreate(actorId: 'ex-admin')['sectionScope'],
      exam.sectionId ?? 'ALL',
    );
    expect(
      exam.copyWith().toFirestoreCreate(actorId: 'a')['sectionScope'],
      isA<String>(),
    );

    var subjects = 0;
    for (final s in [math, sci]) {
      subjects++;
      final b = _Batch('ex-admin', 'add subject ${s.subjectId}');
      b.set(
        _p('examinationSubjects', s.id),
        s.toFirestoreCreate(actorId: 'ex-admin'),
      );
      b.update(
        _p('examinations', id),
        ExamWrites.counter('subjectCount', subjects, 'ex-admin'),
      );
      batches.add(b);
    }

    final editSubject = _Batch('ex-admin', 'change a subject');
    editSubject.update(
      _p('examinationSubjects', math.id),
      ExamWrites.subjectEdit(math, 2, 'ex-admin'),
    );
    batches.add(editSubject);

    exam = exam.copyWith(name: 'Half-yearly examination');
    final edit = _Batch('ex-admin', 'edit configuration');
    edit.update(
      _p('examinations', id),
      ExamWrites.examEdit(exam, 2, 'ex-admin'),
    );
    edit.set(
      _p('examHistory', ExamWrites.historyId(id, 2)),
      ExamWrites.history(
        exam: exam,
        revision: 2,
        event: ExamEvent.edited,
        toStatus: ExamStatus.draft,
        actor: _admin,
      ),
    );
    batches.add(edit);

    _Batch status(
      String as,
      ExamActor actor,
      String label,
      int rev,
      ExamEvent event,
      ExamStatus to, {
      Map<String, dynamic> extra = const {},
      String? note,
    }) {
      final b = _Batch(as, label);
      b.update(
        _p('examinations', id),
        ExamWrites.examStatus(
          to: to,
          event: event,
          revision: rev,
          uid: as,
          extra: extra,
        ),
      );
      b.set(
        _p('examHistory', ExamWrites.historyId(id, rev)),
        ExamWrites.history(
          exam: exam,
          revision: rev,
          event: event,
          toStatus: to,
          actor: actor,
          note: note,
        ),
      );
      return b;
    }

    batches.add(
      status(
        'ex-admin',
        _admin,
        'schedule',
        3,
        ExamEvent.scheduled,
        ExamStatus.scheduled,
      ),
    );
    batches.add(
      status(
        'ex-admin',
        _admin,
        'open marks entry (2 sheets)',
        4,
        ExamEvent.started,
        ExamStatus.inProgress,
        extra: {'sheetCount': 2, 'approvedSheets': 0},
      ),
    );

    // ---- marks (teachers) ------------------------------------------------
    _Batch sheetWith(
      String as,
      ExamActor actor,
      String subjectId,
      List<MarksEntry> entries,
      bool components,
    ) {
      final sheetId = MarksSheet.idFor(id, subjectId, 'sa');
      final b = _Batch(as, 'first save of $subjectId (creates the sheet)');
      b.set(
        _p('marksSheets', sheetId),
        ExamWrites.sheetCreate(
          exam: exam,
          subjectId: subjectId,
          sectionId: 'sa',
          rosterCount: 2,
          uid: as,
        ),
      );
      b.set(
        _p('marksSheetHistory', ExamWrites.sheetHistoryId(sheetId, 1)),
        ExamWrites.sheetHistory(
          exam: exam,
          sheetId: sheetId,
          revision: 1,
          event: SheetEvent.saved,
          toStatus: SheetStatus.draft,
          actor: actor,
        ),
      );
      for (final e in entries) {
        b.set(
          _p('marksEntries', e.id),
          ExamWrites.entryCreate(e: e, components: components, uid: as),
        );
        b.set(
          _p('marksRevisions', '${e.id}__1'),
          ExamWrites.entryRevision(
            e: e,
            components: components,
            revision: 1,
            actor: actor,
          ),
        );
      }
      return b;
    }

    final m1 = _entry(exam, 'math', 'ex-s1', MarkStatus.entered, marks: 0);
    final m2 = _entry(exam, 'math', 'ex-s2', MarkStatus.absent);
    batches.add(sheetWith('ex-t1', _t1, 'math', [m1, m2], false));

    final fixed = _entry(
      exam,
      'math',
      'ex-s1',
      MarkStatus.entered,
      marks: 72,
      revision: 1,
    );
    final correct = _Batch('ex-t1', 'correct an entry');
    correct.update(
      _p('marksEntries', fixed.id),
      ExamWrites.entryUpdate(
        e: fixed,
        components: false,
        revision: 2,
        uid: 'ex-t1',
      ),
    );
    correct.set(
      _p('marksRevisions', '${fixed.id}__2'),
      ExamWrites.entryRevision(
        e: fixed,
        components: false,
        revision: 2,
        actor: _t1,
      ),
    );
    batches.add(correct);

    final mathSheet = MarksSheet.idFor(id, 'math', 'sa');
    _Batch sheetStep(
      String as,
      ExamActor actor,
      String sheetId,
      String label,
      int rev,
      SheetEvent event,
      SheetStatus to,
      Map<String, dynamic> fields, {
      int? approvedCounter,
      String? note,
    }) {
      final b = _Batch(as, label);
      b.update(_p('marksSheets', sheetId), fields);
      if (approvedCounter != null) {
        b.update(
          _p('examinations', id),
          ExamWrites.counter('approvedSheets', approvedCounter, as),
        );
      }
      b.set(
        _p('marksSheetHistory', ExamWrites.sheetHistoryId(sheetId, rev)),
        ExamWrites.sheetHistory(
          exam: exam,
          sheetId: sheetId,
          revision: rev,
          event: event,
          toStatus: to,
          actor: actor,
          note: note,
        ),
      );
      return b;
    }

    batches.add(
      sheetStep(
        'ex-t1',
        _t1,
        mathSheet,
        'submit maths',
        2,
        SheetEvent.submitted,
        SheetStatus.submitted,
        ExamWrites.sheetSubmit(2, 'ex-t1'),
      ),
    );
    batches.add(
      sheetStep(
        'ex-badmin',
        _branchAdmin,
        mathSheet,
        'approve maths',
        3,
        SheetEvent.approved,
        SheetStatus.approved,
        ExamWrites.sheetApprove(3, 'ex-badmin'),
        approvedCounter: 1,
      ),
    );

    final s1 = _entry(
      exam,
      'sci',
      'ex-s1',
      MarkStatus.entered,
      theory: 60,
      practical: 25,
    );
    final s2 = _entry(exam, 'sci', 'ex-s2', MarkStatus.exempted);
    batches.add(sheetWith('ex-t2', _t2, 'sci', [s1, s2], true));
    final sciSheet = MarksSheet.idFor(id, 'sci', 'sa');
    batches.add(
      sheetStep(
        'ex-t2',
        _t2,
        sciSheet,
        'submit science',
        2,
        SheetEvent.submitted,
        SheetStatus.submitted,
        ExamWrites.sheetSubmit(2, 'ex-t2'),
      ),
    );
    batches.add(
      sheetStep(
        'ex-admin',
        _admin,
        sciSheet,
        'approve science',
        3,
        SheetEvent.approved,
        SheetStatus.approved,
        ExamWrites.sheetApprove(3, 'ex-admin'),
        approvedCounter: 2,
      ),
    );

    // ---- finalise, results, publish --------------------------------------
    final scheme = GradingScheme.sample(schoolId: _school, branchId: _branch);
    StudentResult result(String student, double mathMarks) =>
        ResultCalculator.calculate(
          scheme: scheme,
          subjects: [math, sci],
          entries: {
            'math': _entry(
              exam,
              'math',
              student,
              MarkStatus.entered,
              marks: mathMarks,
            ),
            'sci': _entry(
              exam,
              'sci',
              student,
              MarkStatus.entered,
              theory: 60,
              practical: 25,
            ),
          },
          studentId: student,
          studentName: student,
          sectionId: 'sa',
        );
    final results = [result('ex-s1', 72), result('ex-s2', 40)];

    batches.add(
      status(
        'ex-admin',
        _admin,
        'finalise (version 1)',
        5,
        ExamEvent.finalized,
        ExamStatus.completed,
        extra: {
          'resultVersion': 1,
          'resultCount': 2,
          'resultsWritten': 0,
          'schemeSnapshot': scheme.policyMap(),
          'finalizedBy': 'ex-admin',
        },
      ),
    );
    final written = _Batch('ex-admin', 'write the results');
    final published = Examination.fromFirestore({
      'schoolId': _school,
      'branchId': _branch,
      'academicYearId': 'y1',
      'classId': 'c5',
      'sectionId': 'sa',
      'name': 'Half-yearly examination',
      'schemeId': 'scheme-1',
      'startDateKey': '2026-09-01',
      'endDateKey': '2026-09-10',
      'status': 'COMPLETED',
      'resultVersion': 1,
    }, id);
    for (final r in results) {
      written.set(
        _p('resultSummaries', ResultSummary.idFor(id, r.studentId, 1)),
        ExamWrites.resultSummary(
          exam: published,
          version: 1,
          result: r,
          schemeSnapshot: scheme.policyMap(),
          attendance: const AttendanceSnapshot(
            attendedDays: 90,
            markedDays: 100,
            percentage: 90,
            fromKey: '2026-06-01',
            toKey: '2026-09-10',
          ),
          teacherRemark: 'Good',
          principalRemark: '',
          classLabel: 'Class 5 – A',
          uid: 'ex-admin',
        ),
      );
    }
    batches.add(written);
    final counter = _Batch('ex-admin', 'count the results written');
    counter.update(
      _p('examinations', id),
      ExamWrites.counter('resultsWritten', 2, 'ex-admin'),
    );
    batches.add(counter);

    final publish = status(
      'ex-admin',
      _admin,
      'publish (version 1)',
      6,
      ExamEvent.published,
      ExamStatus.published,
      extra: {
        'publishedBy': 'ex-admin',
        'publishedAt': FieldValue.serverTimestamp(),
      },
      note: 'Result version 1',
    );
    publish.set(
      _p('broadcastNotices', ExamWrites.noticeId(id, 1)),
      ExamWrites.resultNotice(published, 'ex-admin'),
    );
    batches.add(publish);

    // ---- correction: withdraw, reopen, return a sheet, redo --------------
    batches.add(
      status(
        'ex-admin',
        _admin,
        'withdraw',
        7,
        ExamEvent.withdrawn,
        ExamStatus.withdrawn,
        note: 'Maths marks were misread',
      ),
    );
    batches.add(
      status(
        'ex-admin',
        _admin,
        'reopen for correction',
        8,
        ExamEvent.reopened,
        ExamStatus.inProgress,
        extra: {'resultsWritten': 0, 'resultCount': 0},
        note: 'Correct the maths marks',
      ),
    );
    batches.add(
      sheetStep(
        'ex-admin',
        _admin,
        mathSheet,
        'return the maths sheet',
        4,
        SheetEvent.returned,
        SheetStatus.returned,
        ExamWrites.sheetReturn(4, 'ex-admin', 'Student 2 was present'),
        approvedCounter: 1,
        note: 'Student 2 was present',
      ),
    );
    final fixed2 = _entry(
      exam,
      'math',
      'ex-s2',
      MarkStatus.entered,
      marks: 40,
      revision: 1,
    );
    final correct2 = _Batch('ex-t1', 'enter the corrected marks');
    correct2.update(
      _p('marksEntries', fixed2.id),
      ExamWrites.entryUpdate(
        e: fixed2,
        components: false,
        revision: 2,
        uid: 'ex-t1',
      ),
    );
    correct2.set(
      _p('marksRevisions', '${fixed2.id}__2'),
      ExamWrites.entryRevision(
        e: fixed2,
        components: false,
        revision: 2,
        actor: _t1,
      ),
    );
    batches.add(correct2);
    batches.add(
      sheetStep(
        'ex-t1',
        _t1,
        mathSheet,
        'resubmit maths',
        5,
        SheetEvent.submitted,
        SheetStatus.submitted,
        ExamWrites.sheetSubmit(5, 'ex-t1'),
      ),
    );
    batches.add(
      sheetStep(
        'ex-admin',
        _admin,
        mathSheet,
        'approve maths again',
        6,
        SheetEvent.approved,
        SheetStatus.approved,
        ExamWrites.sheetApprove(6, 'ex-admin'),
        approvedCounter: 2,
      ),
    );
    batches.add(
      status(
        'ex-admin',
        _admin,
        'finalise (version 2)',
        9,
        ExamEvent.finalized,
        ExamStatus.completed,
        extra: {
          'resultVersion': 2,
          'resultCount': 2,
          'resultsWritten': 0,
          'schemeSnapshot': scheme.policyMap(),
          'finalizedBy': 'ex-admin',
        },
      ),
    );
    final v2 = Examination.fromFirestore({
      'schoolId': _school,
      'branchId': _branch,
      'academicYearId': 'y1',
      'classId': 'c5',
      'sectionId': 'sa',
      'name': 'Half-yearly examination',
      'schemeId': 'scheme-1',
      'startDateKey': '2026-09-01',
      'endDateKey': '2026-09-10',
      'status': 'COMPLETED',
      'resultVersion': 2,
    }, id);
    final written2 = _Batch('ex-admin', 'write version 2');
    for (final r in results) {
      written2.set(
        _p('resultSummaries', ResultSummary.idFor(id, r.studentId, 2)),
        ExamWrites.resultSummary(
          exam: v2,
          version: 2,
          result: r,
          schemeSnapshot: scheme.policyMap(),
          attendance: null,
          teacherRemark: '',
          principalRemark: 'Well done',
          classLabel: 'Class 5 – A',
          uid: 'ex-admin',
        ),
      );
    }
    batches.add(written2);
    final counter2 = _Batch('ex-admin', 'count version 2');
    counter2.update(
      _p('examinations', id),
      ExamWrites.counter('resultsWritten', 2, 'ex-admin'),
    );
    batches.add(counter2);
    final publish2 = status(
      'ex-admin',
      _admin,
      'publish (version 2)',
      10,
      ExamEvent.published,
      ExamStatus.published,
      extra: {
        'publishedBy': 'ex-admin',
        'publishedAt': FieldValue.serverTimestamp(),
      },
      note: 'Result version 2',
    );
    publish2.set(
      _p('broadcastNotices', ExamWrites.noticeId(id, 2)),
      ExamWrites.resultNotice(v2, 'ex-admin'),
    );
    batches.add(publish2);

    // ---- schemes ---------------------------------------------------------
    final schemeCreate = _Batch('ex-admin', 'create a grading scheme');
    schemeCreate.set(
      _p('gradingSchemes', 'scheme-1'),
      ExamWrites.schemeCreate(scheme, 'ex-admin'),
    );
    final schemeEdit = _Batch('ex-admin', 'edit the grading scheme');
    schemeEdit.update(
      _p('gradingSchemes', 'scheme-1'),
      ExamWrites.schemeUpdate(scheme, 2, 'ex-admin'),
    );

    final out = File('firestore-tests/fixtures/exam-write-plans.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'scenarios': [
          {
            'name': 'schemes',
            'batches': [schemeCreate.toJson(), schemeEdit.toJson()],
          },
          {
            'name':
                'examination lifecycle with marks, publication and correction',
            'batches': [for (final b in batches) b.toJson()],
          },
        ],
      }),
    );
    expect(batches.length, greaterThan(20));
  });
}
