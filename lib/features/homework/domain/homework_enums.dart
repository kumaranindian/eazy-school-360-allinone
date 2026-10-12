enum HomeworkStatus {
  draft('DRAFT', 'Draft'),
  published('PUBLISHED', 'Published'),
  closed('CLOSED', 'Closed'),
  archived('ARCHIVED', 'Archived');

  final String wireValue;
  final String displayName;
  const HomeworkStatus(this.wireValue, this.displayName);

  /// Students may submit (subject to the due date and late policy).
  bool get acceptsSubmissions => this == published;

  /// Visible to students and parents.
  bool get isVisibleToFamilies => this == published || this == closed;

  static HomeworkStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// A student's standing on one homework. NOT_SUBMITTED is never stored: it is
/// the *absence* of a submission document. Opening the detail page creates
/// nothing, so it can never be mistaken for completion.
enum SubmissionStatus {
  notSubmitted('NOT_SUBMITTED', 'Not submitted'),
  submitted('SUBMITTED', 'Submitted'),
  lateSubmitted('LATE_SUBMITTED', 'Submitted late'),
  returnedForRevision('RETURNED_FOR_REVISION', 'Returned for revision'),
  resubmitted('RESUBMITTED', 'Resubmitted'),
  graded('GRADED', 'Graded');

  final String wireValue;
  final String displayName;
  const SubmissionStatus(this.wireValue, this.displayName);

  bool get isStored => this != notSubmitted;

  /// Work the teacher still has to look at.
  bool get awaitsReview =>
      this == submitted || this == lateSubmitted || this == resubmitted;

  static SubmissionStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum HomeworkEvent {
  created('CREATED'),
  edited('EDITED'),
  published('PUBLISHED'),
  dueChanged('DUE_CHANGED'),
  closed('CLOSED'),
  archived('ARCHIVED');

  final String wireValue;
  const HomeworkEvent(this.wireValue);

  static HomeworkEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum SubmissionEvent {
  submit('SUBMIT'),
  resubmit('RESUBMIT'),
  returnForRevision('RETURN'),
  grade('GRADE'),
  review('REVIEW');

  final String wireValue;
  const SubmissionEvent(this.wireValue);

  static SubmissionEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}
