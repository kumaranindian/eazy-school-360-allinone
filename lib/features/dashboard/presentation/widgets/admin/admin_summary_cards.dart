import 'package:flutter/material.dart';

import '../../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../fees/domain/money.dart';
import '../../../domain/dashboard_summaries.dart';
import 'admin_dashboard_widgets.dart';

/// Today's attendance: ring, counts and a Mark Attendance action. Shows a
/// real empty state when nothing is recorded (unmarked is never "absent").
class AttendanceSummaryCard extends StatelessWidget {
  final AttendanceToday? data;
  final bool loading;
  final bool error;
  final bool noYear;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  const AttendanceSummaryCard({
    super.key,
    required this.data,
    required this.loading,
    required this.error,
    required this.onOpen,
    required this.onRetry,
    this.noYear = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    final d = data;

    Widget body;
    if (loading) {
      body = const SizedBox(
        height: 110,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (error) {
      body = _Message(
        icon: Icons.error_outline,
        text: "Today's attendance could not be loaded.",
        action: 'Retry',
        onAction: onRetry,
      );
    } else if (noYear) {
      body = _Message(
        icon: Icons.event_outlined,
        text: 'Set up an academic year to start taking attendance.',
        action: 'Open attendance',
        onAction: onOpen,
      );
    } else if (d == null || d.isEmpty) {
      body = _Message(
        icon: Icons.fact_check_outlined,
        text: d == null || d.expected == 0
            ? 'No students to mark yet.'
            : "Attendance has not been recorded today for ${d.expected} "
                  'student${d.expected == 1 ? '' : 's'}.',
        action: 'Mark Attendance',
        onAction: onOpen,
      );
    } else {
      body = Row(
        children: [
          AdminProgressRing(
            fraction: d.completion,
            centerText: '${d.completionPercent}%',
            color: p.success,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                AdminStatLine(
                  color: p.primary,
                  label: 'Total students',
                  value: '${d.expected}',
                ),
                AdminStatLine(
                  color: p.success,
                  label: 'Present',
                  value: '${d.present}',
                ),
                AdminStatLine(
                  color: p.warning,
                  label: 'Absent',
                  value: '${d.absent}',
                ),
                AdminStatLine(
                  color: p.textSecondary,
                  label: 'Not marked',
                  value: '${d.notMarked}',
                ),
              ],
            ),
          ),
        ],
      );
    }

    return AdminCard(
      onTap: onOpen,
      semanticLabel: "Today's attendance",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AdminIconBadge(
                icon: Icons.fact_check_outlined,
                color: p.success,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Today's Attendance",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: p.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

/// This month's collections next to the year's outstanding and rate.
class FeeCollectionCard extends StatelessWidget {
  final FeeMonthCard? data;
  final String currency;
  final bool loading;
  final bool error;
  final bool noYear;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  const FeeCollectionCard({
    super.key,
    required this.data,
    required this.currency,
    required this.loading,
    required this.error,
    required this.onOpen,
    required this.onRetry,
    this.noYear = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    final d = data;

    Widget body;
    if (loading) {
      body = const SizedBox(
        height: 110,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (error) {
      body = _Message(
        icon: Icons.error_outline,
        text: 'Fee totals could not be loaded.',
        action: 'Retry',
        onAction: onRetry,
      );
    } else if (noYear || d == null || !d.hasInvoices) {
      body = _Message(
        icon: Icons.account_balance_wallet_outlined,
        text: noYear
            ? 'Set up an academic year before using fees.'
            : 'No invoices yet. Generate invoices to start collecting fees.',
        action: 'Open fees',
        onAction: onOpen,
      );
    } else {
      final rate = d.collectionRatePercent;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Collected this month',
            style: text.bodySmall?.copyWith(color: p.textSecondary),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              Money.format(d.collectedThisMonthMinor, currency: currency),
              style: text.headlineSmall?.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Collection rate (academic year)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ),
              Text(
                rate == null ? '–' : '${rate.round()}%',
                style: text.labelLarge?.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: d.progress,
              minHeight: 10,
              backgroundColor: p.border,
              valueColor: AlwaysStoppedAnimation(p.primary),
            ),
          ),
          const SizedBox(height: 10),
          AdminStatLine(
            color: p.success,
            label: 'Collected this month',
            value: Money.format(d.collectedThisMonthMinor, currency: currency),
          ),
          AdminStatLine(
            color: p.warning,
            label: 'Outstanding',
            value: Money.format(d.outstandingMinor, currency: currency),
          ),
        ],
      );
    }

    return AdminCard(
      onTap: onOpen,
      semanticLabel: 'Fee collection',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AdminIconBadge(
                icon: Icons.account_balance_wallet_outlined,
                color: p.purple,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fee Collection',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: p.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;
  const _Message({
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: p.textSecondary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: t.bodyMedium?.copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: Text(action),
        ),
      ],
    );
  }
}
