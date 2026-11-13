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

  bool featureOn(String key) => features[key] != false;
  bool get isSuspended => status == 'SUSPENDED' || status == 'INACTIVE';

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
