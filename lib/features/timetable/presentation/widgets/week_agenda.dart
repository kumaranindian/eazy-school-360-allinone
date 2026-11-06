import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dashboard/home_widgets.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../../academic_setup/domain/weekday.dart';

/// One line of a day: a period (or a free slot, or a break).
class AgendaItem {
  final String time;
  final String title;
  final String? subtitle;
  final String? badge;
  final bool isEmpty;
  final bool isBreak;
  final bool highlight;
  final VoidCallback? onTap;

  const AgendaItem({
    required this.time,
    required this.title,
    this.subtitle,
    this.badge,
    this.isEmpty = false,
    this.isBreak = false,
    this.highlight = false,
    this.onTap,
  });
}

/// A week as one column per day on wide screens, and a day-by-day list with a
/// day selector on narrow ones — never a desktop grid squeezed onto a phone.
///
/// Give [mondayKey] (`yyyy-MM-dd`) to show each day's date on its chip and
/// heading ("Mon 02 Nov").
class WeekAgenda extends StatefulWidget {
  final List<Weekday> days;
  final Map<Weekday, List<AgendaItem>> items;
  final String emptyDayMessage;
  final String? mondayKey;

  const WeekAgenda({
    super.key,
    required this.days,
    required this.items,
    this.emptyDayMessage = 'Nothing scheduled.',
    this.mondayKey,
  });

  @override
  State<WeekAgenda> createState() => _WeekAgendaState();
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "02 Nov" for [day] of the week starting [mondayKey]; null without a key.
String? _dayDate(String? mondayKey, Weekday day) {
  if (mondayKey == null) return null;
  final m = AttendanceDate.parse(mondayKey);
  final d = DateTime.utc(m.year, m.month, m.day + day.index);
  return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]}';
}

class _WeekAgendaState extends State<WeekAgenda> {
  Weekday? _selected;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    if (days.isEmpty) {
      return const Center(child: Text('No working days are configured.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _DayColumn(
                        day: d,
                        date: _dayDate(widget.mondayKey, d),
                        items: widget.items[d] ?? const [],
                        emptyMessage: widget.emptyDayMessage,
                        compact: true,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        final selected = days.contains(_selected) ? _selected! : days.first;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DayChip(
                        day: days[i],
                        date: _dayDate(widget.mondayKey, days[i]),
                        selected: days[i] == selected,
                        onTap: () => setState(() => _selected = days[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: _DayColumn(
                  day: selected,
                  date: _dayDate(widget.mondayKey, selected),
                  items: widget.items[selected] ?? const [],
                  emptyMessage: widget.emptyDayMessage,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DayChip extends StatelessWidget {
  final Weekday day;
  final String? date;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.day,
    required this.date,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primary : theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md + 2),
          side: BorderSide(
            color: selected
                ? AppColors.primaryLight
                : theme.colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  day.displayName.substring(0, 3),
                  maxLines: 1,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (date != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      date!,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(color: fg),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent colours cycled over a day's periods, as in the design.
const _periodColors = [
  AppColors.secondary,
  AppColors.teal,
  AppColors.gold,
  AppColors.accent,
  AppColors.orange,
];

IconData _periodIcon(int i) => const [
  Icons.menu_book_outlined,
  Icons.eco_outlined,
  Icons.translate,
  Icons.science_outlined,
  Icons.palette_outlined,
][i % 5];

class _DayColumn extends StatelessWidget {
  final Weekday day;
  final String? date;
  final List<AgendaItem> items;
  final String emptyMessage;
  final bool compact;

  const _DayColumn({
    required this.day,
    required this.items,
    required this.emptyMessage,
    this.date,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heading = date == null
        ? day.displayName
        : '${day.displayName}, $date';
    final periods = items.where((i) => !i.isBreak && !i.isEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Text(heading, style: theme.textTheme.titleSmall)
        else
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  heading,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                StatusPill(
                  '$periods ${periods == 1 ? 'Period' : 'Periods'}',
                  color: AppColors.primaryLight,
                ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Text(emptyMessage, style: theme.textTheme.bodySmall)
        else
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _PeriodCard(
                item: items[i],
                index: i,
                compact: compact,
                splitPeriod: date != null,
              ),
            ),
      ],
    );
  }
}

/// "Period 3 · 12:00 – 12:20 PM" → ("P3", "12:00 – 12:20 PM").
(String?, String) _splitTime(String time) {
  final m = RegExp(r'^Period (\d+) · (.*)$').firstMatch(time);
  return m == null ? (null, time) : ('P${m.group(1)}', m.group(2)!);
}

class _PeriodCard extends StatelessWidget {
  final AgendaItem item;
  final int index;
  final bool compact;
  final bool splitPeriod;

  const _PeriodCard({
    required this.item,
    required this.index,
    required this.compact,
    required this.splitPeriod,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = item.isBreak
        ? theme.colorScheme.outline
        : item.highlight
        ? AppColors.orange
        : _periodColors[index % _periodColors.length];
    final (period, range) = splitPeriod
        ? _splitTime(item.time)
        : (null, item.time);
    final timeBlock = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: accent.withValues(alpha: dark ? 0.28 : 0.14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (period != null)
            Text(
              period,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          Text(range, style: theme.textTheme.bodySmall),
        ],
      ),
    );
    final details = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          if (!compact) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(_periodIcon(index), color: accent, size: 22),
            ),
            const SizedBox(width: AppSpacing.sm + 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: item.isEmpty
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        )
                      : theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                ),
                if (item.subtitle != null && item.subtitle!.isNotEmpty)
                  Row(
                    children: [
                      if (!compact) ...[
                        Icon(
                          Icons.person_outline,
                          size: 15,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          item.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (item.badge != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (item.onTap != null && !compact)
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
        ],
      ),
    );
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: accent.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.onTap,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [timeBlock, details],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: accent),
                    SizedBox(
                      width: (MediaQuery.textScalerOf(
                        context,
                      ).scale(112)).clamp(112, 170),
                      child: timeBlock,
                    ),
                    Expanded(child: details),
                  ],
                ),
              ),
      ),
    );
  }
}

/// A rounded "‹  📅 Week of 02/11/2026  ›" control that wraps instead of
/// overflowing on a narrow screen.
class WeekNavigator extends StatelessWidget {
  final String label;
  final ValueChanged<int> onShift;

  const WeekNavigator({super.key, required this.label, required this.onShift});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget arrow(IconData icon, String tip, int by) => IconButton.filledTonal(
      tooltip: tip,
      icon: Icon(icon),
      onPressed: () => onShift(by),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.chevron_left, 'Previous week', -1),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              color: theme.colorScheme.surface,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        arrow(Icons.chevron_right, 'Next week', 1),
      ],
    );
  }
}
