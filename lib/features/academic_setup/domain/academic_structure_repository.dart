import 'academic_year.dart';
import 'class_subject_link.dart';
import 'school_class.dart';
import 'section.dart';
import 'subject.dart';

/// Boundary for academic years, classes, sections, subjects, and the
/// class-subject relationship — all scoped to a `schoolId`/`branchId`
/// (and, below academic year, an `academicYearId`). Throws an
/// `AppFailure` (via error_mapper) on failure.
abstract class AcademicStructureRepository {
  Stream<List<AcademicYear>> watchAcademicYears(
    String schoolId,
    String branchId,
  );

  Future<AcademicYear?> getAcademicYear(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  Future<void> updateAcademicYear(
    AcademicYear year, {
    required String updatedBy,
  });

  Stream<List<SchoolClass>> watchClasses(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  /// Throws a [ValidationFailure] on a duplicate name/code within the
  /// same branch + academic year.
  Future<String> createClass(
    SchoolClass schoolClass, {
    required String createdBy,
  });

  Future<void> updateClass(
    SchoolClass schoolClass, {
    required String updatedBy,
  });

  /// Persists a new relative order for classes already known to exist —
  /// see `AcademicSetupRepository` callers for how drag-reordered UI state
  /// becomes this call.
  Future<void> reorderClasses(
    List<SchoolClass> classesInNewOrder, {
    required String updatedBy,
  });

  Stream<List<Section>> watchSections(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
  );

  /// Throws a [ValidationFailure] on a duplicate name within the same class.
  Future<String> createSection(Section section, {required String createdBy});

  Future<void> updateSection(Section section, {required String updatedBy});

  Stream<List<Subject>> watchSubjects(
    String schoolId,
    String branchId,
    String academicYearId,
  );

  /// Throws a [ValidationFailure] on a duplicate name/code within the
  /// same branch + academic year.
  Future<String> createSubject(Subject subject, {required String createdBy});

  Future<void> updateSubject(Subject subject, {required String updatedBy});

  Stream<List<ClassSubjectLink>> watchClassSubjects(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
  );

  Future<void> linkSubjectToClass(
    ClassSubjectLink link, {
    required String createdBy,
  });

  Future<void> unlinkSubjectFromClass(
    String schoolId,
    String branchId,
    String academicYearId,
    String classId,
    String subjectId,
  );
}
