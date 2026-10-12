import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/holiday.dart';
import '../../../academic_setup/presentation/providers/calendar_providers.dart';
import '../../domain/attendance_calendar.dart';
import '../../domain/attendance_date.dart';

/// Watches the branch's working-day pattern and the academic year's calendar
/// entries (the Milestone 2 providers — nothing is copied into attendance)
/// and resolves [date]. Loading/error flow through as an [AsyncValue] so the
/// page never lets anyone mark before the calendar is known.
AsyncValue<CalendarDayInfo> watchCalendarDay(
  WidgetRef ref, {
  required String schoolId,
  required String branchId,
  required String? academicYearId,
  required DateTime date,
}) {
  final workingDays = ref.watch(
    workingDaysProvider((schoolId: schoolId, branchId: branchId)),
  );
  final AsyncValue<List<Holiday>> holidays = academicYearId == null
      ? const AsyncData(<Holiday>[])
      : ref.watch(
          holidaysProvider((
            schoolId: schoolId,
            branchId: branchId,
            academicYearId: academicYearId,
          )),
        );

  if (workingDays.hasError) {
    return AsyncError(
      workingDays.error!,
      workingDays.stackTrace ?? StackTrace.empty,
    );
  }
  if (holidays.hasError) {
    return AsyncError(holidays.error!, holidays.stackTrace ?? StackTrace.empty);
  }
  if (!workingDays.hasValue || !holidays.hasValue) return const AsyncLoading();
  return AsyncData(
    AttendanceCalendar.evaluate(
      date: date,
      workingDays: workingDays.value!,
      calendarEntries: holidays.value!,
    ),
  );
}

/// Why [date] cannot be used for attendance at all, or null: never a date
/// after today; and, when a [year] is given, it must lie inside its dates.
String? attendanceDateError(
  DateTime date, {
  AcademicYear? year,
  DateTime? today,
}) {
  final day = AttendanceDate.dateOnly(date);
  final now = AttendanceDate.dateOnly(today ?? DateTime.now());
  if (day.isAfter(now)) return 'Attendance cannot be marked for a future date.';
  if (year != null) {
    final start = AttendanceDate.dateOnly(year.startDate);
    final end = AttendanceDate.dateOnly(year.endDate);
    if (day.isBefore(start) || day.isAfter(end)) {
      return 'This date is outside the academic year ${year.name}.';
    }
  }
  return null;
}
