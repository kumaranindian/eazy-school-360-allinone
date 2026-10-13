import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/layouts/scrollable_header.dart';
import '../../../academic_setup/domain/school_class.dart';
import '../../../academic_setup/domain/section.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_type.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_repositories.dart';
import '../providers/leave_providers.dart';
import '../widgets/leave_scope.dart';
import '../widgets/leave_widgets.dart';

/// `/leave/applications` — the queue and the full list, for reviewers.
/// `?kind=STAFF` and `?status=PENDING` preselect (the dashboard links here).
/// Cursor-paginated, newest first; filters are server-side queries, so a
/// branch with thousands of applications never loads them all.
class LeaveApplicationsPage extends StatelessWidget {
  final LeaveKind initialKind;
  final LeaveStatus? initialStatus;

  const LeaveApplicationsPage({
    super.key,
    this.initialKind = LeaveKind.student,
    this.initialStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leave applications')),
      body: LeaveScope(
        builder: (context, leave) => _Applications(
          leave: leave,
          initialKind: initialKind,
          initialStatus: initialStatus,
        ),
      ),
    );
  }
}

class _Applications extends ConsumerStatefulWidget {
  final LeaveContext leave;
  final LeaveKind initialKind;
  final LeaveStatus? initialStatus;

  const _Applications({
    required this.leave,
    required this.initialKind,
    required this.initialStatus,
  });

  @override
  ConsumerState<_Applications> createState() => _ApplicationsState();
}

class _ApplicationsState extends ConsumerState<_Applications> {
  final _controller = PagedListController<LeaveApplication>();
  late LeaveKind _kind = widget.initialKind;
  LeaveStatus? _status;
  String? _typeId;
  String? _classId;
  String? _sectionId;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    _apply();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final repo = ref.read(leaveApplicationRepositoryProvider);
    final leave = widget.leave;
    _controller.fetch = (cursor) => repo.fetch(
      schoolId: leave.schoolId,
      branchId: leave.branchId,
      filter: LeaveFilter(
        kind: _kind,
        status: _status,
        typeId: _typeId,
        classId: _classId,
        sectionId: _sectionId,
      ),
      cursor: cursor,
    );
    _controller.reload();
  }

  void _set(VoidCallback change) {
    setState(change);
    _apply();
  }

  List<FilterField> _filters(
    List<LeaveType> types,
    List<SchoolClass> classes,
    List<Section> sections,
  ) => [
    FilterField.dropdown<LeaveStatus>(
      label: 'Status',
      value: _status,
      options: [
        (null, 'All'),
        for (final s in LeaveStatus.values) (s, s.displayName),
      ],
      onChanged: (v) => _set(() => _status = v),
    ),
    FilterField.dropdown<String>(
      label: 'Leave type',
      value: types.any((t) => t.typeId == _typeId) ? _typeId : null,
      options: [(null, 'All'), for (final t in types) (t.typeId, t.name)],
      onChanged: (v) => _set(() => _typeId = v),
    ),
    if (_kind == LeaveKind.student) ...[
      FilterField.dropdown<String>(
        label: 'Class',
        value: classes.any((c) => c.classId == _classId) ? _classId : null,
        options: [(null, 'All'), for (final c in classes) (c.classId, c.name)],
        onChanged: (v) => _set(() {
          _classId = v;
          _sectionId = null;
        }),
      ),
      if (_classId != null)
        FilterField.dropdown<String>(
          label: 'Section',
          value: sections.any((s) => s.sectionId == _sectionId)
              ? _sectionId
              : null,
          options: [
            (null, 'All'),
            for (final s in sections) (s.sectionId, s.name),
          ],
          onChanged: (v) => _set(() => _sectionId = v),
        ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final leave = widget.leave;
    final types =
        ref
            .watch(
              leaveTypesProvider((
                schoolId: leave.schoolId,
                branchId: leave.branchId,
                kind: _kind,
              )),
            )
            .value ??
        const [];
    final List<SchoolClass> classes = _kind == LeaveKind.student
        ? ref.watch(classesProvider(leave.yearKey)).value ?? const []
        : const [];
    final List<Section> sections =
        (_kind == LeaveKind.student && _classId != null)
        ? ref
                  .watch(
                    sectionsProvider((
                      schoolId: leave.schoolId,
                      branchId: leave.branchId,
                      academicYearId: leave.year.academicYearId,
                      classId: _classId!,
                    )),
                  )
                  .value ??
              const []
        : const [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton:
          leave.tenant.can(Permission.reviewLeave) && _kind == LeaveKind.student
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/leave/apply'),
              icon: const Icon(Icons.add),
              label: const Text('Apply on behalf'),
            )
          : null,
      body: Column(
        children: [
          ScrollableHeader(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<LeaveKind>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: LeaveKind.student,
                        label: Text('Students'),
                        icon: Icon(Icons.groups_outlined),
                      ),
                      ButtonSegment(
                        value: LeaveKind.staff,
                        label: Text('Staff'),
                        icon: Icon(Icons.badge_outlined),
                      ),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (s) => _set(() {
                      _kind = s.first;
                      _typeId = null;
                      _classId = null;
                      _sectionId = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilterBar(
                    fieldsBuilder: () => _filters(types, classes, sections),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (_controller.errorMessage != null &&
                    _controller.items.isEmpty) {
                  return ErrorView(
                    message: _controller.errorMessage!,
                    onRetry: _controller.reload,
                  );
                }
                if (!_controller.hasLoaded) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_controller.items.isEmpty) {
                  return const EmptyView(
                    icon: Icons.event_available_outlined,
                    message: 'No leave applications match these filters.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  itemCount: _controller.items.length + 1,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    if (index == _controller.items.length) {
                      return _controller.hasMore
                          ? Center(
                              child: _controller.isLoading
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: _controller.loadMore,
                                      child: const Text('Load more'),
                                    ),
                            )
                          : const SizedBox.shrink();
                    }
                    final a = _controller.items[index];
                    return LeaveApplicationTile(
                      application: a,
                      onTap: () =>
                          context.go('/leave/applications/${a.applicationId}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
