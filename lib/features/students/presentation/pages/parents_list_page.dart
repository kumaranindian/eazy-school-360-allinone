import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/scrollable_header.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/widgets/login_access_dialog.dart';
import '../../../users/presentation/widgets/login_selection_bar.dart';
import '../../../users/presentation/widgets/provision_logins_dialog.dart';
import '../../domain/paged_result.dart';
import '../../domain/parent.dart';
import '../../../../core/errors/error_mapper.dart';
import '../providers/parent_providers.dart';
import '../providers/student_providers.dart';
import '../widgets/parent_form_dialog.dart';

/// The parent/guardian directory (brief §21): name, phone, email, number
/// of children, status — search, filter, and cursor pagination, same
/// shape as [StudentsListPage].
class ParentsListPage extends ConsumerStatefulWidget {
  const ParentsListPage({super.key});

  @override
  ConsumerState<ParentsListPage> createState() => _ParentsListPageState();
}

class _ParentsListPageState extends ConsumerState<ParentsListPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  ActivationStatus? _statusFilter;

  List<Parent> _items = [];
  Object? _cursor;
  bool _hasMore = false;
  bool _isLoading = false;
  bool _loadedOnce = false;
  String? _schoolId;
  String? _branchId;

  // Choosing people to give logins to (one or many).
  bool _selecting = false;
  final _selected = <String>{};

  Iterable<Parent> get _selectable => _items.where((p) => !p.hasPortalAccess);

  Future<void> _manageAccess(
    String schoolId,
    String branchId,
    Parent parent,
  ) async {
    final changed = await showLoginAccessDialog(
      context: context,
      schoolId: schoolId,
      branchId: branchId,
      kind: LoginKind.parent,
      id: parent.parentId,
      fallbackName: parent.displayName,
    );
    if (changed == true && mounted) _resetAndLoad(schoolId, branchId);
  }

  Future<void> _giveLogins(String schoolId, String branchId) async {
    final done = await showAdaptiveAppDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProvisionLoginsDialog(
        schoolId: schoolId,
        branchId: branchId,
        kind: LoginKind.parent,
        people: [
          for (final p in _items)
            if (_selected.contains(p.parentId))
              (id: p.parentId, name: p.displayName, email: p.email),
        ],
      ),
    );
    if (done == true && mounted) {
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      _resetAndLoad(schoolId, branchId);
    }
  }

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
    final repository = ref.read(parentRepositoryProvider);
    final query = _searchController.text.trim();
    final PagedResult<Parent> page = query.isNotEmpty
        ? await repository.searchParentsByName(
            schoolId: schoolId,
            branchId: branchId,
            query: query,
            cursor: reset ? null : _cursor,
          )
        : await repository.fetchParents(
            schoolId: schoolId,
            branchId: branchId,
            status: _statusFilter,
            cursor: reset ? null : _cursor,
          );

    if (!mounted) return;
    setState(() {
      _items = reset ? page.items : [..._items, ...page.items];
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      _isLoading = false;
    });
  }

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String branchId,
    String userId, {
    Parent? existing,
  }) async {
    final saved = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (context) => ParentFormDialog(
        schoolId: schoolId,
        branchId: branchId,
        currentUserId: userId,
        existing: existing,
      ),
    );
    if (saved == true) {
      _resetAndLoad(schoolId, branchId);
    }
  }

  /// Rebuilds who-may-see-what for every family of the branch (also the
  /// backfill for data that predates the index).
  Future<void> _refreshAccess(
    BuildContext context,
    String schoolId,
    String branchId,
    String userId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refresh parent access?'),
        content: const Text(
          'Recomputes which classes and sections each family can see from '
          'their linked children. Safe to run at any time; it can take a '
          'moment for a large branch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await ref
          .read(parentAccessSyncProvider)
          .refreshBranch(
            schoolId: schoolId,
            branchId: branchId,
            updatedBy: userId,
          );
      messenger.showSnackBar(
        SnackBar(content: Text('Parent access refreshed for $n families.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    }
  }

  bool get _isSearching => _searchController.text.trim().isNotEmpty;

  /// One query per pause in typing, not one per keystroke.
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && _schoolId != null && _branchId != null) {
        _resetAndLoad(_schoolId!, _branchId!);
      }
    });
    setState(() {});
  }

  List<FilterField> _filters() => [
    FilterField.dropdown<ActivationStatus>(
      label: 'Status',
      value: _statusFilter,
      options: [
        (null, 'All statuses'),
        for (final s in ActivationStatus.values)
          (s, s == ActivationStatus.active ? 'Active' : 'Inactive'),
      ],
      onChanged: (value) {
        setState(() => _statusFilter = value);
        if (_schoolId != null && _branchId != null) {
          _resetAndLoad(_schoolId!, _branchId!);
        }
      },
    ),
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.family_restroom_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageStudentData);

        if (!_loadedOnce || _schoolId != schoolId || _branchId != branchId) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _resetAndLoad(schoolId, branchId),
          );
        }

        return Scaffold(
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  onPressed: () => _openForm(
                    context,
                    schoolId,
                    branchId,
                    tenant.user.userId,
                  ),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add parent'),
                )
              : null,
          body: Column(
            children: [
              ScrollableHeader(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FilterBar(
                          searchController: _searchController,
                          searchHint: 'Search parents by name',
                          onSearchChanged: _onSearchChanged,
                          filtersEnabled: !_isSearching,
                          fieldsBuilder: _filters,
                        ),
                      ),
                      PageActionsMenu(
                        actions: [
                          if (canManage && !_selecting)
                            PageAction(
                              label: 'Give login access',
                              icon: Icons.vpn_key_outlined,
                              onSelected: () =>
                                  setState(() => _selecting = true),
                            ),
                          if (canManage)
                            PageAction(
                              label: 'Refresh parent access',
                              icon: Icons.sync_lock_outlined,
                              onSelected: () => _refreshAccess(
                                context,
                                schoolId,
                                branchId,
                                tenant.user.userId,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_selecting)
                LoginSelectionBar(
                  selected: _selected.length,
                  selectable: _selectable.length,
                  onSelectAll: () => setState(
                    () => _selected.addAll(_selectable.map((p) => p.parentId)),
                  ),
                  onClear: () => setState(_selected.clear),
                  onCreate: () => _giveLogins(schoolId, branchId),
                  onCancel: () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
                ),
              Expanded(
                child: _isLoading && _items.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ResponsiveDataList<Parent>(
                        items: _items,
                        columnHeaders: [
                          if (_selecting) '',
                          'Name',
                          'Phone',
                          'Email',
                          'Status',
                          'Login',
                          '',
                        ],
                        emptyState: const EmptyView(
                          icon: Icons.family_restroom_outlined,
                          message: 'No parents match your filters.',
                        ),
                        cellsBuilder: (parent) => [
                          if (_selecting)
                            DataCell(
                              Checkbox(
                                value: _selected.contains(parent.parentId),
                                onChanged: parent.hasPortalAccess
                                    ? null
                                    : (v) => setState(
                                        () => v == true
                                            ? _selected.add(parent.parentId)
                                            : _selected.remove(parent.parentId),
                                      ),
                              ),
                            ),
                          DataCell(Text(parent.displayName)),
                          DataCell(Text(parent.phone)),
                          DataCell(Text(parent.email ?? '—')),
                          DataCell(
                            Text(
                              parent.status == ActivationStatus.active
                                  ? 'Active'
                                  : 'Inactive',
                            ),
                          ),
                          DataCell(
                            Text(parent.hasPortalAccess ? 'Has login' : '—'),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (canManage)
                                  IconButton(
                                    icon: const Icon(Icons.vpn_key_outlined),
                                    tooltip: 'Login access',
                                    onPressed: () => _manageAccess(
                                      schoolId,
                                      branchId,
                                      parent,
                                    ),
                                  ),
                                TextButton(
                                  onPressed: () => context.push(
                                    '/parents/${parent.parentId}',
                                  ),
                                  child: const Text('View'),
                                ),
                              ],
                            ),
                          ),
                        ],
                        cardBuilder: (parent) => Card(
                          child: ListTile(
                            leading: _selecting
                                ? Checkbox(
                                    value: _selected.contains(parent.parentId),
                                    onChanged: parent.hasPortalAccess
                                        ? null
                                        : (v) => setState(
                                            () => v == true
                                                ? _selected.add(parent.parentId)
                                                : _selected.remove(
                                                    parent.parentId,
                                                  ),
                                          ),
                                  )
                                : null,
                            title: Text(parent.displayName),
                            subtitle: Text(
                              '${parent.phone}'
                              '${parent.hasPortalAccess ? ' · Has login' : ''}',
                            ),
                            trailing: canManage
                                ? IconButton(
                                    icon: const Icon(Icons.vpn_key_outlined),
                                    tooltip: 'Login access',
                                    onPressed: () => _manageAccess(
                                      schoolId,
                                      branchId,
                                      parent,
                                    ),
                                  )
                                : null,
                            onTap: () =>
                                context.push('/parents/${parent.parentId}'),
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
