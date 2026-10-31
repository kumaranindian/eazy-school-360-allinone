import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/error_mapper.dart';
import '../domain/parent.dart';
import '../domain/parent_duplicates.dart';

/// Three small equality queries on the branch's parents (email, phone as it
/// may have been typed, exact name) — single-field indexes only, the same
/// branch-scoped reads the parents list and bulk import already make. The
/// decision itself is [ParentContact.matches].
class FirebaseParentDuplicateFinder implements ParentDuplicateFinder {
  final FirebaseFirestore _db;
  FirebaseParentDuplicateFinder(this._db);

  static const _limit = 10;

  @override
  Future<List<ParentMatch>> find({
    required String schoolId,
    required String branchId,
    required String? email,
    required String? phone,
    required String displayName,
    String? excludeParentId,
  }) async {
    try {
      final parents = _db
          .collection('schools')
          .doc(schoolId)
          .collection('branches')
          .doc(branchId)
          .collection('parents');
      final emails = {
        if ((email ?? '').trim().isNotEmpty) email!.trim(),
        ?ParentContact.normalizeEmail(email),
      }.toList();
      final phones = ParentContact.phoneVariants(phone);
      final name = displayName.trim().toLowerCase();

      final snaps = await Future.wait([
        if (emails.isNotEmpty)
          parents.where('email', whereIn: emails).limit(_limit).get(),
        if (phones.isNotEmpty)
          parents.where('phone', whereIn: phones).limit(_limit).get(),
        if (name.isNotEmpty)
          parents
              .where('displayNameLower', isEqualTo: name)
              .limit(_limit)
              .get(),
      ]);
      final candidates = [
        for (final s in snaps)
          for (final d in s.docs)
            Parent.fromFirestore(schoolId, branchId, d.id, d.data()),
      ];
      return ParentContact.matches(
        email: email,
        phone: phone,
        candidates: candidates,
        excludeParentId: excludeParentId,
      );
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
