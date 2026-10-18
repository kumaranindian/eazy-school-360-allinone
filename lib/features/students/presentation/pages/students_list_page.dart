import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/filters/directory_toolbar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/directory_list.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../../../shared/layouts/status_chips.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/student_providers.dart';
import '../widgets/student_placement_label.dart';

enum _SearchBy {
  name('Name'),
  admissionNumber('Admission #');

  final String label;
  const _SearchBy(this.label);
}

/// The student roster (brief §15-16): desktop table / mobile cards,
/// status filter, name/admission-number search, and cursor pagination —
/// never an unbounded fetch of the whole collection.
class StudentsListPage extends ConsumerStatefulWidget {
  const StudentsListPage({super.key});

  @override
  ConsumerState<StudentsListPage> createState() => _StudentsListPageState();
}

class _StudentsListPageState extends ConsumerState<StudentsListPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  _SearchBy _searchBy = _SearchBy.name;
  StudentStatus? _statusFilter = StudentStatus.active;

  final _controller = PagedListController<Student>();
  bool _loadedOnce = false;
  String? _schoolId;
  String? _branchId;

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  /// Rebuilds the fetch closure from the current search/filters and loads page
  /// one. The shared controller drops a response that arrives after a newer
  /// query started and never runs two page loads at once (STATE-1).
  void _resetAndLoad(String schoolId, String branchId) {
    _schoolId = schoolId;
    _branchId = branchId;
    _loadedOnce = true;
    final repository = ref.read(studentRepositoryProvider);
    final query = _searchController.text.trim();
    final status = _statusFilter;
    final by = _searchBy;
    _controller.fetch = (cursor) {
      if (query.isNotEmpty && by == _SearchBy.name) {
        return repository.searchStudentsByName(
          schoolId: schoolId,
          branchId: branchId,
          query: query,
          cursor: cursor,
        );
      }
      if (query.isNotEmpty) {
        return repository.searchStudentsByAdmissionNumber(
          schoolId: schoolId,
          branchId: branchId,
          query: query,
          cursor: cursor,
        );
      }
      return repository.fetchStudents(
        schoolId: schoolId,
        branchId: branchId,
        status: status,
        cursor: cursor,
      );
    };
    _controller.reload();
  }

  void _reload() {
    if (_schoolId != null && _branchId != null) {
      _resetAndLoad(_schoolId!, _branchId!);
    }
  }

  /// One query per pause in typing, not one per keystroke.
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _reload();
    });
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Headline headcounts that double as quick status filters; inert while a
  /// search is running (search ignores the status filter).
  List<StatChip> _statChips(Map<StudentStatus?, int>? counts) {
    StatChip chip(String label, StudentStatus? status) => StatChip(
      label: label,
      count: counts?[status],
      selected: !_isSearching && _statusFilter == status,
      onTap: _isSearching
          ? null
          : () {
              setState(() => _statusFilter = status);
              _reload();
            },
    );
    return [
      chip('All', null),
      for (final s in StudentStatus.values) chip(s.displayName, s),
    ];
  }

  List<FilterField> _filters() => [
    FilterField.dropdown<StudentStatus>(
      label: 'Status',
      value: _statusFilter,
      options: [
        (null, 'All statuses'),
        for (final s in StudentStatus.values) (s, s.displayName),
      ],
      onChanged: (value) {
        setState(() => _statusFilter = value);
        _reload();
      },
    ),
  ];

  /// "Search by: Name ▾" at the start of the search box.
  Widget _searchByMenu() => PopupMenuButton<_SearchBy>(
    // Icon only: the hint text names the field being searched, so the label
    // does not also have to fit inside a 320px search box.
    tooltip: 'Search by',
    initialValue: _searchBy,
    onSelected: (value) {
      setState(() => _searchBy = value);
      if (_isSearching) _reload();
    },
    itemBuilder: (context) => [
      for (final by in _SearchBy.values)
        PopupMenuItem(value: by, child: Text(by.label)),
    ],
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [const Icon(Icons.search), const Icon(Icons.arrow_drop_down)],
      ),
    ),
  );

  /// The headcount behind the list, when it is the plain status list; a
  /// search changes what is counted, so no total is claimed then.
  int? _totalFor(Map<StudentStatus?, int>? counts) =>
      _isSearching ? null : counts?[_statusFilter];

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.groups_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageStudentData);
        final counts = ref
            .watch(
              studentCountsProvider((schoolId: schoolId, branchId: branchId)),
            )
            .value;

        if (!_loadedOnce || _schoolId != schoolId || _branchId != branchId) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _resetAndLoad(schoolId, branchId),
          );
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => context.push('/students/new'),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Admit student'),
                )
              : null,
          body: DirectoryFrame(
            padding: DirectoryLayout.pagePadding(layout),
            // The shell's hero is directly above: keep the gap to it the same
            // as the gaps between sections.
            top: DirectoryLayout.sectionGap(layout),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DirectoryToolbar(
                    layout: layout,
                    trailing: PageActionsMenu(
                      actions: [
                        if (canManage)
                          PageAction(
                            label: 'Bulk upload (CSV)',
                            icon: Icons.upload_file_outlined,
                            onSelected: () => context.push('/students/import'),
                          ),
                      ],
                    ),
                    searchController: _searchController,
                    searchHint: _searchBy == _SearchBy.name
                        ? 'Search by name'
                        : 'Search by admission number',
                    searchPrefix: _searchByMenu(),
                    onSearchChanged: _onSearchChanged,
                    filtersEnabled: !_isSearching,
                    fieldsBuilder: _filters,
                    inlineCount: 1,
                  ),
                  SizedBox(height: DirectoryLayout.sectionGap(layout)),
                  StatusChips(
                    chips: _statChips(counts),
                    activeFilters: _isSearching ? const [] : _filters(),
                    layout: layout,
                  ),
                  SizedBox(height: DirectoryLayout.sectionGap(layout)),
                  if (_controller.errorMessage != null &&
                      _controller.items.isEmpty)
                    ErrorView(
                      message: _controller.errorMessage!,
                      onRetry: _controller.reload,
                    )
                  else if (!_controller.hasLoaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    DirectoryListCard(
                      layout: layout,
                      nameHeader: 'Student',
                      codeHeader: 'Admission no',
                      columns: const [
                        DirectoryColumn(header: 'Class', flex: 3),
                      ],
                      emptyState: const EmptyView(
                        icon: Icons.groups_outlined,
                        message: 'No students match your filters.',
                      ),
                      items: [
                        for (final student in _controller.items)
                          DirectoryRow(
                            id: student.studentId,
                            name: student.displayName,
                            code: student.admissionNumber,
                            values: const [null],
                            cells: [StudentPlacementLabel(student: student)],
                            phoneLine: null,
                            phoneDetail: StudentPlacementLabel(
                              student: student,
                            ),
                            statusBadge: _StatusChip(status: student.status),
                            onTap: () =>
                                context.push('/students/${student.studentId}'),
                          ),
                      ],
                      total: _totalFor(counts),
                      hasMore: _controller.hasMore,
                      isLoading: _controller.isLoading,
                      onLoadMore: _controller.loadMore,
                      errorText: _controller.errorMessage,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final StudentStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) => HubBadge(
    label: status.displayName,
    tone: switch (status) {
      StudentStatus.active => HubBadgeTone.success,
      StudentStatus.inactive => HubBadgeTone.neutral,
      _ => HubBadgeTone.warning,
    },
  );
}
