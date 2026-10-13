import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/widgets/login_selection_bar.dart';
import '../../../users/presentation/widgets/provision_logins_dialog.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../domain/employment_type.dart';
import '../../domain/staff.dart';
import '../../domain/staff_search_field.dart';
import '../../domain/staff_status.dart';
import '../providers/staff_providers.dart';
import '../widgets/staff_branch_scope.dart';
import '../widgets/staff_bulk_actions.dart';
import '../widgets/staff_section_switcher.dart';
import '../widgets/staff_status_chip.dart';
import '../../../../shared/layouts/scrollable_header.dart';

/// The staff directory: desktop table / mobile cards, search by name,
/// employee code, phone or email, filters for status / department /
/// designation / employment type, and cursor pagination — never an
/// unbounded fetch of the collection.
class StaffListPage extends StatelessWidget {
  const StaffListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffBranchScope(
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

  Widget _filterDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T?>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: _isSearching ? null : onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchKey = (schoolId: widget.schoolId, branchId: widget.branchId);
    final departments =
        ref.watch(departmentsProvider(branchKey)).value ?? const [];
    final designations =
        ref.watch(designationsProvider(branchKey)).value ?? const [];
    final departmentNames = {
      for (final d in departments) d.departmentId: d.name,
    };
    final designationNames = {
      for (final d in designations) d.designationId: d.name,
    };

    return Scaffold(
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/staff/new'),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Add staff'),
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
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const StaffSectionSwitcher(current: StaffSection.staff),
                      StaffBulkActions(
                        schoolId: widget.schoolId,
                        branchId: widget.branchId,
                        teachers: false,
                      ),
                      if (widget.canManage && !_selecting)
                        IconButton(
                          tooltip: 'Give login access',
                          onPressed: () => setState(() => _selecting = true),
                          icon: const Icon(Icons.vpn_key_outlined),
                        ),
                    ],
                  ),
                  if (_selecting)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: ListenableBuilder(
                        listenable: _controller,
                        builder: (context, _) => LoginSelectionBar(
                          selected: _selected.length,
                          selectable: _selectable.length,
                          onSelectAll: () => setState(
                            () => _selected.addAll(
                              _selectable.map((s) => s.staffId),
                            ),
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
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<StaffSearchField>(
                          value: _searchField,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Search by',
                            isDense: true,
                          ),
                          items: [
                            for (final f in StaffSearchField.values)
                              DropdownMenuItem(value: f, child: Text(f.label)),
                          ],
                          onChanged: (v) {
                            setState(() => _searchField = v ?? _searchField);
                            if (_isSearching) _applyQuery();
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText:
                                'Search ${_searchField.label.toLowerCase()}',
                            isDense: true,
                            suffixIcon: _isSearching
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                      _applyQuery();
                                    },
                                  )
                                : null,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _filterDropdown<StaffStatus>(
                        label: 'Status',
                        value: _status,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All statuses'),
                          ),
                          for (final s in StaffStatus.values)
                            DropdownMenuItem(
                              value: s,
                              child: Text(s.displayName),
                            ),
                        ],
                        onChanged: (v) => _setFilter(() => _status = v),
                      ),
                      _filterDropdown<String>(
                        label: 'Department',
                        value: _departmentId,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All departments'),
                          ),
                          for (final d in departments)
                            DropdownMenuItem(
                              value: d.departmentId,
                              child: Text(d.name),
                            ),
                        ],
                        onChanged: (v) => _setFilter(() => _departmentId = v),
                      ),
                      _filterDropdown<String>(
                        label: 'Designation',
                        value: _designationId,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All designations'),
                          ),
                          for (final d in designations)
                            DropdownMenuItem(
                              value: d.designationId,
                              child: Text(d.name),
                            ),
                        ],
                        onChanged: (v) => _setFilter(() => _designationId = v),
                      ),
                      _filterDropdown<EmploymentType>(
                        label: 'Employment type',
                        value: _employmentType,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All types'),
                          ),
                          for (final t in EmploymentType.values)
                            DropdownMenuItem(
                              value: t,
                              child: Text(t.displayName),
                            ),
                        ],
                        onChanged: (v) => _setFilter(() => _employmentType = v),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push('/staff/departments'),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: const Text('Departments'),
                      ),
                      TextButton.icon(
                        onPressed: () => context.push('/staff/designations'),
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text('Designations'),
                      ),
                    ],
                  ),
                  if (_isSearching)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Filters are paused while searching. Clear the search to use them.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                      child: ResponsiveDataList<Staff>(
                        items: _controller.items,
                        columnHeaders: [
                          if (_selecting) '',
                          'Employee Code',
                          'Staff Name',
                          'Department',
                          'Designation',
                          'Phone',
                          'Employment Type',
                          'Status',
                          'Login',
                          'Actions',
                        ],
                        emptyState: const EmptyView(
                          icon: Icons.badge_outlined,
                          message: 'No staff found.',
                        ),
                        cellsBuilder: (staff) => [
                          if (_selecting)
                            DataCell(
                              Checkbox(
                                value: _selected.contains(staff.staffId),
                                onChanged: staff.userId != null
                                    ? null
                                    : (v) => setState(
                                        () => v == true
                                            ? _selected.add(staff.staffId)
                                            : _selected.remove(staff.staffId),
                                      ),
                              ),
                            ),
                          DataCell(Text(staff.employeeCode)),
                          DataCell(Text(staff.displayName)),
                          DataCell(
                            Text(departmentNames[staff.departmentId] ?? '—'),
                          ),
                          DataCell(
                            Text(designationNames[staff.designationId] ?? '—'),
                          ),
                          DataCell(Text(staff.phone)),
                          DataCell(Text(staff.employmentType.displayName)),
                          DataCell(StaffStatusChip(status: staff.status)),
                          DataCell(
                            Text(staff.userId != null ? 'Has login' : '—'),
                          ),
                          DataCell(
                            TextButton(
                              onPressed: () =>
                                  context.push('/staff/${staff.staffId}'),
                              child: const Text('View'),
                            ),
                          ),
                        ],
                        cardBuilder: (staff) => Card(
                          child: ListTile(
                            leading: _selecting
                                ? Checkbox(
                                    value: _selected.contains(staff.staffId),
                                    onChanged: staff.userId != null
                                        ? null
                                        : (v) => setState(
                                            () => v == true
                                                ? _selected.add(staff.staffId)
                                                : _selected.remove(
                                                    staff.staffId,
                                                  ),
                                          ),
                                  )
                                : null,
                            title: Text(staff.displayName),
                            subtitle: Text(
                              '${staff.employeeCode} · ${designationNames[staff.designationId] ?? '—'}'
                              '${staff.userId != null ? ' · Has login' : ''}',
                            ),
                            trailing: StaffStatusChip(status: staff.status),
                            onTap: () =>
                                context.push('/staff/${staff.staffId}'),
                          ),
                        ),
                      ),
                    ),
                    if (_controller.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(
                          _controller.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
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
      ),
    );
  }
}
