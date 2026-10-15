import '../../announcements/domain/announcement.dart';
import '../../students/domain/paged_result.dart';
import 'file_attachment.dart';
import 'homework.dart';
import 'homework_enums.dart';
import 'homework_submission.dart';

class HomeworkActor {
  final String userId;
  final String name;
  final String role;

  const HomeworkActor({
    required this.userId,
    required this.name,
    required this.role,
  });
}

class HomeworkFilter {
  final String? classId;
  final String? sectionId;
  final String? subjectId;
  final String? teacherStaffId;
  final HomeworkStatus? status;

  const HomeworkFilter({
    this.classId,
    this.sectionId,
    this.subjectId,
    this.teacherStaffId,
    this.status,
  });
}

/// The submission counts of one homework, from aggregate queries.
class SubmissionCounts {
  final int submitted;
  final int late;
  final int awaitingReview;
  final int returned;
  final int graded;

  const SubmissionCounts({
    required this.submitted,
    required this.late,
    required this.awaitingReview,
    required this.returned,
    required this.graded,
  });

  /// Counted as handed in (see `HomeworkRules.countsAsComplete`).
  int get complete => submitted;
}

abstract class HomeworkRepository {
  /// Creates one DRAFT per section under a shared batch id. Idempotent: the
  /// ids are `{batchId}__{sectionId}`. Returns the created ids.
  Future<List<String>> createDrafts({
    required List<Homework> homework,
    required HomeworkActor actor,
  });

  Future<void> saveDraft({
    required Homework homework,
    required HomeworkActor actor,
  });

  /// DRAFT → PUBLISHED with its history record and broadcast notice in one
  /// commit. Idempotent: an already-published homework returns quietly.
  Future<void> publish({
    required Homework homework,
    required HomeworkActor actor,
  });

  /// Extends the deadline of a published homework (never shortens it).
  Future<void> changeDue({
    required Homework homework,
    required String dueDateKey,
    required int? dueTimeMin,
    required DateTime dueAt,
    required HomeworkActor actor,
  });

  Future<void> editPublished({
    required Homework homework,
    required String description,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  });

  Future<void> close({
    required Homework homework,
    required HomeworkActor actor,
  });

  Future<void> archive({
    required Homework homework,
    required HomeworkActor actor,
  });

  Stream<Homework?> watch(String schoolId, String branchId, String id);

  /// Paginated, newest first.
  Future<PagedResult<Homework>> fetch({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required HomeworkFilter filter,
    int pageSize = 25,
    Object? cursor,
  });

  /// What a family sees for a child's section (PUBLISHED and CLOSED).
  Future<List<Homework>> fetchForSection({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    int limit = 100,
  });

  Stream<List<HomeworkHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String homeworkId,
  );

  Future<int> countByStatus({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required HomeworkStatus status,
    String? teacherStaffId,
  });
}

abstract class SubmissionRepository {
  /// First submission by (or for) a child. Idempotent on the id: a retry of
  /// a commit that already happened returns quietly.
  Future<void> submit({
    required Homework homework,
    required String studentId,
    required String studentName,
    required String text,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  });

  Future<void> resubmit({
    required Homework homework,
    required HomeworkSubmission current,
    required String text,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  });

  Future<void> grade({
    required Homework homework,
    required HomeworkSubmission current,
    required int? marks,
    required String feedback,
    required HomeworkActor actor,
  });

  Future<void> returnForRevision({
    required Homework homework,
    required HomeworkSubmission current,
    required String feedback,
    required HomeworkActor actor,
  });

  Future<void> markReviewed({
    required Homework homework,
    required HomeworkSubmission current,
    required HomeworkActor actor,
  });

  Stream<HomeworkSubmission?> watch(
    String schoolId,
    String branchId,
    String submissionId,
  );

  /// Teacher review list, paginated, optionally filtered by status.
  Future<PagedResult<HomeworkSubmission>> fetchForHomework({
    required String schoolId,
    required String branchId,
    required String homeworkId,
    SubmissionStatus? status,
    int pageSize = 25,
    Object? cursor,
  });

  /// The submissions of up to 30 named students (one roster page), used to
  /// derive who has NOT submitted without loading the whole class.
  Future<List<HomeworkSubmission>> fetchForStudents({
    required String schoolId,
    required String branchId,
    required String homeworkId,
    required List<String> studentIds,
  });

  /// Every submission of one child in a year (for the family list).
  Future<List<HomeworkSubmission>> fetchForStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String academicYearId,
  });

  Stream<List<SubmissionRevision>> watchRevisions(
    String schoolId,
    String branchId,
    String submissionId,
  );

  Future<SubmissionCounts> counts({
    required String schoolId,
    required String branchId,
    required String homeworkId,
  });

  /// How many submissions of a teacher's homework await review (aggregate).
  Future<int> countAwaitingReview({
    required String schoolId,
    required String branchId,
    required String homeworkId,
  });
}

abstract class AnnouncementRepository {
  Future<void> saveDraft(
    Announcement announcement, {
    required HomeworkActor actor,
  });

  Future<void> publish(
    Announcement announcement, {
    required DateTime publishAt,
    required HomeworkActor actor,
  });

  Future<void> update(
    Announcement announcement, {
    required HomeworkActor actor,
    required bool notify,
  });

  Future<void> archive(
    Announcement announcement, {
    required HomeworkActor actor,
  });

  Stream<Announcement?> watch(String schoolId, String branchId, String id);

  /// Announcements the signed-in user's role may read in a branch (published
  /// ones for non-managers), newest first. Audience filtering by the
  /// reader's relationships is done with `AnnouncementVisibility`.
  Future<List<Announcement>> fetch({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    String? viewerUserId,
    String? viewerParentId,
    bool includeDrafts = false,
    int limit = 100,
  });

  Future<List<BroadcastNotice>> fetchNotices({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    String? viewerParentId,
    int limit = 50,
  });

  /// Live variant of [fetchNotices]: re-emits when a notice is published, so
  /// the bell and alerts react without a refresh.
  Stream<List<BroadcastNotice>> watchNotices({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    String? viewerParentId,
    int limit = 30,
  });
}

/// Upload and authorised download. There is no stored URL: a link is minted
/// when needed and only works if the Storage rules allow this caller.
abstract class HomeworkFileStore {
  Future<FileAttachment> upload({
    required String path,
    required String fileName,
    required List<int> bytes,
    required String uploadedBy,
  });

  Future<String> downloadUrl(String path);
}

abstract final class HomeworkPaths {
  static String homeworkFile(
    String schoolId,
    String branchId,
    String homeworkId,
    String file,
  ) => 'schools/$schoolId/branches/$branchId/homework/$homeworkId/files/$file';

  static String submissionFile(
    String schoolId,
    String branchId,
    String homeworkId,
    String studentId,
    String file,
  ) =>
      'schools/$schoolId/branches/$branchId/homework/$homeworkId/'
      'submissions/$studentId/$file';

  static String announcementFile(
    String schoolId,
    String branchId,
    String announcementId,
    String file,
  ) =>
      'schools/$schoolId/branches/$branchId/announcements/$announcementId/'
      'files/$file';
}
