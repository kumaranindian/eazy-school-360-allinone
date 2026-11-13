/// One platform action from `platformAuditLog`.
class AuditEntry {
  final String id;
  final String action;
  final String actorEmail;
  final String actorRole;
  final String targetEmail;
  final String schoolId;
  final String reason;
  final String result;
  final String source;
  final DateTime? at;

  const AuditEntry({
    required this.id,
    required this.action,
    required this.actorEmail,
    required this.actorRole,
    required this.targetEmail,
    required this.schoolId,
    required this.reason,
    required this.result,
    required this.source,
    required this.at,
  });

  /// "SUPPORT_ACCESS_GRANTED" -> "Support access granted".
  String get actionLabel {
    final words = action.toLowerCase().split('_').where((w) => w.isNotEmpty);
    final text = words.join(' ');
    return text.isEmpty ? '' : text[0].toUpperCase() + text.substring(1);
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      action,
      actorEmail,
      targetEmail,
      schoolId,
      reason,
    ].any((v) => v.toLowerCase().contains(q));
  }
}
