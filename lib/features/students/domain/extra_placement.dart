/// An additional class a student attends besides their main one — e.g. the
/// afternoon day-care class of a child who is in pre-school in the morning.
///
/// Source of truth is an `academicRecords` document with `kind: EXTRA`
/// (so attendance registers and history work unchanged). The student
/// document carries a copy of the active ones (`extraPlacements`) plus
/// [keysOf] (`extraPlacementKeys`) so class lists and rules can find them
/// without scanning the history — the same idea as the current-placement
/// cache.
class ExtraPlacement {
  final String recordId;
  final String academicYearId;
  final String classId;
  final String sectionId;

  /// Free text such as "Morning" or "Afternoon"; empty when not set.
  final String label;
  final String? rollNumber;

  const ExtraPlacement({
    required this.recordId,
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
    this.label = '',
    this.rollNumber,
  });

  /// At most this many extra classes per student.
  static const int maxPerStudent = 3;

  static const int maxLabelLength = 30;

  /// Key of "this class, any section" — what a class-wide list looks for.
  String get classKey => classKeyOf(academicYearId, classId);

  /// Key of "this class and section".
  String get sectionKey => sectionKeyOf(academicYearId, classId, sectionId);

  static String classKeyOf(String academicYearId, String classId) =>
      '$academicYearId|$classId';

  static String sectionKeyOf(
    String academicYearId,
    String classId,
    String sectionId,
  ) => '$academicYearId|$classId|$sectionId';

  /// All lookup keys for [placements] (class-wide and section-wide).
  static List<String> keysOf(Iterable<ExtraPlacement> placements) => [
    for (final p in placements) ...[p.classKey, p.sectionKey],
  ];

  /// `classId__sectionId` — the form the rules use for teacher and parent
  /// access (`teacherAccess.sectionKeys`, `parentAccess.sectionKeys`).
  String get accessKey => '${classId}__$sectionId';

  static List<String> accessKeysOf(Iterable<ExtraPlacement> placements) => [
    for (final p in placements) p.accessKey,
  ];

  Map<String, dynamic> toMap() => {
    'recordId': recordId,
    'academicYearId': academicYearId,
    'classId': classId,
    'sectionId': sectionId,
    'label': label,
    'rollNumber': rollNumber,
  };

  factory ExtraPlacement.fromMap(Map<String, dynamic> map) => ExtraPlacement(
    recordId: map['recordId'] as String? ?? '',
    academicYearId: map['academicYearId'] as String? ?? '',
    classId: map['classId'] as String? ?? '',
    sectionId: map['sectionId'] as String? ?? '',
    label: map['label'] as String? ?? '',
    rollNumber: map['rollNumber'] as String?,
  );

  static List<ExtraPlacement> listFrom(Object? raw) => [
    if (raw is List)
      for (final e in raw)
        if (e is Map) ExtraPlacement.fromMap(Map<String, dynamic>.from(e)),
  ];

  /// A problem with adding [candidate] to a student whose main class is
  /// ([mainYearId], [mainClassId]) and who already has [existing], or null.
  static String? checkAdd({
    required ExtraPlacement candidate,
    required String? mainYearId,
    required String? mainClassId,
    required List<ExtraPlacement> existing,
  }) {
    if (candidate.label.length > maxLabelLength) {
      return 'Keep the label under $maxLabelLength characters.';
    }
    if (mainYearId != candidate.academicYearId) {
      return 'An extra class must be in the same academic year as the main '
          'class.';
    }
    if (mainClassId == candidate.classId) {
      return 'This is already the student\'s main class.';
    }
    if (existing.any(
      (e) =>
          e.academicYearId == candidate.academicYearId &&
          e.classId == candidate.classId,
    )) {
      return 'The student is already in this class.';
    }
    if (existing.length >= maxPerStudent) {
      return 'A student can have at most $maxPerStudent extra classes.';
    }
    return null;
  }
}
