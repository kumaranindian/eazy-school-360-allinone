/// Audiences a parent may be shown, widest first.
const parentAudiences = ['ALL', 'BRANCH', 'PARENTS', 'CLASS', 'SECTION'];

/// School-wide notices only — readable by every active parent of the school.
const schoolWideAudience = ['ALL'];

/// Runs [run] with the widest audience set a parent might read. Firestore
/// rules are not filters: when the family has no `parentAccess` index (no
/// portal-enabled child yet) the rules cannot prove the class/branch-scoped
/// audiences readable and refuse the *whole* query, even though school-wide
/// announcements are the parent's to read. On exactly that refusal ([isDenied])
/// the query is retried with [schoolWideAudience]. Any other error propagates.
///
/// Non-parents pass an empty list (no audience constraint).
Future<T> runWithParentFallback<T>({
  required bool isParent,
  required Future<T> Function(List<String> audiences) run,
  required bool Function(Object error) isDenied,
}) async {
  if (!isParent) return run(const []);
  try {
    return await run(parentAudiences);
  } catch (e) {
    if (!isDenied(e)) rethrow;
    return run(schoolWideAudience);
  }
}
