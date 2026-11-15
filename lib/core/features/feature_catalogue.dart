/// The platform's module catalogue: ONLY modules that exist in this app.
/// Mirrors `functions/features.js` (the server is authoritative; this copy
/// lets the app hide a switched-off module and the console explain
/// dependencies before it calls the server).
class FeatureDef {
  final String key;
  final String label;
  final List<String> dependsOn;

  const FeatureDef(this.key, this.label, [this.dependsOn = const []]);
}

const List<FeatureDef> kFeatureCatalogue = [
  FeatureDef('students', 'Student management', ['academic']),
  FeatureDef('parents', 'Parents and family links', ['students']),
  FeatureDef('staff', 'Staff, teachers and departments'),
  FeatureDef('academic', 'Academic setup (years, classes, subjects, calendar)'),
  FeatureDef('attendance', 'Student and staff attendance', [
    'students',
    'academic',
  ]),
  FeatureDef('leave', 'Leave management', ['staff']),
  FeatureDef('fees', 'Fees, invoices and payments', ['students']),
  FeatureDef('feeReminders', 'Fee reminders', ['fees']),
  FeatureDef('admission', 'Admission management', ['students']),
  FeatureDef('publicAdmission', 'Public admission enquiry page', ['admission']),
  FeatureDef('exams', 'Exams, marks and results', ['students', 'academic']),
  FeatureDef('timetable', 'Timetable and substitutions', ['academic', 'staff']),
  FeatureDef('homework', 'Homework and submissions', ['academic']),
  FeatureDef('announcements', 'Announcements'),
  FeatureDef('messages', 'Parent-teacher messaging', ['parents']),
  FeatureDef('notifications', 'Push and in-app notifications'),
];

FeatureDef? featureDef(String key) {
  for (final f in kFeatureCatalogue) {
    if (f.key == key) return f;
  }
  return null;
}

/// Whether [key] is usable with switches [features]: it and everything it
/// depends on is on (a missing switch means on). Unknown keys are never blocked.
bool featureUsable(Map<String, bool> features, String key) {
  final f = featureDef(key);
  if (f == null) return true;
  if (features[key] == false) return false;
  return f.dependsOn.every((d) => featureUsable(features, d));
}

/// Every feature that depends on [key], directly or through others.
List<String> dependantsOf(String key) {
  final out = <String>{};
  void walk(String k) {
    for (final f in kFeatureCatalogue) {
      if (f.dependsOn.contains(k) && out.add(f.key)) walk(f.key);
    }
  }

  walk(key);
  return out.toList();
}

/// The dependencies of [key] that are currently not usable.
List<String> missingDependencies(Map<String, bool> features, String key) => [
  for (final d in featureDef(key)?.dependsOn ?? const <String>[])
    if (!featureUsable(features, d)) d,
];

String featureLabel(String key) => featureDef(key)?.label ?? key;
