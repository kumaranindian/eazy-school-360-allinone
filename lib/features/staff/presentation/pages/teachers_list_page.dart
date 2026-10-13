import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/layouts/scrollable_header.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../students/domain/paged_result.dart';
import '../../domain/staff.dart';
import '../../domain/staff_search_field.dart';
import '../../domain/staff_status.dart';
import '../../domain/teacher_assignment.dart';
import '../providers/academic_names_provider.dart';
import '../providers/staff_providers.dart';
import '../widgets/staff_branch_scope.dart';
import '../widgets/staff_bulk_actions.dart';
import '../widgets/staff_section_switcher.dart';
import '../widgets/staff_status_chip.dart';

/// One teacher plus their assignments in the selected academic year.
class _TeacherRow {
  final Staff staff;
  final List<TeacherAssignment> assignments;

  const _TeacherRow(this.staff, this.assignments);

  Iterable<TeacherAssignment> get active =>
      assignments.where((a) => a.isActive);
}

/// The teacher-focused view: staff with teaching responsibility and what
/// they teach in an academic year. Without a class/section/subject filter
/// it pages through teachers (optionally by status or name); with one it
/// pages through the year's matching *assignments* and resolves their
/// teachers. Either way each page is bounded.
class TeachersListPage extends StatelessWidget {
  const TeachersListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      builder: (context, tenant, schoolId, branchId) =>
          _TeachersList(schoolId: schoolId, branchId: branchId),
    );
  }
}

class _TeachersList extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;

  const _TeachersList({required this.schoolId, required this.branchId});

  @override
  ConsumerState<_TeachersList> createState() => _TeachersListState();
}

class _TeachersListState extends ConsumerState<_TeachersList> {
  final _controller = PagedListController<_TeacherRow>();
  final _searchController = TextEditingController();
  final _seenStaffIds = <String>{};
  Timer? _debounce;

  String? _yearId;
  String? _classId;
  String? _sectionId;
  String? _subjectId;
  StaffStatus? _status = StaffStatus.active;

  bool get _isSearching => _searchController.text.trim().isNotEmpty;
  bool get _hasAssignmentFilter =>
      _classId != null || _sectionId != null || _subjectId != null;

  /// Search and the status filter apply to the teacher list; an assignment
  /// filter takes over from both (it lists the year's matching assignments).
  void _applyQuery() {
    final yearId = _yearId;
    if (yearId == null) return;
    final staffRepository = ref.read(staffRepositoryProvider);
    final assignmentRepository = ref.read(teacherAssignmentRepositoryProvider);
    _seenStaffIds.clear();

    Future<List<_TeacherRow>> withAssignments(List<Staff> staff) async {
      if (staff.isEmpty) return const [];
      final assignments = await assignmentRepository
          .fetchAssignmentsForTeachers(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: yearId,
            teacherStaffIds: staff.map((s) => s.staffId).toList(),
          );
      return [
        for (final s in staff)
          _TeacherRow(
            s,
            assignments.where((a) => a.teacherStaffId == s.staffId).toList(),
          ),
      ];
    }

    if (_hasAssignmentFilter) {
      _controller.fetch = (cursor) async {
        final page = await assignmentRepository.fetchActiveAssignments(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          academicYearId: yearId,
          classId: _classId,
          sectionId: _sectionId,
          subjectId: _subjectId,
          cursor: cursor,
        );
        final newIds = page.items
            .map((a) => a.teacherStaffId)
            .toSet()
            .difference(_seenStaffIds)
            .toList();
        _seenStaffIds.addAll(newIds);
        final staff = await staffRepository.getStaffByIds(
          widget.schoolId,
          widget.branchId,
          newIds,
        );
        return PagedResult(
          items: await withAssignments(staff),
          nextCursor: page.nextCursor,
        );
      };
    } else {
      final term = _searchController.text.trim();
      _controller.fetch = (cursor) async {
        final page = _isSearching
            ? await staffRepository.searchStaff(
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                field: StaffSearchField.name,
                query: term,
                isTeacher: true,
                cursor: cursor,
              )
            : await staffRepository.fetchStaff(
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                isTeacher: true,
                status: _status,
                cursor: cursor,
              );
        return PagedResult(
          items: await withAssignments(page.items),
          nextCursor: page.nextCursor,
        );
      };
    }
    _controller.reload();
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _applyQuery();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        setState(() {});
        _applyQuery();
      }
    });
  }

  /// Headline headcounts that double as quick status filters; inert while an
  /// assignment filter or a search has taken over the query.
  List<StatChip> _statChips(StaffCounts? counts) {
    final paused = _hasAssignmentFilter || _isSearching;
    StatChip chip(String label, int? count, StaffStatus? status) => StatChip(
      label: label,
      count: count,
      selected: !paused && _status == status,
      onTap: paused ? null : () => _setFilter(() => _status = status),
    );
    return [
      chip('All', counts?.total, null),
      chip('Active', counts?.active, StaffStatus.active),
      chip('On notice', counts?.onNotice, StaffStatus.onNotice),
      chip('Inactive', counts?.inactive, StaffStatus.inactive),
    ];
  }

  /// Built on demand, from the page's current state, because the filter sheet
  /// asks again after every change (e.g. new class options once the year
  /// changes).
  List<FilterField> _filters(List<AcademicYear> years) {
    final yearId = _yearId;
    final classes = yearId == null
        ? const []
        : (ref
                  .read(
                    classesProvider((
                      schoolId: widget.schoolId,
                      branchId: widget.branchId,
                      academicYearId: yearId,
                    )),
                  )
                  .value ??
              const []);
    final classKey = (yearId == null || _classId == null)
        ? null
        : (
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            academicYearId: yearId,
            classId: _classId!,
          );
    final sections = classKey == null
        ? const []
        : (ref.read(sectionsProvider(classKey)).value ?? const []);
    final subjectOptions = yearId == null
        ? const <({String id, String name})>[]
        : classKey == null
        ? (ref
                      .read(
                        subjectsProvider((
                          schoolId: widget.schoolId,
                          branchId: widget.branchId,
                          academicYearId: yearId,
                        )),
                      )
                      .value ??
                  const [])
              .map((s) => (id: s.subjectId, name: s.name))
              .toList()
        : (ref.read(classSubjectsProvider(classKey)).value ?? const [])
              .map((s) => (id: s.subjectId, name: s.subjectName))
              .toList();

    return [
      FilterField.dropdown<String>(
        label: 'Academic year',
        value: _yearId,
        countsAsFilter: false,
        options: [for (final y in years) (y.academicYearId, y.name)],
        onChanged: (v) => _setFilter(() {
          _yearId = v ?? _yearId;
          _classId = null;
          _sectionId = null;
          _subjectId = null;
        }),
      ),
      FilterField.dropdown<String>(
        label: 'Class',
        value: _classId,
        options: [
          (null, 'All classes'),
          for (final c in classes) (c.classId, c.name),
        ],
        onChanged: (v) => _setFilter(() {
          _classId = v;
          _sectionId = null;
          _subjectId = null;
        }),
      ),
      FilterField.dropdown<String>(
        label: 'Section',
        value: sections.any((s) => s.sectionId == _sectionId)
            ? _sectionId
            : null,
        options: [
          (null, 'All sections'),
          for (final s in sections) (s.sectionId, s.name),
        ],
        onChanged: _classId == null
            ? null
            : (v) => _setFilter(() => _sectionId = v),
      ),
      FilterField.dropdown<String>(
        label: 'Subject',
        value: subjectOptions.any((s) => s.id == _subjectId)
            ? _subjectId
            : null,
        options: [
          (null, 'All subjects'),
          for (final s in subjectOptions) (s.id, s.name),
        ],
        onChanged: (v) => _setFilter(() => _subjectId = v),
      ),
      FilterField.dropdown<StaffStatus>(
        label: 'Status',
        value: _status,
        options: [
          (null, 'All statuses'),
          for (final s in StaffStatus.values) (s, s.displayName),
        ],
        onChanged: (_hasAssignmentFilter || _isSearching)
            ? null
            : (v) => _setFilter(() => _status = v),
      ),
    ];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final yearsAsync = ref.watch(academicYearsProvider(branchKey));

    return yearsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(
        message: userMessageFor(error),
        onRetry: () => ref.invalidate(academicYearsProvider(branchKey)),
      ),
      data: (years) {
        if (years.isEmpty) {
          return const EmptyView(
            icon: Icons.event_outlined,
            message:
                'Create an academic year in Settings before viewing teachers.',
          );
        }
        if (_yearId == null || !years.any((y) => y.academicYearId == _yearId)) {
          final initial = years.firstWhere(
            (y) => y.status == AcademicYearStatus.active,
            orElse: () => years.first,
          );
          _yearId = initial.academicYearId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _applyQuery();
          });
        }
        return _buildBody(context, years);
      },
    );
  }

  Widget _buildBody(BuildContext context, List<AcademicYear> years) {
    final yearKey = (
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      academicYearId: _yearId!,
    );
    // Watched so this page rebuilds when the class / section / subject lists
    // load; [_filters] reads the same providers for the filter controls.
    ref.watch(classesProvider(yearKey));
    if (_classId != null) {
      final classKey = (
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        academicYearId: _yearId!,
        classId: _classId!,
      );
      ref.watch(sectionsProvider(classKey));
      ref.watch(classSubjectsProvider(classKey));
    } else {
      ref.watch(subjectsProvider(yearKey));
    }
    final names = ref.watch(academicNamesProvider(yearKey)).value;
    final counts = ref
        .watch(
          staffCountsProvider((
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            teachersOnly: true,
          )),
        )
        .value;

    String list(Iterable<String> values) {
      final distinct = values.toSet().toList()..sort();
      return distinct.isEmpty ? '—' : distinct.join(', ');
    }

    String subjectsOf(_TeacherRow r) => list(
      r.active
          .where((a) => !a.isClassTeacher)
          .map((a) => names?.subjectName(a.subjectId) ?? '…'),
    );
    String classesOf(_TeacherRow r) => list(
      r.active.map((a) => names?.classSection(a.classId, a.sectionId) ?? '…'),
    );
    String classTeacherOf(_TeacherRow r) => list(
      r.active
          .where((a) => a.isClassTeacher)
          .map((a) => names?.classSection(a.classId, a.sectionId) ?? '…'),
    );

    return Column(
      children: [
        ScrollableHeader(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(
                      child: StaffSectionSwitcher(
                        current: StaffSection.teachers,
                      ),
                    ),
                    PageActionsMenu(
                      actions: staffBulkPageActions(
                        context,
                        ref,
                        schoolId: widget.schoolId,
                        branchId: widget.branchId,
                        teachers: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                StatChipsBar(chips: _statChips(counts)),
                const SizedBox(height: AppSpacing.sm),
                FilterBar(
                  searchController: _searchController,
                  searchHint: 'Search teachers by name',
                  onSearchChanged: _onSearchChanged,
                  searchEnabled: !_hasAssignmentFilter,
                  fieldsBuilder: () => _filters(years),
                  note: _hasAssignmentFilter
                      ? 'Showing teachers with active assignments matching the class / section / subject. Search and status are paused.'
                      : null,
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
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveDataList<_TeacherRow>(
                      items: _controller.items,
                      columnHeaders: const [
                        'Teacher',
                        'Employee Code',
                        'Subjects',
                        'Classes',
                        'Class Teacher',
                        'Status',
                      ],
                      emptyState: const EmptyView(
                        icon: Icons.school_outlined,
                        message: 'No teachers found.',
                      ),
                      cellsBuilder: (row) => [
                        DataCell(
                          TextButton(
                            onPressed: () =>
                                context.push('/staff/${row.staff.staffId}'),
                            child: Text(row.staff.displayName),
                          ),
                        ),
                        DataCell(Text(row.staff.employeeCode)),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              subjectsOf(row),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              classesOf(row),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text(classTeacherOf(row))),
                        DataCell(StaffStatusChip(status: row.staff.status)),
                      ],
                      cardBuilder: (row) => Card(
                        child: ListTile(
                          isThreeLine: true,
                          title: Text(row.staff.displayName),
                          subtitle: Text(
                            '${row.staff.employeeCode}\nSubjects: ${subjectsOf(row)}\nClasses: ${classesOf(row)}'
                            '${classTeacherOf(row) == '—' ? '' : '\nClass teacher: ${classTeacherOf(row)}'}',
                          ),
                          trailing: StaffStatusChip(status: row.staff.status),
                          onTap: () =>
                              context.push('/staff/${row.staff.staffId}'),
                        ),
                      ),
                    ),
                  ),
                  if (_controller.hasMore)
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: OutlinedButton(
                        onPressed: _controller.isLoading
                            ? null
                            : _controller.loadMore,
                        child: _controller.isLoading
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Load more'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
