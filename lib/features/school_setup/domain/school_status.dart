/// Lifecycle state of a school (platform-controlled; clients never write it).
///
/// * [inactive]: created but not activated by the platform. Every new school
///   starts here. Users are paused.
/// * [active]: usable (subject to subscription and module settings).
/// * [suspended]: paused by the platform. Data is kept.
/// * [expired]: the subscription ended. Data is kept.
/// * [closed]: terminal; only a two-owner recovery reopens it.
enum SchoolStatus {
  active,
  inactive,
  suspended,
  expired,
  closed;

  static const Map<SchoolStatus, String> _wireValues = {
    SchoolStatus.active: 'ACTIVE',
    SchoolStatus.inactive: 'INACTIVE',
    SchoolStatus.suspended: 'SUSPENDED',
    SchoolStatus.expired: 'EXPIRED',
    SchoolStatus.closed: 'CLOSED',
  };

  String get wireValue => _wireValues[this]!;

  /// True for every state in which the school's users are paused.
  bool get isPaused => this != active;

  /// An unknown value (a state added by a newer server) reads as [inactive]:
  /// safer to pause than to guess "active".
  static SchoolStatus fromWireValue(String value) {
    for (final e in _wireValues.entries) {
      if (e.value == value) return e.key;
    }
    return SchoolStatus.inactive;
  }
}
