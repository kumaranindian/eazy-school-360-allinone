import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/holiday.dart';
import '../../domain/holiday_type.dart';
import '../../domain/school_calendar.dart';
import '../../domain/working_days.dart';

/// A plain `DateTime`-driven month grid — intentionally not a third-party
/// calendar package. Every cell is judged by [SchoolCalendar], the same
/// service attendance and leave use, so what the admin sees here is exactly
/// what those screens will do: holidays by type, weekly offs (including
/// Saturday patterns), special working days, and ordinary working days.
class HolidayCalendarView extends StatefulWidget {
  final List<Holiday> holidays;

  /// The branch's weekly pattern. Without it only holidays are marked.
  final WorkingDays? workingDays;
  final void Function(DateTime date, Holiday? existing) onDayTap;

  const HolidayCalendarView({
    super.key,
    required this.holidays,
    required this.onDayTap,
    this.workingDays,
  });

  @override
  State<HolidayCalendarView> createState() => _HolidayCalendarViewState();
}

class _HolidayCalendarViewState extends State<HolidayCalendarView> {
  late DateTime _visibleMonth = DateTime(
    SchoolTime.wallNow().year,
    SchoolTime.wallNow().month,
  );

  SchoolDayInfo _info(DateTime day) => SchoolCalendar.evaluate(
    date: day,
    workingDays:
        widget.workingDays ??
        WorkingDays(
          schoolId: '',
          branchId: '',
          // Without a pattern nothing is marked as a weekly off.
          isWorkingDay: {
            for (final d in WorkingDays.defaultPattern().keys) d: true,
          },
        ),
    holidays: widget.holidays,
  );

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month);
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leadingBlanks =
        firstOfMonth.weekday - 1; // Monday = 1 -> 0 leading blanks

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Previous month',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                () => _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month - 1,
                ),
              ),
            ),
            Text(
              '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Next month',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                () => _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month + 1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            for (var i = 0; i < leadingBlanks; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++)
              _dayCell(
                context,
                DateTime(_visibleMonth.year, _visibleMonth.month, day),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const CalendarLegend(),
      ],
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final info = _info(date);
    final colors = Theme.of(context).colorScheme;
    final (bg, fg) = _paint(colors, info);
    final label = info.isHoliday
        ? '${info.primary!.name} (${info.primary!.type.displayName})'
        : info.isWeeklyOff
        ? 'Weekly off: ${info.weeklyOffLabel}'
        : null;
    return Semantics(
      label: label == null ? '${date.day}' : '${date.day}, $label',
      child: Tooltip(
        message: label ?? '',
        child: InkWell(
          onTap: () => widget.onDayTap(date, info.primary),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
                border: info.kind == SchoolDayKind.specialWorkingDay
                    ? Border.all(color: colors.primary)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                '${date.day}',
                style: fg == null ? null : TextStyle(color: fg),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Colours by meaning; the legend uses the same function.
  static (Color?, Color?) _paint(ColorScheme c, SchoolDayInfo info) {
    switch (info.kind) {
      case SchoolDayKind.holiday:
        return _holidayPaint(c, info.primary!.type);
      case SchoolDayKind.weeklyOff:
        return (c.surfaceContainerHighest, c.onSurfaceVariant);
      case SchoolDayKind.specialWorkingDay:
      case SchoolDayKind.workingDay:
        return (null, null);
    }
  }

  static (Color?, Color?) _holidayPaint(ColorScheme c, HolidayType type) =>
      switch (type) {
        HolidayType.public => (c.errorContainer, c.onErrorContainer),
        HolidayType.vacation => (c.secondaryContainer, c.onSecondaryContainer),
        HolidayType.festival => (c.tertiaryContainer, c.onTertiaryContainer),
        _ => (c.primaryContainer, c.onPrimaryContainer),
      };

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}

/// What the colours on the calendar mean.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget item(String text, Color? color, {bool outlined = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: outlined ? c.primary : c.outlineVariant),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    return Wrap(
      key: const ValueKey('calendarLegend'),
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        item('Working day', null),
        item('Weekly off', c.surfaceContainerHighest),
        item('Public holiday', c.errorContainer),
        item('Festival', c.tertiaryContainer),
        item('School holiday', c.primaryContainer),
        item('Vacation', c.secondaryContainer),
        item('Special working day', null, outlined: true),
      ],
    );
  }
}
