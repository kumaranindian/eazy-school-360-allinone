import '../../../../core/regional/school_time.dart';
import '../../../academic_setup/domain/weekday.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../domain/timetable.dart';
import '../../domain/timetable_enums.dart';

String ttDate(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
}

String ttRange(Timetable t) =>
    '${ttDate(t.effectiveFromKey)} – ${t.effectiveToKey == null ? 'open' : ttDate(t.effectiveToKey!)}';

const List<Weekday> kWeekOrder = Weekday.values;

List<Weekday> orderedDays(Iterable<String> wires) {
  final set = wires.toSet();
  return [
    for (final d in Weekday.values)
      if (set.contains(d.wireValue)) d,
  ];
}

String todayKey() => AttendanceDate.key(SchoolTime.wallNow());

String statusLabel(TimetableStatus s) => s.displayName;
