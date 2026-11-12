/// Lifecycle status of an admission enquiry. The wire value is what the
/// admission Cloud Functions store (`functions/admission.js` STATUSES).
///
/// The server owns the state machine; this enum only describes statuses for
/// display and for which direct changes the UI offers ([manualTargets] mirrors
/// `MANUAL_TARGETS` there). The server refuses anything else regardless.
enum AdmissionStatus {
  newEnquiry('NEW', 'New'),
  contacted('CONTACTED', 'Contacted'),
  interested('INTERESTED', 'Interested'),
  visitScheduled('VISIT_SCHEDULED', 'Visit scheduled'),
  visitCompleted('VISIT_COMPLETED', 'Visit completed'),
  applicationSubmitted('APPLICATION_SUBMITTED', 'Application submitted'),
  underReview('UNDER_REVIEW', 'Under review'),
  approved('APPROVED', 'Approved'),
  admissionConfirmed('ADMISSION_CONFIRMED', 'Admission confirmed'),
  onHold('ON_HOLD', 'On hold'),
  rejected('REJECTED', 'Rejected'),
  withdrawn('WITHDRAWN', 'Withdrawn'),
  notInterested('NOT_INTERESTED', 'Not interested');

  final String wire;
  final String label;
  const AdmissionStatus(this.wire, this.label);

  static AdmissionStatus? tryParse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }

  /// Statuses a person may set directly (the lead stages).
  static const List<AdmissionStatus> manualTargets = [
    contacted,
    interested,
    notInterested,
    onHold,
    rejected,
    withdrawn,
  ];

  /// Finished: nothing further can happen to the enquiry.
  bool get isClosed =>
      this == rejected || this == withdrawn || this == admissionConfirmed;

  /// Still moving through the pipeline (not closed, not dropped).
  bool get isOpen => !isClosed && this != notInterested;

  /// Whether the server requires a reason for moving to this status.
  bool get needsReason => this == rejected || this == withdrawn;

  /// The direct changes the UI offers from this status. Mirrors the server's
  /// state machine for the lead stages (`functions/admission.js`
  /// `TRANSITIONS` ∩ `MANUAL_TARGETS`); the server remains the authority, so
  /// a drift here can only hide or show a button, never allow a change.
  /// `RESUME` returns an enquiry on hold to the status it was on.
  List<String> manualOptions() {
    const alternates = ['NOT_INTERESTED', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'];
    switch (this) {
      case newEnquiry:
        return ['CONTACTED', 'INTERESTED', ...alternates];
      case contacted:
        return ['INTERESTED', ...alternates];
      case interested:
        return alternates;
      case visitScheduled:
      case visitCompleted:
        return ['INTERESTED', ...alternates];
      case applicationSubmitted:
      case underReview:
      case approved:
        return ['ON_HOLD', 'REJECTED', 'WITHDRAWN'];
      case onHold:
        return ['RESUME', 'NOT_INTERESTED', 'REJECTED', 'WITHDRAWN'];
      case notInterested:
        return ['CONTACTED', 'INTERESTED'];
      case rejected:
      case withdrawn:
      case admissionConfirmed:
        return const [];
    }
  }
}
