import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/paged_result.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/student_providers.dart';
import '../widgets/student_placement_label.dart';

enum _SearchMode { none, byName, byAdmissionNumber }

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
  _SearchMode _searchMode = _SearchMode.none;
  StudentStatus? _statusFilter = StudentStatus.active;

  List<Student> _items = [];
  Object? _cursor;
  bool _hasMore = false;
  bool _isLoading = false;
  bool _loadedOnce = false;
  String? _schoolId;
  String? _branchId;

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

    if (_searchMode == _SearchMode.byName && query.isNotEmpty) {
      page = await repository.searchStudentsByName(
        schoolId: schoolId,
        branchId: branchId,
        query: query,
        cursor: reset ? null : _cursor,
      );
    } else if (_searchMode == _SearchMode.byAdmissionNumber &&
        query.isNotEmpty) {
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

  void _onSearchChanged(String value) {
    setState(
      () => _searchMode = value.trim().isEmpty ? _SearchMode.none : _searchMode,
    );
    if (_schoolId != null && _branchId != null) {
      _resetAndLoad(_schoolId!, _branchId!);
    }
  }

  @override
  void dispose() {
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
            icon: Icons.groups_outlined,
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
                  onPressed: () => context.push('/students/new'),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Admit student'),
                )
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    if (canManage)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => context.push('/students/import'),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Bulk upload (CSV)'),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search by name',
                              isDense: true,
                            ),
                            onChanged: (v) {
                              setState(
                                () => _searchMode = v.trim().isEmpty
                                    ? _SearchMode.none
                                    : _SearchMode.byName,
                              );
                              _onSearchChanged(v);
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        OutlinedButton(
                          onPressed: () {
                            setState(
                              () => _searchMode =
                                  _searchController.text.trim().isEmpty
                                  ? _SearchMode.none
                                  : _SearchMode.byAdmissionNumber,
                            );
                            _onSearchChanged(_searchController.text);
                          },
                          child: const Text('By admission #'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        DropdownButton<StudentStatus?>(
                          value: _statusFilter,
                          hint: const Text('All statuses'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('All statuses'),
                            ),
                            for (final s in StudentStatus.values)
                              DropdownMenuItem(
                                value: s,
                                child: Text(s.displayName),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() => _statusFilter = value);
                            if (_schoolId != null && _branchId != null) {
                              _resetAndLoad(_schoolId!, _branchId!);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
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
  Widget build(BuildContext context) {
    final isActive = status == StudentStatus.active;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Chip(
      label: Text(
        status.displayName,
        style: TextStyle(color: color, fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}
