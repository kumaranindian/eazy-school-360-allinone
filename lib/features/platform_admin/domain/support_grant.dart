/// A time-boxed, read-only support grant (`supportGrants/{admin}__{school}`).
/// Written only by the server; the app reads it to resume a session and to show
/// the school who has access.
class SupportGrant {
  final String schoolId;
  final String adminUid;
  final String adminName;
  final String adminEmail;
  final String reason;
  final String? ticket;
  final DateTime? expiresAt;
  final bool revoked;

  const SupportGrant({
    required this.schoolId,
    required this.adminUid,
    required this.adminName,
    required this.adminEmail,
    required this.reason,
    required this.ticket,
    required this.expiresAt,
    required this.revoked,
  });

  /// Still usable at [now]: not revoked and not past its expiry.
  bool isActiveAt(DateTime now) =>
      !revoked && expiresAt != null && now.isBefore(expiresAt!);

  factory SupportGrant.fromMap(Map<String, dynamic> m) => SupportGrant(
    schoolId: (m['schoolId'] as String?) ?? '',
    adminUid: (m['adminUid'] as String?) ?? '',
    adminName: (m['adminName'] as String?) ?? '',
    adminEmail: (m['adminEmail'] as String?) ?? '',
    reason: (m['reason'] as String?) ?? '',
    ticket: m['ticket'] as String?,
    expiresAt: _date(m['expiresAt']),
    revoked: m['revokedAt'] != null,
  );
}

/// One line of the school-visible support access log.
class SupportAccessLogEntry {
  final String event; // GRANTED | REVOKED
  final String adminName;
  final String adminEmail;
  final String? reason;
  final String? ticket;
  final DateTime? expiresAt;
  final DateTime? at;
  final String? revokedBy;

  const SupportAccessLogEntry({
    required this.event,
    required this.adminName,
    required this.adminEmail,
    required this.reason,
    required this.ticket,
    required this.expiresAt,
    required this.at,
    required this.revokedBy,
  });

  factory SupportAccessLogEntry.fromMap(Map<String, dynamic> m) =>
      SupportAccessLogEntry(
        event: (m['event'] as String?) ?? '',
        adminName: (m['adminName'] as String?) ?? '',
        adminEmail: (m['adminEmail'] as String?) ?? '',
        reason: m['reason'] as String?,
        ticket: m['ticket'] as String?,
        expiresAt: _date(m['expiresAt']),
        at: _date(m['createdAt']),
        revokedBy: m['revokedBy'] as String?,
      );
}

DateTime? _date(Object? v) {
  if (v is DateTime) return v;
  // Firestore Timestamp exposes toDate(); avoid importing it in the domain.
  try {
    final d = (v as dynamic)?.toDate();
    return d is DateTime ? d : null;
  } catch (_) {
    return null;
  }
}
