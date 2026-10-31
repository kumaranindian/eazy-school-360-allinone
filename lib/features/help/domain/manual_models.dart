import 'package:flutter/widgets.dart';

import '../../../core/permissions/permission.dart';

/// One screen-sized instruction in a guide. A step only ever *describes* work
/// and may link to the real screen ([route]); marking it done never performs
/// anything in the app.
class ManualStep {
  final String title;
  final String instruction;

  /// An `AppRoutes` path without parameters. The "open" button is hidden when
  /// the signed-in user may not open it.
  final String? route;
  final String? actionLabel;

  /// What to check before moving on.
  final String? check;

  /// A frequent mistake at this step.
  final String? mistake;

  const ManualStep(
    this.title,
    this.instruction, {
    this.route,
    this.actionLabel,
    this.check,
    this.mistake,
  });
}

class ManualCategory {
  final String id;
  final String title;
  final String description;
  final IconData icon;

  const ManualCategory(this.id, this.title, this.description, this.icon);
}

class ManualTroubleshooting {
  final String problem;
  final String solution;
  const ManualTroubleshooting(this.problem, this.solution);
}

class ManualGuide {
  final String id;
  final String categoryId;
  final String title;
  final String summary;

  /// Shown when the user holds ANY of these permissions; empty = everyone.
  /// Permissions, not roles, so the manual always agrees with the app.
  final Set<Permission> anyOf;
  final List<String> prerequisites;
  final int minutes;

  /// Empty for a reference page (FAQ / troubleshooting): it shows only
  /// [troubleshooting] as questions and answers, with no stepper.
  final List<ManualStep> steps;
  final List<ManualTroubleshooting> troubleshooting;
  final List<String> keywords;

  /// Screens (route prefixes) whose Help icon opens this guide.
  final List<String> contextRoutes;
  final List<String> related;

  /// Bump when steps change meaning: saved progress for an older version is
  /// ignored.
  final int version;

  const ManualGuide({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.summary,
    required this.steps,
    this.anyOf = const {},
    this.prerequisites = const [],
    this.minutes = 5,
    this.troubleshooting = const [],
    this.keywords = const [],
    this.contextRoutes = const [],
    this.related = const [],
    this.version = 1,
  });
}

/// A user's saved place in one guide.
class ManualProgress {
  final String guideId;
  final int version;
  final Set<int> completed;
  final int lastStep;

  const ManualProgress({
    required this.guideId,
    required this.version,
    this.completed = const {},
    this.lastStep = 0,
  });

  double fraction(int totalSteps) =>
      totalSteps == 0 ? 0 : completed.length / totalSteps;

  bool isComplete(int totalSteps) =>
      totalSteps > 0 && completed.length >= totalSteps;
}
