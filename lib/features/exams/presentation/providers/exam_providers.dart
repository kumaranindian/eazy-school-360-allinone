import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../students/domain/student.dart';
import '../../../students/domain/student_status.dart';
import '../../../students/presentation/providers/student_providers.dart';
import '../../../users/presentation/providers/user_providers.dart';
import '../../data/firebase_exam_repositories.dart';
import '../../data/result_access_probe.dart';
import '../../domain/exam_repositories.dart';
import '../../domain/examination.dart';
import '../../domain/grading_scheme.dart';
import '../../domain/marks.dart';
import '../../domain/result_calculator.dart';
import '../../domain/result_summary.dart';

final gradingSchemeRepositoryProvider = Provider<GradingSchemeRepository>(
  (ref) => FirebaseGradingSchemeRepository(ref.watch(firestoreProvider)),
);
final examRepositoryProvider = Provider<ExamRepository>(
  (ref) => FirebaseExamRepository(ref.watch(firestoreProvider)),
);
final marksRepositoryProvider = Provider<MarksRepository>(
  (ref) => FirebaseMarksRepository(ref.watch(firestoreProvider)),
);
final resultRepositoryProvider = Provider<ResultRepository>(
  (ref) => FirebaseResultRepository(ref.watch(firestoreProvider)),
);

ExamActor examActorFor(TenantContext tenant) => ExamActor(
  userId: tenant.user.userId,
  name: tenant.user.name,
  role: tenant.role.wireValue,
);

typedef ExamKey = ({String schoolId, String branchId, String examId});
typedef SchemesKey = ({String schoolId, String branchId});

final schemesProvider = StreamProvider.autoDispose
    .family<List<GradingScheme>, SchemesKey>((ref, key) {
      return ref
          .watch(gradingSchemeRepositoryProvider)
          .watch(key.schoolId, key.branchId);
    });

final examProvider = StreamProvider.autoDispose.family<Examination?, ExamKey>((
  ref,
  key,
) {
  return ref
      .watch(examRepositoryProvider)
      .watch(key.schoolId, key.branchId, key.examId);
});

final examSubjectsProvider = StreamProvider.autoDispose
    .family<List<ExaminationSubject>, ExamKey>((ref, key) {
      return ref
          .watch(examRepositoryProvider)
          .watchSubjects(key.schoolId, key.branchId, key.examId);
    });

final examAuditProvider = FutureProvider.autoDispose
    .family<List<ExamAuditEntry>, ExamKey>((ref, key) {
      return ref
          .watch(examRepositoryProvider)
          .fetchAudit(key.schoolId, key.branchId, key.examId);
    });

/// The ACTIVE students the examination covers, from current placement.
Future<List<Student>> loadRoster(
  Ref ref,
  Examination exam, {
  String? onlySection,
}) async {
  final repo = ref.read(studentRepositoryProvider);
  final out = <Student>[];
  Object? cursor;
  do {
    final page = await repo.fetchStudentsByPlacement(
      schoolId: exam.schoolId,
      branchId: exam.branchId,
      academicYearId: exam.academicYearId,
      classId: exam.classId,
      sectionId: onlySection ?? exam.sectionId,
      pageSize: 100,
      cursor: cursor,
    );
    out.addAll(page.items.where((s) => s.status == StudentStatus.active));
    cursor = page.nextCursor;
  } while (cursor != null);
  out.sort((a, b) {
    final ra = int.tryParse(a.currentRollNumber ?? '');
    final rb = int.tryParse(b.currentRollNumber ?? '');
    if (ra != null && rb != null && ra != rb) return ra.compareTo(rb);
    return a.displayName.compareTo(b.displayName);
  });
  return out;
}

/// A result computed *now* from stored marks: always provisional until the
/// examination is finalised.
class ProvisionalResults {
  final Examination exam;
  final GradingScheme scheme;
  final List<ExaminationSubject> subjects;
  final List<Student> roster;
  final List<StudentResult> results;

  const ProvisionalResults({
    required this.exam,
    required this.scheme,
    required this.subjects,
    required this.roster,
    required this.results,
  });

  int get incomplete => results.where((r) => !r.isComplete).length;
}

final provisionalResultsProvider = FutureProvider.autoDispose
    .family<ProvisionalResults, ExamKey>((ref, key) async {
      final exam = await ref.watch(examProvider(key).future);
      if (exam == null) throw StateError('Examination not found');
      final subjects = await ref.watch(examSubjectsProvider(key).future);
      final scheme = exam.schemeSnapshot != null && exam.resultVersion > 0
          ? GradingScheme.fromSnapshot(exam.schemeSnapshot!)
          : await ref
                .read(gradingSchemeRepositoryProvider)
                .fetch(exam.schoolId, exam.branchId, exam.schemeId);
      if (scheme == null) {
        throw StateError('The grading scheme of this examination is missing.');
      }
      final roster = await loadRoster(ref, exam);
      final entries = await ref
          .read(marksRepositoryProvider)
          .fetchAllEntries(exam);
      final bySubjectStudent = <String, MarksEntry>{
        for (final e in entries) '${e.subjectId}__${e.studentId}': e,
      };
      var results = [
        for (final s in roster)
          ResultCalculator.calculate(
            scheme: scheme,
            subjects: subjects,
            entries: {
              for (final sub in subjects)
                sub.subjectId:
                    bySubjectStudent['${sub.subjectId}__${s.studentId}'],
            },
            studentId: s.studentId,
            studentName: s.displayName,
            admissionNumber: s.admissionNumber,
            rollNumber: s.currentRollNumber,
            sectionId: s.currentSectionId ?? '',
          ),
      ];
      if (scheme.rankingEnabled) {
        results = ResultCalculator.assignRanks(results);
      }
      return ProvisionalResults(
        exam: exam,
        scheme: scheme,
        subjects: subjects,
        roster: roster,
        results: results,
      );
    });

/// The stored results of the version in force (paged internally).
final storedResultsProvider = FutureProvider.autoDispose
    .family<List<ResultSummary>, ExamKey>((ref, key) async {
      final exam = await ref.watch(examProvider(key).future);
      if (exam == null || exam.resultVersion == 0) return const [];
      final repo = ref.read(resultRepositoryProvider);
      final out = <ResultSummary>[];
      Object? cursor;
      do {
        final page = await repo.fetchResults(exam: exam, cursor: cursor);
        out.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      return out;
    });

typedef ChildResultKey = ({
  String schoolId,
  String branchId,
  String examId,
  String studentId,
  int version,
});

final childResultProvider = FutureProvider.autoDispose
    .family<ResultSummary?, ChildResultKey>((ref, key) {
      return ref
          .read(resultRepositoryProvider)
          .fetchResult(
            schoolId: key.schoolId,
            branchId: key.branchId,
            examId: key.examId,
            studentId: key.studentId,
            version: key.version,
          );
    });

typedef ClassExamsKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String classId,
  String? sectionId,
});

final publishedExamsProvider = FutureProvider.autoDispose
    .family<List<Examination>, ClassExamsKey>((ref, key) async {
      try {
        return await ref
            .read(resultRepositoryProvider)
            .fetchPublishedForClass(
              schoolId: key.schoolId,
              branchId: key.branchId,
              academicYearId: key.academicYearId,
              classId: key.classId,
              sectionId: key.sectionId,
            );
      } on PermissionFailure {
        // Only after a refusal: log why, to the console, then report as usual.
        try {
          await ResultAccessProbe(ref.read(firestoreProvider)).run(
            schoolId: key.schoolId,
            branchId: key.branchId,
            parentId: ref
                .read(tenantContextProvider)
                .value
                ?.user
                .linkedParentId,
            academicYearId: key.academicYearId,
            classId: key.classId,
            sectionId: key.sectionId,
          );
        } catch (_) {
          // A diagnostic must never replace the real error.
        }
        rethrow;
      }
    });

typedef SectionRosterKey = ({ExamKey exam, String sectionId});

/// The ACTIVE students of one section of the examination's class.
final sectionRosterProvider = FutureProvider.autoDispose
    .family<List<Student>, SectionRosterKey>((ref, key) async {
      final exam = await ref.watch(examProvider(key.exam).future);
      if (exam == null) return const [];
      return loadRoster(ref, exam, onlySection: key.sectionId);
    });

typedef SheetEntriesKey = ({ExamKey exam, String subjectId, String sectionId});

/// Stored entries of one marks sheet and the sheet itself.
class SheetData {
  final MarksSheet? sheet;
  final List<MarksEntry> entries;

  const SheetData(this.sheet, this.entries);
}

final sheetDataProvider = FutureProvider.autoDispose
    .family<SheetData, SheetEntriesKey>((ref, key) async {
      final exam = await ref.watch(examProvider(key.exam).future);
      if (exam == null) return const SheetData(null, []);
      final repo = ref.read(marksRepositoryProvider);
      final sheet = await repo.fetchSheet(exam, key.subjectId, key.sectionId);
      final entries = sheet == null
          ? const <MarksEntry>[]
          : await repo.fetchEntries(exam, key.subjectId, key.sectionId);
      return SheetData(sheet, entries);
    });

final examRemarksProvider = FutureProvider.autoDispose
    .family<Map<String, ExamRemark>, ExamKey>((ref, key) async {
      final exam = await ref.watch(examProvider(key).future);
      if (exam == null) return const {};
      return ref.read(resultRepositoryProvider).fetchRemarks(exam);
    });

final examSheetsProvider = FutureProvider.autoDispose
    .family<List<MarksSheet>, ExamKey>((ref, key) async {
      final exam = await ref.watch(examProvider(key).future);
      if (exam == null) return const [];
      return ref.read(marksRepositoryProvider).fetchSheets(exam);
    });
