import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../../../shared/layouts/status_chips.dart';
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
import '../widgets/directory_list.dart';
import '../widgets/staff_hero.dart';
import '../widgets/staff_login_access.dart';
import '../widgets/staff_toolbar.dart';

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
      // The branch choice lives in the compact hero instead.
      showBranchRow: false,
      builder: (context, tenant, schoolId, branchId) => _TeachersList(
        schoolId: schoolId,
        branchId: branchId,
        canManage: tenant.can(Permission.manageStaff),
      ),
    );
  }
}

class _TeachersList extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final bool canManage;

  const _TeachersList({
    required this.schoolId,
    required this.branchId,
    required this.canManage,
  });

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

  Widget _hero(ScreenSize layout) => StaffHero(
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    layout: layout,
    title: 'Teaching staff',
    subtitle: 'Who teaches what, and where',
    icon: Icons.co_present_outlined,
  );

  Future<void> _manageAccess(Staff staff) async {
    final changed = await openStaffLoginAccess(
      context,
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      staff: staff,
    );
    if (changed && mounted) _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final yearsAsync = ref.watch(academicYearsProvider(branchKey));
    // One layout decision for the whole screen, from the window width — the
    // same input the navigation shell uses, so the two always agree.
    final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);

    // The header stays while the page loads, fails, or has no year yet.
    Widget framed(Widget child) => DirectoryFrame(
      padding: DirectoryLayout.pagePadding(layout),
      child: Column(
        children: [
          _hero(layout),
          SizedBox(height: DirectoryLayout.sectionGap(layout)),
          Expanded(child: child),
        ],
      ),
    );

    return yearsAsync.when(
      loading: () => framed(const Center(child: CircularProgressIndicator())),
      error: (error, _) => framed(
        ErrorView(
          message: userMessageFor(error),
          onRetry: () => ref.invalidate(academicYearsProvider(branchKey)),
        ),
      ),
      data: (years) {
        if (years.isEmpty) {
          return framed(
            const EmptyView(
              icon: Icons.event_outlined,
              message:
                  'Create an academic year in Settings before viewing teachers.',
            ),
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
        return _buildBody(context, years, layout);
      },
    );
  }

  /// The headcount behind the current list, when the page knows it: only for
  /// the plain status list (a search or assignment filter changes what is
  /// counted, and nothing is invented).
  int? _totalFor(StaffCounts? counts) {
    if (counts == null || _hasAssignmentFilter || _isSearching) return null;
    return switch (_status) {
      null => counts.total,
      StaffStatus.active => counts.active,
      StaffStatus.onNotice => counts.onNotice,
      StaffStatus.inactive => counts.inactive,
      _ => null,
    };
  }

  Widget _buildBody(
    BuildContext context,
    List<AcademicYear> years,
    ScreenSize layout,
  ) {
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

    /// Distinct names, sorted; null when there are none (a teacher without a
    /// class is genuinely empty, whereas '…' marks names still loading).
    String? list(Iterable<String> values) {
      final distinct = values.toSet().toList()..sort();
      return distinct.isEmpty ? null : distinct.join(', ');
    }

    String? subjectsOf(_TeacherRow r) => list(
      r.active
          .where((a) => !a.isClassTeacher)
          .map((a) => names?.subjectName(a.subjectId) ?? '…'),
    );
    String? classesOf(_TeacherRow r) => list(
      r.active.map((a) => names?.classSection(a.classId, a.sectionId) ?? '…'),
    );
    String? classTeacherOf(_TeacherRow r) => list(
      r.active
          .where((a) => a.isClassTeacher)
          .map((a) => names?.classSection(a.classId, a.sectionId) ?? '…'),
    );

    final gap = SizedBox(height: DirectoryLayout.sectionGap(layout));
    return DirectoryFrame(
      padding: DirectoryLayout.pagePadding(layout),
      // Every row is built (a page holds at most a few dozen), so layout and
      // finders never depend on what has scrolled into view.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _hero(layout),
            gap,
            StaffToolbar(
              layout: layout,
              switcher: const StaffSectionSwitcher(
                current: StaffSection.teachers,
              ),
              trailing: PageActionsMenu(
                actions: staffBulkPageActions(
                  context,
                  ref,
                  schoolId: widget.schoolId,
                  branchId: widget.branchId,
                  teachers: true,
                ),
              ),
              searchController: _searchController,
              searchHint: 'Search teachers by name',
              onSearchChanged: _onSearchChanged,
              searchEnabled: !_hasAssignmentFilter,
              fieldsBuilder: () => _filters(years),
              note: _hasAssignmentFilter
                  ? 'Showing teachers with active assignments matching the class / section / subject. Search and status are paused.'
                  : null,
            ),
            gap,
            StatusChips(
              chips: _statChips(counts),
              activeFilters: _filters(years),
              layout: layout,
            ),
            gap,
            ListenableBuilder(
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
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return DirectoryListCard(
                  layout: layout,
                  nameHeader: 'Teacher',
                  codeHeader: 'ID',
                  columns: const [
                    DirectoryColumn(header: 'Classes', flex: 3),
                    DirectoryColumn(
                      header: 'Subjects',
                      flex: 3,
                      showAtWidth: 700,
                    ),
                    DirectoryColumn(
                      header: 'Class teacher',
                      flex: 2,
                      showAtWidth: 900,
                    ),
                  ],
                  emptyState: const EmptyView(
                    icon: Icons.school_outlined,
                    message: 'No teachers found.',
                  ),
                  items: [
                    for (final row in _controller.items)
                      DirectoryRow(
                        id: row.staff.staffId,
                        name: row.staff.displayName,
                        code: row.staff.employeeCode,
                        values: [
                          classesOf(row),
                          subjectsOf(row),
                          classTeacherOf(row),
                        ],
                        phoneLine: [
                          classesOf(row),
                          subjectsOf(row),
                          if (classTeacherOf(row) != null)
                            'Class teacher: ${classTeacherOf(row)}',
                        ].whereType<String>().join(' · '),
                        status: row.staff.status,
                        onTap: () =>
                            context.push('/staff/${row.staff.staffId}'),
                        actions: [
                          if (widget.canManage)
                            LoginAccessButton(
                              onPressed: () => _manageAccess(row.staff),
                            ),
                        ],
                      ),
                  ],
                  total: _totalFor(counts),
                  hasMore: _controller.hasMore,
                  isLoading: _controller.isLoading,
                  onLoadMore: _controller.loadMore,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
