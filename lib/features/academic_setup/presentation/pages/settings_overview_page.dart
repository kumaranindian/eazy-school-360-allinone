import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/setup_status.dart';
import '../providers/setup_status_provider.dart';

/// One place a user can configure, and (via [setupLabel]) which row of the
/// computed [SetupStatus] reports on it.
class _Section {
  final String label;
  final String description;
  final IconData icon;
  final String route;
  final Permission permission;
  final String setupLabel;

  const _Section({
    required this.label,
    required this.description,
    required this.icon,
    required this.route,
    required this.permission,
    required this.setupLabel,
  });
}

class _Group {
  final String title;
  final String subtitle;
  final List<_Section> sections;

  const _Group(this.title, this.subtitle, this.sections);
}

/// Landing page for `/settings`: how far setup has got, what to do next, and
/// every configuration area grouped by purpose. REQUIRED and OPTIONAL steps
/// are told apart rather than blocking the app on all of them being done.
class SettingsOverviewPage extends ConsumerWidget {
  const SettingsOverviewPage({super.key});

  static const _groups = [
    _Group('Organisation', 'Who the school is and where it operates', [
      _Section(
        label: 'School profile',
        description: 'Name, logo, address and contact details',
        icon: Icons.school_outlined,
        route: AppRoutes.school,
        permission: Permission.manageSchool,
        setupLabel: 'School Profile',
      ),
      _Section(
        label: 'Branches',
        description: 'Campuses and the details of each branch',
        icon: Icons.apartment_outlined,
        route: AppRoutes.settingsBranches,
        permission: Permission.manageBranches,
        setupLabel: 'Branch',
      ),
    ]),
    _Group('Academic structure', 'How teaching is organised each year', [
      _Section(
        label: 'Academic years',
        description: 'Terms and the current academic year',
        icon: Icons.event_outlined,
        route: AppRoutes.settingsAcademicYears,
        permission: Permission.viewAcademicSetup,
        setupLabel: 'Academic Year',
      ),
      _Section(
        label: 'Classes',
        description: 'Grades or standards offered this year',
        icon: Icons.class_outlined,
        route: AppRoutes.settingsClasses,
        permission: Permission.viewAcademicSetup,
        setupLabel: 'Classes',
      ),
      _Section(
        label: 'Sections',
        description: 'Divisions within each class',
        icon: Icons.grid_view_outlined,
        route: AppRoutes.settingsSections,
        permission: Permission.viewAcademicSetup,
        setupLabel: 'Sections',
      ),
      _Section(
        label: 'Subjects',
        description: 'Subjects taught and where they apply',
        icon: Icons.menu_book_outlined,
        route: AppRoutes.settingsSubjects,
        permission: Permission.viewAcademicSetup,
        setupLabel: 'Subjects',
      ),
    ]),
    _Group('Calendar', 'When the school is in session', [
      _Section(
        label: 'Working days',
        description: 'Which days of the week classes run',
        icon: Icons.calendar_view_week_outlined,
        route: AppRoutes.settingsWorkingDays,
        permission: Permission.viewAcademicSetup,
        setupLabel: 'Working Days',
      ),
      _Section(
        label: 'Holiday calendar',
        description: 'Holidays and closures for the year',
        icon: Icons.event_busy_outlined,
        route: AppRoutes.settingsHolidays,
        permission: Permission.viewAcademicSetup,
        setupLabel: 'Holiday Calendar',
      ),
    ]),
    _Group('Security', 'Who can sign in, and how', [
      _Section(
        label: 'Authentication',
        description: 'Email, Google and phone sign-in for your school',
        icon: Icons.admin_panel_settings_outlined,
        route: AppRoutes.settingsAuthentication,
        permission: Permission.manageSchool,
        setupLabel: 'Authentication',
      ),
    ]),
  ];

  static _Section? _sectionFor(String setupLabel) {
    for (final g in _groups) {
      for (final s in g.sections) {
        if (s.setupLabel == setupLabel) return s;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.settings_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final statusAsync = ref.watch(
          setupStatusProvider((schoolId: schoolId, branchId: branchId)),
        );
        // Null while loading or on error: the page still works as a menu.
        final status = statusAsync.value;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (statusAsync.hasError)
                const _StatusUnavailable()
              else if (status == null)
                const _ProgressSkeleton()
              else
                _SetupProgressCard(status: status, tenant: tenant),
              for (final group in _groups) ...[
                const SizedBox(height: AppSpacing.lg),
                HubGroup(
                  title: group.title,
                  subtitle: group.subtitle,
                  tiles: [
                    for (final s in group.sections)
                      if (tenant.can(s.permission))
                        _tileFor(context, s, status),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }

  static Widget _tileFor(
    BuildContext context,
    _Section section,
    SetupStatus? status,
  ) {
    SetupItem? item;
    for (final i in status?.items ?? const <SetupItem>[]) {
      if (i.label == section.setupLabel) item = i;
    }
    String? badge;
    var tone = HubBadgeTone.neutral;
    if (item != null) {
      if (item.isComplete) {
        badge = 'Done';
        tone = HubBadgeTone.success;
      } else if (item.isRequired) {
        badge = 'Needs setup';
        tone = HubBadgeTone.warning;
      } else {
        badge = 'Optional';
      }
    }
    return HubTile(
      icon: section.icon,
      title: section.label,
      description: section.description,
      badge: badge,
      badgeTone: tone,
      onTap: () => context.go(section.route),
    );
  }
}

/// Progress through the required steps, the next thing to do, and every step
/// as a tappable chip.
class _SetupProgressCard extends StatelessWidget {
  final SetupStatus status;
  final TenantContext tenant;

  const _SetupProgressCard({required this.status, required this.tenant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final required = status.requiredItems;
    final done = required.where((i) => i.isComplete).length;
    final complete = status.isRequiredSetupComplete;
    final next = required.where((i) => !i.isComplete).firstOrNull;
    final nextSection = next == null
        ? null
        : SettingsOverviewPage._sectionFor(next.label);
    final canGoNext = nextSection != null && tenant.can(nextSection.permission);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final action = canGoNext
                    ? FilledButton.icon(
                        onPressed: () => context.go(nextSection.route),
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(
                          'Set up ${nextSection.label.toLowerCase()}',
                        ),
                      )
                    : null;
                final summary = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          complete
                              ? Icons.verified
                              : Icons.rocket_launch_outlined,
                          color: complete
                              ? AppColors.success
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            complete ? 'Setup complete' : 'Finish setting up',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      complete
                          ? 'Every required step is done.'
                          : '$done of ${required.length} required steps done',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
                if (action == null) return summary;
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      summary,
                      const SizedBox(height: AppSpacing.md),
                      action,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: AppSpacing.md),
                    action,
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: '$done of ${required.length} required steps done',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: required.isEmpty ? 1 : done / required.length,
                  minHeight: 8,
                  color: complete ? AppColors.success : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in status.items) _stepChip(context, item),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepChip(BuildContext context, SetupItem item) {
    final section = SettingsOverviewPage._sectionFor(item.label);
    final tappable = section != null && tenant.can(section.permission);
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(
        item.isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: item.isComplete ? AppColors.success : scheme.outline,
      ),
      label: Text(item.isRequired ? item.label : '${item.label} (optional)'),
      onPressed: tappable ? () => context.go(section.route) : null,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ProgressSkeleton extends StatelessWidget {
  const _ProgressSkeleton();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: LinearProgressIndicator(),
    ),
  );
}

/// The progress summary failed to load; the sections below still work.
class _StatusUnavailable extends StatelessWidget {
  const _StatusUnavailable();

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text('Setup progress is unavailable right now.'),
          ),
        ],
      ),
    ),
  );
}
