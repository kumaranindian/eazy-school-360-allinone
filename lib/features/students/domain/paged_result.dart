/// A single page from a cursor-paginated Firestore query. [nextCursor] is
/// opaque on purpose — callers pass it straight back into the same fetch
/// method to get the next page, never inspect it. Keeps `cloud_firestore`
/// types (`DocumentSnapshot`) out of this domain-layer interface; only
/// the `Firebase*Repository` implementation knows what's really inside.
class PagedResult<T> {
  final List<T> items;
  final Object? nextCursor;

  const PagedResult({required this.items, required this.nextCursor});

  bool get hasMore => nextCursor != null;
}
