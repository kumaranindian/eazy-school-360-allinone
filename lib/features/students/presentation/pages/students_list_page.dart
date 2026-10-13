import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/layouts/scrollable_header.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/paged_result.dart';
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

  List<Student> _items = [];
  Object? _cursor;
  bool _hasMore = false;
  bool _isLoading = false;
  bool _loadedOnce = false;
  String? _schoolId;
  String? _branchId;

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  Future<void> _resetAndLoad(String schoolId, String branchId) async {
    setState(() {
      _schoolId = schoolId;
      _branchId = branchId;
      _items = [];
      _cursor = null;
      _hasMore = false;
      _isLoading = true;
      _loadedOnce = true;
    });
    await _loadPage(schoolId, branchId, reset: true);
  }

  Future<void> _loadPage(
    String schoolId,
    String branchId, {
    bool reset = false,
  }) async {
    final repository = ref.read(studentRepositoryProvider);
    PagedResult<Student> page;
    final query = _searchController.text.trim();

    if (query.isNotEmpty && _searchBy == _SearchBy.name) {
      page = await repository.searchStudentsByName(
        schoolId: schoolId,
        branchId: branchId,
        query: query,
        cursor: reset ? null : _cursor,
      );
    } else if (query.isNotEmpty) {
      page = await repository.searchStudentsByAdmissionNumber(
        schoolId: schoolId,
        branchId: branchId,
        query: query,
        cursor: reset ? null : _cursor,
      );
    } else {
      page = await repository.fetchStudents(
        schoolId: schoolId,
        branchId: branchId,
        status: _statusFilter,
        cursor: reset ? null : _cursor,
      );
    }

    if (!mounted) return;
    setState(() {
      _items = reset ? page.items : [..._items, ...page.items];
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      _isLoading = false;
    });
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
  void dispose() {
    _debounce?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

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
          body: Column(
            children: [
              ScrollableHeader(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: StatChipsBar(chips: _statChips(counts)),
                          ),
                          PageActionsMenu(
                            actions: [
                              if (canManage)
                                PageAction(
                                  label: 'Bulk upload (CSV)',
                                  icon: Icons.upload_file_outlined,
                                  onSelected: () =>
                                      context.push('/students/import'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilterBar(
                        searchController: _searchController,
                        searchHint: _searchBy == _SearchBy.name
                            ? 'Search by name'
                            : 'Search by admission number',
                        onSearchChanged: _onSearchChanged,
                        searchPrefix: _searchByMenu(),
                        filtersEnabled: !_isSearching,
                        fieldsBuilder: _filters,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _isLoading && _items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ResponsiveDataList<Student>(
                        items: _items,
                        columnHeaders: const [
                          'Admission No',
                          'Student',
                          'Class',
                          'Status',
                          '',
                        ],
                        emptyState: const EmptyView(
                          icon: Icons.groups_outlined,
                          message: 'No students match your filters.',
                        ),
                        cellsBuilder: (student) => [
                          DataCell(Text(student.admissionNumber)),
                          DataCell(Text(student.displayName)),
                          DataCell(StudentPlacementLabel(student: student)),
                          DataCell(_StatusChip(status: student.status)),
                          DataCell(
                            TextButton(
                              onPressed: () => context.push(
                                '/students/${student.studentId}',
                              ),
                              child: const Text('View'),
                            ),
                          ),
                        ],
                        cardBuilder: (student) => Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(student.displayName),
                            subtitle: Text(student.admissionNumber),
                            trailing: _StatusChip(status: student.status),
                            onTap: () =>
                                context.push('/students/${student.studentId}'),
                          ),
                        ),
                      ),
              ),
              if (_hasMore)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _loadPage(_schoolId!, _branchId!),
                    child: _isLoading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load more'),
                  ),
                ),
            ],
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
