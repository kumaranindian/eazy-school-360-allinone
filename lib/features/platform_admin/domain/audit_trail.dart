/// The central audit trail as the console sees it (`queryAuditEvents`).
/// Trust: T1 written with the change, T2 observed afterwards by a trigger,
/// T3 system job, T4 reported by the app (NOT proof).
library;

class AuditChange {
  final String field;

  /// False when the value is deliberately not recorded (personal or
  /// non-allow-listed fields): only the fact that it changed is kept.
  final bool hasValues;
  final Object? from;
  final Object? to;

  const AuditChange({
    required this.field,
    required this.hasValues,
    this.from,
    this.to,
  });

  factory AuditChange.fromMap(Map<String, dynamic> m) => AuditChange(
    field: (m['field'] as String?) ?? '',
    hasValues: m['changed'] != true,
    from: m['from'],
    to: m['to'],
  );
}

class AuditEventView {
  final String id;
  final String eventType;
  final String category;
  final String? schoolId;
  final String? branchId;
  final String? actorUserId;
  final String? actor;
  final String? actorRole;
  final String? application;
  final String? platform;
  final String? targetEntity;
  final String? targetEntityId;
  final String action;
  final String result; // SUCCESS | FAILURE | DENIED | FLAGGED
  final DateTime? at;
  final String source;
  final String trust;
  final bool clientReported;
  final String? description;
  final List<AuditChange> changes;
  final Map<String, dynamic> metadata;
  final String? correlationId;

  const AuditEventView({
    required this.id,
    required this.eventType,
    required this.category,
    required this.action,
    required this.result,
    required this.source,
    required this.trust,
    required this.clientReported,
    this.schoolId,
    this.branchId,
    this.actorUserId,
    this.actor,
    this.actorRole,
    this.application,
    this.platform,
    this.targetEntity,
    this.targetEntityId,
    this.at,
    this.description,
    this.changes = const [],
    this.metadata = const {},
    this.correlationId,
  });

  factory AuditEventView.fromMap(Map<String, dynamic> m) => AuditEventView(
    id: (m['id'] as String?) ?? '',
    eventType: (m['eventType'] as String?) ?? '',
    category: (m['category'] as String?) ?? '',
    action: (m['action'] as String?) ?? 'OTHER',
    result: (m['result'] as String?) ?? 'SUCCESS',
    source: (m['source'] as String?) ?? '',
    trust: (m['trust'] as String?) ?? '',
    clientReported: m['clientReported'] == true,
    schoolId: m['schoolId'] as String?,
    branchId: m['branchId'] as String?,
    actorUserId: m['actorUserId'] as String?,
    actor: m['actor'] as String?,
    actorRole: m['actorRole'] as String?,
    application: m['application'] as String?,
    platform: m['platform'] as String?,
    targetEntity: m['targetEntity'] as String?,
    targetEntityId: m['targetEntityId'] as String?,
    at: m['atMs'] is num
        ? DateTime.fromMillisecondsSinceEpoch((m['atMs'] as num).toInt())
        : null,
    description: m['description'] as String?,
    changes: [
      for (final c in (m['changes'] as List? ?? const []))
        AuditChange.fromMap(Map<String, dynamic>.from(c as Map)),
    ],
    metadata: Map<String, dynamic>.from((m['metadata'] as Map?) ?? const {}),
    correlationId: m['correlationId'] as String?,
  );

  bool get denied => result == 'DENIED';
  bool get failed => result == 'FAILURE';

  /// A plain-language label for how much to trust this entry.
  String get trustLabel => switch (trust) {
    'T1' => 'Recorded with the change',
    'T2' => 'Observed after the change',
    'T3' => 'System job',
    'T4' => 'Reported by the app (not verified)',
    _ => trust,
  };

  /// "STUDENT_UPDATED" -> "Student updated".
  String get title {
    final words = eventType.toLowerCase().replaceAll('_', ' ');
    return words.isEmpty ? '' : words[0].toUpperCase() + words.substring(1);
  }
}

/// One page of events and where the next one starts (null = no more).
class AuditPage {
  final List<AuditEventView> events;
  final Map<String, dynamic>? nextCursor;
  final bool truncated;

  const AuditPage({
    required this.events,
    this.nextCursor,
    this.truncated = false,
  });

  factory AuditPage.fromMap(Map<String, dynamic> m) => AuditPage(
    events: [
      for (final e in (m['events'] as List? ?? const []))
        AuditEventView.fromMap(Map<String, dynamic>.from(e as Map)),
    ],
    nextCursor: m['nextCursor'] is Map
        ? Map<String, dynamic>.from(m['nextCursor'] as Map)
        : null,
    truncated: m['truncated'] == true,
  );
}

class AuditSummary {
  final int hours;
  final int total;
  final Map<String, int> byCategory;
  final int denied;
  final int failures;
  final int clientReported;

  const AuditSummary({
    required this.hours,
    required this.total,
    required this.byCategory,
    required this.denied,
    required this.failures,
    required this.clientReported,
  });

  factory AuditSummary.fromMap(Map<String, dynamic> m) => AuditSummary(
    hours: (m['hours'] as num?)?.toInt() ?? 24,
    total: (m['total'] as num?)?.toInt() ?? 0,
    byCategory: {
      for (final e in Map<String, dynamic>.from(
        (m['byCategory'] as Map?) ?? const {},
      ).entries)
        e.key: (e.value as num).toInt(),
    },
    denied: (m['denied'] as num?)?.toInt() ?? 0,
    failures: (m['failures'] as num?)?.toInt() ?? 0,
    clientReported: (m['clientReported'] as num?)?.toInt() ?? 0,
  );
}

/// What the person asked to see. Every field is optional except the window.
class AuditFilter {
  final int hours; // window ending now: 24, 168, 720 or 2160 (92 days max)
  final String? schoolId;
  final String? actorUserId;
  final String? category;
  final String? result;
  final String? source;
  final String? eventType;

  const AuditFilter({
    this.hours = 168,
    this.schoolId,
    this.actorUserId,
    this.category,
    this.result,
    this.source,
    this.eventType,
  });

  static const windows = [24, 168, 720, 2160];

  static String windowLabel(int hours) => switch (hours) {
    24 => 'Last 24 hours',
    168 => 'Last 7 days',
    720 => 'Last 30 days',
    2160 => 'Last 90 days',
    _ => 'Last $hours hours',
  };

  AuditFilter copyWith({
    int? hours,
    Object? schoolId = _keep,
    Object? actorUserId = _keep,
    Object? category = _keep,
    Object? result = _keep,
    Object? source = _keep,
    Object? eventType = _keep,
  }) => AuditFilter(
    hours: hours ?? this.hours,
    schoolId: identical(schoolId, _keep) ? this.schoolId : schoolId as String?,
    actorUserId: identical(actorUserId, _keep)
        ? this.actorUserId
        : actorUserId as String?,
    category: identical(category, _keep) ? this.category : category as String?,
    result: identical(result, _keep) ? this.result : result as String?,
    source: identical(source, _keep) ? this.source : source as String?,
    eventType: identical(eventType, _keep)
        ? this.eventType
        : eventType as String?,
  );

  /// The server request for [now]; blank values are left out.
  Map<String, Object?> toRequest(DateTime now) {
    String? t(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    return {
      'fromMs': now.subtract(Duration(hours: hours)).millisecondsSinceEpoch,
      'toMs': now.millisecondsSinceEpoch,
      'schoolId': ?t(schoolId),
      'actorUserId': ?t(actorUserId),
      'category': ?t(category),
      'result': ?t(result),
      'source': ?t(source),
      'eventType': ?t(eventType),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is AuditFilter &&
      other.hours == hours &&
      other.schoolId == schoolId &&
      other.actorUserId == actorUserId &&
      other.category == category &&
      other.result == result &&
      other.source == source &&
      other.eventType == eventType;

  @override
  int get hashCode => Object.hash(
    hours,
    schoolId,
    actorUserId,
    category,
    result,
    source,
    eventType,
  );

  /// Ready-made views: what a security reviewer or a school-by-school look needs.
  static const security = AuditFilter(category: 'SECURITY');
  static const denied = AuditFilter(result: 'DENIED');
  static const clientReportedOnly = AuditFilter(source: 'CLIENT_REPORTED');
}

const Object _keep = Object();

const auditCategories = [
  'AUTHENTICATION',
  'SCHOOL',
  'SUBSCRIPTION',
  'FEATURE',
  'STUDENT',
  'PARENT',
  'STAFF',
  'ATTENDANCE_LEAVE',
  'FEES',
  'ACADEMIC',
  'ADMISSION',
  'COMMUNICATION',
  'DATA_CONFIG',
  'PLATFORM',
  'SECURITY',
];

String auditCategoryLabel(String c) {
  final w = c.toLowerCase().replaceAll('_', ' / ');
  return w.isEmpty ? c : w[0].toUpperCase() + w.substring(1);
}
