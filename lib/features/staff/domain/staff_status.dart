/// A staff member's employment lifecycle. Staff are never hard-deleted —
/// attendance, leave, payroll and audit all need the historical record —
/// so this status is the only way someone leaves the active workforce.
///
/// Allowed moves are encoded in [allowedTransitions] (enforced by
/// `StaffRepository.changeStaffStatus`; `firestore.rules` independently
/// blocks leaving a terminal status):
///
/// ```text
/// ACTIVE ──► ON_NOTICE ──► RESIGNED | TERMINATED
///   │  └───► INACTIVE ──► ACTIVE
///   └──────► RESIGNED | TERMINATED | RETIRED
/// ```
enum StaffStatus {
  active,
  inactive,
  onNotice,
  resigned,
  terminated,
  retired;

  static const Map<StaffStatus, String> _wireValues = {
    StaffStatus.active: 'ACTIVE',
    StaffStatus.inactive: 'INACTIVE',
    StaffStatus.onNotice: 'ON_NOTICE',
    StaffStatus.resigned: 'RESIGNED',
    StaffStatus.terminated: 'TERMINATED',
    StaffStatus.retired: 'RETIRED',
  };

  /// Statuses a member can never leave — keep in sync with the
  /// `isTerminalStaffStatus` list in `firestore.rules`.
  static const Set<StaffStatus> terminal = {
    StaffStatus.resigned,
    StaffStatus.terminated,
    StaffStatus.retired,
  };

  String get wireValue => _wireValues[this]!;

  static StaffStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case StaffStatus.active:
        return 'Active';
      case StaffStatus.inactive:
        return 'Inactive';
      case StaffStatus.onNotice:
        return 'On notice';
      case StaffStatus.resigned:
        return 'Resigned';
      case StaffStatus.terminated:
        return 'Terminated';
      case StaffStatus.retired:
        return 'Retired';
    }
  }

  bool get isTerminal => terminal.contains(this);

  /// Only ACTIVE staff may receive new teaching assignments. ON_NOTICE
  /// staff keep the assignments they already have but get no new ones.
  bool get canReceiveAssignments => this == StaffStatus.active;

  /// Moving *into* this status ends the member's active teaching
  /// assignments (history is kept). ON_NOTICE deliberately does not —
  /// they are still working.
  bool get endsActiveAssignments => this == StaffStatus.inactive || isTerminal;

  Set<StaffStatus> get allowedTransitions {
    switch (this) {
      case StaffStatus.active:
        return {
          StaffStatus.inactive,
          StaffStatus.onNotice,
          StaffStatus.resigned,
          StaffStatus.terminated,
          StaffStatus.retired,
        };
      case StaffStatus.onNotice:
        return {
          StaffStatus.active,
          StaffStatus.inactive,
          StaffStatus.resigned,
          StaffStatus.terminated,
        };
      case StaffStatus.inactive:
        return {StaffStatus.active};
      case StaffStatus.resigned:
      case StaffStatus.terminated:
      case StaffStatus.retired:
        return const {};
    }
  }

  bool canTransitionTo(StaffStatus next) => allowedTransitions.contains(next);

  /// Why moving to [next] is refused, or null when it is allowed.
  String? transitionError(StaffStatus next) {
    if (canTransitionTo(next)) return null;
    return 'A staff member who is ${displayName.toLowerCase()} cannot be changed to ${next.displayName.toLowerCase()}.';
  }
}
