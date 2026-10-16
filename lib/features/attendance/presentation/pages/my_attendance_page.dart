import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/domain/student.dart';
import '../../../students/presentation/providers/parent_providers.dart';
import '../../../students/presentation/providers/selected_child.dart';
import '../../../students/presentation/widgets/child_switcher.dart';
import '../../domain/attendance_date.dart';
import '../../domain/attendance_status.dart';
import '../../domain/parent_attendance_month.dart';
import '../providers/attendance_providers.dart';

typedef ChildMonthKey = ({
  String schoolId,
  String branchId,
  String studentId,
  int year,
  int month,
});

/// One child's month of attendance. Which records may be read is decided by
/// `firestore.rules` (the parent of that student only).
final childAttendanceMonthProvider = FutureProvider.autoDispose
    .family<ParentAttendanceMonth, ChildMonthKey>((ref, key) async {
      final range = await ref
          .watch(studentAttendanceRepositoryProvider)
          .fetchStudentRange(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
            fromKey: AttendanceDate.firstOfMonthKey(key.year, key.month),
            toKey: AttendanceDate.lastOfMonthKey(key.year, key.month),
          );
      return ParentAttendanceMonth.of(
        range.items,
        year: key.year,
        month: key.month,
      );
    });

/// `/my-attendance` — a parent's read-only attendance calendar for a linked
/// child, with the month's tally and percentage.
class MyAttendancePage extends ConsumerStatefulWidget {
  const MyAttendancePage({super.key});

  @override
  ConsumerState<MyAttendancePage> createState() => _MyAttendancePageState();
}

class _MyAttendancePageState extends ConsumerState<MyAttendancePage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shift(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: AsyncValueWidget<TenantContext?>(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final schoolId = tenant?.school?.schoolId;
          final parentId = tenant?.user.linkedParentId;
          if (tenant == null || schoolId == null) {
            return const EmptyView(
              icon: Icons.family_restroom_outlined,
              message: 'No school found for your account.',
            );
          }
          if (parentId == null) {
            return const EmptyView(
              icon: Icons.link_off,
              message:
                  "Your account isn't linked to a parent record yet. Please contact the school office.",
            );
          }
          final key = (schoolId: schoolId, parentId: parentId, branchId: null);
          return ref
              .watch(childrenForParentProvider(key))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorView(
                  message: userMessageFor(error),
                  onRetry: () => ref.invalidate(childrenForParentProvider),
                ),
                data: (children) {
                  final child = resolveSelectedChild(
                    children,
                    ref.watch(selectedChildIdProvider),
                  );
                  if (child == null) {
                    return const EmptyView(
                      icon: Icons.child_care_outlined,
                      message:
                          'No children are linked to your account with portal access yet.',
                    );
                  }
                  return _Body(
                    children: children,
                    child: child,
                    month: _month,
                    canGoForward: !_isCurrentMonth,
                    onPrev: () => _shift(-1),
                    onNext: () => _shift(1),
                  );
                },
              );
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final List<Student> children;
  final Student child;
  final DateTime month;
  final bool canGoForward;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _Body({
    required this.children,
    required this.child,
    required this.month,
    required this.canGoForward,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: child.schoolId,
      branchId: child.branchId,
      studentId: child.studentId,
      year: month.year,
      month: month.month,
    );
    final monthAsync = ref.watch(childAttendanceMonthProvider(key));
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ChildSwitcher(
          children: children,
          selectedId: child.studentId,
          onSelected: ref.read(selectedChildIdProvider.notifier).select,
        ),
        if (children.length > 1) const SizedBox(height: AppSpacing.md),
        Text(
          '${child.firstName} ${child.lastName}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _monthLabel(month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: canGoForward ? onNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        monthAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ErrorView(
            message: userMessageFor(error),
            onRetry: () => ref.invalidate(childAttendanceMonthProvider),
          ),
          data: (data) => data.isEmpty
              ? const EmptyView(
                  icon: Icons.event_busy_outlined,
                  message: 'No attendance has been recorded for this month.',
                )
              : _MonthView(data: data),
        ),
      ],
    );
  }
}

const _months = [
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

String _monthLabel(DateTime m) => '${_months[m.month - 1]} ${m.year}';

/// Theme-derived colours per status (no raw colours in feature code).
({Color bg, Color fg}) _statusColors(ColorScheme c, AttendanceStatus s) =>
    switch (s) {
      AttendanceStatus.present => (
        bg: c.primaryContainer,
        fg: c.onPrimaryContainer,
      ),
      AttendanceStatus.absent => (bg: c.errorContainer, fg: c.onErrorContainer),
      AttendanceStatus.late => (
        bg: c.tertiaryContainer,
        fg: c.onTertiaryContainer,
      ),
      AttendanceStatus.halfDay => (
        bg: c.secondaryContainer,
        fg: c.onSecondaryContainer,
      ),
    };

class _MonthView extends StatelessWidget {
  final ParentAttendanceMonth data;
  const _MonthView({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = data.percentage;
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _Stat(
              label: 'Attendance',
              value: pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
            ),
            for (final s in AttendanceStatus.values)
              _Stat(
                label: s.displayName,
                value: '${data.tally.countOf(s)}',
                color: _statusColors(colors, s),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _Grid(data: data),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Days with no colour have no record (weekend, holiday or not marked).',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final ({Color bg, Color fg})? color;
  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = color?.bg ?? theme.colorScheme.surfaceContainerHighest;
    final fg = color?.fg ?? theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: theme.textTheme.titleLarge?.copyWith(color: fg)),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final ParentAttendanceMonth data;
  const _Grid({required this.data});

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cells = <Widget>[
      for (final w in _weekdays)
        Center(child: Text(w, style: theme.textTheme.labelMedium)),
      for (var i = 0; i < data.leadingBlanks; i++) const SizedBox.shrink(),
      for (var d = 1; d <= data.daysInMonth; d++) _Day(day: d, data: data),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      children: cells,
    );
  }
}

class _Day extends StatelessWidget {
  final int day;
  final ParentAttendanceMonth data;
  const _Day({required this.day, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = data.statusOn(day);
    final c = status == null ? null : _statusColors(theme.colorScheme, status);
    return Semantics(
      label: status == null
          ? 'Day $day, no record'
          : 'Day $day, ${status.displayName}',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c?.bg,
          borderRadius: BorderRadius.circular(8),
          border: c == null
              ? Border.all(color: theme.colorScheme.outlineVariant)
              : null,
        ),
        child: Text(
          '$day',
          style: theme.textTheme.bodyMedium?.copyWith(color: c?.fg),
        ),
      ),
    );
  }
}
