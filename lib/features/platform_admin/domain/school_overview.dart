import '../../../core/features/feature_catalogue.dart';

/// One school's metadata and head counts for the platform console. The server
/// never includes student, staff, parent or finance records here.
class SchoolOverview {
  final String id;
  final String name;
  final String code;
  final String status;
  final String email;
  final String phone;
  final String city;
  final String state;
  final String country;
  final String currency;
  final String timezone;
  final DateTime? createdAt;
  final List<OverviewBranch> branches;
  final int students;
  final int staff;
  final int parents;
  final List<OverviewAdmin> admins;
  final List<OverviewGrant> activeGrants;
  final List<OverviewAction> recentActions;

  /// Why the school is suspended (empty when it is not).
  final String statusReason;

  /// Platform switches (missing = on).
  final Map<String, bool> features;

  /// An offboarding in progress or finished, if any.
  final OverviewOffboarding? offboarding;

  bool featureOn(String key) => featureUsable(features, key);

  /// Any state in which the school's users are paused (everything but ACTIVE).
  bool get isSuspended => status.isNotEmpty && status != 'ACTIVE';
  bool get isInactive => status == 'INACTIVE';
  bool get isClosed => status == 'CLOSED';

  /// A request to recover a CLOSED school, if one exists.
  final OverviewRecovery? recovery;

  /// Null = legacy school (no subscription).
  final OverviewSubscription? subscription;

  const SchoolOverview({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.email,
    required this.phone,
    required this.city,
    required this.state,
    required this.country,
    required this.currency,
    required this.timezone,
    required this.createdAt,
    required this.branches,
    required this.students,
    required this.staff,
    required this.parents,
    required this.admins,
    required this.activeGrants,
    required this.recentActions,
    this.statusReason = '',
    this.features = const {},
    this.offboarding,
    this.recovery,
    this.subscription,
  });

  factory SchoolOverview.fromMap(Map<String, dynamic> m) {
    final s = Map<String, dynamic>.from(m['school'] as Map);
    final c = Map<String, dynamic>.from((m['counts'] as Map?) ?? const {});
    List<Map<String, dynamic>> rows(Object? v) => [
      for (final e in (v as List? ?? const []))
        Map<String, dynamic>.from(e as Map),
    ];
    DateTime? at(Object? ms) =>
        ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null;
    return SchoolOverview(
      id: s['id'] as String,
      statusReason: (s['statusReason'] as String?) ?? '',
      features: {
        for (final e in Map<String, dynamic>.from(
          (s['features'] as Map?) ?? const {},
        ).entries)
          if (e.value is bool) e.key: e.value as bool,
      },
      subscription: m['subscription'] is Map
          ? OverviewSubscription.fromMap(
              Map<String, dynamic>.from(m['subscription'] as Map),
            )
          : null,
      recovery: m['recovery'] is Map
          ? OverviewRecovery.fromMap(
              Map<String, dynamic>.from(m['recovery'] as Map),
            )
          : null,
      offboarding: m['offboarding'] is Map
          ? OverviewOffboarding.fromMap(
              Map<String, dynamic>.from(m['offboarding'] as Map),
            )
          : null,
      name: (s['name'] as String?) ?? '',
      code: (s['code'] as String?) ?? '',
      status: (s['status'] as String?) ?? '',
      email: (s['email'] as String?) ?? '',
      phone: (s['phone'] as String?) ?? '',
      city: (s['city'] as String?) ?? '',
      state: (s['state'] as String?) ?? '',
      country: (s['country'] as String?) ?? '',
      currency: (s['currency'] as String?) ?? '',
      timezone: (s['timezone'] as String?) ?? '',
      createdAt: at(s['createdAtMs']),
      branches: [
        for (final b in rows(m['branches']))
          OverviewBranch(
            id: b['id'] as String,
            name: (b['name'] as String?) ?? '',
            status: (b['status'] as String?) ?? '',
          ),
      ],
      students: (c['students'] as num?)?.toInt() ?? 0,
      staff: (c['staff'] as num?)?.toInt() ?? 0,
      parents: (c['parents'] as num?)?.toInt() ?? 0,
      admins: [
        for (final a in rows(m['admins']))
          OverviewAdmin(
            uid: a['uid'] as String,
            name: (a['name'] as String?) ?? '',
            email: (a['email'] as String?) ?? '',
            status: (a['status'] as String?) ?? '',
          ),
      ],
      activeGrants: [
        for (final g in rows(m['activeGrants']))
          OverviewGrant(
            adminUid: g['adminUid'] as String,
            adminName: (g['adminName'] as String?) ?? '',
            adminEmail: (g['adminEmail'] as String?) ?? '',
            reason: (g['reason'] as String?) ?? '',
            expiresAt: at(g['expiresAtMs']),
          ),
      ],
      recentActions: [
        for (final r in rows(m['recentActions']))
          OverviewAction(
            action: (r['action'] as String?) ?? '',
            actorEmail: (r['actorEmail'] as String?) ?? '',
            reason: r['reason'] as String?,
            at: at(r['atMs']),
          ),
      ],
    );
  }
}

class OverviewBranch {
  final String id;
  final String name;
  final String status;
  const OverviewBranch({
    required this.id,
    required this.name,
    required this.status,
  });
}

class OverviewAdmin {
  final String uid;
  final String name;
  final String email;
  final String status;
  const OverviewAdmin({
    required this.uid,
    required this.name,
    required this.email,
    required this.status,
  });
}

class OverviewGrant {
  final String adminUid;
  final String adminName;
  final String adminEmail;
  final String reason;
  final DateTime? expiresAt;
  const OverviewGrant({
    required this.adminUid,
    required this.adminName,
    required this.adminEmail,
    required this.reason,
    required this.expiresAt,
  });
}

class OverviewAction {
  final String action;
  final String actorEmail;
  final String? reason;
  final DateTime? at;
  const OverviewAction({
    required this.action,
    required this.actorEmail,
    required this.reason,
    required this.at,
  });
}

/// The offboarding workflow state of a school (nothing is purged automatically).
class OverviewOffboarding {
  final String state; // REQUESTED | APPROVED | CANCELLED
  final String reason;
  final String requestedBy;
  final String requestedByEmail;
  final DateTime? graceUntil;

  const OverviewOffboarding({
    required this.state,
    required this.reason,
    required this.requestedBy,
    required this.requestedByEmail,
    required this.graceUntil,
  });

  bool get isOpen => state == 'REQUESTED' || state == 'APPROVED';

  factory OverviewOffboarding.fromMap(Map<String, dynamic> m) =>
      OverviewOffboarding(
        state: (m['state'] as String?) ?? '',
        reason: (m['reason'] as String?) ?? '',
        requestedBy: (m['requestedBy'] as String?) ?? '',
        requestedByEmail: (m['requestedByEmail'] as String?) ?? '',
        graceUntil: m['graceUntilMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (m['graceUntilMs'] as num).toInt(),
              )
            : null,
      );
}

/// A request to recover a CLOSED school: a written reason, approved by a
/// DIFFERENT owner. The school then returns INACTIVE.
class OverviewRecovery {
  final String state; // REQUESTED | APPROVED | CANCELLED
  final String reason;
  final String requestedBy;
  final String requestedByEmail;

  const OverviewRecovery({
    required this.state,
    required this.reason,
    required this.requestedBy,
    required this.requestedByEmail,
  });

  bool get isOpen => state == 'REQUESTED';

  factory OverviewRecovery.fromMap(Map<String, dynamic> m) => OverviewRecovery(
    state: (m['state'] as String?) ?? '',
    reason: (m['reason'] as String?) ?? '',
    requestedBy: (m['requestedBy'] as String?) ?? '',
    requestedByEmail: (m['requestedByEmail'] as String?) ?? '',
  );
}

/// The school's subscription as the server reports it (status computed live).
/// A school without one is a legacy school and is never blocked by it.
class OverviewSubscription {
  final String? planName;
  final String classification; // TRIAL | PAID
  final String startDate; // yyyy-MM-dd in the school's time zone
  final String endDate;
  final int gracePeriodDays;
  final String
  status; // NOT_STARTED | TRIAL | ACTIVE | GRACE_PERIOD | EXPIRED | CANCELLED
  final String? remarks;
  final String? internalNotes;
  final String? cancellationReason;

  const OverviewSubscription({
    required this.planName,
    required this.classification,
    required this.startDate,
    required this.endDate,
    required this.gracePeriodDays,
    required this.status,
    this.remarks,
    this.internalNotes,
    this.cancellationReason,
  });

  factory OverviewSubscription.fromMap(Map<String, dynamic> m) =>
      OverviewSubscription(
        planName: m['planName'] as String?,
        classification: (m['classification'] as String?) ?? 'PAID',
        startDate: (m['startDate'] as String?) ?? '',
        endDate: (m['endDate'] as String?) ?? '',
        gracePeriodDays: (m['gracePeriodDays'] as num?)?.toInt() ?? 0,
        status: (m['status'] as String?) ?? 'EXPIRED',
        remarks: m['remarks'] as String?,
        internalNotes: m['internalNotes'] as String?,
        cancellationReason: m['cancellationReason'] as String?,
      );

  bool get blocking => status == 'EXPIRED' || status == 'CANCELLED';

  static String statusLabel(String s) => switch (s) {
    'NOT_STARTED' => 'Not started',
    'TRIAL' => 'Trial',
    'ACTIVE' => 'Active',
    'GRACE_PERIOD' => 'Grace period',
    'EXPIRED' => 'Expired',
    'CANCELLED' => 'Cancelled',
    _ => s,
  };
}
