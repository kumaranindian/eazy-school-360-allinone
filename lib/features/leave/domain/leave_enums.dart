/// Whose leave it is. Students and staff share one application workflow but
/// have different rules (staff have entitlements and balances; students do
/// not — a student's leave is an absence record, not an employment benefit).
enum LeaveKind {
  student('STUDENT', 'Student'),
  staff('STAFF', 'Staff');

  final String wireValue;
  final String displayName;
  const LeaveKind(this.wireValue, this.displayName);

  static LeaveKind fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum LeavePayType {
  paid('PAID', 'Paid'),
  unpaid('UNPAID', 'Unpaid'),
  notApplicable('NA', 'Not applicable');

  final String wireValue;
  final String displayName;
  const LeavePayType(this.wireValue, this.displayName);

  static LeavePayType fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum LeaveStatus {
  pending('PENDING', 'Pending'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected'),
  withdrawn('WITHDRAWN', 'Withdrawn'),
  returned('RETURNED', 'Returned for correction'),
  cancelled('CANCELLED', 'Cancelled');

  final String wireValue;
  final String displayName;
  const LeaveStatus(this.wireValue, this.displayName);

  static LeaveStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);

  /// Still waiting on someone: the applicant may withdraw, a reviewer decides.
  bool get isOpen => this == pending || this == returned;

  /// Holds the days: the leave-day locks and the calendar entry exist.
  bool get holdsDays => this == pending || this == approved;
}

/// A half-day application covers one session of a single day.
enum HalfDay {
  none('NONE', 'Full day'),
  first('FIRST', 'First half'),
  second('SECOND', 'Second half');

  final String wireValue;
  final String displayName;
  const HalfDay(this.wireValue, this.displayName);

  static HalfDay fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// How a staff entitlement becomes available during the leave year.
enum AccrualMode {
  /// The whole annual entitlement is available from day one.
  upfront('UPFRONT', 'Whole entitlement up front'),

  /// 1/12 of the entitlement per elapsed month of the leave year.
  monthly('MONTHLY', 'Monthly accrual');

  final String wireValue;
  final String displayName;
  const AccrualMode(this.wireValue, this.displayName);

  static AccrualMode fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// What happens when an application asks for more than is available.
enum ExceedPolicy {
  block('BLOCK', 'Block the application'),
  warn('WARN', 'Warn, but allow (balance may go negative)');

  final String wireValue;
  final String displayName;
  const ExceedPolicy(this.wireValue, this.displayName);

  static ExceedPolicy fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum LedgerEntryType {
  consume('CONSUME', 'Leave taken'),
  restore('RESTORE', 'Leave restored'),
  adjustment('ADJUSTMENT', 'Manual adjustment'),
  carryForward('CARRY_FORWARD', 'Carry-forward');

  final String wireValue;
  final String displayName;
  const LedgerEntryType(this.wireValue, this.displayName);

  static LedgerEntryType fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// What last happened to an application. Rules tie each application change
/// to its history record by this value.
enum LeaveEvent {
  submit('SUBMIT'),
  approve('APPROVE'),
  reject('REJECT'),
  withdraw('WITHDRAW'),
  returnForCorrection('RETURN'),
  resubmit('RESUBMIT'),
  cancel('CANCEL');

  final String wireValue;
  const LeaveEvent(this.wireValue);

  static LeaveEvent fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}
