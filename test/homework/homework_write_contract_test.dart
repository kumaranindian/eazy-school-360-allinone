import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/announcements/data/announcement_writes.dart';
import 'package:eazy_school_360/features/announcements/domain/announcement.dart';
import 'package:eazy_school_360/features/homework/data/homework_writes.dart';
import 'package:eazy_school_360/features/homework/domain/homework.dart';
import 'package:eazy_school_360/features/homework/domain/homework_enums.dart';
import 'package:eazy_school_360/features/homework/domain/homework_repositories.dart';
import 'package:eazy_school_360/features/homework/domain/homework_submission.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exports the exact documents the Dart homework / submission / announcement
/// code writes, step by step through each workflow, to
/// `firestore-tests/fixtures/homework-write-plans.json`. The emulator test
/// `homework-contract.test.mjs` replays them under the real
/// `firestore.rules`; every step must be accepted.
const _school = '__SCHOOL__';
const _branch = 'north';
const _teacher = HomeworkActor(
  userId: 'hc-t1',
  name: 'Teacher',
  role: 'TEACHER',
);
const _classTeacher = HomeworkActor(
  userId: 'hc-t2',
  name: 'Class teacher',
  role: 'TEACHER',
);
const _parent = HomeworkActor(userId: 'hc-p1', name: 'Parent', role: 'PARENT');
const _admin = HomeworkActor(
  userId: 'hc-admin',
  name: 'Admin',
  role: 'SCHOOL_ADMIN',
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

Homework _hw(String batch, {String subject = 'math', String teacher = 'st1'}) =>
    Homework(
      homeworkId: Homework.idFor(batch, 'sa'),
      batchId: batch,
      schoolId: _school,
      branchId: _branch,
      academicYearId: 'y1',
      classId: 'c5',
      sectionId: 'sa',
      classLabel: 'Class 5 – A',
      subjectId: subject,
      subjectName: 'Mathematics',
      teacherStaffId: teacher,
      teacherName: 'Teacher',
      title: 'Chapter 4 exercises',
      description: 'Do questions 1 to 10',
      assignedDateKey: '2026-08-01',
      dueDateKey: '2099-06-01',
      dueAt: DateTime.utc(2099, 6, 1, 17),
      maxMarks: 10,
    );

String _p(String c, String id) => '$c/$id';

void main() {
  test('exports the homework, submission and announcement write plans', () {
    final scenarios = <Map<String, Object?>>[];

    // ---------------------------------------------------------- homework
    {
      var h = _hw('hcb1');
      final id = h.homeworkId;
      final steps = <_Batch>[];

      final create = _Batch('hc-t1', 'create draft');
      create.set(_p('homework', id), h.toFirestoreCreate(actorId: 'hc-t1'));
      create.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 1)),
        HomeworkWrites.history(
          homework: h,
          revision: 1,
          event: HomeworkEvent.created,
          toStatus: HomeworkStatus.draft,
          actor: _teacher,
        ),
      );
      steps.add(create);

      h = h.copyWith(title: 'Chapter 4 exercises (v2)', allowLate: true);
      final edit = _Batch('hc-t1', 'edit draft');
      edit.update(_p('homework', id), HomeworkWrites.draftEdit(h, 2, 'hc-t1'));
      edit.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 2)),
        HomeworkWrites.history(
          homework: h,
          revision: 2,
          event: HomeworkEvent.edited,
          toStatus: HomeworkStatus.draft,
          actor: _teacher,
        ),
      );
      steps.add(edit);

      final publish = _Batch('hc-t1', 'publish');
      publish.update(_p('homework', id), HomeworkWrites.publish(3, 'hc-t1'));
      publish.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 3)),
        HomeworkWrites.history(
          homework: h,
          revision: 3,
          event: HomeworkEvent.published,
          toStatus: HomeworkStatus.published,
          actor: _teacher,
        ),
      );
      publish.set(
        _p('broadcastNotices', HomeworkWrites.noticeId(id, 'PUBLISHED', 3)),
        HomeworkWrites.homeworkNotice(h, 'HOMEWORK_PUBLISHED', 3, 'hc-t1'),
      );
      steps.add(publish);

      final due = DateTime.utc(2099, 6, 8, 17);
      final extended = h.copyWith(dueDateKey: '2099-06-08', dueAt: due);
      final extend = _Batch('hc-t1', 'extend the deadline');
      extend.update(
        _p('homework', id),
        HomeworkWrites.dueChange(
          dueDateKey: '2099-06-08',
          dueTimeMin: null,
          dueAt: due,
          revision: 4,
          uid: 'hc-t1',
        ),
      );
      extend.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 4)),
        HomeworkWrites.history(
          homework: extended,
          revision: 4,
          event: HomeworkEvent.dueChanged,
          toStatus: HomeworkStatus.published,
          actor: _teacher,
        ),
      );
      extend.set(
        _p('broadcastNotices', HomeworkWrites.noticeId(id, 'DUE_CHANGED', 4)),
        HomeworkWrites.homeworkNotice(
          extended,
          'HOMEWORK_DUE_CHANGED',
          4,
          'hc-t1',
        ),
      );
      steps.add(extend);

      final instructions = _Batch('hc-t1', 'update instructions');
      instructions.update(
        _p('homework', id),
        HomeworkWrites.editPublished(
          description: 'Do questions 1 to 12',
          attachments: const [],
          revision: 5,
          uid: 'hc-t1',
        ),
      );
      instructions.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 5)),
        HomeworkWrites.history(
          homework: extended,
          revision: 5,
          event: HomeworkEvent.edited,
          toStatus: HomeworkStatus.published,
          actor: _teacher,
        ),
      );
      steps.add(instructions);

      for (final (rev, to, event) in const [
        (6, HomeworkStatus.closed, HomeworkEvent.closed),
        (7, HomeworkStatus.archived, HomeworkEvent.archived),
      ]) {
        final b = _Batch('hc-t1', event.wireValue.toLowerCase());
        b.update(
          _p('homework', id),
          HomeworkWrites.statusChange(
            to: to,
            event: event,
            revision: rev,
            uid: 'hc-t1',
          ),
        );
        b.set(
          _p('homeworkHistory', HomeworkWrites.historyId(id, rev)),
          HomeworkWrites.history(
            homework: extended,
            revision: rev,
            event: event,
            toStatus: to,
            actor: _teacher,
          ),
        );
        steps.add(b);
      }
      scenarios.add({
        'name': 'homework lifecycle',
        'batches': [for (final s in steps) s.toJson()],
      });
    }

    // ------------------------------------------------------ submissions
    {
      final h = _hw('hcb2');
      final id = h.homeworkId;
      const studentId = 'hc-stu1';
      final subId = HomeworkSubmission.idFor(id, studentId);
      final steps = <_Batch>[];

      final create = _Batch('hc-t1', 'create draft');
      create.set(_p('homework', id), h.toFirestoreCreate(actorId: 'hc-t1'));
      create.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 1)),
        HomeworkWrites.history(
          homework: h,
          revision: 1,
          event: HomeworkEvent.created,
          toStatus: HomeworkStatus.draft,
          actor: _teacher,
        ),
      );
      steps.add(create);

      final publish = _Batch('hc-t1', 'publish');
      publish.update(_p('homework', id), HomeworkWrites.publish(2, 'hc-t1'));
      publish.set(
        _p('homeworkHistory', HomeworkWrites.historyId(id, 2)),
        HomeworkWrites.history(
          homework: h,
          revision: 2,
          event: HomeworkEvent.published,
          toStatus: HomeworkStatus.published,
          actor: _teacher,
        ),
      );
      publish.set(
        _p('broadcastNotices', HomeworkWrites.noticeId(id, 'PUBLISHED', 2)),
        HomeworkWrites.homeworkNotice(h, 'HOMEWORK_PUBLISHED', 2, 'hc-t1'),
      );
      steps.add(publish);

      final submit = _Batch('hc-p1', 'family hands in');
      submit.set(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionCreate(
          homework: h,
          studentId: studentId,
          studentName: 'Student One',
          text: 'My first answer',
          attachments: const [],
          status: SubmissionStatus.submitted,
          uid: 'hc-p1',
        ),
      );
      submit.set(
        _p('homeworkRevisions', '${subId}__1'),
        HomeworkWrites.revisionRecord(
          submissionId: subId,
          homework: h,
          studentId: studentId,
          revision: 1,
          event: SubmissionEvent.submit,
          status: SubmissionStatus.submitted,
          text: 'My first answer',
          attachments: const [],
          actor: _parent,
        ),
      );
      steps.add(submit);

      _Batch revision(
        String as,
        HomeworkActor actor,
        String label,
        int rev,
        SubmissionEvent event,
        SubmissionStatus status, {
        String text = 'My first answer',
        String? feedback,
        int? marks,
      }) {
        final b = _Batch(as, label);
        b.set(
          _p('homeworkRevisions', '${subId}__$rev'),
          HomeworkWrites.revisionRecord(
            submissionId: subId,
            homework: h,
            studentId: studentId,
            revision: rev,
            event: event,
            status: status,
            text: text,
            attachments: const [],
            feedback: feedback,
            marks: marks,
            actor: actor,
          ),
        );
        return b;
      }

      HomeworkSubmission snapshot(int rev) => HomeworkSubmission(
        submissionId: subId,
        homeworkId: id,
        studentId: studentId,
        studentName: 'Student One',
        schoolId: _school,
        branchId: _branch,
        academicYearId: 'y1',
        classId: 'c5',
        sectionId: 'sa',
        status: SubmissionStatus.submitted,
        revision: rev,
        submittedBy: 'hc-p1',
      );

      final resubmit = revision(
        'hc-p1',
        _parent,
        'family changes the answer',
        2,
        SubmissionEvent.resubmit,
        SubmissionStatus.resubmitted,
        text: 'A better answer',
      );
      resubmit.update(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionResubmit(
          text: 'A better answer',
          attachments: const [],
          late: false,
          revision: 2,
          uid: 'hc-p1',
        ),
      );
      steps.add(resubmit);

      final grade = revision(
        'hc-t1',
        _teacher,
        'teacher grades',
        3,
        SubmissionEvent.grade,
        SubmissionStatus.graded,
        text: 'A better answer',
        feedback: 'Well done',
        marks: 8,
      );
      grade.update(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionGrade(
          marks: 8,
          feedback: 'Well done',
          revision: 3,
          actor: _teacher,
        ),
      );
      grade.set(
        _p('notifications', HomeworkWrites.targetedNoticeId(subId, 'GRADE', 3)),
        HomeworkWrites.targetedNotification(
          submission: snapshot(2),
          homework: h,
          type: 'HOMEWORK_GRADED',
          revision: 3,
          createdBy: 'hc-t1',
        ),
      );
      steps.add(grade);

      final regrade = revision(
        'hc-admin',
        _admin,
        'admin regrades',
        4,
        SubmissionEvent.grade,
        SubmissionStatus.graded,
        text: 'A better answer',
        feedback: 'Regraded',
        marks: 7,
      );
      regrade.update(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionGrade(
          marks: 7,
          feedback: 'Regraded',
          revision: 4,
          actor: _admin,
        ),
      );
      regrade.set(
        _p('notifications', HomeworkWrites.targetedNoticeId(subId, 'GRADE', 4)),
        HomeworkWrites.targetedNotification(
          submission: snapshot(3),
          homework: h,
          type: 'HOMEWORK_GRADED',
          revision: 4,
          createdBy: 'hc-admin',
        ),
      );
      steps.add(regrade);

      final back = revision(
        'hc-t1',
        _teacher,
        'teacher returns for revision',
        5,
        SubmissionEvent.returnForRevision,
        SubmissionStatus.returnedForRevision,
        text: 'A better answer',
        feedback: 'Show your working',
      );
      back.update(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionReturn(
          feedback: 'Show your working',
          revision: 5,
          actor: _teacher,
        ),
      );
      back.set(
        _p(
          'notifications',
          HomeworkWrites.targetedNoticeId(subId, 'RETURN', 5),
        ),
        HomeworkWrites.targetedNotification(
          submission: snapshot(4),
          homework: h,
          type: 'HOMEWORK_RETURNED',
          revision: 5,
          createdBy: 'hc-t1',
        ),
      );
      steps.add(back);

      final again = revision(
        'hc-p1',
        _parent,
        'family revises and resubmits',
        6,
        SubmissionEvent.resubmit,
        SubmissionStatus.resubmitted,
        text: 'With working',
      );
      again.update(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionResubmit(
          text: 'With working',
          attachments: const [],
          late: false,
          revision: 6,
          uid: 'hc-p1',
        ),
      );
      steps.add(again);

      final review = revision(
        'hc-t1',
        _teacher,
        'teacher marks reviewed',
        7,
        SubmissionEvent.review,
        SubmissionStatus.resubmitted,
        text: 'With working',
      );
      review.update(
        _p('homeworkSubmissions', subId),
        HomeworkWrites.submissionReview(revision: 7, uid: 'hc-t1'),
      );
      steps.add(review);

      scenarios.add({
        'name': 'submission lifecycle',
        'batches': [for (final s in steps) s.toJson()],
      });
    }

    // ----------------------------------------------------- announcements
    {
      Announcement make(
        String id,
        AnnouncementAudience audience, {
        String author = 'hc-admin',
        String role = 'SCHOOL_ADMIN',
        String? classId,
        String? sectionId,
        String title = 'Sports day',
      }) => Announcement(
        announcementId: id,
        schoolId: _school,
        branchId: _branch,
        academicYearId: classId == null ? null : 'y1',
        audience: audience,
        classId: classId,
        sectionId: sectionId,
        title: title,
        body: 'On Friday at 9am',
        authorId: author,
        authorName: 'Author',
        authorRole: role,
      );

      final steps = <_Batch>[];
      var a = make('an_hc1', AnnouncementAudience.parents);
      final create = _Batch('hc-admin', 'create draft');
      create.set(_p('announcements', a.announcementId), a.toFirestoreCreate());
      create.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(a.announcementId, 1),
        ),
        AnnouncementWrites.history(
          a: a,
          revision: 1,
          event: AnnouncementEvent.created,
          toStatus: AnnouncementStatus.draft,
          actor: _admin,
        ),
      );
      steps.add(create);

      final edit = _Batch('hc-admin', 'edit draft');
      edit.update(
        _p('announcements', a.announcementId),
        AnnouncementWrites.draftEdit(
          make(
            'an_hc1',
            AnnouncementAudience.parents,
            title: 'Sports day (moved)',
          ),
          2,
          'hc-admin',
        ),
      );
      edit.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(a.announcementId, 2),
        ),
        AnnouncementWrites.history(
          a: a,
          revision: 2,
          event: AnnouncementEvent.edited,
          toStatus: AnnouncementStatus.draft,
          actor: _admin,
        ),
      );
      steps.add(edit);

      final publish = _Batch('hc-admin', 'publish');
      publish.update(
        _p('announcements', a.announcementId),
        AnnouncementWrites.publish(
          publishAt: DateTime.utc(2026, 8, 1),
          expiresAt: DateTime.utc(2099, 1, 1),
          revision: 3,
          uid: 'hc-admin',
        ),
      );
      publish.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(a.announcementId, 3),
        ),
        AnnouncementWrites.history(
          a: a,
          revision: 3,
          event: AnnouncementEvent.published,
          toStatus: AnnouncementStatus.published,
          actor: _admin,
        ),
      );
      publish.set(
        _p(
          'broadcastNotices',
          HomeworkWrites.noticeId(a.announcementId, 'PUBLISHED', 3),
        ),
        HomeworkWrites.broadcastNotice(
          schoolId: _school,
          branchId: _branch,
          type: 'ANNOUNCEMENT_PUBLISHED',
          audienceKind: 'PARENTS',
          title: 'New announcement',
          body: a.title,
          refType: 'ANNOUNCEMENT',
          refId: a.announcementId,
          revision: 3,
          createdBy: 'hc-admin',
        ),
      );
      steps.add(publish);

      a = make(
        'an_hc1',
        AnnouncementAudience.parents,
        title: 'Sports day (moved)',
      );
      final update = _Batch('hc-admin', 'update published text');
      update.update(
        _p('announcements', a.announcementId),
        AnnouncementWrites.updatePublished(a, 4, 'hc-admin'),
      );
      update.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(a.announcementId, 4),
        ),
        AnnouncementWrites.history(
          a: a,
          revision: 4,
          event: AnnouncementEvent.updated,
          toStatus: AnnouncementStatus.published,
          actor: _admin,
        ),
      );
      update.set(
        _p(
          'broadcastNotices',
          HomeworkWrites.noticeId(a.announcementId, 'UPDATED', 4),
        ),
        HomeworkWrites.broadcastNotice(
          schoolId: _school,
          branchId: _branch,
          type: 'ANNOUNCEMENT_UPDATED',
          audienceKind: 'PARENTS',
          title: 'Announcement updated',
          body: a.title,
          refType: 'ANNOUNCEMENT',
          refId: a.announcementId,
          revision: 4,
          createdBy: 'hc-admin',
        ),
      );
      steps.add(update);

      final archive = _Batch('hc-admin', 'archive');
      archive.update(
        _p('announcements', a.announcementId),
        AnnouncementWrites.archive(5, 'hc-admin'),
      );
      archive.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(a.announcementId, 5),
        ),
        AnnouncementWrites.history(
          a: a,
          revision: 5,
          event: AnnouncementEvent.archived,
          toStatus: AnnouncementStatus.archived,
          actor: _admin,
        ),
      );
      steps.add(archive);

      // A class teacher posts to their own section.
      final t = make(
        'an_hc2',
        AnnouncementAudience.section,
        author: 'hc-t2',
        role: 'TEACHER',
        classId: 'c5',
        sectionId: 'sa',
        title: 'Bring a sweater',
      );
      final tCreate = _Batch('hc-t2', 'class teacher drafts a section notice');
      tCreate.set(_p('announcements', t.announcementId), t.toFirestoreCreate());
      tCreate.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(t.announcementId, 1),
        ),
        AnnouncementWrites.history(
          a: t,
          revision: 1,
          event: AnnouncementEvent.created,
          toStatus: AnnouncementStatus.draft,
          actor: _classTeacher,
        ),
      );
      steps.add(tCreate);
      final tPublish = _Batch('hc-t2', 'class teacher publishes it');
      tPublish.update(
        _p('announcements', t.announcementId),
        AnnouncementWrites.publish(
          publishAt: DateTime.utc(2026, 8, 1),
          expiresAt: null,
          revision: 2,
          uid: 'hc-t2',
        ),
      );
      tPublish.set(
        _p(
          'announcementHistory',
          AnnouncementWrites.historyId(t.announcementId, 2),
        ),
        AnnouncementWrites.history(
          a: t,
          revision: 2,
          event: AnnouncementEvent.published,
          toStatus: AnnouncementStatus.published,
          actor: _classTeacher,
        ),
      );
      tPublish.set(
        _p(
          'broadcastNotices',
          HomeworkWrites.noticeId(t.announcementId, 'PUBLISHED', 2),
        ),
        HomeworkWrites.broadcastNotice(
          schoolId: _school,
          branchId: _branch,
          type: 'ANNOUNCEMENT_PUBLISHED',
          audienceKind: 'SECTION',
          classId: 'c5',
          sectionId: 'sa',
          title: 'New announcement',
          body: t.title,
          refType: 'ANNOUNCEMENT',
          refId: t.announcementId,
          revision: 2,
          createdBy: 'hc-t2',
        ),
      );
      steps.add(tPublish);

      scenarios.add({
        'name': 'announcement lifecycle',
        'batches': [for (final s in steps) s.toJson()],
      });
    }

    final out = File('firestore-tests/fixtures/homework-write-plans.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'scenarios': scenarios}),
    );
    expect(scenarios.length, 3);
  });
}
