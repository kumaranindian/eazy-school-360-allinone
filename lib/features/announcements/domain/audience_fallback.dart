/// Audiences every active parent of the branch may be shown. `CLASS` and
/// `SECTION` content is not here: it is only readable when the query is pinned
/// to a class / section of the family's own `parentAccess` index, so those are
/// asked for separately (see [planScopedParentQueries]).
const parentAudiences = ['ALL', 'BRANCH', 'PARENTS'];

/// One class- or section-pinned audience query a parent is allowed to ask.
class ScopedAudienceQuery {
  /// `CLASS` or `SECTION`.
  final String kind;
  final String classId;
  final String? sectionId;

  const ScopedAudienceQuery.forClass(this.classId)
    : kind = 'CLASS',
      sectionId = null;
  const ScopedAudienceQuery.forSection(this.classId, String this.sectionId)
    : kind = 'SECTION';

  @override
  bool operator ==(Object other) =>
      other is ScopedAudienceQuery &&
      other.kind == kind &&
      other.classId == classId &&
      other.sectionId == sectionId;

  @override
  int get hashCode => Object.hash(kind, classId, sectionId);

  @override
  String toString() => '$kind:$classId/${sectionId ?? ''}';
}

/// The class / section queries a family may issue, from its `parentAccess`
/// keys (`classId`, `classId__sectionId`). Malformed keys are skipped, so a
/// corrupt index narrows what is asked rather than widening it.
List<ScopedAudienceQuery> planScopedParentQueries({
  required Iterable<String> classKeys,
  required Iterable<String> sectionKeys,
}) {
  final out = <ScopedAudienceQuery>{};
  for (final k in classKeys) {
    if (k.isNotEmpty) out.add(ScopedAudienceQuery.forClass(k));
  }
  for (final k in sectionKeys) {
    final i = k.indexOf('__');
    if (i <= 0 || i + 2 >= k.length) continue;
    out.add(
      ScopedAudienceQuery.forSection(k.substring(0, i), k.substring(i + 2)),
    );
  }
  return out.toList();
}

/// Merges result lists, the first occurrence of an id winning, newest first
/// by [instantOf], capped at [limit].
List<T> mergeNewestFirst<T>(
  Iterable<Iterable<T>> lists, {
  required String Function(T) idOf,
  required DateTime? Function(T) instantOf,
  required int limit,
}) {
  final byId = <String, T>{};
  for (final l in lists) {
    for (final x in l) {
      byId.putIfAbsent(idOf(x), () => x);
    }
  }
  final out = byId.values.toList()
    ..sort(
      (a, b) =>
          (instantOf(b) ?? DateTime(0)).compareTo(instantOf(a) ?? DateTime(0)),
    );
  return out.length > limit ? out.sublist(0, limit) : out;
}

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
