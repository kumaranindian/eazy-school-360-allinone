import '../../../core/permissions/permission.dart';
import 'manual_models.dart';

/// Which guides a user sees, which guide a screen's Help icon opens, and
/// search. Pure so it is tested without widgets.
class ManualCatalog {
  final List<ManualCategory> categories;
  final List<ManualGuide> guides;

  const ManualCatalog(this.categories, this.guides);

  /// Guides this user may see: no permission needed, or holds any listed one.
  List<ManualGuide> visibleTo(bool Function(Permission) can) => [
    for (final g in guides)
      if (g.anyOf.isEmpty || g.anyOf.any(can)) g,
  ];

  ManualGuide? byId(String id) {
    for (final g in guides) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// The guide for the screen at [path], by longest route prefix, among the
  /// guides the user may see.
  ManualGuide? forPath(String path, bool Function(Permission) can) {
    final p = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    ManualGuide? best;
    var bestLen = -1;
    for (final g in visibleTo(can)) {
      for (final prefix in g.contextRoutes) {
        final hit = p == prefix || p.startsWith('$prefix/');
        if (hit && prefix.length > bestLen) {
          best = g;
          bestLen = prefix.length;
        }
      }
    }
    return best;
  }

  /// Visible guides matching every word of [query], best first. Titles and
  /// keywords weigh more than summaries and step text.
  List<ManualGuide> search(String query, bool Function(Permission) can) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 1 && !_stop.contains(w))
        .toList();
    if (words.isEmpty) return const [];
    final scored = <(ManualGuide, int)>[];
    for (final g in visibleTo(can)) {
      final title = g.title.toLowerCase();
      final keys = g.keywords.join(' ').toLowerCase();
      final summary = g.summary.toLowerCase();
      final body = [
        for (final s in g.steps) '${s.title} ${s.instruction}',
        for (final t in g.troubleshooting) '${t.problem} ${t.solution}',
      ].join(' ').toLowerCase();
      var total = 0;
      var matchedAll = true;
      for (final w in words) {
        final stem = w.length > 4 ? w.substring(0, w.length - 1) : w;
        var s = 0;
        if (title.contains(stem)) s += 6;
        if (keys.contains(stem)) s += 4;
        if (summary.contains(stem)) s += 2;
        if (body.contains(stem)) s += 1;
        if (s == 0) {
          matchedAll = false;
          break;
        }
        total += s;
      }
      if (matchedAll) scored.add((g, total));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored) e.$1];
  }

  static const _stop = {
    'how',
    'to',
    'the',
    'a',
    'an',
    'of',
    'for',
    'do',
    'i',
    'in',
    'on',
    'and',
    'my',
    'can',
    'is',
    'what',
    'where',
  };
}
