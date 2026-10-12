/// Examination lifecycle. A published result is never edited in place: it is
/// *withdrawn*, corrected through the marks workflow, finalised again as a new
/// version and published again.
enum ExamStatus {
  draft('DRAFT', 'Draft'),
  scheduled('SCHEDULED', 'Scheduled'),
  inProgress('IN_PROGRESS', 'Marks entry'),
  completed('COMPLETED', 'Finalised'),
  published('PUBLISHED', 'Published'),
  withdrawn('WITHDRAWN', 'Withdrawn'),
  cancelled('CANCELLED', 'Cancelled');

  final String wireValue;
  final String displayName;
  const ExamStatus(this.wireValue, this.displayName);

  /// Configuration (dates, subjects, marks) may change.
  bool get isConfigurable => this == draft || this == scheduled;

  /// Marks may be entered or corrected.
  bool get acceptsMarks => this == inProgress;

  static ExamStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum ExamType {
  unitTest('UNIT_TEST', 'Unit test'),
  quarterly('QUARTERLY', 'Quarterly'),
  halfYearly('HALF_YEARLY', 'Half-yearly'),
  annual('ANNUAL', 'Annual'),
  practical('PRACTICAL', 'Practical'),
  other('OTHER', 'Other assessment');

  final String wireValue;
  final String displayName;
  const ExamType(this.wireValue, this.displayName);

  static ExamType fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v, orElse: () => other);
}

/// What a marks entry means. **Zero is `entered` with marks 0** — never
/// confused with absent, exempted or not yet entered.
enum MarkStatus {
  entered('ENTERED', 'Entered'),
  absent('ABSENT', 'Absent'),
  exempted('EXEMPTED', 'Exempted'),
  pending('PENDING', 'Pending');

  final String wireValue;
  final String displayName;
  const MarkStatus(this.wireValue, this.displayName);

  static MarkStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// Marks sheet (one subject in one section) review state.
enum SheetStatus {
  draft('DRAFT', 'Draft'),
  submitted('SUBMITTED', 'Submitted for review'),
  approved('APPROVED', 'Approved'),
  returned('RETURNED', 'Returned');

  final String wireValue;
  final String displayName;
  const SheetStatus(this.wireValue, this.displayName);

  bool get isEditable => this == draft || this == returned;

  static SheetStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum ExamEvent {
  created('CREATED'),
  edited('EDITED'),
  scheduled('SCHEDULED'),
  started('STARTED'),
  finalized('FINALIZED'),
  published('PUBLISHED'),
  withdrawn('WITHDRAWN'),
  reopened('REOPENED'),
  cancelled('CANCELLED');

  final String wireValue;
  const ExamEvent(this.wireValue);

  static ExamEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum SheetEvent {
  saved('SAVED'),
  submitted('SUBMITTED'),
  approved('APPROVED'),
  returned('RETURNED');

  final String wireValue;
  const SheetEvent(this.wireValue);

  static SheetEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// How an absent subject enters the aggregate.
enum AbsentPolicy {
  /// Left out of totals and percentages; the report card says "Absent".
  exclude('EXCLUDE', 'Excluded from totals'),

  /// Counted as zero out of the maximum, and as a failed subject.
  zero('ZERO', 'Counted as zero (fails)');

  final String wireValue;
  final String displayName;
  const AbsentPolicy(this.wireValue, this.displayName);

  static AbsentPolicy fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v, orElse: () => exclude);
}

/// How percentages and marks are rounded to the configured precision.
enum RoundingMode {
  halfUp('HALF_UP', 'Half up (0.5 → 1)'),
  down('DOWN', 'Down (truncate)');

  final String wireValue;
  final String displayName;
  const RoundingMode(this.wireValue, this.displayName);

  static RoundingMode fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v, orElse: () => halfUp);
}

/// How an overall percentage combines subjects.
enum AggregateMethod {
  /// Σ obtained ÷ Σ maximum.
  total('TOTAL', 'Total marks'),

  /// Σ(percentage × weightage) ÷ Σ weightage.
  weighted('WEIGHTED', 'Weighted average');

  final String wireValue;
  final String displayName;
  const AggregateMethod(this.wireValue, this.displayName);

  static AggregateMethod fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v, orElse: () => total);
}
