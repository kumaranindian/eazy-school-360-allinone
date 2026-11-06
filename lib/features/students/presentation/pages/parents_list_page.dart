import '../../../users/presentation/widgets/login_access_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/admin_dashboard_palette.dart';
import '../../../../core/utils/responsive.dart';
import '../widgets/parents/parents_ui.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/filters/directory_toolbar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../../shared/filters/page_actions.dart';
import '../../../../shared/layouts/directory_list.dart';
import '../../../../shared/layouts/status_chips.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../users/domain/login_provisioning.dart';
import '../../../users/presentation/widgets/login_selection_bar.dart';
import '../../../users/presentation/widgets/bulk_reset_password_dialog.dart';
import '../../../users/presentation/widgets/provision_logins_dialog.dart';
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

  final _controller = PagedListController<Parent>();
  bool _loadedOnce = false;
  String? _schoolId;
  String? _branchId;

  // A second "Refresh parent access" while one runs would only repeat the work.
  bool _refreshingAccess = false;

  // Choosing people to give logins to (one or many).
  bool _selecting = false;

  /// Selecting people who already have a login, to reset their passwords
  /// (otherwise: people without one, to give them a login).
  bool _resetMode = false;
  final _selected = <String>{};

  Iterable<Parent> get _selectable => _controller.items.where(
    (p) => _resetMode ? p.hasPortalAccess : !p.hasPortalAccess,
  );

  Future<void> _manageAccess(
    String schoolId,
    String branchId,
    Parent parent,
  ) async {
    final changed = await context.push<bool>(
      '/parents/${parent.parentId}/login-access',
      extra: parent.displayName,
    );
    if (changed == true && mounted) _resetAndLoad(schoolId, branchId);
  }

  Future<void> _resetPasswords(String schoolId, String branchId) async {
    final done = await showBulkResetPasswordDialog(
      context: context,
      schoolId: schoolId,
      branchId: branchId,
      kind: LoginKind.parent,
      people: [
        for (final p in _controller.items)
          if (_selected.contains(p.parentId))
            (id: p.parentId, name: p.displayName, email: p.email),
      ],
    );
    if (done == true && mounted) {
      setState(() {
        _selecting = false;
        _resetMode = false;
        _selected.clear();
      });
    }
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
          for (final p in _controller.items)
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

  /// Rebuilds the fetch closure from the current search/filter and loads page
  /// one; the shared controller drops stale responses (STATE-1).
  void _resetAndLoad(String schoolId, String branchId) {
    _schoolId = schoolId;
    _branchId = branchId;
    _loadedOnce = true;
    final repository = ref.read(parentRepositoryProvider);
    final query = _searchController.text.trim();
    final status = _statusFilter;
    _controller.fetch = (cursor) => query.isNotEmpty
        ? repository.searchParentsByName(
            schoolId: schoolId,
            branchId: branchId,
            query: query,
            cursor: cursor,
          )
        : repository.fetchParents(
            schoolId: schoolId,
            branchId: branchId,
            status: status,
            cursor: cursor,
          );
    _controller.reload();
  }

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String branchId,
    String userId, {
    Parent? existing,
  }) async {
    final saved = await showAdaptiveAppDialog<ParentFormResult>(
      context: context,
      builder: (context) => ParentFormDialog(
        schoolId: schoolId,
        branchId: branchId,
        currentUserId: userId,
        existing: existing,
      ),
    );
    if (saved == null || !mounted) return;
    if (!saved.created && existing == null) {
      // The person picked an existing parent instead of adding a duplicate.
      this.context.push('/parents/${saved.parentId}');
      return;
    }
    _resetAndLoad(schoolId, branchId);
    if (saved.giveLogin) {
      final given = await showProvisionLoginsDialog(
        context: this.context,
        schoolId: schoolId,
        branchId: branchId,
        kind: LoginKind.parent,
        people: [(id: saved.parentId, name: saved.name, email: saved.email)],
      );
      if (given == true && mounted) _resetAndLoad(schoolId, branchId);
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
    if (ok != true || _refreshingAccess) return;
    _refreshingAccess = true;
    messenger.showSnackBar(
      const SnackBar(content: Text('Refreshing parent access…')),
    );
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
    } finally {
      _refreshingAccess = false;
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

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    final layout = screenSizeForWidth(MediaQuery.sizeOf(context).width);

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
                  label: const Text('Add Parent'),
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
                        if (canManage && !_selecting)
                          PageAction(
                            label: 'Give login access',
                            icon: Icons.vpn_key_outlined,
                            onSelected: () => setState(() {
                              _selecting = true;
                              _resetMode = false;
                              _selected.clear();
                            }),
                          ),
                        if (canManage && !_selecting)
                          PageAction(
                            label: 'Reset passwords',
                            icon: Icons.lock_reset,
                            onSelected: () => setState(() {
                              _selecting = true;
                              _resetMode = true;
                              _selected.clear();
                            }),
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
                    searchController: _searchController,
                    searchHint: 'Search parents by name',
                    onSearchChanged: _onSearchChanged,
                    filtersEnabled: !_isSearching,
                    fieldsBuilder: _filters,
                    inlineCount: 1,
                  ),
                  if (!_isSearching && _filters().any((f) => f.isApplied)) ...[
                    SizedBox(height: DirectoryLayout.sectionGap(layout)),
                    StatusChips(
                      chips: const [],
                      activeFilters: _filters(),
                      layout: layout,
                    ),
                  ],
                  if (_selecting) ...[
                    SizedBox(height: DirectoryLayout.sectionGap(layout)),
                    LoginSelectionBar(
                      selected: _selected.length,
                      selectable: _selectable.length,
                      onSelectAll: () => setState(
                        () => _selected.addAll(
                          _selectable.map((p) => p.parentId),
                        ),
                      ),
                      onClear: () => setState(_selected.clear),
                      onCreate: () => _resetMode
                          ? _resetPasswords(schoolId, branchId)
                          : _giveLogins(schoolId, branchId),
                      actionLabel: _resetMode
                          ? 'Reset passwords'
                          : 'Give login access',
                      actionIcon: _resetMode
                          ? Icons.lock_reset
                          : Icons.vpn_key_outlined,
                      selectAllLabel: _resetMode
                          ? 'Select all (${_selectable.length} with a login)'
                          : null,
                      onCancel: () => setState(() {
                        _selecting = false;
                        _resetMode = false;
                        _selected.clear();
                      }),
                    ),
                  ],
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
                    _ParentCards(
                      items: _controller.items,
                      canManage: canManage,
                      selecting: _selecting,
                      resetMode: _resetMode,
                      selected: _selected,
                      isSearching: _isSearching,
                      hasMore: _controller.hasMore,
                      isLoading: _controller.isLoading,
                      errorText: _controller.errorMessage,
                      onLoadMore: _controller.loadMore,
                      onToggle: (id, on) => setState(
                        () => on ? _selected.add(id) : _selected.remove(id),
                      ),
                      onOpen: (p) => context.push('/parents/${p.parentId}'),
                      onAccess: (p) => _manageAccess(schoolId, branchId, p),
                    ),
                  if (canManage) const SizedBox(height: 72),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The parents as cards (one column on phones and tablets, two on wide
/// screens), with the count, "Load more", loading and empty states.
class _ParentCards extends StatelessWidget {
  final List<Parent> items;
  final bool canManage;
  final bool selecting;
  final bool resetMode;
  final Set<String> selected;
  final bool isSearching;
  final bool hasMore;
  final bool isLoading;
  final String? errorText;
  final VoidCallback onLoadMore;
  final void Function(String id, bool on) onToggle;
  final void Function(Parent) onOpen;
  final void Function(Parent) onAccess;

  const _ParentCards({
    required this.items,
    required this.canManage,
    required this.selecting,
    required this.resetMode,
    required this.selected,
    required this.isSearching,
    required this.hasMore,
    required this.isLoading,
    required this.errorText,
    required this.onLoadMore,
    required this.onToggle,
    required this.onOpen,
    required this.onAccess,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    if (items.isEmpty) {
      return EmptyView(
        icon: isSearching
            ? Icons.search_off_outlined
            : Icons.family_restroom_outlined,
        message: isSearching
            ? 'No parents match your search.'
            : 'No parents match your filters.',
      );
    }
    final cards = [
      for (final parent in items)
        ParentListCard(
          name: parent.displayName,
          photoUrl: parent.photoUrl,
          phone: parent.phone,
          email: parent.email,
          active: parent.status == ActivationStatus.active,
          hasLogin: parent.hasPortalAccess,
          onTap: () => onOpen(parent),
          leading: selecting
              ? Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: selected.contains(parent.parentId),
                    // Same rule as before: only people who can take the
                    // chosen action are selectable.
                    onChanged:
                        (resetMode
                            ? !parent.hasPortalAccess
                            : parent.hasPortalAccess)
                        ? null
                        : (v) => onToggle(parent.parentId, v == true),
                  ),
                )
              : null,
          actions: [
            if (canManage) LoginAccessButton(onPressed: () => onAccess(parent)),
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            '${items.length}${hasMore ? '+' : ''} '
            '${items.length == 1 && !hasMore ? 'Parent' : 'Parents'}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: p.textSecondary),
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 1000 ? 2 : 1;
            const gap = 12.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards) SizedBox(width: w, child: card),
              ],
            );
          },
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (hasMore || isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: isLoading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: onLoadMore,
                      child: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}
