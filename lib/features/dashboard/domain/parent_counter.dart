import '../../../core/constants/activation_status.dart';

/// How many parent/guardian records a branch has (a server-side count; no
/// documents are downloaded). Kept apart from `ParentRepository` so the
/// dashboard's read-only count does not widen that interface.
abstract class ParentCounter {
  Future<int> countParents({
    required String schoolId,
    required String branchId,
    ActivationStatus? status,
  });
}
