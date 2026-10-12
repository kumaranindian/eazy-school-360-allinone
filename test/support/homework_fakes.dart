import 'dart:async';

import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/announcements/domain/announcement.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';
import 'package:eazy_school_360/features/homework/domain/homework.dart';
import 'package:eazy_school_360/features/homework/domain/homework_enums.dart';
import 'package:eazy_school_360/features/homework/domain/homework_repositories.dart';
import 'package:eazy_school_360/features/homework/domain/homework_rules.dart';
import 'package:eazy_school_360/features/homework/domain/homework_submission.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_repository.dart';

/// An in-memory homework store that applies the same domain rules the real
/// repository does (publish needs a draft and a future deadline; a deadline
/// can only be extended) so UI tests exercise real behaviour.
class FakeHomeworkRepository implements HomeworkRepository {
  final Map<String, Homework> docs = {};
  final List<List<Homework>> createdBatches = [];
  final List<String> published = [];
  final List<String> closed = [];
  final List<String> archived = [];
  final List<({String id, DateTime dueAt})> dueChanges = [];
  Object? publishError;

  FakeHomeworkRepository({List<Homework> homework = const []}) {
    for (final h in homework) {
      docs[h.homeworkId] = h;
    }
  }

  @override
  Future<List<String>> createDrafts({
    required List<Homework> homework,
    required HomeworkActor actor,
  }) async {
    createdBatches.add(homework);
    for (final h in homework) {
      docs.putIfAbsent(h.homeworkId, () => h);
    }
    return [for (final h in homework) h.homeworkId];
  }

  @override
  Future<void> saveDraft({
    required Homework homework,
    required HomeworkActor actor,
  }) async {
    final current = docs[homework.homeworkId];
    if (current == null) throw const NotFoundFailure('missing');
    if (current.status != HomeworkStatus.draft) {
      throw const ConflictFailure('Only a draft can be edited.');
    }
    docs[homework.homeworkId] = homework.copyWith(
      status: HomeworkStatus.draft,
      revision: current.revision + 1,
    );
  }

  @override
  Future<void> publish({
    required Homework homework,
    required HomeworkActor actor,
  }) async {
    if (publishError != null) throw publishError!;
    final h = docs[homework.homeworkId];
    if (h == null) throw const NotFoundFailure('missing');
    if (h.status != HomeworkStatus.draft) return;
    final problem = HomeworkRules.checkPublish(h, now: DateTime.now());
    if (problem != null) throw ConflictFailure(problem);
    docs[h.homeworkId] = h.copyWith(
      status: HomeworkStatus.published,
      revision: h.revision + 1,
    );
    published.add(h.homeworkId);
  }

  @override
  Future<void> changeDue({
    required Homework homework,
    required String dueDateKey,
    required int? dueTimeMin,
    required DateTime dueAt,
    required HomeworkActor actor,
  }) async {
    final h = docs[homework.homeworkId]!;
    final problem = HomeworkRules.checkDueChange(h, dueAt);
    if (problem != null) throw ConflictFailure(problem);
    docs[h.homeworkId] = h.copyWith(
      dueDateKey: dueDateKey,
      dueTimeMin: dueTimeMin,
      clearDueTime: dueTimeMin == null,
      dueAt: dueAt,
      revision: h.revision + 1,
    );
    dueChanges.add((id: h.homeworkId, dueAt: dueAt));
  }

  @override
  Future<void> editPublished({
    required Homework homework,
    required String description,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  }) async {
    final h = docs[homework.homeworkId]!;
    docs[h.homeworkId] = h.copyWith(
      description: description,
      attachments: attachments,
      revision: h.revision + 1,
    );
  }

  @override
  Future<void> close({
    required Homework homework,
    required HomeworkActor actor,
  }) async {
    final h = docs[homework.homeworkId]!;
    docs[h.homeworkId] = h.copyWith(
      status: HomeworkStatus.closed,
      revision: h.revision + 1,
    );
    closed.add(h.homeworkId);
  }

  @override
  Future<void> archive({
    required Homework homework,
    required HomeworkActor actor,
  }) async {
    final h = docs[homework.homeworkId]!;
    docs[h.homeworkId] = h.copyWith(
      status: HomeworkStatus.archived,
      revision: h.revision + 1,
    );
    archived.add(h.homeworkId);
  }

  @override
  Stream<Homework?> watch(String schoolId, String branchId, String id) =>
      Stream.value(docs[id]);

  @override
  Future<PagedResult<Homework>> fetch({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required HomeworkFilter filter,
    int pageSize = 25,
    Object? cursor,
  }) async {
    final all = [
      for (final h in docs.values)
        if (h.academicYearId == academicYearId &&
            (filter.teacherStaffId == null ||
                h.teacherStaffId == filter.teacherStaffId) &&
            (filter.classId == null || h.classId == filter.classId) &&
            (filter.sectionId == null || h.sectionId == filter.sectionId) &&
            (filter.subjectId == null || h.subjectId == filter.subjectId) &&
            (filter.status == null || h.status == filter.status))
          h,
    ]..sort((a, b) => b.dueDateKey.compareTo(a.dueDateKey));
    final start = cursor as int? ?? 0;
    final page = all.skip(start).take(pageSize).toList();
    final next = start + pageSize;
    return PagedResult(
      items: page,
      nextCursor: next < all.length ? next : null,
    );
  }

  @override
  Future<List<Homework>> fetchForSection({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    int limit = 100,
  }) async => [
    for (final h in docs.values)
      if (h.classId == classId &&
          h.sectionId == sectionId &&
          h.academicYearId == academicYearId &&
          h.status.isVisibleToFamilies)
        h,
  ];

  @override
  Stream<List<HomeworkHistoryEntry>> watchHistory(
    String schoolId,
    String branchId,
    String homeworkId,
  ) => Stream.value(const []);

  @override
  Future<int> countByStatus({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required HomeworkStatus status,
    String? teacherStaffId,
  }) async => docs.values
      .where(
        (h) =>
            h.status == status &&
            (teacherStaffId == null || h.teacherStaffId == teacherStaffId),
      )
      .length;
}

class FakeSubmissionRepository implements SubmissionRepository {
  final Map<String, HomeworkSubmission> docs = {};
  final Map<String, List<SubmissionRevision>> revisions = {};
  final List<String> submitted = [];
  final List<String> graded = [];
  final List<String> returned = [];
  Object? submitError;
  final _changes = StreamController<String>.broadcast();

  FakeSubmissionRepository({List<HomeworkSubmission> submissions = const []}) {
    for (final s in submissions) {
      docs[s.submissionId] = s;
    }
  }

  void _revision(
    HomeworkSubmission s,
    SubmissionEvent event,
    HomeworkActor actor,
  ) {
    revisions
        .putIfAbsent(s.submissionId, () => [])
        .add(
          SubmissionRevision(
            submissionId: s.submissionId,
            revision: s.revision,
            event: event,
            status: s.status,
            textAnswer: s.textAnswer,
            attachments: s.attachments,
            feedback: s.feedback,
            marks: s.marks,
            actorId: actor.userId,
            actorName: actor.name,
            actorRole: actor.role,
            at: DateTime.now(),
          ),
        );
    _changes.add(s.submissionId);
  }

  @override
  Future<void> submit({
    required Homework homework,
    required String studentId,
    required String studentName,
    required String text,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  }) async {
    if (submitError != null) throw submitError!;
    final decision = HomeworkRules.checkSubmit(
      homework: homework,
      now: DateTime.now(),
    );
    if (decision.error != null) throw ValidationFailure(decision.error!);
    final id = HomeworkSubmission.idFor(homework.homeworkId, studentId);
    if (docs.containsKey(id)) return; // idempotent on the id
    final s = HomeworkSubmission(
      submissionId: id,
      homeworkId: homework.homeworkId,
      studentId: studentId,
      studentName: studentName,
      schoolId: homework.schoolId,
      branchId: homework.branchId,
      academicYearId: homework.academicYearId,
      classId: homework.classId,
      sectionId: homework.sectionId,
      status: decision.status!,
      textAnswer: text.trim(),
      attachments: attachments,
      late: decision.status == SubmissionStatus.lateSubmitted,
      submittedBy: actor.userId,
      submittedAt: DateTime.now(),
    );
    docs[id] = s;
    submitted.add(id);
    _revision(s, SubmissionEvent.submit, actor);
  }

  HomeworkSubmission _copy(
    HomeworkSubmission s, {
    SubmissionStatus? status,
    String? text,
    List<FileAttachment>? attachments,
    String? feedback,
    int? marks,
    bool clearMarks = false,
    String? gradedByName,
    String? reviewedBy,
    bool? late,
  }) => HomeworkSubmission(
    submissionId: s.submissionId,
    homeworkId: s.homeworkId,
    studentId: s.studentId,
    studentName: s.studentName,
    schoolId: s.schoolId,
    branchId: s.branchId,
    academicYearId: s.academicYearId,
    classId: s.classId,
    sectionId: s.sectionId,
    status: status ?? s.status,
    textAnswer: text ?? s.textAnswer,
    attachments: attachments ?? s.attachments,
    revision: s.revision + 1,
    late: late ?? s.late,
    submittedBy: s.submittedBy,
    submittedAt: s.submittedAt,
    feedback: feedback ?? s.feedback,
    marks: clearMarks ? null : (marks ?? s.marks),
    gradedBy: s.gradedBy,
    gradedByName: gradedByName ?? s.gradedByName,
    gradedAt: s.gradedAt,
    reviewedBy: reviewedBy ?? s.reviewedBy,
    reviewedAt: s.reviewedAt,
  );

  @override
  Future<void> resubmit({
    required Homework homework,
    required HomeworkSubmission current,
    required String text,
    required List<FileAttachment> attachments,
    required HomeworkActor actor,
  }) async {
    final decision = HomeworkRules.checkResubmit(
      homework: homework,
      current: docs[current.submissionId]!,
      now: DateTime.now(),
    );
    if (decision.error != null) throw ValidationFailure(decision.error!);
    final s = _copy(
      docs[current.submissionId]!,
      status: SubmissionStatus.resubmitted,
      text: text.trim(),
      attachments: attachments,
      late: current.late || homework.isPastDue(DateTime.now()),
    );
    docs[s.submissionId] = s;
    _revision(s, SubmissionEvent.resubmit, actor);
  }

  @override
  Future<void> grade({
    required Homework homework,
    required HomeworkSubmission current,
    required int? marks,
    required String feedback,
    required HomeworkActor actor,
  }) async {
    final fresh = docs[current.submissionId]!;
    final problem = HomeworkRules.checkGrade(
      homework: homework,
      submission: fresh,
      marks: marks,
      feedback: feedback,
    );
    if (problem != null) throw ValidationFailure(problem);
    final s = _copy(
      fresh,
      status: SubmissionStatus.graded,
      marks: marks,
      feedback: feedback.trim(),
      gradedByName: actor.name,
    );
    docs[s.submissionId] = s;
    graded.add(s.submissionId);
    _revision(s, SubmissionEvent.grade, actor);
  }

  @override
  Future<void> returnForRevision({
    required Homework homework,
    required HomeworkSubmission current,
    required String feedback,
    required HomeworkActor actor,
  }) async {
    final fresh = docs[current.submissionId]!;
    final problem = HomeworkRules.checkReturn(
      submission: fresh,
      feedback: feedback,
    );
    if (problem != null) throw ValidationFailure(problem);
    final s = _copy(
      fresh,
      status: SubmissionStatus.returnedForRevision,
      feedback: feedback.trim(),
      clearMarks: true,
    );
    docs[s.submissionId] = s;
    returned.add(s.submissionId);
    _revision(s, SubmissionEvent.returnForRevision, actor);
  }

  @override
  Future<void> markReviewed({
    required Homework homework,
    required HomeworkSubmission current,
    required HomeworkActor actor,
  }) async {
    final s = _copy(docs[current.submissionId]!, reviewedBy: actor.userId);
    docs[s.submissionId] = s;
    _revision(s, SubmissionEvent.review, actor);
  }

  @override
  Stream<HomeworkSubmission?> watch(
    String schoolId,
    String branchId,
    String submissionId,
  ) async* {
    yield docs[submissionId];
    yield* _changes.stream
        .where((id) => id == submissionId)
        .map((_) => docs[submissionId]);
  }

  @override
  Future<PagedResult<HomeworkSubmission>> fetchForHomework({
    required String schoolId,
    required String branchId,
    required String homeworkId,
    SubmissionStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    final all = [
      for (final s in docs.values)
        if (s.homeworkId == homeworkId &&
            (status == null || s.status == status))
          s,
    ]..sort((a, b) => a.studentName.compareTo(b.studentName));
    final start = cursor as int? ?? 0;
    final next = start + pageSize;
    return PagedResult(
      items: all.skip(start).take(pageSize).toList(),
      nextCursor: next < all.length ? next : null,
    );
  }

  @override
  Future<List<HomeworkSubmission>> fetchForStudents({
    required String schoolId,
    required String branchId,
    required String homeworkId,
    required List<String> studentIds,
  }) async => [
    for (final s in docs.values)
      if (s.homeworkId == homeworkId && studentIds.contains(s.studentId)) s,
  ];

  @override
  Future<List<HomeworkSubmission>> fetchForStudent({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String academicYearId,
  }) async => [
    for (final s in docs.values)
      if (s.studentId == studentId && s.academicYearId == academicYearId) s,
  ];

  @override
  Stream<List<SubmissionRevision>> watchRevisions(
    String schoolId,
    String branchId,
    String submissionId,
  ) async* {
    yield revisions[submissionId] ?? const [];
    yield* _changes.stream
        .where((id) => id == submissionId)
        .map((_) => revisions[submissionId] ?? const []);
  }

  @override
  Future<SubmissionCounts> counts({
    required String schoolId,
    required String branchId,
    required String homeworkId,
  }) async {
    final mine = docs.values.where((s) => s.homeworkId == homeworkId).toList();
    int n(bool Function(HomeworkSubmission) t) => mine.where(t).length;
    return SubmissionCounts(
      submitted: n((s) => HomeworkRules.countsAsComplete(s.status)),
      late: n((s) => s.late),
      awaitingReview: await countAwaitingReview(
        schoolId: schoolId,
        branchId: branchId,
        homeworkId: homeworkId,
      ),
      returned: n((s) => s.status == SubmissionStatus.returnedForRevision),
      graded: n((s) => s.status == SubmissionStatus.graded),
    );
  }

  @override
  Future<int> countAwaitingReview({
    required String schoolId,
    required String branchId,
    required String homeworkId,
  }) async => docs.values
      .where(
        (s) =>
            s.homeworkId == homeworkId &&
            (s.status == SubmissionStatus.resubmitted ||
                ((s.status == SubmissionStatus.submitted ||
                        s.status == SubmissionStatus.lateSubmitted) &&
                    s.reviewedBy == null)),
      )
      .length;
}

class FakeAnnouncementRepository implements AnnouncementRepository {
  final Map<String, Announcement> docs = {};
  final List<String> published = [];
  final List<String> archivedIds = [];
  final List<Announcement> drafts = [];
  List<BroadcastNotice> notices;

  FakeAnnouncementRepository({
    List<Announcement> announcements = const [],
    this.notices = const [],
  }) {
    for (final a in announcements) {
      docs[a.announcementId] = a;
    }
  }

  @override
  Future<void> saveDraft(
    Announcement announcement, {
    required HomeworkActor actor,
  }) async {
    docs[announcement.announcementId] = announcement;
    drafts.add(announcement);
  }

  @override
  Future<void> publish(
    Announcement announcement, {
    required DateTime publishAt,
    required HomeworkActor actor,
  }) async {
    final a = docs[announcement.announcementId] ?? announcement;
    if (a.status != AnnouncementStatus.draft) return;
    docs[a.announcementId] = Announcement(
      announcementId: a.announcementId,
      schoolId: a.schoolId,
      branchId: a.branchId,
      academicYearId: a.academicYearId,
      audience: a.audience,
      classId: a.classId,
      sectionId: a.sectionId,
      title: a.title,
      body: a.body,
      attachments: a.attachments,
      publishAt: publishAt,
      expiresAt: announcement.expiresAt,
      status: AnnouncementStatus.published,
      revision: a.revision + 1,
      authorId: a.authorId,
      authorName: a.authorName,
      authorRole: a.authorRole,
    );
    published.add(a.announcementId);
  }

  @override
  Future<void> update(
    Announcement announcement, {
    required HomeworkActor actor,
    required bool notify,
  }) async {
    docs[announcement.announcementId] = announcement;
  }

  @override
  Future<void> archive(
    Announcement announcement, {
    required HomeworkActor actor,
  }) async {
    archivedIds.add(announcement.announcementId);
  }

  @override
  Stream<Announcement?> watch(String schoolId, String branchId, String id) =>
      Stream.value(docs[id]);

  @override
  Future<List<Announcement>> fetch({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    String? viewerUserId,
    bool includeDrafts = false,
    int limit = 100,
  }) async {
    final admin =
        viewerRole == 'SCHOOL_ADMIN' ||
        viewerRole == 'BRANCH_ADMIN' ||
        viewerRole == 'PLATFORM_ADMIN';
    return [
      for (final a in docs.values)
        if (a.branchId == branchId &&
            (admin ||
                a.status == AnnouncementStatus.published ||
                (includeDrafts && a.authorId == viewerUserId)))
          a,
    ];
  }

  @override
  Future<List<BroadcastNotice>> fetchNotices({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    int limit = 50,
  }) async => notices;

  @override
  Stream<List<BroadcastNotice>> watchNotices({
    required String schoolId,
    required String branchId,
    required String viewerRole,
    int limit = 30,
  }) => Stream.value(notices);
}

class FakeHomeworkFileStore implements HomeworkFileStore {
  final List<String> uploads = [];

  @override
  Future<FileAttachment> upload({
    required String path,
    required String fileName,
    required List<int> bytes,
    required String uploadedBy,
  }) async {
    final problem = FilePolicy.validate(
      fileName: fileName,
      sizeBytes: bytes.length,
    );
    if (problem != null) throw ValidationFailure(problem);
    uploads.add(path);
    return FileAttachment(
      path: path,
      name: FilePolicy.safeName(fileName),
      contentType: FilePolicy.contentTypeFor(fileName)!,
      sizeBytes: bytes.length,
      uploadedBy: uploadedBy,
    );
  }

  @override
  Future<String> downloadUrl(String path) async => 'https://example.test/$path';
}

/// A student roster for the "not submitted" review tab.
class FakeStudentRepository implements StudentRepository {
  final List<Student> students;

  FakeStudentRepository(this.students);

  @override
  Future<PagedResult<Student>> fetchStudentsByPlacement({
    required String schoolId,
    required String branchId,
    required String academicYearId,
    required String classId,
    String? sectionId,
    int pageSize = 25,
    Object? cursor,
  }) async => PagedResult(
    items: [
      for (final s in students)
        if (s.currentClassId == classId &&
            (sectionId == null || s.currentSectionId == sectionId))
          s,
    ],
    nextCursor: null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
