import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_application.dart';
import '../providers/admission_providers.dart';
import '../widgets/application_widgets.dart';

/// All applications of the branch, newest first, filtered by status. A status
/// chip carries its server-side count.
class ApplicationsPage extends ConsumerStatefulWidget {
  const ApplicationsPage({super.key});

  @override
  ConsumerState<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends ConsumerState<ApplicationsPage> {
  ApplicationStatus? _status;
  final List<AdmissionApplication> _items = [];
  Object? _cursor;
  bool _loading = false;
  bool _loadedOnce = false;
  Object? _error;
  String? _scope;
  int _generation = 0;

  void _reset(String schoolId, String branchId) {
    _generation++;
    _items.clear();
    _cursor = null;
    _error = null;
    _load(schoolId, branchId);
  }

  Future<void> _load(String schoolId, String branchId) async {
    if (_loading) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final page = await ref
          .read(admissionRepositoryProvider)
          .fetchApplications(
            schoolId: schoolId,
            branchId: branchId,
            status: _status,
            cursor: _cursor,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
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
            icon: Icons.description_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final scope = '$schoolId/$branchId';
        if (_scope != scope) {
          _scope = scope;
          _loadedOnce = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _reset(schoolId, branchId);
          });
        }
        final BranchKey key = (schoolId: schoolId, branchId: branchId);
        final counts = ref.watch(applicationCountsProvider(key)).value;
        final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);
        final p = AdminDashboardPalette.of(context);

        Widget chip(String label, ApplicationStatus? s) => ChoiceChip(
          label: Text(
            counts == null
                ? label
                : '$label ${s == null ? counts.values.fold<int>(0, (a, b) => a + b) : (counts[s] ?? 0)}',
          ),
          selected: _status == s,
          onSelected: (_) {
            if (_status == s) return;
            setState(() => _status = s);
            _reset(schoolId, branchId);
          },
        );

        return Scaffold(
          body: Column(
            children: [
              ParentsPageBar(
                title: 'Applications',
                onBack: () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.admissions),
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
                                chip('All', null),
                                for (final s in ApplicationStatus.values)
                                  chip(s.label, s),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (!_loadedOnce && _loading)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_error != null && _items.isEmpty)
                              EmptyView(
                                icon: Icons.error_outline,
                                message: userMessageFor(_error!),
                              )
                            else if (_items.isEmpty)
                              const EmptyView(
                                icon: Icons.description_outlined,
                                message: 'No applications here yet.',
                              )
                            else
                              LayoutBuilder(
                                builder: (context, box) {
                                  final two = box.maxWidth >= 900;
                                  const gap = 12.0;
                                  final width = two
                                      ? (box.maxWidth - gap) / 2
                                      : box.maxWidth;
                                  return Wrap(
                                    spacing: gap,
                                    runSpacing: gap,
                                    children: [
                                      for (final a in _items)
                                        SizedBox(
                                          width: width,
                                          child: ParentsCard(
                                            onTap: () => context.push(
                                              '/admissions/enquiries/${a.enquiryId}',
                                            ),
                                            semanticLabel:
                                                '${a.studentName}, ${a.status.label}, '
                                                'application ${a.applicationNumber}',
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                ParentsAvatar(
                                                  name: a.studentName,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Wrap(
                                                        spacing: 8,
                                                        runSpacing: 4,
                                                        crossAxisAlignment:
                                                            WrapCrossAlignment
                                                                .center,
                                                        children: [
                                                          Text(
                                                            a.studentName,
                                                            style: Theme.of(context)
                                                                .textTheme
                                                                .titleMedium
                                                                ?.copyWith(
                                                                  color: p
                                                                      .textPrimary,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                          ),
                                                          ApplicationStatusBadge(
                                                            a.status,
                                                          ),
                                                        ],
                                                      ),
                                                      Text(
                                                        '${a.applicationNumber} · ${a.enquiryNumber}',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: p
                                                                  .textSecondary,
                                                            ),
                                                      ),
                                                      if (a
                                                          .guardians
                                                          .isNotEmpty)
                                                        ParentsFactRow(
                                                          icon: Icons
                                                              .person_outline,
                                                          text:
                                                              '${a.guardians.first.name} · ${a.guardians.first.phone}',
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right,
                                                  color: p.textSecondary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            if (_cursor != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Center(
                                  child: _loading
                                      ? const CircularProgressIndicator()
                                      : OutlinedButton(
                                          onPressed: () =>
                                              _load(schoolId, branchId),
                                          child: const Text('Load more'),
                                        ),
                                ),
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
}
