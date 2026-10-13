import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
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

            return SectionPage(
              title: 'Subjects',
              description: 'Subjects taught and where they apply',
              parentRoute: AppRoutes.settings,
              primaryAction: canManage
                  ? SectionAction(
                      label: 'Add subject',
                      icon: Icons.add,
                      onPressed: () => _openForm(
                        context,
                        schoolId,
                        branchId,
                        yearId,
                        tenant.user.userId,
                        (subjectsAsync.value ?? const <Subject>[]).length,
                      ),
                    )
                  : null,
              toolbar: SectionToolbar(
                children: [
                  ToolbarField(
                    child: AcademicYearSelector(
                      years: years,
                      selectedId: yearId,
                      onChanged: (id) => setState(() => _selectedYearId = id),
                    ),
                  ),
                  ToolbarField(
                    width: 280,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search subjects',
                        isDense: true,
                      ),
                      onChanged: (value) => setState(() => _search = value),
                    ),
                  ),
                ],
              ),
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
                    columnHeaders: const ['Name', 'Code', 'Type', 'Status', ''],
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
            );
          },
        );
      },
    );
  }
}
