import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
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
class WeekAgenda extends StatefulWidget {
  final List<Weekday> days;
  final Map<Weekday, List<AgendaItem>> items;
  final String emptyDayMessage;

  const WeekAgenda({
    super.key,
    required this.days,
    required this.items,
    this.emptyDayMessage = 'Nothing scheduled.',
  });

  @override
  State<WeekAgenda> createState() => _WeekAgendaState();
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
                        items: widget.items[d] ?? const [],
                        emptyMessage: widget.emptyDayMessage,
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
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                children: [
                  for (final d in days)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(d.displayName.substring(0, 3)),
                        selected: d == selected,
                        onSelected: (_) => setState(() => _selected = d),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _DayColumn(
                  day: selected,
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

class _DayColumn extends StatelessWidget {
  final Weekday day;
  final List<AgendaItem> items;
  final String emptyMessage;

  const _DayColumn({
    required this.day,
    required this.items,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(day.displayName, style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (items.isEmpty)
          Text(emptyMessage, style: theme.textTheme.bodySmall)
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Card(
                margin: EdgeInsets.zero,
                color: item.isBreak
                    ? theme.colorScheme.surfaceContainerHighest
                    : item.highlight
                    ? theme.colorScheme.tertiaryContainer
                    : null,
                child: InkWell(
                  onTap: item.onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.time, style: theme.textTheme.labelSmall),
                        const SizedBox(height: 2),
                        Text(
                          item.title,
                          style: item.isEmpty
                              ? theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                )
                              : theme.textTheme.titleSmall,
                        ),
                        if (item.subtitle != null)
                          Text(
                            item.subtitle!,
                            style: theme.textTheme.bodySmall,
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
                ),
              ),
            ),
      ],
    );
  }
}

/// "‹ Week of 06/10/2026 ›" that wraps instead of overflowing on a narrow
/// screen.
class WeekNavigator extends StatelessWidget {
  final String label;
  final ValueChanged<int> onShift;

  const WeekNavigator({super.key, required this.label, required this.onShift});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onShift(-1),
        ),
        Text(label),
        IconButton(
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onShift(1),
        ),
      ],
    );
  }
}
