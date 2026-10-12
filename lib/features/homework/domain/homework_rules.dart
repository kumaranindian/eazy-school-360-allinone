import '../../attendance/domain/attendance_date.dart';
import 'homework.dart';
import 'homework_enums.dart';
import 'homework_submission.dart';

/// The business rules of homework, as pure functions returning a
/// user-readable reason or null. The UI and repositories call them for good
/// messages; `firestore.rules` independently re-enforces the same
/// invariants (due-date/late policy against the **server** clock, status
/// transitions, marks within the maximum, ownership), so the UI is never
/// the only guard.
abstract final class HomeworkRules {
  // ---------------------------------------------------------------- homework
  static const int maxMarksCap = 1000;

  static String? validate(Homework h, {required String todayKey}) {
    final t = h.title.trim();
    if (t.length < 3 || t.length > 120) {
      return 'The title must be 3-120 characters.';
    }
    if (h.description.trim().length > 4000) {
      return 'Keep the instructions under 4000 characters.';
    }
    final key = AttendanceDate.keyPattern;
    if (!key.hasMatch(h.dueDateKey) || !key.hasMatch(h.assignedDateKey)) {
      return 'Choose the due date.';
    }
    if (h.dueDateKey.compareTo(h.assignedDateKey) < 0) {
      return 'The due date cannot be before the assigned date.';
    }
    final time = h.dueTimeMin;
    if (time != null && (time < 0 || time >= 24 * 60)) {
      return 'The due time is not valid.';
    }
    final marks = h.maxMarks;
    if (marks != null && (marks < 1 || marks > maxMarksCap)) {
      return 'Maximum marks must be between 1 and $maxMarksCap.';
    }
    if (h.attachments.length > 5) return 'Attach at most 5 files.';
    return null;
  }

  /// Extra checks that apply at the moment of publishing.
  static String? checkPublish(Homework h, {required DateTime now}) {
    if (h.status != HomeworkStatus.draft) {
      return 'Only a draft can be published; this one is '
          '${h.status.displayName.toLowerCase()}.';
    }
    if (h.dueAt.isBefore(now)) {
      return 'The deadline is already in the past. Choose a later due date.';
    }
    return null;
  }

  /// A published homework's deadline can only be **extended**: shortening it
  /// would turn work students already handed in on time into late work.
  static String? checkDueChange(Homework current, DateTime newDueAt) {
    if (current.status != HomeworkStatus.published) {
      return 'Only a published homework\'s deadline can be changed here.';
    }
    if (newDueAt.isBefore(current.dueAt)) {
      return 'A deadline can only be extended once homework is published.';
    }
    return null;
  }

  // ------------------------------------------------------------ submissions
  /// Whether a student's first submission is on time, late (allowed), or
  /// refused. Returns the status to store.
  static ({SubmissionStatus? status, String? error}) checkSubmit({
    required Homework homework,
    required DateTime now,
  }) {
    if (!homework.requiresSubmission) {
      return (status: null, error: 'This homework does not take submissions.');
    }
    if (!homework.status.acceptsSubmissions) {
      return (
        status: null,
        error: homework.status == HomeworkStatus.closed
            ? 'This homework is closed.'
            : 'This homework is not open for submissions.',
      );
    }
    if (homework.isPastDue(now)) {
      if (!homework.allowLate) {
        return (
          status: null,
          error: 'The deadline has passed and late work is not accepted.',
        );
      }
      return (status: SubmissionStatus.lateSubmitted, error: null);
    }
    return (status: SubmissionStatus.submitted, error: null);
  }

  /// A student changing an existing submission.
  static ({SubmissionStatus? status, String? error}) checkResubmit({
    required Homework homework,
    required HomeworkSubmission current,
    required DateTime now,
  }) {
    if (!homework.status.acceptsSubmissions) {
      return (status: null, error: 'This homework is no longer open.');
    }
    switch (current.status) {
      case SubmissionStatus.graded:
        return (
          status: null,
          error: 'Graded work cannot be changed unless the teacher returns it.',
        );
      case SubmissionStatus.returnedForRevision:
        // The teacher asked for it: allowed even after the deadline.
        return (status: SubmissionStatus.resubmitted, error: null);
      case SubmissionStatus.notSubmitted:
        return (status: null, error: 'There is nothing to resubmit yet.');
      case SubmissionStatus.submitted:
      case SubmissionStatus.lateSubmitted:
      case SubmissionStatus.resubmitted:
        if (!homework.allowResubmission) {
          return (
            status: null,
            error: 'Resubmission is not allowed for this homework.',
          );
        }
        if (homework.isPastDue(now) && !homework.allowLate) {
          return (
            status: null,
            error: 'The deadline has passed and late changes are not accepted.',
          );
        }
        return (status: SubmissionStatus.resubmitted, error: null);
    }
  }

  static String? checkContent({
    required Homework homework,
    required String text,
    required int attachmentCount,
  }) {
    if (text.trim().isEmpty && attachmentCount == 0) {
      return 'Write an answer or attach a file.';
    }
    if (text.trim().length > 5000) {
      return 'Keep the answer under 5000 characters.';
    }
    if (attachmentCount > 0 && !homework.allowFiles) {
      return 'File attachments are not enabled for this homework.';
    }
    if (attachmentCount > 3) return 'Attach at most 3 files.';
    return null;
  }

  // ---------------------------------------------------------------- grading
  static String? checkGrade({
    required Homework homework,
    required HomeworkSubmission submission,
    required int? marks,
    required String feedback,
  }) {
    if (!submission.status.isStored ||
        submission.status == SubmissionStatus.returnedForRevision) {
      return 'This work is not waiting for a grade.';
    }
    final max = homework.maxMarks;
    if (max == null) {
      if (marks != null) {
        return 'This homework is not graded with marks.';
      }
    } else {
      if (marks == null) return 'Enter the marks (out of $max).';
      if (marks < 0 || marks > max) {
        return 'Marks must be between 0 and $max.';
      }
    }
    if (feedback.trim().length > 2000) {
      return 'Keep the feedback under 2000 characters.';
    }
    return null;
  }

  static String? checkReturn({
    required HomeworkSubmission submission,
    required String feedback,
  }) {
    if (!submission.status.isStored ||
        submission.status == SubmissionStatus.returnedForRevision) {
      return 'This work is already with the student.';
    }
    if (feedback.trim().length < 3) {
      return 'Tell the student what to revise.';
    }
    return null;
  }

  // -------------------------------------------------------------- reporting
  /// Report definitions, applied everywhere:
  /// - a **late** submission counts as submitted (and separately as late);
  /// - RETURNED_FOR_REVISION counts as *not yet complete* (outstanding);
  /// - RESUBMITTED and GRADED count as submitted;
  /// - students no longer enrolled in the section are excluded from the
  ///   denominator (the roster is the current placement); their historical
  ///   submissions remain readable in the homework's own record;
  /// - expired announcements are excluded from "current" views and kept in
  ///   history.
  static bool countsAsComplete(SubmissionStatus s) =>
      s == SubmissionStatus.submitted ||
      s == SubmissionStatus.lateSubmitted ||
      s == SubmissionStatus.resubmitted ||
      s == SubmissionStatus.graded;

  /// What a family sees for one homework.
  static FamilyHomeworkState familyState({
    required Homework homework,
    required HomeworkSubmission? submission,
    required DateTime now,
  }) {
    if (submission == null) {
      if (!homework.requiresSubmission) return FamilyHomeworkState.noSubmission;
      return homework.isPastDue(now)
          ? FamilyHomeworkState.overdue
          : FamilyHomeworkState.upcoming;
    }
    return switch (submission.status) {
      SubmissionStatus.returnedForRevision => FamilyHomeworkState.revision,
      SubmissionStatus.graded => FamilyHomeworkState.graded,
      _ => FamilyHomeworkState.submitted,
    };
  }
}

enum FamilyHomeworkState {
  upcoming('Upcoming'),
  overdue('Overdue'),
  submitted('Submitted'),
  revision('Needs revision'),
  graded('Graded'),
  noSubmission('No submission needed');

  final String label;
  const FamilyHomeworkState(this.label);
}
