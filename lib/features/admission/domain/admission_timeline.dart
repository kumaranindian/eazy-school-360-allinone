import 'admission_activity.dart';
import 'admission_enquiry.dart';

/// One line of an enquiry's timeline: either a status change or something
/// that happened to a follow-up or school visit. Both are immutable history.
sealed class TimelineItem {
  const TimelineItem();
  DateTime? get at;
}

final class StatusTimelineItem extends TimelineItem {
  final StatusHistoryEntry entry;
  const StatusTimelineItem(this.entry);
  @override
  DateTime? get at => entry.at;
}

final class ActivityTimelineItem extends TimelineItem {
  final ActivityHistoryEntry entry;
  const ActivityTimelineItem(this.entry);
  @override
  DateTime? get at => entry.at;
}

/// Both histories in one list, newest first. An entry whose server timestamp
/// has not arrived yet (`at == null`, just written) counts as newest. Ties keep
/// status changes above activity events, then the higher revision first, so
/// "Visit scheduled" reads above the booking that caused it.
List<TimelineItem> mergeTimeline(
  List<StatusHistoryEntry> status,
  List<ActivityHistoryEntry> activity,
) {
  final items = <TimelineItem>[
    for (final s in status) StatusTimelineItem(s),
    for (final a in activity) ActivityTimelineItem(a),
  ];
  int revisionOf(TimelineItem i) => switch (i) {
    StatusTimelineItem(:final entry) => entry.revision,
    ActivityTimelineItem(:final entry) => entry.revision,
  };
  int kindOf(TimelineItem i) => i is StatusTimelineItem ? 0 : 1;
  items.sort((x, y) {
    final ax = x.at;
    final ay = y.at;
    if (ax == null && ay != null) return -1;
    if (ax != null && ay == null) return 1;
    if (ax != null && ay != null) {
      final c = ay.compareTo(ax);
      if (c != 0) return c;
    }
    final k = kindOf(x).compareTo(kindOf(y));
    if (k != 0) return k;
    return revisionOf(y).compareTo(revisionOf(x));
  });
  return items;
}
