import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../homework/data/homework_writes.dart';
import '../domain/exam_enums.dart';
import '../domain/exam_repositories.dart';
import '../domain/examination.dart';
import '../domain/grading_scheme.dart';
import '../domain/marks.dart';
import '../domain/result_calculator.dart';
import '../domain/result_summary.dart';

/// Every document the examination workflow writes, as a pure function. The
/// repositories apply them; `test/exams/exam_write_contract_test.dart` exports
/// the same maps and `firestore-tests/exam-contract.test.mjs` replays them
/// through the real rules.
abstract final class ExamWrites {
  static Map<String, dynamic> stamp(String uid) => {
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: uid,
  };

  static String historyId(String examId, int revision) =>
      '${examId}__$revision';

  static Map<String, dynamic> history({
    required Examination exam,
    required int revision,
    required ExamEvent event,
    required ExamStatus toStatus,
    required ExamActor actor,
    String? note,
  }) => {
    FirestoreFields.schoolId: exam.schoolId,
    FirestoreFields.branchId: exam.branchId,
    'academicYearId': exam.academicYearId,
    'examId': exam.examId,
    'classId': exam.classId,
    'revision': revision,
    'event': event.wireValue,
    'toStatus': toStatus.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'at': FieldValue.serverTimestamp(),
  };

  static Map<String, dynamic> examEdit(Examination e, int rev, String uid) => {
    ...e.body(),
    'revision': rev,
    'lastEvent': ExamEvent.edited.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> examStatus({
    required ExamStatus to,
    required ExamEvent event,
    required int revision,
    required String uid,
    Map<String, dynamic> extra = const {},
  }) => {
    FirestoreFields.status: to.wireValue,
    'revision': revision,
    'lastEvent': event.wireValue,
    ...extra,
    ...stamp(uid),
  };

  static Map<String, dynamic> counter(String field, int value, String uid) => {
    field: value,
    ...stamp(uid),
  };

  static Map<String, dynamic> subjectEdit(
    ExaminationSubject s,
    int revision,
    String uid,
  ) => {...s.body(), 'revision': revision, ...stamp(uid)};

  // ----------------------------------------------------------------- schemes
  static Map<String, dynamic> schemeCreate(GradingScheme s, String uid) => {
    FirestoreFields.schoolId: s.schoolId,
    FirestoreFields.branchId: s.branchId,
    ...s.body(),
    'revision': 1,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: uid,
    FirestoreFields.updatedBy: uid,
  };

  static Map<String, dynamic> schemeUpdate(
    GradingScheme s,
    int revision,
    String uid,
  ) => {...s.body(), 'revision': revision, ...stamp(uid)};

  // ------------------------------------------------------------------- marks
  static Map<String, dynamic> sheetCreate({
    required Examination exam,
    required String subjectId,
    required String sectionId,
    required int rosterCount,
    required String uid,
  }) => {
    FirestoreFields.schoolId: exam.schoolId,
    FirestoreFields.branchId: exam.branchId,
    'examId': exam.examId,
    'subjectId': subjectId,
    'sectionId': sectionId,
    'classId': exam.classId,
    'academicYearId': exam.academicYearId,
    FirestoreFields.status: SheetStatus.draft.wireValue,
    'revision': 1,
    'lastEvent': SheetEvent.saved.wireValue,
    'rosterCount': rosterCount,
    'submittedBy': null,
    'submittedAt': null,
    'approvedBy': null,
    'approvedAt': null,
    'reviewNote': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: uid,
    FirestoreFields.updatedBy: uid,
  };

  static String sheetHistoryId(String sheetId, int revision) =>
      '${sheetId}__$revision';

  static Map<String, dynamic> sheetHistory({
    required Examination exam,
    required String sheetId,
    required int revision,
    required SheetEvent event,
    required SheetStatus toStatus,
    required ExamActor actor,
    String? note,
  }) => {
    FirestoreFields.schoolId: exam.schoolId,
    FirestoreFields.branchId: exam.branchId,
    'examId': exam.examId,
    'sheetId': sheetId,
    'revision': revision,
    'event': event.wireValue,
    'toStatus': toStatus.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'at': FieldValue.serverTimestamp(),
  };

  static Map<String, dynamic> sheetSubmit(int revision, String uid) => {
    FirestoreFields.status: SheetStatus.submitted.wireValue,
    'submittedBy': uid,
    'submittedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': SheetEvent.submitted.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> sheetApprove(int revision, String uid) => {
    FirestoreFields.status: SheetStatus.approved.wireValue,
    'approvedBy': uid,
    'approvedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': SheetEvent.approved.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> sheetReturn(
    int revision,
    String uid,
    String note,
  ) => {
    FirestoreFields.status: SheetStatus.returned.wireValue,
    'reviewNote': note.trim(),
    'approvedBy': null,
    'approvedAt': null,
    'revision': revision,
    'lastEvent': SheetEvent.returned.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> entryCreate({
    required MarksEntry e,
    required bool components,
    required String uid,
  }) => {
    FirestoreFields.schoolId: e.schoolId,
    FirestoreFields.branchId: e.branchId,
    'examId': e.examId,
    'subjectId': e.subjectId,
    'sheetId': e.sheetId,
    'sectionId': e.sectionId,
    'classId': e.classId,
    'academicYearId': e.academicYearId,
    'studentId': e.studentId,
    'studentName': e.studentName,
    'rollNumber': e.rollNumber,
    ...e.body(components: components),
    'revision': 1,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: uid,
    FirestoreFields.updatedBy: uid,
  };

  static Map<String, dynamic> entryUpdate({
    required MarksEntry e,
    required bool components,
    required int revision,
    required String uid,
  }) => {
    ...e.body(components: components),
    'revision': revision,
    ...stamp(uid),
  };

  static Map<String, dynamic> entryRevision({
    required MarksEntry e,
    required bool components,
    required int revision,
    required ExamActor actor,
  }) {
    final body = e.body(components: components);
    return {
      FirestoreFields.schoolId: e.schoolId,
      FirestoreFields.branchId: e.branchId,
      'examId': e.examId,
      'subjectId': e.subjectId,
      'entryId': e.id,
      'studentId': e.studentId,
      'revision': revision,
      FirestoreFields.status: body[FirestoreFields.status],
      'marks': body['marks'],
      'remark': body['remark'],
      'actorId': actor.userId,
      'actorName': actor.name,
      'at': FieldValue.serverTimestamp(),
    };
  }

  // ----------------------------------------------------------------- results
  static Map<String, dynamic> remark({
    required Examination exam,
    required String studentId,
    required String sectionId,
    required String teacherRemark,
    required String principalRemark,
    required String uid,
  }) => {
    FirestoreFields.schoolId: exam.schoolId,
    FirestoreFields.branchId: exam.branchId,
    'examId': exam.examId,
    'academicYearId': exam.academicYearId,
    'classId': exam.classId,
    'sectionId': sectionId,
    'studentId': studentId,
    'teacherRemark': teacherRemark.trim(),
    'principalRemark': principalRemark.trim(),
    ...stamp(uid),
  };

  static Map<String, dynamic> resultSummary({
    required Examination exam,
    required int version,
    required StudentResult result,
    required Map<String, dynamic> schemeSnapshot,
    required AttendanceSnapshot? attendance,
    required String teacherRemark,
    required String principalRemark,
    required String classLabel,
    required String uid,
  }) => {
    FirestoreFields.schoolId: exam.schoolId,
    FirestoreFields.branchId: exam.branchId,
    'examId': exam.examId,
    'examName': exam.name,
    'studentId': result.studentId,
    'studentName': result.studentName,
    'version': version,
    'academicYearId': exam.academicYearId,
    'classId': exam.classId,
    'sectionId': result.sectionId,
    'classLabel': classLabel,
    FirestoreFields.status: 'FINAL',
    'summary': result.toMap(),
    'schemeSnapshot': schemeSnapshot,
    'attendance': attendance?.toMap(),
    'teacherRemark': teacherRemark.trim(),
    'principalRemark': principalRemark.trim(),
    'calculatedBy': uid,
    'calculatedAt': FieldValue.serverTimestamp(),
  };

  static String noticeId(String examId, int version) =>
      HomeworkWrites.noticeId(examId, 'PUBLISHED', version);

  static Map<String, dynamic> resultNotice(Examination exam, String uid) =>
      HomeworkWrites.broadcastNotice(
        schoolId: exam.schoolId,
        branchId: exam.branchId,
        type: 'RESULT_PUBLISHED',
        audienceKind: exam.sectionId == null ? 'CLASS' : 'SECTION',
        classId: exam.classId,
        sectionId: exam.sectionId,
        title: 'Results published',
        body: exam.name,
        refType: 'EXAM',
        refId: exam.examId,
        revision: exam.resultVersion,
        createdBy: uid,
      );
}
