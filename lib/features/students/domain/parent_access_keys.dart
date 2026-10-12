import 'student.dart';
import 'student_status.dart';

/// The content a family may read, as the security rules see it.
///
/// Rules cannot enumerate a parent's children, so a small per-branch index
/// (`parentAccess/{parentId}`) lists the classes and sections where the
/// family has an ACTIVE, placed child behind an ACTIVE portal-enabled link.
/// Keys: `classId` and `classId__sectionId` — the same strings the rules
/// build from a document's own `classId`/`sectionId`.
///
/// Pure and deterministic: the sync service only feeds it the children.
class ParentAccessKeys {
  final List<String> classKeys;
  final List<String> sectionKeys;

  const ParentAccessKeys({required this.classKeys, required this.sectionKeys});

  static String sectionKey(String classId, String sectionId) =>
      '${classId}__$sectionId';

  /// Keys for the children who attend [branchId]. Children who are not
  /// ACTIVE, or not placed in a class and section, contribute nothing.
  factory ParentAccessKeys.forChildren(
    Iterable<Student> children, {
    required String branchId,
  }) {
    final classes = <String>{};
    final sections = <String>{};
    for (final c in children) {
      if (c.branchId != branchId || c.status != StudentStatus.active) continue;
      final classId = c.currentClassId;
      final sectionId = c.currentSectionId;
      if (classId == null || classId.isEmpty) continue;
      classes.add(classId);
      if (sectionId != null && sectionId.isNotEmpty) {
        sections.add(sectionKey(classId, sectionId));
      }
    }
    return ParentAccessKeys(
      classKeys: classes.toList()..sort(),
      sectionKeys: sections.toList()..sort(),
    );
  }

  bool get isEmpty => classKeys.isEmpty && sectionKeys.isEmpty;
}
