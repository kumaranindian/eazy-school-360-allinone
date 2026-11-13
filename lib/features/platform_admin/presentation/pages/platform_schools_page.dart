import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/platform_school.dart';
import '../providers/platform_console_providers.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../domain/platform_role.dart';
import '../widgets/create_school_dialog.dart';
import '../widgets/platform_scaffold.dart';

/// Every school on the platform (metadata only): search, filter by status, and
/// open one for its overview or a support session.
class PlatformSchoolsPage extends ConsumerStatefulWidget {
  const PlatformSchoolsPage({super.key});

  @override
  ConsumerState<PlatformSchoolsPage> createState() =>
      _PlatformSchoolsPageState();
}

class _PlatformSchoolsPageState extends ConsumerState<PlatformSchoolsPage> {
  final _search = TextEditingController();
  String? _status; // null = all

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final out = await showDialog<({String schoolId, bool emailSent})>(
      context: context,
      builder: (_) => const CreateSchoolDialog(),
    );
    if (out == null || !mounted) return;
    context.showSnackBar(
      out.emailSent
          ? 'School created. A password-setup email is on its way to the administrator.'
          : 'School created, but the email could not be sent. Use "Reset access" on the school.',
      isError: !out.emailSent,
    );
    context.go('/platform/schools/${out.schoolId}');
  }

  @override
  Widget build(BuildContext context) {
    final isOwner =
        ref.watch(tenantContextProvider).value?.user.platformRole ==
        PlatformRole.owner;
    return PlatformScaffold(
      title: 'Schools',
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              key: const ValueKey('schools-create'),
              onPressed: _create,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Create school'),
            )
          : null,
      child: AsyncValueWidget(
        value: ref.watch(platformSchoolsProvider),
        errorMessage: userMessageFor,
        onRetry: () => ref.invalidate(platformSchoolsProvider),
        data: (schools) {
          final shown = [
            for (final s in schools)
              if ((_status == null || s.status == _status) &&
                  s.matches(_search.text))
                s,
          ];
          final counts = <String, int>{};
          for (final s in schools) {
            counts[s.status] = (counts[s.status] ?? 0) + 1;
          }
          return PlatformBody(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: TextField(
                    key: const ValueKey('schools-search'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search by name, code or city',
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      for (final f in <(String?, String)>[
                        (null, 'All ${schools.length}'),
                        for (final st in const [
                          'ACTIVE',
                          'SUSPENDED',
                          'INACTIVE',
                        ])
                          if ((counts[st] ?? 0) > 0)
                            (st, '${_label(st)} ${counts[st]}'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: ChoiceChip(
                            key: ValueKey('schools-filter-${f.$1 ?? 'all'}'),
                            label: Text(f.$2),
                            selected: _status == f.$1,
                            onSelected: (_) => setState(() => _status = f.$1),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const EmptyView(
                          icon: Icons.school_outlined,
                          message: 'No schools match.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (_, i) => _SchoolCard(school: shown[i]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _label(String status) => switch (status) {
  'ACTIVE' => 'Active',
  'SUSPENDED' => 'Suspended',
  'INACTIVE' => 'Inactive',
  _ => status,
};

class _SchoolCard extends StatelessWidget {
  final PlatformSchool school;

  const _SchoolCard({required this.school});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final where = [
      school.code,
      school.city,
      school.country,
    ].where((e) => e.isNotEmpty).join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('school-${school.id}'),
        onTap: () => context.go('/platform/schools/${school.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      school.name.isEmpty ? school.id : school.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (where.isNotEmpty)
                      Text(where, style: theme.textTheme.bodySmall),
                    if (school.createdAt != null)
                      Text(
                        'Joined ${formatDisplayDate(school.createdAt!)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Chip(
                label: Text(_label(school.status)),
                backgroundColor: school.isActive
                    ? null
                    : theme.colorScheme.errorContainer,
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
