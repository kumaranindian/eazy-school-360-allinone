import 'package:flutter/foundation.dart';

import '../../core/errors/error_mapper.dart';
import '../../features/students/domain/paged_result.dart';

/// Drives a cursor-paginated list: [reload] fetches the first page,
/// [loadMore] the next, and [items]/[isLoading]/[errorMessage]/[hasMore]
/// describe the current state for the UI. Never fetches more than one page
/// at a time, and a response that arrives after the filters changed (an
/// older [reload] still in flight) is dropped instead of overwriting newer
/// results.
///
/// [fetch] is replaced whenever the filters change; it receives the opaque
/// cursor of the previous page (null for the first).
class PagedListController<T> extends ChangeNotifier {
  Future<PagedResult<T>> Function(Object? cursor)? fetch;

  List<T> _items = const [];
  Object? _cursor;
  bool _hasMore = false;
  bool _isLoading = false;
  bool _hasLoaded = false;
  String? _errorMessage;
  int _generation = 0;
  bool _disposed = false;

  List<T> get items => _items;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  /// True once the first page of the current query has resolved (success or
  /// failure) — distinguishes "still loading" from "loaded, empty".
  bool get hasLoaded => _hasLoaded;
  String? get errorMessage => _errorMessage;

  Future<void> reload() {
    _generation++;
    _items = const [];
    _cursor = null;
    _hasMore = false;
    _hasLoaded = false;
    _errorMessage = null;
    return _loadPage(_generation, null);
  }

  Future<void> loadMore() {
    if (_isLoading || !_hasMore) return Future.value();
    return _loadPage(_generation, _cursor);
  }

  Future<void> _loadPage(int generation, Object? cursor) async {
    final currentFetch = fetch;
    if (currentFetch == null) return;
    _isLoading = true;
    _errorMessage = null;
    _notify();
    try {
      final page = await currentFetch(cursor);
      if (generation != _generation || _disposed) return;
      _items = cursor == null ? page.items : [..._items, ...page.items];
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (error) {
      if (generation != _generation || _disposed) return;
      _errorMessage = userMessageFor(error);
    } finally {
      if (generation == _generation && !_disposed) {
        _isLoading = false;
        _hasLoaded = true;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
