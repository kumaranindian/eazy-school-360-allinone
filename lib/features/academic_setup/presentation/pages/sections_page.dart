import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/academic_year.dart';
import '../../domain/school_class.dart';
import '../providers/academic_structure_providers.dart';
import '../widgets/academic_year_selector.dart';
import '../widgets/section_form_dialog.dart';

class SectionsPage extends ConsumerStatefulWidget {
  const SectionsPage({super.key});

  @override
  ConsumerState<SectionsPage> createState() => _SectionsPageState();
}

class _SectionsPageState extends ConsumerState<SectionsPage> {
  String? _selectedYearId;
  String? _selectedClassId;

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.grid_view_outlined,
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
                icon: Icons.grid_view_outlined,
                message: 'Add an academic year first.',
              );
            }
            final yearId = years.any((y) => y.academicYearId == _selectedYearId)
                ? _selectedYearId!
                : years.first.academicYearId;
            final classesAsync = ref.watch(
              classesProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: yearId,
              )),
            );

            return AsyncValueWidget(
              value: classesAsync,
              data: (classes) {
                if (classes.isEmpty) {
                  return _Header(
                    years: years,
                    selectedYearId: yearId,
                    onYearChanged: (id) => setState(() {
                      _selectedYearId = id;
                      _selectedClassId = null;
                    }),
                    classId: null,
                    classes: const [],
                    onClassChanged: (_) {},
                    child: const EmptyView(
                      icon: Icons.grid_view_outlined,
                      message:
                          'Add a class first, then configure its sections.',
                    ),
                  );
                }
                final classId =
                    classes.any((c) => c.classId == _selectedClassId)
                    ? _selectedClassId!
                    : classes.first.classId;
                final classKey = (
                  schoolId: schoolId,
                  branchId: branchId,
                  academicYearId: yearId,
                  classId: classId,
                );
                final sectionsAsync = ref.watch(sectionsProvider(classKey));

                return _Header(
                  years: years,
                  selectedYearId: yearId,
                  onYearChanged: (id) => setState(() {
                    _selectedYearId = id;
                    _selectedClassId = null;
                  }),
                  classId: classId,
                  classes: classes,
                  onClassChanged: (id) => setState(() => _selectedClassId = id),
                  primaryAction: canManage
                      ? SectionAction(
                          label: 'Add section',
                          icon: Icons.add,
                          onPressed: () async {
                            final saved = await showAdaptiveAppDialog<bool>(
                              context: context,
                              builder: (context) => SectionFormDialog(
                                schoolId: schoolId,
                                branchId: branchId,
                                academicYearId: yearId,
                                classId: classId,
                                currentUserId: tenant.user.userId,
                              ),
                            );
                            if (saved == true && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Section created.'),
                                ),
                              );
                            }
                          },
                        )
                      : null,
                  child: AsyncValueWidget(
                    value: sectionsAsync,
                    data: (sections) {
                      if (sections.isEmpty) {
                        return const EmptyView(
                          icon: Icons.grid_view_outlined,
                          message: 'No sections yet for this class.',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: sections.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final section = sections[index];
                          return Card(
                            child: ListTile(
                              title: Text(section.name),
                              subtitle: Text(
                                section.capacity != null
                                    ? 'Capacity: ${section.capacity}'
                                    : 'No capacity set',
                              ),
                              trailing: canManage
                                  ? IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () async {
                                        final saved =
                                            await showAdaptiveAppDialog<bool>(
                                              context: context,
                                              builder: (context) =>
                                                  SectionFormDialog(
                                                    schoolId: schoolId,
                                                    branchId: branchId,
                                                    academicYearId: yearId,
                                                    classId: classId,
                                                    currentUserId:
                                                        tenant.user.userId,
                                                    existing: section,
                                                  ),
                                            );
                                        if (saved == true && context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('Section updated.'),
                                            ),
                                          );
                                        }
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final List<AcademicYear> years;
  final String selectedYearId;
  final ValueChanged<String> onYearChanged;
  final String? classId;
  final List<SchoolClass> classes;
  final ValueChanged<String> onClassChanged;
  final SectionAction? primaryAction;
  final Widget child;

  const _Header({
    required this.years,
    required this.selectedYearId,
    required this.onYearChanged,
    required this.classId,
    required this.classes,
    required this.onClassChanged,
    required this.child,
    this.primaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return SectionPage(
      title: 'Sections',
      description: 'Divisions within each class',
      parentRoute: AppRoutes.settings,
      primaryAction: primaryAction,
      toolbar: SectionToolbar(
        children: [
          ToolbarField(
            child: AcademicYearSelector(
              years: years,
              selectedId: selectedYearId,
              onChanged: onYearChanged,
            ),
          ),
          if (classes.isNotEmpty)
            ToolbarField(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: classId,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  isDense: true,
                ),
                items: [
                  for (final c in classes)
                    DropdownMenuItem(value: c.classId, child: Text(c.name)),
                ],
                onChanged: (value) {
                  if (value != null) onClassChanged(value);
                },
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}
