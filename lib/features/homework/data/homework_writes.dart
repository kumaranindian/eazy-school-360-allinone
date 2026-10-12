import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../domain/file_attachment.dart';
import '../domain/homework.dart';
import '../domain/homework_enums.dart';
import '../domain/homework_repositories.dart';
import '../domain/homework_submission.dart';

/// Every document the homework workflow writes, as a pure function. The
/// repositories apply them; `test/homework/homework_write_contract_test.dart`
/// exports the very same maps and `firestore-tests/homework-contract.test.mjs`
/// replays them against the real rules, so the shapes the Dart code writes
/// are verified against the rules, not assumed.
abstract final class HomeworkWrites {
  static Map<String, dynamic> stamp(String uid) => {
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedBy: uid,
  };

  static String historyId(String homeworkId, int revision) =>
      '${homeworkId}__$revision';

  static Map<String, dynamic> history({
    required Homework homework,
    required int revision,
    required HomeworkEvent event,
    required HomeworkStatus toStatus,
    required HomeworkActor actor,
    String? note,
  }) => {
    FirestoreFields.schoolId: homework.schoolId,
    FirestoreFields.branchId: homework.branchId,
    'academicYearId': homework.academicYearId,
    'homeworkId': homework.homeworkId,
    'classId': homework.classId,
    'sectionId': homework.sectionId,
    'revision': revision,
    'event': event.wireValue,
    'toStatus': toStatus.wireValue,
    'actorId': actor.userId,
    'actorName': actor.name,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'at': FieldValue.serverTimestamp(),
  };

  static Map<String, dynamic> draftEdit(Homework h, int revision, String uid) =>
      {
        ...h.body(),
        'revision': revision,
        'lastEvent': HomeworkEvent.edited.wireValue,
        ...stamp(uid),
      };

  static Map<String, dynamic> publish(int revision, String uid) => {
    FirestoreFields.status: HomeworkStatus.published.wireValue,
    'revision': revision,
    'lastEvent': HomeworkEvent.published.wireValue,
    'publishedBy': uid,
    'publishedAt': FieldValue.serverTimestamp(),
    ...stamp(uid),
  };

  static Map<String, dynamic> dueChange({
    required String dueDateKey,
    required int? dueTimeMin,
    required DateTime dueAt,
    required int revision,
    required String uid,
  }) => {
    'dueDateKey': dueDateKey,
    'dueTimeMin': dueTimeMin,
    'dueAt': Timestamp.fromDate(dueAt),
    'revision': revision,
    'lastEvent': HomeworkEvent.dueChanged.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> editPublished({
    required String description,
    required List<FileAttachment> attachments,
    required int revision,
    required String uid,
  }) => {
    'description': description.trim(),
    'attachments': [for (final a in attachments) a.toMap()],
    'revision': revision,
    'lastEvent': HomeworkEvent.edited.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> statusChange({
    required HomeworkStatus to,
    required HomeworkEvent event,
    required int revision,
    required String uid,
  }) => {
    FirestoreFields.status: to.wireValue,
    'revision': revision,
    'lastEvent': event.wireValue,
    ...stamp(uid),
  };

  // ---------------------------------------------------------------- notices
  static String noticeId(String refId, String event, int revision) =>
      '${refId}__${event}__$revision';

  static Map<String, dynamic> broadcastNotice({
    required String schoolId,
    required String branchId,
    required String type,
    required String audienceKind,
    String? classId,
    String? sectionId,
    required String title,
    required String body,
    required String refType,
    required String refId,
    required int revision,
    required String createdBy,
  }) => {
    FirestoreFields.schoolId: schoolId,
    FirestoreFields.branchId: branchId,
    'type': type,
    'audienceKind': audienceKind,
    'classId': classId,
    'sectionId': sectionId,
    'title': title,
    'body': body,
    'refType': refType,
    'refId': refId,
    'revision': revision,
    'createdBy': createdBy,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
  };

  static Map<String, dynamic> homeworkNotice(
    Homework h,
    String type,
    int revision,
    String uid,
  ) => broadcastNotice(
    schoolId: h.schoolId,
    branchId: h.branchId,
    type: type,
    audienceKind: 'SECTION',
    classId: h.classId,
    sectionId: h.sectionId,
    title: type == 'HOMEWORK_PUBLISHED'
        ? 'New homework: ${h.subjectName}'
        : 'Deadline changed: ${h.subjectName}',
    body: '${h.title} · due ${_date(h.dueDateKey)}',
    refType: 'HOMEWORK',
    refId: h.homeworkId,
    revision: revision,
    createdBy: uid,
  );

  static String _date(String key) {
    final p = key.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
  }

  /// A targeted, in-app notice to the user who submitted (existing
  /// `notifications` collection): returned or graded.
  static Map<String, dynamic> targetedNotification({
    required HomeworkSubmission submission,
    required Homework homework,
    required String type,
    required int revision,
    required String createdBy,
  }) => {
    FirestoreFields.schoolId: submission.schoolId,
    FirestoreFields.branchId: submission.branchId,
    'audience': 'USER',
    'recipientUserId': submission.submittedBy,
    'type': type,
    'applicationId': null,
    'submissionId': submission.submissionId,
    'homeworkId': homework.homeworkId,
    'revision': revision,
    'title': type == 'HOMEWORK_RETURNED'
        ? 'Homework returned for revision'
        : 'Homework graded',
    // No feedback text and no marks: the notice says only that there is news.
    'body': '${homework.subjectName} · ${homework.title}',
    'createdBy': createdBy,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    'readAt': null,
  };

  static String targetedNoticeId(String submissionId, String event, int rev) =>
      '${submissionId}__${event}__$rev';

  // ------------------------------------------------------------ submissions
  static Map<String, dynamic> submissionCreate({
    required Homework homework,
    required String studentId,
    required String studentName,
    required String text,
    required List<FileAttachment> attachments,
    required SubmissionStatus status,
    required String uid,
  }) => {
    FirestoreFields.schoolId: homework.schoolId,
    FirestoreFields.branchId: homework.branchId,
    'academicYearId': homework.academicYearId,
    'homeworkId': homework.homeworkId,
    'studentId': studentId,
    'studentName': studentName,
    'classId': homework.classId,
    'sectionId': homework.sectionId,
    FirestoreFields.status: status.wireValue,
    'late': status == SubmissionStatus.lateSubmitted,
    'textAnswer': text.trim(),
    'attachments': [for (final a in attachments) a.toMap()],
    'revision': 1,
    'lastEvent': SubmissionEvent.submit.wireValue,
    'submittedBy': uid,
    'submittedAt': FieldValue.serverTimestamp(),
    'feedback': null,
    'marks': null,
    'gradedBy': null,
    'gradedByName': null,
    'gradedAt': null,
    'reviewedBy': null,
    'reviewedAt': null,
    FirestoreFields.createdAt: FieldValue.serverTimestamp(),
    FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
    FirestoreFields.createdBy: uid,
    FirestoreFields.updatedBy: uid,
  };

  static Map<String, dynamic> submissionResubmit({
    required String text,
    required List<FileAttachment> attachments,
    required bool late,
    required int revision,
    required String uid,
  }) => {
    FirestoreFields.status: SubmissionStatus.resubmitted.wireValue,
    'late': late,
    'textAnswer': text.trim(),
    'attachments': [for (final a in attachments) a.toMap()],
    'revision': revision,
    'lastEvent': SubmissionEvent.resubmit.wireValue,
    'submittedBy': uid,
    'submittedAt': FieldValue.serverTimestamp(),
    ...stamp(uid),
  };

  static Map<String, dynamic> submissionGrade({
    required int? marks,
    required String feedback,
    required int revision,
    required HomeworkActor actor,
  }) => {
    FirestoreFields.status: SubmissionStatus.graded.wireValue,
    'marks': marks,
    'feedback': feedback.trim().isEmpty ? null : feedback.trim(),
    'gradedBy': actor.userId,
    'gradedByName': actor.name,
    'gradedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': SubmissionEvent.grade.wireValue,
    ...stamp(actor.userId),
  };

  static Map<String, dynamic> submissionReturn({
    required String feedback,
    required int revision,
    required HomeworkActor actor,
  }) => {
    FirestoreFields.status: SubmissionStatus.returnedForRevision.wireValue,
    'marks': null,
    'feedback': feedback.trim(),
    'gradedBy': null,
    'gradedByName': null,
    'gradedAt': null,
    'reviewedBy': actor.userId,
    'reviewedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': SubmissionEvent.returnForRevision.wireValue,
    ...stamp(actor.userId),
  };

  static Map<String, dynamic> submissionReview({
    required int revision,
    required String uid,
  }) => {
    'reviewedBy': uid,
    'reviewedAt': FieldValue.serverTimestamp(),
    'revision': revision,
    'lastEvent': SubmissionEvent.review.wireValue,
    ...stamp(uid),
  };

  static Map<String, dynamic> revisionRecord({
    required String submissionId,
    required Homework homework,
    required String studentId,
    required int revision,
    required SubmissionEvent event,
    required SubmissionStatus status,
    required String text,
    required List<FileAttachment> attachments,
    String? feedback,
    int? marks,
    required HomeworkActor actor,
  }) => {
    FirestoreFields.schoolId: homework.schoolId,
    FirestoreFields.branchId: homework.branchId,
    'submissionId': submissionId,
    'homeworkId': homework.homeworkId,
    'studentId': studentId,
    'revision': revision,
    'event': event.wireValue,
    FirestoreFields.status: status.wireValue,
    'textAnswer': text,
    'attachments': [for (final a in attachments) a.toMap()],
    'feedback': feedback,
    'marks': marks,
    'actorId': actor.userId,
    'actorName': actor.name,
    'actorRole': actor.role,
    'at': FieldValue.serverTimestamp(),
  };
}
