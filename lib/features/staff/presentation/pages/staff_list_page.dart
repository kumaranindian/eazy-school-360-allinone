import '../../../users/presentation/widgets/login_access_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/providers/login_access_providers.dart';
import '../../../users/presentation/widgets/login_selection_bar.dart';
import '../../../users/presentation/widgets/provision_logins_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../domain/department.dart';
import '../../domain/designation.dart';
import '../../domain/employment_type.dart';
import '../../domain/staff.dart';
import '../../domain/staff_search_field.dart';
import '../../domain/staff_status.dart';
import '../providers/staff_providers.dart';
import '../widgets/staff_status_chip.dart';
import '../widgets/staff_branch_scope.dart';
import '../widgets/staff_section_switcher.dart';
import '../../../../shared/layouts/directory_list.dart';
import '../widgets/staff_hero.dart';
import '../widgets/staff_login_access.dart';
import '../../../../shared/filters/directory_toolbar.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/stat_chips.dart';
import '../../../../shared/layouts/status_chips.dart';
import '../staff_export_action.dart';

/// The staff directory: desktop table / mobile cards, search by name,
/// employee code, phone or email, filters for status / department /
/// designation / employment type, and cursor pagination — never an
/// unbounded fetch of the collection.
class StaffListPage extends StatelessWidget {
  const StaffListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
      // The branch choice lives in the compact hero instead.
      showBranchRow: false,
      builder: (context, tenant, schoolId, branchId) => _StaffList(
        schoolId: schoolId,
        branchId: branchId,
        canManage: tenant.can(Permission.manageStaff),
        isSchoolAdmin: tenant.role == UserRole.schoolAdmin,
      ),
    );
  }
}

class _StaffList extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final bool canManage;
  final bool isSchoolAdmin;

  const _StaffList({
    required this.schoolId,
    required this.branchId,
    required this.canManage,
    required this.isSchoolAdmin,
  });

  @override
  ConsumerState<_StaffList> createState() => _StaffListState();
}

class _StaffListState extends ConsumerState<_StaffList> {
  final _controller = PagedListController<Staff>();
  final _searchController = TextEditingController();
  Timer? _debounce;

  StaffSearchField _searchField = StaffSearchField.name;
  StaffStatus? _status = StaffStatus.active;
  String? _departmentId;
  String? _designationId;
  EmploymentType? _employmentType;

  // Choosing people to give logins to (one or many).
  bool _selecting = false;
  final _selected = <String>{};

  Iterable<Staff> get _selectable =>
      _controller.items.where((s) => s.userId == null);

  /// Rebuilds the teachers' class-access index (used by the security rules).
  /// Normally automatic on every assignment change; this is the repair/backfill.
  Future<void> _refreshTeacherAccess() async {
    try {
      final r = await ref
          .read(loginAccessRepositoryProvider)
          .refreshTeacherAccess(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
          );
      if (!mounted) return;
      context.showSnackBar(
        'Teacher access refreshed (${r.written} of ${r.teachers} teachers).',
      );
    } catch (e) {
      if (mounted) context.showSnackBar(userMessageFor(e), isError: true);
    }
  }

  Future<void> _manageAccess(Staff s) async {
    final changed = await openStaffLoginAccess(
      context,
      schoolId: widget.schoolId,
      branchId: widget.branchId,
      staff: s,
    );
    if (changed && mounted) _controller.reload();
  }

  Future<void> _giveLogins() async {
    final chosen = _controller.items.where(
      (s) => _selected.contains(s.staffId),
    );
    final done = await showAdaptiveAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProvisionLoginsDialog(
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        kind: LoginKind.staff,
        canGrantBranchAdmin: widget.isSchoolAdmin,
        people: [
          for (final s in chosen)
            (id: s.staffId, name: s.displayName, email: s.email),
        ],
      ),
    );
    if (done == true && mounted) {
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      _controller.reload();
    }
  }

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _applyQuery();
  }

  /// Rebuilds the fetch closure from the current search/filters and loads
  /// page one. Search and the browse filters are mutually exclusive — see
  /// `StaffRepository.searchStaff`.
  void _applyQuery() {
    final repository = ref.read(staffRepositoryProvider);
    final term = _searchController.text.trim();
    _controller.fetch = _isSearching
        ? (cursor) => repository.searchStaff(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            field: _searchField,
            query: term,
            cursor: cursor,
          )
        : (cursor) => repository.fetchStaff(
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            status: _status,
            departmentId: _departmentId,
            designationId: _designationId,
            employmentType: _employmentType,
            cursor: cursor,
          );
    _controller.reload();
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

  void _setFilter(VoidCallback change) {
    setState(change);
    _applyQuery();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Secondary actions live in the page's "⋮" menu; the one primary action
  /// (Add staff) stays as the floating button.
  List<PageAction> _pageActions(BuildContext context) => [
    if (widget.canManage)
      PageAction(
        label: 'Import (CSV)',
        icon: Icons.upload_file_outlined,
        onSelected: () => context.push('/staff/import'),
      ),
    PageAction(
      label: 'Export (CSV)',
      icon: Icons.download_outlined,
      onSelected: () => exportStaffCsv(
        context,
        ref,
        schoolId: widget.schoolId,
        branchId: widget.branchId,
        teachersOnly: false,
      ),
    ),
    if (widget.canManage && !_selecting)
      PageAction(
        label: 'Give login access',
        icon: Icons.vpn_key_outlined,
        onSelected: () => setState(() => _selecting = true),
      ),
    if (widget.canManage)
      PageAction(
        label: 'Refresh teacher access',
        icon: Icons.sync_outlined,
        onSelected: _refreshTeacherAccess,
      ),
    PageAction(
      label: 'Departments',
      icon: Icons.account_tree_outlined,
      onSelected: () => context.push('/staff/departments'),
    ),
    PageAction(
      label: 'Designations',
      icon: Icons.badge_outlined,
      onSelected: () => context.push('/staff/designations'),
    ),
  ];

  /// Headline numbers that double as quick status filters. Searching pauses
  /// the filters, so the chips are inert (not selected) while it is on.
  List<StatChip> _statChips(StaffCounts? counts) {
    StatChip chip(String label, int? count, StaffStatus? status) => StatChip(
      label: label,
      count: count,
      selected: !_isSearching && _status == status,
      onTap: _isSearching ? null : () => _setFilter(() => _status = status),
    );
    return [
      chip('All', counts?.total, null),
      chip('Active', counts?.active, StaffStatus.active),
      chip('On notice', counts?.onNotice, StaffStatus.onNotice),
      chip('Inactive', counts?.inactive, StaffStatus.inactive),
    ];
  }

  /// "Search by: Name ▾" at the start of the search box.
  Widget _searchByMenu() => PopupMenuButton<StaffSearchField>(
    // Icon only: the hint text names the field being searched, so the label
    // does not also have to fit inside a 320px search box.
    tooltip: 'Search by',
    initialValue: _searchField,
    onSelected: (v) {
      setState(() => _searchField = v);
      if (_isSearching) _applyQuery();
    },
    itemBuilder: (context) => [
      for (final f in StaffSearchField.values)
        PopupMenuItem(value: f, child: Text(f.label)),
    ],
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [const Icon(Icons.search), const Icon(Icons.arrow_drop_down)],
      ),
    ),
  );

  List<FilterField> _filters(
    List<Department> departments,
    List<Designation> designations,
  ) => [
    FilterField.dropdown<StaffStatus>(
      label: 'Status',
      value: _status,
      options: [
        (null, 'All statuses'),
        for (final s in StaffStatus.values) (s, s.displayName),
      ],
      onChanged: (v) => _setFilter(() => _status = v),
    ),
    FilterField.dropdown<String>(
      label: 'Department',
      value: _departmentId,
      options: [
        (null, 'All departments'),
        for (final d in departments) (d.departmentId, d.name),
      ],
      onChanged: (v) => _setFilter(() => _departmentId = v),
    ),
    FilterField.dropdown<String>(
      label: 'Designation',
      value: _designationId,
      options: [
        (null, 'All designations'),
        for (final d in designations) (d.designationId, d.name),
      ],
      onChanged: (v) => _setFilter(() => _designationId = v),
    ),
    FilterField.dropdown<EmploymentType>(
      label: 'Employment type',
      value: _employmentType,
      options: [
        (null, 'All types'),
        for (final t in EmploymentType.values) (t, t.displayName),
      ],
      onChanged: (v) => _setFilter(() => _employmentType = v),
    ),
  ];

  /// The headcount behind the current list, when the page knows it: only for
  /// the plain status list (a search or a narrowing filter changes what is
  /// counted, and nothing is invented).
  int? _totalFor(StaffCounts? counts) {
    if (counts == null ||
        _isSearching ||
        _departmentId != null ||
        _designationId != null ||
        _employmentType != null) {
      return null;
    }
    return switch (_status) {
      null => counts.total,
      StaffStatus.active => counts.active,
      StaffStatus.onNotice => counts.onNotice,
      StaffStatus.inactive => counts.inactive,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final departments =
        ref.watch(departmentsProvider(branchKey)).value ?? const [];
    final designations =
        ref.watch(designationsProvider(branchKey)).value ?? const [];
    final counts = ref
        .watch(
          staffCountsProvider((
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            teachersOnly: false,
          )),
        )
        .value;
    final departmentNames = {
      for (final d in departments) d.departmentId: d.name,
    };
    final designationNames = {
      for (final d in designations) d.designationId: d.name,
    };
    // One layout decision for the whole screen, from the window width — the
    // same input the navigation shell uses, so the two always agree.
    final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);
    final gap = SizedBox(height: DirectoryLayout.sectionGap(layout));

    Widget? checkbox(Staff staff) => _selecting
        ? Checkbox(
            value: _selected.contains(staff.staffId),
            onChanged: staff.userId != null
                ? null
                : (v) => setState(
                    () => v == true
                        ? _selected.add(staff.staffId)
                        : _selected.remove(staff.staffId),
                  ),
          )
        : null;

    return Scaffold(
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/staff/new'),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add staff'),
            )
          : null,
      body: DirectoryFrame(
        padding: DirectoryLayout.pagePadding(layout),
        // Every row is built (a page holds at most a few dozen), so layout and
        // finders never depend on what has scrolled into view.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaffHero(
                schoolId: widget.schoolId,
                branchId: widget.branchId,
                layout: layout,
                title: 'Staff directory',
                subtitle: 'People, departments and designations',
                icon: Icons.badge_outlined,
              ),
              gap,
              DirectoryToolbar(
                layout: layout,
                switcher: const StaffSectionSwitcher(
                  current: StaffSection.staff,
                ),
                trailing: PageActionsMenu(actions: _pageActions(context)),
                searchController: _searchController,
                searchHint: 'Search ${_searchField.label.toLowerCase()}',
                searchPrefix: _searchByMenu(),
                onSearchChanged: _onSearchChanged,
                filtersEnabled: !_isSearching,
                fieldsBuilder: () => _filters(departments, designations),
              ),
              if (_selecting)
                Padding(
                  padding: EdgeInsets.only(
                    top: DirectoryLayout.sectionGap(layout),
                  ),
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => LoginSelectionBar(
                      selected: _selected.length,
                      selectable: _selectable.length,
                      onSelectAll: () => setState(
                        () =>
                            _selected.addAll(_selectable.map((s) => s.staffId)),
                      ),
                      onClear: () => setState(_selected.clear),
                      onCreate: _giveLogins,
                      onCancel: () => setState(() {
                        _selecting = false;
                        _selected.clear();
                      }),
                    ),
                  ),
                ),
              gap,
              StatusChips(
                chips: _statChips(counts),
                // Filters are paused while searching, as the bar always said.
                activeFilters: _isSearching
                    ? const []
                    : _filters(departments, designations),
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
                    nameHeader: 'Staff',
                    codeHeader: 'ID',
                    columns: const [
                      DirectoryColumn(header: 'Department', showAtWidth: 640),
                      DirectoryColumn(header: 'Designation', showAtWidth: 760),
                      DirectoryColumn(
                        header: 'Login',
                        flex: 2,
                        showAtWidth: 880,
                      ),
                      DirectoryColumn(
                        header: 'Phone',
                        flex: 2,
                        showAtWidth: 1000,
                      ),
                      DirectoryColumn(
                        header: 'Employment type',
                        flex: 2,
                        showAtWidth: 1120,
                      ),
                    ],
                    emptyState: const EmptyView(
                      icon: Icons.badge_outlined,
                      message: 'No staff found.',
                    ),
                    items: [
                      for (final staff in _controller.items)
                        DirectoryRow(
                          id: staff.staffId,
                          name: staff.displayName,
                          code: staff.employeeCode,
                          values: [
                            departmentNames[staff.departmentId],
                            designationNames[staff.designationId],
                            staff.userId != null ? 'Has login' : null,
                            staff.phone,
                            staff.employmentType.displayName,
                          ],
                          phoneLine: [
                            designationNames[staff.designationId],
                            if (staff.userId != null) 'Has login',
                          ].whereType<String>().join(' · '),
                          statusBadge: StaffStatusChip(
                            status: staff.status,
                            dense: true,
                          ),
                          leading: checkbox(staff),
                          onTap: () => context.push('/staff/${staff.staffId}'),
                          actions: [
                            if (widget.canManage)
                              LoginAccessButton(
                                onPressed: () => _manageAccess(staff),
                              ),
                          ],
                        ),
                    ],
                    total: _totalFor(counts),
                    hasMore: _controller.hasMore,
                    isLoading: _controller.isLoading,
                    onLoadMore: _controller.loadMore,
                    errorText: _controller.errorMessage,
                  );
                },
              ),
              // Room for the Add staff button below the last row.
              if (widget.canManage) const SizedBox(height: 72),
            ],
          ),
        ),
      ),
    );
  }
}
