import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/responsive_data_list.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/subject.dart';
import '../providers/academic_structure_providers.dart';
import '../widgets/academic_year_selector.dart';
import '../widgets/subject_form_dialog.dart';

class SubjectsPage extends ConsumerStatefulWidget {
  const SubjectsPage({super.key});

  @override
  ConsumerState<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends ConsumerState<SubjectsPage> {
  String? _selectedYearId;
  String _search = '';

  Future<void> _openForm(
    BuildContext context,
    String schoolId,
    String branchId,
    String yearId,
    String userId,
    int nextOrder, {
    Subject? existing,
  }) async {
    final saved = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (context) => SubjectFormDialog(
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: yearId,
        currentUserId: userId,
        nextDisplayOrder: nextOrder,
        existing: existing,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null ? 'Subject created.' : 'Subject updated.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.menu_book_outlined,
            message: 'No branch found for your account.',
          );
        }
        final schoolId = tenant!.school!.schoolId;
        final branchId = tenant.branch!.branchId;
        final canManage = tenant.can(Permission.manageAcademicSetup);
        final yearsAsync = ref.watch(
          academicYearsProvider((schoolId: schoolId, branchId: branchId)),
        );

        return AsyncValueWidget(
          value: yearsAsync,
          data: (years) {
            if (years.isEmpty) {
              return const EmptyView(
                icon: Icons.menu_book_outlined,
                message: 'Add an academic year first.',
              );
            }
            final yearId = years.any((y) => y.academicYearId == _selectedYearId)
                ? _selectedYearId!
                : years.first.academicYearId;
            final subjectsAsync = ref.watch(
              subjectsProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: yearId,
              )),
            );

            return Scaffold(
              floatingActionButton: canManage
                  ? FloatingActionButton.extended(
                      onPressed: () {
                        final current =
                            subjectsAsync.value ?? const <Subject>[];
                        _openForm(
                          context,
                          schoolId,
                          branchId,
                          yearId,
                          tenant.user.userId,
                          current.length,
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add subject'),
                    )
                  : null,
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: AcademicYearSelector(
                            years: years,
                            selectedId: yearId,
                            onChanged: (id) =>
                                setState(() => _selectedYearId = id),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search subjects',
                              isDense: true,
                            ),
                            onChanged: (value) =>
                                setState(() => _search = value),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AsyncValueWidget(
                      value: subjectsAsync,
                      data: (subjects) {
                        final filtered = subjects
                            .where(
                              (s) =>
                                  _search.isEmpty ||
                                  s.name.toLowerCase().contains(
                                    _search.toLowerCase(),
                                  ),
                            )
                            .toList();
                        return ResponsiveDataList<Subject>(
                          items: filtered,
                          columnHeaders: const [
                            'Name',
                            'Code',
                            'Type',
                            'Status',
                            '',
                          ],
                          emptyState: const EmptyView(
                            icon: Icons.menu_book_outlined,
                            message: 'No subjects match.',
                          ),
                          cellsBuilder: (subject) => [
                            DataCell(Text(subject.name)),
                            DataCell(Text(subject.code ?? '—')),
                            DataCell(Text(subject.type.displayName)),
                            DataCell(
                              Text(
                                subject.status.name == 'active'
                                    ? 'Active'
                                    : 'Inactive',
                              ),
                            ),
                            DataCell(
                              canManage
                                  ? IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _openForm(
                                        context,
                                        schoolId,
                                        branchId,
                                        yearId,
                                        tenant.user.userId,
                                        subjects.length,
                                        existing: subject,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                          cardBuilder: (subject) => Card(
                            child: ListTile(
                              title: Text(subject.name),
                              subtitle: Text(
                                '${subject.type.displayName} · ${subject.code ?? 'no code'}',
                              ),
                              trailing: canManage
                                  ? IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _openForm(
                                        context,
                                        schoolId,
                                        branchId,
                                        yearId,
                                        tenant.user.userId,
                                        subjects.length,
                                        existing: subject,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
