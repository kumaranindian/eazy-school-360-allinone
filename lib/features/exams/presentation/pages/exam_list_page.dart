import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../timetable/presentation/widgets/timetable_scope.dart';
import '../../domain/exam_enums.dart';
import '../../domain/examination.dart';
import '../providers/exam_providers.dart';
import '../widgets/exam_widgets.dart';

/// `/exams` — the branch's examinations for an academic year, with their
/// state and what to do next. Teachers see them to find their marks sheets;
/// administrators also create, review and publish.
class ExamListPage extends ConsumerWidget {
  const ExamListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final canManage = tenant?.can(Permission.manageExams) ?? false;
    return Scaffold(
      appBar: pageAppBar(
        context,
        title: const Text('Examinations'),
        actions: [
          IconButton(
            tooltip: 'Academic performance',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.go(AppRoutes.examPerformance),
          ),
          if (canManage)
            IconButton(
              tooltip: 'Grading schemes',
              icon: const Icon(Icons.rule),
              onPressed: () => context.go(AppRoutes.examSchemes),
            ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.examNew),
              icon: const Icon(Icons.add),
              label: const Text('New examination'),
            )
          : null,
      body: TimetableScope(builder: (context, tt) => _ExamList(tt: tt)),
    );
  }
}

class _ExamList extends ConsumerStatefulWidget {
  final TimetableContext tt;
  const _ExamList({required this.tt});

  @override
  ConsumerState<_ExamList> createState() => _ExamListState();
}

class _ExamListState extends ConsumerState<_ExamList> {
  final _controller = PagedListController<Examination>();
  String? _classId;
  ExamStatus? _status;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => mounted ? setState(() {}) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _configure());
  }

  void _configure() {
    final repo = ref.read(examRepositoryProvider);
    _controller.fetch = (cursor) => repo.fetch(
      schoolId: widget.tt.schoolId,
      branchId: widget.tt.branchId,
      academicYearId: widget.tt.year.academicYearId,
      classId: _classId,
      status: _status,
      cursor: cursor,
    );
    _controller.reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    final classes = ref
        .watch(
          classesProvider((
            schoolId: tt.schoolId,
            branchId: tt.branchId,
            academicYearId: tt.year.academicYearId,
          )),
        )
        .value;
    final items = _controller.items;
    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<ExamStatus?>(
                  value: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final s in ExamStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.displayName)),
                  ],
                  onChanged: (v) {
                    setState(() => _status = v);
                    _configure();
                  },
                ),
              ),
              if (classes != null)
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String?>(
                    value: _classId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Class',
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      for (final c in classes)
                        DropdownMenuItem(value: c.classId, child: Text(c.name)),
                    ],
                    onChanged: (v) {
                      setState(() => _classId = v);
                      _configure();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (items.isNotEmpty) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final (label, status, icon) in [
                  ('Marks entry open', ExamStatus.inProgress, Icons.edit_note),
                  (
                    'Awaiting publication',
                    ExamStatus.completed,
                    Icons.fact_check_outlined,
                  ),
                  ('Published', ExamStatus.published, Icons.public),
                  ('Withdrawn', ExamStatus.withdrawn, Icons.undo),
                ])
                  CountTile(
                    label: label,
                    icon: icon,
                    value: items.where((e) => e.status == status).length,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Counts cover the examinations loaded below.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_controller.errorMessage != null && items.isEmpty)
            ErrorView(
              message: _controller.errorMessage!,
              onRetry: _controller.reload,
            )
          else if (!_controller.hasLoaded)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: EmptyView(
                icon: Icons.grading_outlined,
                message: 'No examinations match these filters yet.',
              ),
            )
          else ...[
            for (final e in items)
              Card(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  title: Text(e.name),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(e.classLabel ?? e.classId),
                        Text(e.type.displayName),
                        Text(
                          '${formatDateKey(e.startDateKey)} – '
                          '${formatDateKey(e.endDateKey)}',
                        ),
                        ExamStatusPill(e.status),
                        Text(
                          '${e.subjectCount} subject'
                          '${e.subjectCount == 1 ? '' : 's'}',
                        ),
                      ],
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(
                    AppRoutes.examDetail.replaceFirst(':examId', e.examId),
                  ),
                ),
              ),
            if (_controller.hasMore)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: _controller.isLoading
                      ? const CircularProgressIndicator()
                      : OutlinedButton(
                          onPressed: _controller.loadMore,
                          child: const Text('Load more'),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
