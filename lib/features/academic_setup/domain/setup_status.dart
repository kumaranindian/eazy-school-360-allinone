/// One row of [SetupStatus] — e.g. "Academic Year" is done or not, and
/// whether it's required before the school can be considered ready.
class SetupItem {
  final String label;
  final bool isComplete;
  final bool isRequired;

  const SetupItem({
    required this.label,
    required this.isComplete,
    required this.isRequired,
  });
}

/// Computed (never stored) summary of how much of initial setup a
/// branch has completed — see `setup_status_provider.dart`. Recomputing
/// this from the real collections on every read means it can never drift
/// from what's actually configured, unlike a cached "setupComplete: true"
/// flag that someone forgot to update after deleting their only class.
class SetupStatus {
  final List<SetupItem> items;

  const SetupStatus({required this.items});

  bool get isRequiredSetupComplete =>
      items.where((i) => i.isRequired).every((i) => i.isComplete);

  List<SetupItem> get requiredItems =>
      items.where((i) => i.isRequired).toList();

  List<SetupItem> get optionalItems =>
      items.where((i) => !i.isRequired).toList();
}
