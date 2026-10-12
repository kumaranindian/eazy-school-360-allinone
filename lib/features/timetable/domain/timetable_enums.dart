enum SlotKind {
  teaching('TEACHING', 'Teaching period'),
  breakSlot('BREAK', 'Break'),
  lunch('LUNCH', 'Lunch'),
  assembly('ASSEMBLY', 'Assembly'),
  other('OTHER', 'Other');

  final String wireValue;
  final String displayName;
  const SlotKind(this.wireValue, this.displayName);

  bool get isTeaching => this == teaching;

  static SlotKind fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum TimetableStatus {
  draft('DRAFT', 'Draft'),
  published('PUBLISHED', 'Published'),
  archived('ARCHIVED', 'Archived');

  final String wireValue;
  final String displayName;
  const TimetableStatus(this.wireValue, this.displayName);

  static TimetableStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum SubstitutionStatus {
  active('ACTIVE', 'Active'),
  cancelled('CANCELLED', 'Cancelled');

  final String wireValue;
  final String displayName;
  const SubstitutionStatus(this.wireValue, this.displayName);

  static SubstitutionStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum SubstitutionReasonKind {
  leave('LEAVE', 'Approved leave'),
  absence('ABSENCE', 'Absence'),
  duty('DUTY', 'School duty'),
  other('OTHER', 'Other');

  final String wireValue;
  final String displayName;
  const SubstitutionReasonKind(this.wireValue, this.displayName);

  static SubstitutionReasonKind fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// What last happened to a timetable / substitution (history + rules).
enum TimetableEvent {
  created('CREATED'),
  edited('EDITED'),
  published('PUBLISHED'),
  superseded('SUPERSEDED'),
  truncated('TRUNCATED'),
  archived('ARCHIVED');

  final String wireValue;
  const TimetableEvent(this.wireValue);

  static TimetableEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum SubstitutionEvent {
  assigned('ASSIGNED'),
  changed('CHANGED'),
  cancelled('CANCELLED'),
  reinstated('REINSTATED');

  final String wireValue;
  const SubstitutionEvent(this.wireValue);

  static SubstitutionEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum IssueSeverity { error, warning }

enum IssueKind {
  invalidSlot('INVALID_SLOT'),
  nonWorkingDay('NON_WORKING_DAY'),
  missingPeriodSet('MISSING_PERIOD_SET'),
  notAssigned('NOT_ASSIGNED'),
  teacherConflict('TEACHER_CONFLICT'),
  roomConflict('ROOM_CONFLICT'),
  sectionOverlap('SECTION_OVERLAP'),
  teacherOnLeave('TEACHER_ON_LEAVE'),
  empty('EMPTY'),
  stalePeriods('STALE_PERIODS');

  final String wireValue;
  const IssueKind(this.wireValue);
}
