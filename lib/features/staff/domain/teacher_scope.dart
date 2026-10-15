/// One section a teacher is assigned to (from `teacherAccess/{uid}`, which
/// Cloud Functions rebuild from the teacher's ACTIVE assignments).
class TeacherSection {
  final String? academicYearId;
  final String classId;
  final String sectionId;

  const TeacherSection({
    required this.academicYearId,
    required this.classId,
    required this.sectionId,
  });

  /// The key `firestore.rules` checks (`classId__sectionId`).
  String get key => '${classId}__$sectionId';

  @override
  bool operator ==(Object other) =>
      other is TeacherSection &&
      other.academicYearId == academicYearId &&
      other.classId == classId &&
      other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(academicYearId, classId, sectionId);
}

/// The sections a teacher may see students of. This is what the rules enforce;
/// the app mirrors it so screens ask only for what will be allowed (Firestore
/// rules are not filters, so an unpinned query is refused outright).
class TeacherScope {
  final List<TeacherSection> sections;

  const TeacherScope(this.sections);

  static const empty = TeacherScope([]);

  bool get isEmpty => sections.isEmpty;

  bool covers(String? classId, String? sectionId) =>
      classId != null &&
      sectionId != null &&
      sections.any((s) => s.classId == classId && s.sectionId == sectionId);

  /// Parses the `teacherAccess` document; tolerant of a missing/odd list.
  factory TeacherScope.fromData(Map<String, dynamic> data) {
    final raw = data['scopes'];
    final out = <TeacherSection>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        final c = e['classId'];
        final s = e['sectionId'];
        if (c is String && s is String) {
          out.add(
            TeacherSection(
              academicYearId: e['academicYearId'] as String?,
              classId: c,
              sectionId: s,
            ),
          );
        }
      }
    }
    // Fall back to the keys the rules use when the display list is absent.
    if (out.isEmpty && data['sectionKeys'] is List) {
      for (final k in data['sectionKeys'] as List) {
        if (k is! String) continue;
        final i = k.indexOf('__');
        if (i <= 0) continue;
        out.add(
          TeacherSection(
            academicYearId: null,
            classId: k.substring(0, i),
            sectionId: k.substring(i + 2),
          ),
        );
      }
    }
    return TeacherScope(List.unmodifiable(out));
  }
}

abstract class TeacherScopeRepository {
  /// The caller's own scope. Emits null when no `teacherAccess` document
  /// exists (not provisioned yet — distinct from "assigned to nothing").
  Stream<TeacherScope?> watchScope({
    required String schoolId,
    required String branchId,
    required String userId,
  });
}
