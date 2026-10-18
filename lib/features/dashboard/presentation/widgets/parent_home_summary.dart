import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/regional/regional_providers.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../attendance/domain/parent_attendance_month.dart';
import '../../../attendance/presentation/pages/my_attendance_page.dart';
import '../../../fees/domain/fee_planners.dart';
import '../../../fees/domain/fee_dates.dart';
import '../../../fees/domain/money.dart';
import '../../../fees/presentation/providers/fee_providers.dart';
import '../../../students/domain/student.dart';
import '../../../students/presentation/providers/parent_providers.dart';
import '../../../students/presentation/providers/selected_child.dart';
import '../../../students/presentation/widgets/child_switcher.dart';

typedef _ChildKey = ({String schoolId, String branchId, String studentId});

class _FeeNow {
  final int balanceMinor;
  final int overdueMinor;
  final String currency;
  const _FeeNow(this.balanceMinor, this.overdueMinor, this.currency);
}

final _childFeeNowProvider = FutureProvider.autoDispose
    .family<_FeeNow, _ChildKey>((ref, key) async {
      final invoices = await ref
          .watch(invoiceRepositoryProvider)
          .fetchStudentInvoices(
            schoolId: key.schoolId,
            branchId: key.branchId,
            studentId: key.studentId,
          );
      final summary = StudentFeeSummary.of(
        invoices,
        todayKey: FeeDates.todayKey(),
      );
      return _FeeNow(
        summary.balanceMinor,
        summary.overdueMinor,
        invoices.firstOrNull?.currency ??
            ref.read(regionalSettingsProvider).currency,
      );
    });

/// The top of a parent's dashboard: pick a child, then see this month's
/// attendance and the fee balance at a glance. Each card opens the full
/// screen. Everything shown is read through `firestore.rules`, so a parent
/// only ever gets their own linked children.
class ParentHomeSummary extends ConsumerWidget {
  final TenantContext tenant;
  const ParentHomeSummary({super.key, required this.tenant});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = tenant.school?.schoolId;
    final parentId = tenant.user.linkedParentId;
    if (schoolId == null || parentId == null) {
      return const _Note(
        icon: Icons.link_off,
        text:
            "Your account isn't linked to a parent record yet. Please contact the school office.",
      );
    }
    final key = (schoolId: schoolId, parentId: parentId, branchId: null);
    return ref
        .watch(childrenForParentProvider(key))
        .when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _Note(
            icon: Icons.error_outline,
            text: userMessageFor(e),
            onRetry: () => ref.invalidate(childrenForParentProvider),
          ),
          data: (children) {
            final child = resolveSelectedChild(
              children,
              ref.watch(selectedChildIdProvider),
            );
            if (child == null) {
              return const _Note(
                icon: Icons.child_care_outlined,
                text:
                    'No children are linked to your account with portal access yet.',
              );
            }
            return _Summary(tenant: tenant, children: children, child: child);
          },
        );
  }
}

class _Summary extends ConsumerWidget {
  final TenantContext tenant;
  final List<Student> children;
  final Student child;
  const _Summary({
    required this.tenant,
    required this.children,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = SchoolTime.wallNow();
    final attendance = ref.watch(
      childAttendanceMonthProvider((
        schoolId: child.schoolId,
        branchId: child.branchId,
        studentId: child.studentId,
        year: now.year,
        month: now.month,
      )),
    );
    final fees = tenant.can(AppRoutes.requiredPermissions[AppRoutes.myFees]!)
        ? ref.watch(
            _childFeeNowProvider((
              schoolId: child.schoolId,
              branchId: child.branchId,
              studentId: child.studentId,
            )),
          )
        : null;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${child.firstName} ${child.lastName}',
          style: theme.textTheme.titleLarge,
        ),
        if (children.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          ChildSwitcher(
            children: children,
            selectedId: child.studentId,
            onSelected: ref.read(selectedChildIdProvider.notifier).select,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            _Card(
              icon: Icons.fact_check_outlined,
              title: 'Attendance this month',
              value: attendance.when(
                loading: () => '…',
                error: (_, _) => 'Unavailable',
                data: _attendanceValue,
              ),
              onTap: () => context.go(AppRoutes.myAttendance),
            ),
            if (fees != null)
              _Card(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Fees due',
                value: fees.when(
                  loading: () => '…',
                  error: (_, _) => 'Unavailable',
                  data: (f) => f.balanceMinor == 0
                      ? 'All paid'
                      : Money.format(f.balanceMinor, currency: f.currency),
                ),
                caption: fees.value != null && fees.value!.overdueMinor > 0
                    ? '${Money.format(fees.value!.overdueMinor, currency: fees.value!.currency)} overdue'
                    : null,
                onTap: () => context.go(AppRoutes.myFees),
              ),
          ],
        ),
      ],
    );
  }

  static String _attendanceValue(ParentAttendanceMonth m) {
    final pct = m.percentage;
    if (pct == null) return 'No records yet';
    return '${pct.toStringAsFixed(0)}% present';
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String? caption;
  final VoidCallback onTap;

  const _Card({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(title, style: theme.textTheme.labelLarge),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(value, style: theme.textTheme.headlineSmall),
                if (caption != null)
                  Text(
                    caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
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

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Note({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(text)),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
