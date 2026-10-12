import '../../students/domain/paged_result.dart';
import 'examination.dart';
import 'exam_enums.dart';
import 'grading_scheme.dart';
import 'marks.dart';
import 'result_calculator.dart';
import 'result_summary.dart';

class ExamActor {
  final String userId;
  final String name;
  final String role;

  const ExamActor({
    required this.userId,
    required this.name,
    required this.role,
  });

  bool get isSchoolAdmin => role == 'SCHOOL_ADMIN' || role == 'PLATFORM_ADMIN';
}

abstract class GradingSchemeRepository {
  Stream<List<GradingScheme>> watch(String schoolId, String branchId);

  Future<GradingScheme?> fetch(
    String schoolId,
    String branchId,
    String schemeId,
  );

  /// Creates (empty id) or updates. Editing never changes a finalised
  /// result: those carry their own snapshot.
  Future<String> save(GradingScheme scheme, {required ExamActor actor});
}

abstract class ExamRepository {
  Future<PagedResult<Examination>> fetch({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    String? classId,
    ExamStatus? status,
    int pageSize = 25,
    Object? cursor,
  });

  Stream<Examination?> watch(String schoolId, String branchId, String examId);

  Stream<List<ExaminationSubject>> watchSubjects(
    String schoolId,
    String branchId,
    String examId,
  );

  Future<void> create(Examination exam, {required ExamActor actor});

  Future<void> update(Examination exam, {required ExamActor actor});

  /// Adds or changes a subject (only while the exam is configurable).
  Future<void> saveSubject(
    Examination exam,
    ExaminationSubject subject, {
    required bool isNew,
    required ExamActor actor,
  });

  Future<void> removeSubject(
    Examination exam,
    ExaminationSubject subject, {
    required ExamActor actor,
  });

  Future<void> schedule(Examination exam, {required ExamActor actor});

  Future<void> startMarksEntry(
    Examination exam, {
    required int sheetCount,
    required ExamActor actor,
  });

  Future<void> cancel(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  });

  Future<void> withdraw(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  });

  Future<void> reopen(
    Examination exam, {
    required String reason,
    required ExamActor actor,
  });

  Future<List<ExamAuditEntry>> fetchAudit(
    String schoolId,
    String branchId,
    String examId,
  );
}

abstract class MarksRepository {
  Future<MarksSheet?> fetchSheet(
    Examination exam,
    String subjectId,
    String sectionId,
  );

  Future<List<MarksSheet>> fetchSheets(Examination exam);

  /// Stored entries of one sheet.
  Future<List<MarksEntry>> fetchEntries(
    Examination exam,
    String subjectId,
    String sectionId,
  );

  /// Every stored entry of the examination (managers only; paged inside).
  Future<List<MarksEntry>> fetchAllEntries(Examination exam);

  /// Saves the changed entries (creating the sheet on first save), each with
  /// its revision record. Returns how many were written.
  Future<int> saveEntries({
    required Examination exam,
    required ExaminationSubject subject,
    required String sectionId,
    required List<MarksEntry> changed,
    required int rosterCount,
    required ExamActor actor,
  });

  Future<void> submitSheet({
    required Examination exam,
    required MarksSheet sheet,
    required ExamActor actor,
  });

  Future<void> approveSheet({
    required Examination exam,
    required MarksSheet sheet,
    required ExamActor actor,
  });

  Future<void> returnSheet({
    required Examination exam,
    required MarksSheet sheet,
    required String note,
    required ExamActor actor,
  });
}

abstract class ResultRepository {
  /// Remarks typed before finalisation, by student.
  Future<Map<String, ExamRemark>> fetchRemarks(Examination exam);

  Future<void> saveRemark({
    required Examination exam,
    required ExamRemark remark,
    required String sectionId,
    required ExamActor actor,
    required bool principal,
  });

  /// Moves the examination to COMPLETED with the scheme snapshot and the next
  /// result version, then writes the results (idempotent: existing ones are
  /// kept). Returns the new version.
  Future<int> finalize({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required Map<String, String> classLabels,
    required ExamActor actor,
  });

  /// Writes any result of the current version not yet stored (after an
  /// interrupted finalisation) and updates the written counter.
  Future<void> completeResults({
    required Examination exam,
    required GradingScheme scheme,
    required List<StudentResult> results,
    required Map<String, AttendanceSnapshot?> attendance,
    required Map<String, ExamRemark> remarks,
    required String classLabel,
    required ExamActor actor,
  });

  Future<void> publish(Examination exam, {required ExamActor actor});

  Future<PagedResult<ResultSummary>> fetchResults({
    required Examination exam,
    int pageSize = 50,
    Object? cursor,
  });

  /// One student's result of the version in force (parents' read path).
  Future<ResultSummary?> fetchResult({
    required String schoolId,
    required String branchId,
    required String examId,
    required String studentId,
    required int version,
  });

  /// Published examinations of a class (what a family may open).
  Future<List<Examination>> fetchPublishedForClass({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
  });
}
