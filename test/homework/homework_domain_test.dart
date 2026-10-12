import 'package:eazy_school_360/features/announcements/domain/announcement.dart';
import 'package:eazy_school_360/features/homework/domain/file_attachment.dart';
import 'package:eazy_school_360/features/homework/domain/homework.dart';
import 'package:eazy_school_360/features/homework/domain/homework_enums.dart';
import 'package:eazy_school_360/features/homework/domain/homework_rules.dart';
import 'package:eazy_school_360/features/homework/domain/homework_submission.dart';
import 'package:flutter_test/flutter_test.dart';

Homework _hw({
  HomeworkStatus status = HomeworkStatus.published,
  DateTime? dueAt,
  int? maxMarks = 10,
  bool allowLate = false,
  bool allowResubmission = true,
  bool requiresSubmission = true,
  String assigned = '2026-08-01',
  String due = '2026-08-10',
  int? dueTimeMin,
  String title = 'Chapter 4',
}) => Homework(
  homeworkId: 'b1__sa',
  batchId: 'b1',
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: 'sa',
  subjectId: 'math',
  subjectName: 'Maths',
  teacherStaffId: 't1',
  teacherName: 'T',
  title: title,
  assignedDateKey: assigned,
  dueDateKey: due,
  dueTimeMin: dueTimeMin,
  dueAt: dueAt ?? Homework.dueInstant(due, dueTimeMin),
  status: status,
  maxMarks: maxMarks,
  allowLate: allowLate,
  allowResubmission: allowResubmission,
  requiresSubmission: requiresSubmission,
);

HomeworkSubmission _sub(
  SubmissionStatus status, {
  bool late = false,
  int? marks,
}) => HomeworkSubmission(
  submissionId: 'b1__sa__stu',
  homeworkId: 'b1__sa',
  studentId: 'stu',
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y1',
  classId: 'c5',
  sectionId: 'sa',
  status: status,
  late: late,
  marks: marks,
  submittedBy: 'p',
);

void main() {
  final due = DateTime(2026, 8, 10, 17);
  final before = DateTime(2026, 8, 9, 12);
  final after = DateTime(2026, 8, 11, 9);

  group('Homework validation', () {
    test('accepts a well-formed homework', () {
      expect(HomeworkRules.validate(_hw(), todayKey: '2026-08-01'), isNull);
    });
    test('refuses short titles, bad marks and due before assigned', () {
      expect(
        HomeworkRules.validate(_hw(title: 'ab'), todayKey: 'x'),
        isNotNull,
      );
      expect(
        HomeworkRules.validate(_hw(maxMarks: 0), todayKey: 'x'),
        isNotNull,
      );
      expect(
        HomeworkRules.validate(_hw(maxMarks: 1001), todayKey: 'x'),
        isNotNull,
      );
      expect(
        HomeworkRules.validate(
          _hw(assigned: '2026-08-10', due: '2026-08-01'),
          todayKey: 'x',
        ),
        isNotNull,
      );
    });
    test('a due time defaults to the end of the day', () {
      expect(Homework.dueInstant('2026-08-10', null).hour, 23);
      expect(Homework.dueInstant('2026-08-10', 9 * 60 + 30).minute, 30);
    });
  });

  group('Publication and deadline changes', () {
    test('only a draft with a future deadline is published', () {
      final draft = _hw(status: HomeworkStatus.draft, dueAt: due);
      expect(HomeworkRules.checkPublish(draft, now: before), isNull);
      expect(HomeworkRules.checkPublish(draft, now: after), isNotNull);
      expect(
        HomeworkRules.checkPublish(
          _hw(status: HomeworkStatus.published, dueAt: due),
          now: before,
        ),
        isNotNull,
      );
    });
    test('a published deadline may be extended but never shortened', () {
      final h = _hw(dueAt: due);
      expect(
        HomeworkRules.checkDueChange(h, due.add(const Duration(days: 2))),
        isNull,
      );
      expect(
        HomeworkRules.checkDueChange(h, due.subtract(const Duration(days: 1))),
        isNotNull,
      );
      expect(
        HomeworkRules.checkDueChange(
          _hw(status: HomeworkStatus.draft, dueAt: due),
          due,
        ),
        isNotNull,
      );
    });
  });

  group('Submitting', () {
    test('on time is SUBMITTED', () {
      final d = HomeworkRules.checkSubmit(
        homework: _hw(dueAt: due),
        now: before,
      );
      expect(d.status, SubmissionStatus.submitted);
    });
    test('after the deadline is refused unless late work is allowed', () {
      expect(
        HomeworkRules.checkSubmit(
          homework: _hw(dueAt: due),
          now: after,
        ).error,
        isNotNull,
      );
      final d = HomeworkRules.checkSubmit(
        homework: _hw(dueAt: due, allowLate: true),
        now: after,
      );
      expect(d.status, SubmissionStatus.lateSubmitted);
    });
    test('closed, draft and no-submission homework take nothing', () {
      for (final h in [
        _hw(status: HomeworkStatus.closed, dueAt: due),
        _hw(status: HomeworkStatus.draft, dueAt: due),
        _hw(requiresSubmission: false, dueAt: due),
      ]) {
        expect(
          HomeworkRules.checkSubmit(homework: h, now: before).error,
          isNotNull,
        );
      }
    });
    test('content: needs text or a file, bounded, files only if enabled', () {
      final h = _hw(dueAt: due);
      expect(
        HomeworkRules.checkContent(homework: h, text: ' ', attachmentCount: 0),
        isNotNull,
      );
      expect(
        HomeworkRules.checkContent(homework: h, text: 'a', attachmentCount: 0),
        isNull,
      );
      expect(
        HomeworkRules.checkContent(homework: h, text: 'a', attachmentCount: 4),
        isNotNull,
      );
      expect(
        HomeworkRules.checkContent(
          homework: h,
          text: 'x' * 5001,
          attachmentCount: 0,
        ),
        isNotNull,
      );
    });
  });

  group('Resubmitting', () {
    final h = _hw(dueAt: due);
    test('before the deadline when permitted', () {
      final d = HomeworkRules.checkResubmit(
        homework: h,
        current: _sub(SubmissionStatus.submitted),
        now: before,
      );
      expect(d.status, SubmissionStatus.resubmitted);
    });
    test('not when the homework forbids it', () {
      expect(
        HomeworkRules.checkResubmit(
          homework: _hw(dueAt: due, allowResubmission: false),
          current: _sub(SubmissionStatus.submitted),
          now: before,
        ).error,
        isNotNull,
      );
    });
    test('not after the deadline, unless returned for revision', () {
      expect(
        HomeworkRules.checkResubmit(
          homework: h,
          current: _sub(SubmissionStatus.submitted),
          now: after,
        ).error,
        isNotNull,
      );
      expect(
        HomeworkRules.checkResubmit(
          homework: h,
          current: _sub(SubmissionStatus.returnedForRevision),
          now: after,
        ).status,
        SubmissionStatus.resubmitted,
      );
    });
    test('graded work is locked until returned', () {
      expect(
        HomeworkRules.checkResubmit(
          homework: h,
          current: _sub(SubmissionStatus.graded, marks: 8),
          now: before,
        ).error,
        isNotNull,
      );
    });
  });

  group('Grading', () {
    final h = _hw(dueAt: due, maxMarks: 10);
    final s = _sub(SubmissionStatus.submitted);
    test('marks must be within 0..max', () {
      expect(
        HomeworkRules.checkGrade(
          homework: h,
          submission: s,
          marks: 10,
          feedback: '',
        ),
        isNull,
      );
      expect(
        HomeworkRules.checkGrade(
          homework: h,
          submission: s,
          marks: 11,
          feedback: '',
        ),
        isNotNull,
      );
      expect(
        HomeworkRules.checkGrade(
          homework: h,
          submission: s,
          marks: -1,
          feedback: '',
        ),
        isNotNull,
      );
      expect(
        HomeworkRules.checkGrade(
          homework: h,
          submission: s,
          marks: null,
          feedback: '',
        ),
        isNotNull,
      );
    });
    test('an ungraded homework takes no marks', () {
      final g = _hw(dueAt: due, maxMarks: null);
      expect(
        HomeworkRules.checkGrade(
          homework: g,
          submission: s,
          marks: 3,
          feedback: '',
        ),
        isNotNull,
      );
      expect(
        HomeworkRules.checkGrade(
          homework: g,
          submission: s,
          marks: null,
          feedback: 'ok',
        ),
        isNull,
      );
    });
    test(
      'returning needs a reason; work with the student is not reviewable',
      () {
        expect(
          HomeworkRules.checkReturn(submission: s, feedback: 'no'),
          isNotNull,
        );
        expect(
          HomeworkRules.checkReturn(submission: s, feedback: 'Show working'),
          isNull,
        );
        final back = _sub(SubmissionStatus.returnedForRevision);
        expect(
          HomeworkRules.checkReturn(submission: back, feedback: 'Again please'),
          isNotNull,
        );
        expect(
          HomeworkRules.checkGrade(
            homework: h,
            submission: back,
            marks: 5,
            feedback: '',
          ),
          isNotNull,
        );
      },
    );
  });

  group('Family state and reporting definitions', () {
    final h = _hw(dueAt: due);
    test('state from submission and clock', () {
      FamilyHomeworkState f(HomeworkSubmission? s, DateTime now) =>
          HomeworkRules.familyState(homework: h, submission: s, now: now);
      expect(f(null, before), FamilyHomeworkState.upcoming);
      expect(f(null, after), FamilyHomeworkState.overdue);
      expect(
        f(_sub(SubmissionStatus.submitted), after),
        FamilyHomeworkState.submitted,
      );
      expect(
        f(_sub(SubmissionStatus.returnedForRevision), before),
        FamilyHomeworkState.revision,
      );
      expect(
        f(_sub(SubmissionStatus.graded), before),
        FamilyHomeworkState.graded,
      );
      expect(
        HomeworkRules.familyState(
          homework: _hw(requiresSubmission: false, dueAt: due),
          submission: null,
          now: before,
        ),
        FamilyHomeworkState.noSubmission,
      );
    });
    test(
      'late, resubmitted and graded count as handed in; returned does not',
      () {
        expect(
          HomeworkRules.countsAsComplete(SubmissionStatus.lateSubmitted),
          isTrue,
        );
        expect(
          HomeworkRules.countsAsComplete(SubmissionStatus.resubmitted),
          isTrue,
        );
        expect(HomeworkRules.countsAsComplete(SubmissionStatus.graded), isTrue);
        expect(
          HomeworkRules.countsAsComplete(SubmissionStatus.returnedForRevision),
          isFalse,
        );
        expect(
          HomeworkRules.countsAsComplete(SubmissionStatus.notSubmitted),
          isFalse,
        );
      },
    );
  });

  group('File policy', () {
    test('allows the listed types and sizes only', () {
      expect(FilePolicy.validate(fileName: 'a.pdf', sizeBytes: 1000), isNull);
      expect(FilePolicy.validate(fileName: 'A.PNG', sizeBytes: 1000), isNull);
      expect(
        FilePolicy.validate(fileName: 'a.exe', sizeBytes: 1000),
        isNotNull,
      );
      expect(
        FilePolicy.validate(fileName: 'a.html', sizeBytes: 1000),
        isNotNull,
      );
      expect(
        FilePolicy.validate(fileName: 'noext', sizeBytes: 1000),
        isNotNull,
      );
      expect(FilePolicy.validate(fileName: 'a.pdf', sizeBytes: 0), isNotNull);
      expect(
        FilePolicy.validate(fileName: 'a.pdf', sizeBytes: FilePolicy.maxBytes),
        isNotNull,
        reason: 'the Storage rule is "< 10 MB"',
      );
      expect(
        FilePolicy.validate(
          fileName: 'a.pdf',
          sizeBytes: FilePolicy.maxBytes - 1,
        ),
        isNull,
      );
    });
    test('content type comes from the extension, never the client', () {
      expect(FilePolicy.contentTypeFor('x.JPG'), 'image/jpeg');
      expect(FilePolicy.safeName('../my file?.pdf'), '.._my_file_.pdf');
    });
  });

  group('Announcement audience and time', () {
    Announcement a(
      AnnouncementAudience audience, {
      String? classId,
      String? sectionId,
      AnnouncementStatus status = AnnouncementStatus.published,
      DateTime? publishAt,
      DateTime? expiresAt,
    }) => Announcement(
      announcementId: 'a',
      schoolId: 's',
      branchId: 'b',
      audience: audience,
      classId: classId,
      sectionId: sectionId,
      title: 'Notice',
      body: 'Body',
      status: status,
      publishAt: publishAt ?? DateTime(2026, 1, 1),
      expiresAt: expiresAt,
      authorId: 'u',
      authorName: 'A',
      authorRole: 'SCHOOL_ADMIN',
    );
    final now = DateTime(2026, 8, 10);
    const parent = AnnouncementViewer(
      role: 'PARENT',
      children: [(branchId: 'b', classId: 'c5', sectionId: 'sa')],
    );
    const otherParent = AnnouncementViewer(
      role: 'PARENT',
      children: [(branchId: 'b', classId: 'c6', sectionId: 'sx')],
    );
    const teacher = AnnouncementViewer(
      role: 'TEACHER',
      branchId: 'b',
      teaching: [(classId: 'c5', sectionId: 'sa')],
    );

    test('addressing follows relationships', () {
      final section = a(
        AnnouncementAudience.section,
        classId: 'c5',
        sectionId: 'sa',
      );
      expect(AnnouncementVisibility.addressedTo(section, parent), isTrue);
      expect(AnnouncementVisibility.addressedTo(section, otherParent), isFalse);
      expect(AnnouncementVisibility.addressedTo(section, teacher), isTrue);
      final staff = a(AnnouncementAudience.staff);
      expect(AnnouncementVisibility.addressedTo(staff, teacher), isTrue);
      expect(AnnouncementVisibility.addressedTo(staff, parent), isFalse);
      final parents = a(AnnouncementAudience.parents);
      expect(AnnouncementVisibility.addressedTo(parents, parent), isTrue);
      expect(AnnouncementVisibility.addressedTo(parents, teacher), isFalse);
      expect(
        AnnouncementVisibility.addressedTo(
          a(AnnouncementAudience.classGroup, classId: 'c5'),
          parent,
        ),
        isTrue,
      );
    });

    test('only published, started, unexpired announcements are current', () {
      final list = [
        a(AnnouncementAudience.all),
        a(AnnouncementAudience.all, status: AnnouncementStatus.draft),
        a(AnnouncementAudience.all, status: AnnouncementStatus.archived),
        a(AnnouncementAudience.all, publishAt: DateTime(2026, 9, 1)),
        a(AnnouncementAudience.all, expiresAt: DateTime(2026, 8, 1)),
      ];
      final shown = AnnouncementVisibility.currentFor(list, parent, now);
      expect(shown.length, 1);
    });

    test(
      'validation: audience needs its class/section; expiry after start',
      () {
        expect(
          a(AnnouncementAudience.section, classId: 'c5').validate(),
          isNotNull,
        );
        expect(
          a(
            AnnouncementAudience.all,
            publishAt: DateTime(2026, 8, 10),
            expiresAt: DateTime(2026, 8, 1),
          ).validate(),
          isNotNull,
        );
        expect(a(AnnouncementAudience.all).validate(), isNull);
      },
    );
  });
}
