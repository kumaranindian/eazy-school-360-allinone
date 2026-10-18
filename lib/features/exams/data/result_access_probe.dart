import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../../core/constants/firestore_fields.dart';

/// Explains, in the browser console, why a family's list of published
/// examinations was refused. Run only after such a refusal (never on the happy
/// path), reads only what the family may already read, and writes nothing.
///
/// It prints the family's `parentAccess` record next to the class being asked
/// about, and tries the section-specific query too, so the log shows whether
/// the class entry is missing or the class-wide query itself is what the rules
/// cannot prove.
class ResultAccessProbe {
  final FirebaseFirestore _firestore;

  ResultAccessProbe(this._firestore);

  Future<void> run({
    required String schoolId,
    required String branchId,
    required String? parentId,
    required String academicYearId,
    required String classId,
    required String? sectionId,
  }) async {
    // It prints a family's access keys: never in a release build (LOG-2).
    if (!kDebugMode) return;
    final branch = _firestore
        .collection(FirestoreFields.schoolsCollection)
        .doc(schoolId)
        .collection(FirestoreFields.branchesCollection)
        .doc(branchId);
    if (parentId == null) {
      debugPrint('[results] probe: the login has no linkedParentId');
    } else {
      try {
        final doc = await branch.collection('parentAccess').doc(parentId).get();
        if (!doc.exists) {
          debugPrint(
            '[results] probe: parentAccess/$parentId does not exist in branch $branchId',
          );
        } else {
          final classKeys = List<String>.from(
            doc.data()?['classKeys'] ?? const [],
          );
          final sectionKeys = List<String>.from(
            doc.data()?['sectionKeys'] ?? const [],
          );
          debugPrint(
            '[results] probe: parentAccess/$parentId in branch $branchId '
            'classKeys=$classKeys sectionKeys=$sectionKeys; asked class=$classId '
            'section=$sectionId -> class listed: ${classKeys.contains(classId)}',
          );
        }
      } catch (error) {
        debugPrint(
          '[results] probe: could not read parentAccess/$parentId: $error',
        );
      }
    }
    if (sectionId != null) {
      try {
        final snap = await branch
            .collection(FirestoreFields.examinationsCollection)
            .where('academicYearId', isEqualTo: academicYearId)
            .where('classId', isEqualTo: classId)
            .where(FirestoreFields.status, isEqualTo: 'PUBLISHED')
            .where('sectionId', isEqualTo: sectionId)
            .get();
        debugPrint(
          '[results] probe: the section-specific query is ALLOWED (${snap.docs.length} exam(s))',
        );
      } catch (error) {
        debugPrint(
          '[results] probe: the section-specific query is also refused: $error',
        );
      }
    }
  }
}
