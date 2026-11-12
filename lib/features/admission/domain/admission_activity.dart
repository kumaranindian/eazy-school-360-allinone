/// The kind of contact a follow-up is. The wire value is what
/// `functions/admission_activities.js` stores (`TYPES`).
enum ActivityType {
  phoneCall('PHONE_CALL', 'Phone call'),
  whatsapp('WHATSAPP', 'WhatsApp'),
  email('EMAIL', 'Email'),
  schoolVisit('SCHOOL_VISIT', 'School visit'),
  meeting('MEETING', 'Meeting'),
  other('OTHER', 'Other');

  final String wire;
  final String label;
  const ActivityType(this.wire, this.label);

  static ActivityType? tryParse(String? wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return null;
  }
}

enum ActivityStatus {
  scheduled('SCHEDULED', 'Scheduled'),
  completed('COMPLETED', 'Completed'),
  cancelled('CANCELLED', 'Cancelled');

  final String wire;
  final String label;
  const ActivityStatus(this.wire, this.label);

  static ActivityStatus? tryParse(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return null;
  }
}

/// Why a family is visiting the school (`PURPOSES` in the server).
enum VisitPurpose {
  campusTour('CAMPUS_TOUR', 'Campus tour'),
  meetPrincipal('MEET_PRINCIPAL', 'Meet the principal'),
  assessment('ASSESSMENT', 'Assessment'),
  counselling('COUNSELLING', 'Counselling'),
  other('OTHER', 'Other');

  final String wire;
  final String label;
  const VisitPurpose(this.wire, this.label);

  static VisitPurpose? tryParse(String? wire) {
    for (final p in values) {
      if (p.wire == wire) return p;
    }
    return null;
  }
}

/// The lists on the follow-up dashboard.
enum FollowUpBucket {
  today('Today'),
  overdue('Overdue'),
  upcoming('Upcoming'),
  visits('Visits'),
  mine('Mine'),
  unassigned('Unassigned'),
  completed('Completed');

  final String label;
  const FollowUpBucket(this.label);
}

/// Headline numbers of the follow-up dashboard (server-side `count()`s).
class FollowUpCounts {
  final int today;
  final int overdue;
  final int upcoming;

  /// Open school visits dated today or later.
  final int visits;
  final int mine;
  final int unassigned;
  final int completed;

  /// Open enquiries with no follow-up date at all.
  final int withoutFollowUp;

  const FollowUpCounts({
    this.today = 0,
    this.overdue = 0,
    this.upcoming = 0,
    this.visits = 0,
    this.mine = 0,
    this.unassigned = 0,
    this.completed = 0,
    this.withoutFollowUp = 0,
  });

  int of(FollowUpBucket b) => switch (b) {
    FollowUpBucket.today => today,
    FollowUpBucket.overdue => overdue,
    FollowUpBucket.upcoming => upcoming,
    FollowUpBucket.visits => visits,
    FollowUpBucket.mine => mine,
    FollowUpBucket.unassigned => unassigned,
    FollowUpBucket.completed => completed,
  };
}

/// What `scheduleAdmissionActivity` accepts for one activity.
class ActivityInput {
  final ActivityType type;
  final String scheduledDate; // yyyy-mm-dd, school time
  final String? scheduledTime; // hh:mm
  final String? remarks;

  /// Set for a school visit (sent through `scheduleAdmissionVisit`).
  final VisitPurpose? purpose;

  /// When true, [assignedTo] (even null = nobody) is sent; otherwise the
  /// server uses the enquiry's assignee.
  final bool assignExplicitly;
  final String? assignedTo;

  const ActivityInput({
    required this.type,
    required this.scheduledDate,
    this.scheduledTime,
    this.remarks,
    this.purpose,
    this.assignExplicitly = false,
    this.assignedTo,
  });

  Map<String, dynamic> toWire() => {
    'type': type.wire,
    'scheduledDate': scheduledDate,
    'scheduledTime': scheduledTime,
    'remarks': remarks,
    if (purpose != null) 'purpose': purpose!.wire,
    if (assignExplicitly) 'assignedTo': assignedTo,
  };
}

/// What `completeAdmissionActivity` accepts.
class ActivityCompletion {
  final String outcome;
  final String? parentFeedback;
  final String? remarks;
  const ActivityCompletion({
    required this.outcome,
    this.parentFeedback,
    this.remarks,
  });

  Map<String, dynamic> toWire() => {
    'outcome': outcome,
    'parentFeedback': parentFeedback,
    'remarks': remarks,
  };
}

/// A follow-up activity as read from Firestore.
class AdmissionActivity {
  final String id;
  final String enquiryId;
  final String enquiryNumber;
  final String studentName;
  final ActivityType type;
  final VisitPurpose? purpose;
  final ActivityStatus status;
  final String scheduledDate;
  final String? scheduledTime;
  final String? assignedTo;
  final String? remarks;
  final String? outcome;
  final String? parentFeedback;
  final String? cancelReason;
  final int rescheduleCount;
  final int revision;
  final DateTime? completedAt;

  const AdmissionActivity({
    required this.id,
    required this.enquiryId,
    required this.enquiryNumber,
    required this.studentName,
    required this.type,
    required this.status,
    required this.scheduledDate,
    required this.revision,
    this.scheduledTime,
    this.purpose,
    this.assignedTo,
    this.remarks,
    this.outcome,
    this.parentFeedback,
    this.cancelReason,
    this.rescheduleCount = 0,
    this.completedAt,
  });

  bool get isOpen => status == ActivityStatus.scheduled;

  /// A school visit (also moves the enquiry's status on the server).
  bool get isVisit => type == ActivityType.schoolVisit;

  /// Open and dated before [todayKey].
  bool isOverdue(String todayKey) =>
      isOpen && scheduledDate.compareTo(todayKey) < 0;

  factory AdmissionActivity.fromMap(
    String id,
    Map<String, dynamic> d, {
    DateTime? completedAt,
  }) => AdmissionActivity(
    id: id,
    enquiryId: d['enquiryId'] as String? ?? '',
    enquiryNumber: d['enquiryNumber'] as String? ?? '',
    studentName: d['studentName'] as String? ?? '',
    type: ActivityType.tryParse(d['type'] as String?) ?? ActivityType.other,
    status:
        ActivityStatus.tryParse(d['status'] as String?) ??
        ActivityStatus.scheduled,
    scheduledDate: d['scheduledDate'] as String? ?? '',
    scheduledTime: d['scheduledTime'] as String?,
    purpose: VisitPurpose.tryParse(d['purpose'] as String?),
    assignedTo: d['assignedTo'] as String?,
    remarks: d['remarks'] as String?,
    outcome: d['outcome'] as String?,
    parentFeedback: d['parentFeedback'] as String?,
    cancelReason: d['cancelReason'] as String?,
    rescheduleCount: d['rescheduleCount'] is int
        ? d['rescheduleCount'] as int
        : 0,
    revision: d['revision'] is int ? d['revision'] as int : 1,
    completedAt: completedAt,
  );
}

/// What happened to an activity (`admissionActivityHistory`).
enum ActivityEvent {
  created('CREATED'),
  rescheduled('RESCHEDULED'),
  reassigned('REASSIGNED'),
  completed('COMPLETED'),
  cancelled('CANCELLED');

  final String wire;
  const ActivityEvent(this.wire);

  static ActivityEvent? tryParse(String? wire) {
    for (final e in values) {
      if (e.wire == wire) return e;
    }
    return null;
  }
}

/// One immutable line of an activity's history, enough to say what happened
/// without loading the activity itself.
class ActivityHistoryEntry {
  final String activityId;
  final int revision;
  final ActivityEvent event;
  final ActivityType type;
  final VisitPurpose? purpose;
  final String? fromDate;
  final String? toDate;
  final String? toTime;
  final String? reason;
  final String actorId;
  final DateTime? at;

  const ActivityHistoryEntry({
    required this.activityId,
    required this.revision,
    required this.event,
    required this.type,
    required this.actorId,
    this.purpose,
    this.fromDate,
    this.toDate,
    this.toTime,
    this.reason,
    this.at,
  });

  bool get isVisit => type == ActivityType.schoolVisit;

  factory ActivityHistoryEntry.fromMap(Map<String, dynamic> d, {DateTime? at}) {
    Map<String, dynamic> m(Object? v) =>
        v is Map ? v.cast<String, dynamic>() : const {};
    final from = m(d['from']);
    final to = m(d['to']);
    return ActivityHistoryEntry(
      activityId: d['activityId'] as String? ?? '',
      revision: d['revision'] is int ? d['revision'] as int : 0,
      event:
          ActivityEvent.tryParse(d['event'] as String?) ??
          ActivityEvent.created,
      type: ActivityType.tryParse(d['type'] as String?) ?? ActivityType.other,
      purpose: VisitPurpose.tryParse(d['purpose'] as String?),
      fromDate: from['scheduledDate'] as String?,
      toDate: to['scheduledDate'] as String?,
      toTime: to['scheduledTime'] as String?,
      reason: d['reason'] as String?,
      actorId: d['actorId'] as String? ?? '',
      at: at,
    );
  }
}
