import 'exam_enums.dart';
import 'examination.dart';
import 'marks.dart';

/// Workflow preconditions, checked by the app before a write and re-checked by
/// the security rules at commit. Each returns a user-readable reason, or null.
abstract final class ExamRules {
  static String? checkSchedule(Examination e) {
    if (e.status != ExamStatus.draft) return 'Only a draft can be scheduled.';
    if (e.subjectCount < 1) return 'Add at least one subject first.';
    return e.validate();
  }

  static String? checkStart(Examination e, int sheetCount) {
    if (e.status != ExamStatus.scheduled) {
      return 'Marks entry opens for a scheduled examination.';
    }
    if (sheetCount < 1) return 'There are no sections to enter marks for.';
    return null;
  }

  /// Finalisation needs every sheet approved.
  static String? checkFinalize(Examination e) {
    if (e.status != ExamStatus.inProgress) {
      return 'Only an examination in marks entry can be finalised.';
    }
    if (e.sheetCount < 1) return 'No marks sheets exist yet.';
    if (e.approvedSheets != e.sheetCount) {
      return '${e.sheetCount - e.approvedSheets} of ${e.sheetCount} marks '
          'sheet(s) are not approved yet.';
    }
    return null;
  }

  static String? checkPublish(Examination e) {
    if (e.status != ExamStatus.completed) {
      return 'Only a finalised result can be published.';
    }
    if (e.resultCount < 1 || e.resultsWritten != e.resultCount) {
      return 'Not every result has been written yet '
          '(${e.resultsWritten} of ${e.resultCount}). Finish finalising '
          'first.';
    }
    return null;
  }

  static String? checkWithdraw(Examination e, String reason) {
    if (e.status != ExamStatus.published) {
      return 'Only a published result can be withdrawn.';
    }
    return _reason(reason);
  }

  static String? checkReopen(Examination e, String reason) {
    if (e.status != ExamStatus.completed && e.status != ExamStatus.withdrawn) {
      return 'Only a finalised or withdrawn result can be reopened.';
    }
    return _reason(reason);
  }

  static String? checkCancel(Examination e, String reason) {
    if (e.status == ExamStatus.published ||
        e.status == ExamStatus.completed ||
        e.status == ExamStatus.withdrawn ||
        e.status == ExamStatus.cancelled) {
      return 'A finalised or published examination cannot be cancelled; '
          'withdraw it first.';
    }
    return _reason(reason);
  }

  static String? _reason(String reason) => reason.trim().length < 3
      ? 'Give a reason (at least 3 characters).'
      : null;

  /// A sheet may be submitted when it can be edited and every student on the
  /// roster has a decided entry (zero, absent or exempted — never pending).
  static String? checkSubmitSheet({
    required MarksSheet? sheet,
    required ExaminationSubject subject,
    required List<MarksEntry> roster,
  }) {
    if (sheet != null && !sheet.status.isEditable) {
      return 'This sheet is ${sheet.status.displayName.toLowerCase()}.';
    }
    if (roster.isEmpty) return 'There are no students on this sheet.';
    var missing = 0;
    for (final e in roster) {
      if (e.status == MarkStatus.pending) {
        missing++;
        continue;
      }
      final problem = e.validate(subject);
      if (problem != null) return '${e.studentName}: $problem';
    }
    if (missing > 0) {
      return '$missing student(s) have no marks, absence or exemption yet.';
    }
    return null;
  }

  /// Teachers do not approve their own marks. A school administrator may (a
  /// school with a single administrator must be able to finish its results);
  /// the history records it either way.
  static String? checkApprove({
    required MarksSheet sheet,
    required String approverUserId,
    required bool approverIsSchoolAdmin,
  }) {
    if (sheet.status != SheetStatus.submitted) {
      return 'Only a submitted sheet can be approved.';
    }
    if (sheet.submittedBy == approverUserId && !approverIsSchoolAdmin) {
      return 'You submitted this sheet, so someone else must approve it.';
    }
    return null;
  }

  static String? checkReturn(MarksSheet sheet, String note) {
    if (sheet.status != SheetStatus.submitted &&
        sheet.status != SheetStatus.approved) {
      return 'Only a submitted or approved sheet can be returned.';
    }
    return _reason(note);
  }
}
