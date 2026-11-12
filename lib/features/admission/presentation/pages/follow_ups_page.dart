import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_activity.dart';
import '../../domain/admission_enquiry.dart';
import '../providers/admission_providers.dart';
import '../widgets/activity_widgets.dart';
import '../widgets/admission_widgets.dart';

/// Follow-up dashboard: what is due today, overdue, coming up, mine,
/// unassigned or already done, and the open enquiries that have no follow-up
/// planned at all. Numbers are server-side counts; "today" is the school's.
class FollowUpsPage extends ConsumerStatefulWidget {
  const FollowUpsPage({super.key});

  @override
  ConsumerState<FollowUpsPage> createState() => _FollowUpsPageState();
}

/// The "no follow-up" list is a list of enquiries, not activities.
const _noFollowUp = 'NONE';

class _FollowUpsPageState extends ConsumerState<FollowUpsPage> {
  Object _selected = FollowUpBucket.today; // FollowUpBucket or _noFollowUp
  final List<AdmissionActivity> _activities = [];
  final List<AdmissionEnquiry> _enquiries = [];
  Object? _cursor;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;
  String? _scope;
  int _generation = 0;

  void _reset(String schoolId, String branchId, String userId) {
    _generation++;
    _activities.clear();
    _enquiries.clear();
    _cursor = null;
    _error = null;
    _load(schoolId, branchId, userId);
  }

  Future<void> _load(String schoolId, String branchId, String userId) async {
    if (_loading) return;
    final generation = _generation;
    setState(() => _loading = true);
    final repo = ref.read(admissionRepositoryProvider);
    try {
      if (_selected == _noFollowUp) {
        final page = await repo.fetchWithoutFollowUp(
          schoolId: schoolId,
          branchId: branchId,
          cursor: _cursor,
        );
        if (!mounted || generation != _generation) return;
        _enquiries.addAll(page.items);
        _cursor = page.nextCursor;
      } else {
        final page = await repo.fetchFollowUps(
          schoolId: schoolId,
          branchId: branchId,
          bucket: _selected as FollowUpBucket,
          todayKey: SchoolTime.todayKey(),
          userId: userId,
          cursor: _cursor,
        );
        if (!mounted || generation != _generation) return;
        _activities.addAll(page.items);
        _cursor = page.nextCursor;
      }
      setState(() {
        _loadedOnce = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loadedOnce = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncValueWidget(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.event_note_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final userId = tenant.user.userId;
        final scope = '$schoolId/$branchId/$userId';
        if (_scope != scope) {
          _scope = scope;
          _loadedOnce = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reset(schoolId, branchId, userId);
          });
        }
        final countsKey = (
          schoolId: schoolId,
          branchId: branchId,
          userId: userId,
        );
        final counts = ref.watch(followUpCountsProvider(countsKey)).value;
        final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        final todayKey = SchoolTime.todayKey();

        void select(Object v) {
          if (_selected == v) return;
          setState(() => _selected = v);
          _reset(schoolId, branchId, userId);
        }

        return Scaffold(
          body: Column(
            children: [
              ParentsPageBar(
                title: 'Follow-ups',
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.admissions),
                trailing: IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    ref.invalidate(followUpCountsProvider(countsKey));
                    _reset(schoolId, branchId, userId);
                  },
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(layout.isMobile ? 16 : 24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final b in FollowUpBucket.values)
                                  ChoiceChip(
                                    label: Text(
                                      counts == null
                                          ? b.label
                                          : '${b.label} ${counts.of(b)}',
                                    ),
                                    selected: _selected == b,
                                    onSelected: (_) => select(b),
                                  ),
                                ChoiceChip(
                                  label: Text(
                                    counts == null
                                        ? 'No follow-up'
                                        : 'No follow-up ${counts.withoutFollowUp}',
                                  ),
                                  selected: _selected == _noFollowUp,
                                  onSelected: (_) => select(_noFollowUp),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _list(
                              context,
                              layout,
                              todayKey,
                              schoolId,
                              branchId,
                              userId,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _list(
    BuildContext context,
    ScreenSize layout,
    String todayKey,
    String schoolId,
    String branchId,
    String userId,
  ) {
    final p = AdminDashboardPalette.of(context);
    if (!_loadedOnce && _loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final empty = _selected == _noFollowUp
        ? _enquiries.isEmpty
        : _activities.isEmpty;
    if (_error != null && empty) {
      return EmptyView(
        icon: Icons.error_outline,
        message: userMessageFor(_error!),
      );
    }
    if (empty) {
      return EmptyView(
        icon: Icons.event_available_outlined,
        message: switch (_selected) {
          FollowUpBucket.today => 'Nothing is due today.',
          FollowUpBucket.overdue => 'Nothing is overdue.',
          FollowUpBucket.upcoming => 'No follow-ups are planned.',
          FollowUpBucket.mine => 'Nothing is assigned to you.',
          FollowUpBucket.unassigned => 'Every follow-up has an owner.',
          FollowUpBucket.completed => 'No follow-ups have been completed yet.',
          _ => 'Every open enquiry has a follow-up planned.',
        },
      );
    }
    final names = {
      for (final a
          in ref
                  .watch(
                    assigneesProvider((schoolId: schoolId, branchId: branchId)),
                  )
                  .value ??
              const <Assignee>[])
        a.userId: a.name,
    };
    final cards = _selected == _noFollowUp
        ? [
            for (final e in _enquiries)
              EnquiryCard(
                enquiry: e,
                onTap: () => context.push('/admissions/enquiries/${e.id}'),
              ),
          ]
        : [
            for (final a in _activities)
              ActivityCard(
                activity: a,
                todayKey: todayKey,
                showEnquiry: true,
                assigneeName: names[a.assignedTo],
                onTap: () =>
                    context.push('/admissions/enquiries/${a.enquiryId}'),
              ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final two = box.maxWidth >= 900;
            const gap = 12.0;
            final width = two ? (box.maxWidth - gap) / 2 : box.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final c in cards) SizedBox(width: width, child: c),
              ],
            );
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              userMessageFor(_error!),
              style: TextStyle(color: p.warning),
            ),
          ),
        if (_cursor != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: () => _load(schoolId, branchId, userId),
                      child: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}
