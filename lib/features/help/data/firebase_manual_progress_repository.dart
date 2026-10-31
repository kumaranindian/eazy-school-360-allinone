import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/manual_models.dart';
import '../domain/manual_progress_repository.dart';

/// `users/{uid}/manualProgress/{guideId}`: the user's own document, one per
/// guide: `{completed: [stepIndex…], version, lastStep, updatedAt}`.
class FirebaseManualProgressRepository implements ManualProgressRepository {
  final FirebaseFirestore _db;
  FirebaseManualProgressRepository(this._db);

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _db.collection('users').doc(userId).collection('manualProgress');

  @override
  Stream<Map<String, ManualProgress>> watch(String userId) {
    return _col(userId)
        .snapshots()
        .map((snap) {
          final out = <String, ManualProgress>{};
          for (final d in snap.docs) {
            final data = d.data();
            out[d.id] = ManualProgress(
              guideId: d.id,
              version: (data['version'] as num?)?.toInt() ?? 1,
              completed: {
                for (final i in (data['completed'] as List? ?? const []))
                  if (i is num) i.toInt(),
              },
              lastStep: (data['lastStep'] as num?)?.toInt() ?? 0,
            );
          }
          return out;
        })
        .handleError((Object error, StackTrace stackTrace) {
          throw mapExceptionToFailure(error, stackTrace);
        });
  }

  @override
  Future<void> save(String userId, ManualProgress progress) async {
    try {
      await _col(userId).doc(progress.guideId).set({
        'completed': (progress.completed.toList()..sort()),
        'version': progress.version,
        'lastStep': progress.lastStep,
        FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }

  @override
  Future<void> reset(String userId, String guideId) async {
    try {
      await _col(userId).doc(guideId).delete();
    } catch (error, stackTrace) {
      throw mapExceptionToFailure(error, stackTrace);
    }
  }
}
