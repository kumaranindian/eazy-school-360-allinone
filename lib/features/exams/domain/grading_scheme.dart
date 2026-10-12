import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'exam_enums.dart';

/// One grade band: the grade applies from [minPercent] (inclusive) up to the
/// next band's minimum (exclusive); the top band runs to 100 inclusive.
class GradeBand {
  final String grade;
  final String label;
  final double minPercent;

  /// Present on every band or on none: GPA is only produced when the scheme
  /// defines it.
  final double? gradePoint;

  const GradeBand({
    required this.grade,
    this.label = '',
    required this.minPercent,
    this.gradePoint,
  });

  factory GradeBand.fromMap(Map<String, dynamic> m) => GradeBand(
    grade: m['grade'] as String,
    label: m['label'] as String? ?? '',
    minPercent: (m['minPercent'] as num).toDouble(),
    gradePoint: (m['gradePoint'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'grade': grade,
    'label': label,
    'minPercent': minPercent,
    'gradePoint': gradePoint,
  };
}

/// A school's grading policy. Nothing here is hard-coded: bands, pass rule,
/// precision, rounding, absent handling, aggregation, GPA and ranking are all
/// configuration. A finalised result stores a snapshot of the scheme it used,
/// so editing a scheme never rewrites a report card.
class GradingScheme {
  final String schemeId;
  final String schoolId;
  final String branchId;
  final String name;
  final String description;
  final List<GradeBand> bands;

  /// Default subject pass threshold (percentage of the subject maximum),
  /// used when a subject has no explicit passing marks.
  final double passPercent;

  /// Optional additional rule: overall percentage must reach this to pass.
  final double? overallPassPercent;
  final int decimals;
  final RoundingMode rounding;
  final AbsentPolicy absentPolicy;
  final AggregateMethod aggregate;
  final bool rankingEnabled;
  final bool active;
  final int revision;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const GradingScheme({
    required this.schemeId,
    required this.schoolId,
    required this.branchId,
    required this.name,
    this.description = '',
    required this.bands,
    this.passPercent = 33,
    this.overallPassPercent,
    this.decimals = 2,
    this.rounding = RoundingMode.halfUp,
    this.absentPolicy = AbsentPolicy.exclude,
    this.aggregate = AggregateMethod.total,
    this.rankingEnabled = false,
    this.active = true,
    this.revision = 1,
    this.createdAt,
    this.updatedAt,
  });

  /// GPA exists only when every band defines a grade point.
  bool get gpaEnabled =>
      bands.isNotEmpty && bands.every((b) => b.gradePoint != null);

  List<GradeBand> get sortedBands =>
      [...bands]..sort((a, b) => b.minPercent.compareTo(a.minPercent));

  /// A user-readable problem with the scheme, or null.
  String? validate() {
    if (name.trim().length < 2 || name.trim().length > 60) {
      return 'The scheme name must be 2-60 characters.';
    }
    if (bands.isEmpty) return 'Add at least one grade band.';
    if (bands.length > 20) return 'Use at most 20 grade bands.';
    final minimums = <double>{};
    final grades = <String>{};
    for (final b in bands) {
      if (b.grade.trim().isEmpty || b.grade.trim().length > 6) {
        return 'Each grade needs a short label (1-6 characters).';
      }
      if (b.minPercent < 0 || b.minPercent > 100) {
        return 'Grade boundaries must be between 0 and 100.';
      }
      if (!minimums.add(b.minPercent)) {
        return 'Two grades start at ${b.minPercent}% — boundaries must be '
            'distinct (ranges would overlap).';
      }
      if (!grades.add(b.grade.trim().toLowerCase())) {
        return 'The grade "${b.grade}" is used twice.';
      }
    }
    if (!minimums.contains(0.0)) {
      return 'The lowest grade must start at 0% so every score has a grade.';
    }
    final points = bands.where((b) => b.gradePoint != null).length;
    if (points != 0 && points != bands.length) {
      return 'Give a grade point to every band, or to none.';
    }
    for (final b in bands) {
      if (b.gradePoint != null && (b.gradePoint! < 0 || b.gradePoint! > 100)) {
        return 'Grade points must be between 0 and 100.';
      }
    }
    // Higher bands should not have lower points (ambiguous otherwise).
    if (gpaEnabled) {
      final s = sortedBands;
      for (var i = 1; i < s.length; i++) {
        if (s[i].gradePoint! > s[i - 1].gradePoint!) {
          return 'A lower grade cannot carry a higher grade point.';
        }
      }
    }
    if (passPercent < 0 || passPercent > 100) {
      return 'The pass percentage must be between 0 and 100.';
    }
    if (overallPassPercent != null &&
        (overallPassPercent! < 0 || overallPassPercent! > 100)) {
      return 'The overall pass percentage must be between 0 and 100.';
    }
    if (decimals < 0 || decimals > 3) return 'Use 0 to 3 decimal places.';
    return null;
  }

  factory GradingScheme.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      GradingScheme(
        schemeId: id.isEmpty ? (d['schemeId'] as String? ?? '') : id,
        schoolId: d[FirestoreFields.schoolId] as String? ?? '',
        branchId: d[FirestoreFields.branchId] as String? ?? '',
        name: d['name'] as String? ?? '',
        description: d['description'] as String? ?? '',
        bands: [
          for (final b in d['bands'] as List? ?? [])
            GradeBand.fromMap(Map<String, dynamic>.from(b as Map)),
        ],
        passPercent: (d['passPercent'] as num?)?.toDouble() ?? 33,
        overallPassPercent: (d['overallPassPercent'] as num?)?.toDouble(),
        decimals: (d['decimals'] as num?)?.toInt() ?? 2,
        rounding: RoundingMode.fromWireValue(d['rounding'] as String? ?? ''),
        absentPolicy: AbsentPolicy.fromWireValue(
          d['absentPolicy'] as String? ?? '',
        ),
        aggregate: AggregateMethod.fromWireValue(
          d['aggregate'] as String? ?? '',
        ),
        rankingEnabled: d['rankingEnabled'] as bool? ?? false,
        active: (d[FirestoreFields.status] as String? ?? 'ACTIVE') == 'ACTIVE',
        revision: (d['revision'] as num?)?.toInt() ?? 1,
        createdAt: (d[FirestoreFields.createdAt] as Timestamp?)?.toDate(),
        updatedAt: (d[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      );

  /// The portable, calculation-relevant body (also the snapshot stored with a
  /// finalised result).
  Map<String, dynamic> policyMap() => {
    'schemeId': schemeId,
    'name': name.trim(),
    'bands': [for (final b in sortedBands) b.toMap()],
    'passPercent': passPercent,
    'overallPassPercent': overallPassPercent,
    'decimals': decimals,
    'rounding': rounding.wireValue,
    'absentPolicy': absentPolicy.wireValue,
    'aggregate': aggregate.wireValue,
    'rankingEnabled': rankingEnabled,
    'revision': revision,
  };

  Map<String, dynamic> body() => {
    'name': name.trim(),
    'description': description.trim(),
    'bands': [for (final b in sortedBands) b.toMap()],
    'passPercent': passPercent,
    'overallPassPercent': overallPassPercent,
    'decimals': decimals,
    'rounding': rounding.wireValue,
    'absentPolicy': absentPolicy.wireValue,
    'aggregate': aggregate.wireValue,
    'rankingEnabled': rankingEnabled,
    FirestoreFields.status: active ? 'ACTIVE' : 'INACTIVE',
  };

  /// A scheme rebuilt from a stored snapshot (finalised results).
  factory GradingScheme.fromSnapshot(Map<String, dynamic> s) =>
      GradingScheme.fromMap(s, id: s['schemeId'] as String? ?? '');

  /// A common starting point; schools edit it. Not a mandate.
  static GradingScheme sample({
    required String schoolId,
    required String branchId,
  }) => GradingScheme(
    schemeId: '',
    schoolId: schoolId,
    branchId: branchId,
    name: 'Standard grading',
    bands: const [
      GradeBand(grade: 'A+', label: 'Outstanding', minPercent: 90),
      GradeBand(grade: 'A', label: 'Excellent', minPercent: 80),
      GradeBand(grade: 'B', label: 'Very good', minPercent: 70),
      GradeBand(grade: 'C', label: 'Good', minPercent: 60),
      GradeBand(grade: 'D', label: 'Satisfactory', minPercent: 33),
      GradeBand(grade: 'E', label: 'Needs improvement', minPercent: 0),
    ],
  );
}
