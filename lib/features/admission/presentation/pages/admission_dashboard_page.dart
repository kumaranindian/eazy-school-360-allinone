import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_activity.dart';
import '../../domain/admission_status.dart';
import '../providers/admission_providers.dart';
import '../widgets/admission_widgets.dart';

/// Admission home: whether the module is on, headline numbers (server-side
/// `count()` aggregates, never a download of the enquiries) and the ways in.
class AdmissionDashboardPage extends ConsumerWidget {
  const AdmissionDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.contact_phone_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canSetUp = tenant.can(Permission.manageSchool);
        final settings = ref.watch(admissionSettingsProvider(schoolId));
        final counts = ref.watch(
          admissionCountsProvider((schoolId: schoolId, branchId: branchId)),
        );
        final followUps = ref.watch(
          followUpCountsProvider((
            schoolId: schoolId,
            branchId: branchId,
            userId: tenant.user.userId,
          )),
        );
        final enabled = settings.value?.enabled ?? false;
        final wide = screenSizeForWidth(MediaQuery.sizeOf(context).width);

        return Scaffold(
          floatingActionButton: enabled
              ? FloatingActionButton.extended(
                  onPressed: () => context.push(AppRoutes.admissionNewEnquiry),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('New enquiry'),
                )
              : null,
          body: ListView(
            padding: EdgeInsets.all(wide.isMobile ? 16 : 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (settings.hasValue && !enabled)
                        _NotEnabledCard(canSetUp: canSetUp),
                      if (enabled) ...[
                        counts.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => ParentsCard(
                            child: Text(
                              'Could not load the numbers. Pull down or try '
                              'again later.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          data: (c) => _Stats(counts: c),
                        ),
                        const SizedBox(height: 16),
                        ParentsCard(
                          onTap: () =>
                              context.push(AppRoutes.admissionFollowUps),
                          semanticLabel: 'Follow-ups',
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const ParentsSectionTitle(
                                      icon: Icons.event_note_outlined,
                                      title: 'Follow-ups',
                                    ),
                                    if (followUps.value != null) ...[
                                      const SizedBox(height: 8),
                                      _FollowUpSummary(counts: followUps.value),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ParentsCard(
                          onTap: () =>
                              context.push(AppRoutes.admissionApplications),
                          child: const Row(
                            children: [
                              Expanded(
                                child: ParentsSectionTitle(
                                  icon: Icons.description_outlined,
                                  title: 'Applications',
                                ),
                              ),
                              Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ParentsCard(
                          onTap: () => context.push(AppRoutes.admissionReports),
                          child: const Row(
                            children: [
                              Expanded(
                                child: ParentsSectionTitle(
                                  icon: Icons.insights_outlined,
                                  title: 'Reports',
                                ),
                              ),
                              Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ParentsCard(
                          onTap: () =>
                              context.push(AppRoutes.admissionEnquiries),
                          child: const Row(
                            children: [
                              Expanded(
                                child: ParentsSectionTitle(
                                  icon: Icons.list_alt_outlined,
                                  title: 'All enquiries',
                                ),
                              ),
                              Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ],
                      if (canSetUp) ...[
                        const SizedBox(height: 16),
                        ParentsCard(
                          onTap: () =>
                              context.push(AppRoutes.admissionSettings),
                          child: const Row(
                            children: [
                              Expanded(
                                child: ParentsSectionTitle(
                                  icon: Icons.tune_outlined,
                                  title: 'Admission settings',
                                ),
                              ),
                              Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "3 today · 2 overdue" beside the Follow-ups entry.
class _FollowUpSummary extends StatelessWidget {
  final FollowUpCounts? counts;
  const _FollowUpSummary({required this.counts});

  @override
  Widget build(BuildContext context) {
    final c = counts;
    if (c == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      children: [
        ParentsBadge('${c.today} today', tone: ParentsTone.neutral),
        if (c.overdue > 0)
          ParentsBadge('${c.overdue} overdue', tone: ParentsTone.warning),
      ],
    );
  }
}

class _NotEnabledCard extends StatelessWidget {
  final bool canSetUp;
  const _NotEnabledCard({required this.canSetUp});

  @override
  Widget build(BuildContext context) {
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ParentsSectionTitle(
            icon: Icons.info_outline,
            title: 'Admissions are not switched on',
          ),
          const SizedBox(height: 8),
          Text(
            canSetUp
                ? 'Turn the admission module on in Admission settings to start '
                      'recording enquiries.'
                : 'A school administrator needs to turn the admission module '
                      'on in Admission settings.',
          ),
          if (canSetUp) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () => context.push(AppRoutes.admissionSettings),
                child: const Text('Open settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final Map<AdmissionStatus, int> counts;
  const _Stats({required this.counts});

  int _n(AdmissionStatus s) => counts[s] ?? 0;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final active = counts.entries
        .where((e) => e.key.isOpen)
        .fold<int>(0, (a, e) => a + e.value);
    final pendingApplications =
        _n(AdmissionStatus.applicationSubmitted) +
        _n(AdmissionStatus.underReview);
    final confirmed = _n(AdmissionStatus.admissionConfirmed);
    final lost =
        _n(AdmissionStatus.rejected) +
        _n(AdmissionStatus.withdrawn) +
        _n(AdmissionStatus.notInterested);
    // Conversion rate: confirmed admissions ÷ all enquiries recorded.
    final rate = total == 0 ? '—' : '${(confirmed * 100 / total).round()}%';
    final tiles = [
      AdmissionStatTile(
        icon: Icons.all_inbox_outlined,
        label: 'Total enquiries',
        value: '$total',
      ),
      AdmissionStatTile(
        icon: Icons.fiber_new_outlined,
        label: 'New',
        value: '${_n(AdmissionStatus.newEnquiry)}',
      ),
      AdmissionStatTile(
        icon: Icons.trending_up,
        label: 'Active',
        value: '$active',
      ),
      AdmissionStatTile(
        icon: Icons.thumb_up_alt_outlined,
        label: 'Interested',
        value: '${_n(AdmissionStatus.interested)}',
      ),
      AdmissionStatTile(
        icon: Icons.event_available_outlined,
        label: 'Visits scheduled',
        value: '${_n(AdmissionStatus.visitScheduled)}',
      ),
      AdmissionStatTile(
        icon: Icons.school_outlined,
        label: 'Visits completed',
        value: '${_n(AdmissionStatus.visitCompleted)}',
      ),
      AdmissionStatTile(
        icon: Icons.description_outlined,
        label: 'Applications pending',
        value: '$pendingApplications',
      ),
      AdmissionStatTile(
        icon: Icons.verified_outlined,
        label: 'Approved',
        value: '${_n(AdmissionStatus.approved)}',
      ),
      AdmissionStatTile(
        icon: Icons.how_to_reg_outlined,
        label: 'Admissions confirmed',
        value: '$confirmed',
      ),
      AdmissionStatTile(
        icon: Icons.person_off_outlined,
        label: 'Lost (rejected, withdrawn, not interested)',
        value: '$lost',
      ),
      AdmissionStatTile(
        icon: Icons.percent,
        label: 'Conversion (confirmed ÷ all enquiries)',
        value: rate,
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 900 ? 3 : (box.maxWidth >= 560 ? 2 : 1);
        const gap = 12.0;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}
