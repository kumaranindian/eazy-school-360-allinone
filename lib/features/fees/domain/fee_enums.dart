enum FeeCategory {
  tuition('TUITION', 'Tuition'),
  admission('ADMISSION', 'Admission'),
  examination('EXAMINATION', 'Examination'),
  transport('TRANSPORT', 'Transport'),
  books('BOOKS', 'Books'),
  uniform('UNIFORM', 'Uniform'),
  activity('ACTIVITY', 'Activity'),
  other('OTHER', 'Other');

  final String wireValue;
  final String displayName;

  const FeeCategory(this.wireValue, this.displayName);

  static FeeCategory fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// How often a fee is billed; also the *kind* of billing period an invoice
/// for it belongs to.
enum FeeFrequency {
  oneTime('ONE_TIME', 'One time'),
  monthly('MONTHLY', 'Monthly'),
  quarterly('QUARTERLY', 'Quarterly'),
  halfYearly('HALF_YEARLY', 'Half-yearly'),
  annual('ANNUAL', 'Annual'),
  custom('CUSTOM', 'Custom period');

  final String wireValue;
  final String displayName;

  const FeeFrequency(this.wireValue, this.displayName);

  static FeeFrequency fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum ConcessionType {
  none('NONE', 'None'),
  percent('PERCENT', 'Percentage'),
  fixed('FIXED', 'Fixed amount');

  final String wireValue;
  final String displayName;

  const ConcessionType(this.wireValue, this.displayName);

  static ConcessionType fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum PaymentMethod {
  cash('CASH', 'Cash'),
  upi('UPI', 'UPI'),
  bankTransfer('BANK_TRANSFER', 'Bank transfer'),
  cheque('CHEQUE', 'Cheque'),
  other('OTHER', 'Other');

  final String wireValue;
  final String displayName;

  const PaymentMethod(this.wireValue, this.displayName);

  /// UPI, bank transfers and cheques must carry a reference/cheque number.
  bool get needsReference =>
      this == upi || this == bankTransfer || this == cheque;

  static PaymentMethod fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// ISSUED -> PARTIALLY_PAID -> PAID as money arrives (and back again when a
/// payment is reversed); VOID is terminal and only reachable with nothing
/// paid. "Overdue" is **not** a stored status: it is derived from the due
/// date, so it can never go stale.
enum InvoiceStatus {
  issued('ISSUED', 'Issued'),
  partiallyPaid('PARTIALLY_PAID', 'Partially paid'),
  paid('PAID', 'Paid'),
  voided('VOID', 'Void');

  final String wireValue;
  final String displayName;

  const InvoiceStatus(this.wireValue, this.displayName);

  bool get isOpen => this == issued || this == partiallyPaid;

  static InvoiceStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

enum PaymentStatus {
  active('ACTIVE', 'Active'),
  reversed('REVERSED', 'Reversed');

  final String wireValue;
  final String displayName;

  const PaymentStatus(this.wireValue, this.displayName);

  static PaymentStatus fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}

/// A reversal cancels a payment that should not have been recorded (wrong
/// amount, bounced cheque); a refund returns money that was validly paid.
/// Both remove the payment from the invoice and are recorded, never edited
/// in place; partial refunds are not supported.
enum ReversalKind {
  reversal('REVERSAL', 'Reversal'),
  refund('REFUND', 'Refund');

  final String wireValue;
  final String displayName;

  const ReversalKind(this.wireValue, this.displayName);

  static ReversalKind fromWireValue(String v) =>
      values.firstWhere((e) => e.wireValue == v);
}
