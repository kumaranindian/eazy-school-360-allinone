import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/holiday.dart';

/// A plain `DateTime`-driven month grid — intentionally not a third-party
/// calendar package (see the brief: "don't introduce a heavy calendar
/// dependency unless necessary"). Marks each day that has a holiday and
/// reports taps so the page can open the add/edit dialog.
class HolidayCalendarView extends StatefulWidget {
  final List<Holiday> holidays;
  final void Function(DateTime date, Holiday? existing) onDayTap;

  const HolidayCalendarView({
    super.key,
    required this.holidays,
    required this.onDayTap,
  });

  @override
  State<HolidayCalendarView> createState() => _HolidayCalendarViewState();
}

class _HolidayCalendarViewState extends State<HolidayCalendarView> {
  late DateTime _visibleMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );

  Holiday? _holidayOn(DateTime day) {
    for (final holiday in widget.holidays) {
      if (holiday.date.year == day.year &&
          holiday.date.month == day.month &&
          holiday.date.day == day.day) {
        return holiday;
      }
    }
    return null;
  }

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
      ],
    );
  }

  Widget _dayCell(BuildContext context, DateTime date) {
    final holiday = _holidayOn(date);
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => widget.onDayTap(date, holiday),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          decoration: BoxDecoration(
            color: holiday != null ? colors.errorContainer : null,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(
            '${date.day}',
            style: holiday != null
                ? TextStyle(color: colors.onErrorContainer)
                : null,
          ),
        ),
      ),
    );
  }

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
