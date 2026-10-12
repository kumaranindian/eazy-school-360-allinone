import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/school_class.dart';
import '../providers/academic_setup_keys.dart';
import '../providers/academic_structure_providers.dart';
import '../widgets/academic_year_selector.dart';
import '../widgets/class_form_dialog.dart';
import '../widgets/class_subjects_dialog.dart';

class ClassesPage extends ConsumerStatefulWidget {
  const ClassesPage({super.key});

  @override
  ConsumerState<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends ConsumerState<ClassesPage> {
  String? _selectedYearId;

  Future<void> _openForm(
    BuildContext context,
    AcademicYearKey yearKey,
    String userId,
    int nextOrder, {
    SchoolClass? existing,
  }) async {
    final saved = await showAdaptiveAppDialog<bool>(
      context: context,
      builder: (context) => ClassFormDialog(
        schoolId: yearKey.schoolId,
        branchId: yearKey.branchId,
        academicYearId: yearKey.academicYearId,
        currentUserId: userId,
        nextDisplayOrder: nextOrder,
        existing: existing,
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null ? 'Class created.' : 'Class updated.'),
        ),
      );
    }
  }

  Future<void> _move(
    List<SchoolClass> classes,
    int index,
    int delta,
    String userId,
  ) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= classes.length) return;
    final reordered = [...classes];
    final moved = reordered.removeAt(index);
    reordered.insert(newIndex, moved);
    await ref
        .read(academicStructureRepositoryProvider)
        .reorderClasses(reordered, updatedBy: userId);
  }

  Future<void> _manageSubjects(
    BuildContext context,
    SchoolClass schoolClass,
    String userId,
  ) async {
    final subjectsKey = (
      schoolId: schoolClass.schoolId,
      branchId: schoolClass.branchId,
      academicYearId: schoolClass.academicYearId,
    );
    final subjects = await ref
        .read(academicStructureRepositoryProvider)
        .watchSubjects(
          subjectsKey.schoolId,
          subjectsKey.branchId,
          subjectsKey.academicYearId,
        )
        .first;
    if (!context.mounted) return;
    await showAdaptiveAppDialog<void>(
      context: context,
      builder: (context) => ClassSubjectsDialog(
        schoolClass: schoolClass,
        allSubjects: subjects,
        currentUserId: userId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);

    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null || tenant?.branch == null) {
          return const EmptyView(
            icon: Icons.class_outlined,
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
                icon: Icons.class_outlined,
                message:
                    'Add an academic year first, then come back to configure classes.',
              );
            }
            final selectedYearId =
                years.any((y) => y.academicYearId == _selectedYearId)
                ? _selectedYearId!
                : years.first.academicYearId;
            final yearKey = (
              schoolId: schoolId,
              branchId: branchId,
              academicYearId: selectedYearId,
            );
            final classesAsync = ref.watch(classesProvider(yearKey));

            return Scaffold(
              floatingActionButton: canManage
                  ? FloatingActionButton.extended(
                      onPressed: () {
                        final current =
                            classesAsync.value ?? const <SchoolClass>[];
                        _openForm(
                          context,
                          yearKey,
                          tenant.user.userId,
                          current.length,
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add class'),
                    )
                  : null,
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SizedBox(
                      width: 280,
                      child: AcademicYearSelector(
                        years: years,
                        selectedId: selectedYearId,
                        onChanged: (id) => setState(() => _selectedYearId = id),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AsyncValueWidget(
                      value: classesAsync,
                      data: (classes) {
                        if (classes.isEmpty) {
                          return const EmptyView(
                            icon: Icons.class_outlined,
                            message: 'No classes yet for this academic year.',
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: classes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (context, index) {
                            final schoolClass = classes[index];
                            return Card(
                              child: ListTile(
                                leading:
                                    schoolClass.status ==
                                        ActivationStatus.inactive
                                    ? const Icon(Icons.visibility_off_outlined)
                                    : const CircleAvatar(
                                        radius: 4,
                                        backgroundColor: Colors.transparent,
                                      ),
                                title: Text(schoolClass.name),
                                subtitle:
                                    schoolClass.code != null &&
                                        schoolClass.code!.isNotEmpty
                                    ? Text(schoolClass.code!)
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canManage) ...[
                                      IconButton(
                                        icon: const Icon(
                                          Icons.arrow_upward,
                                          size: 18,
                                        ),
                                        onPressed: index == 0
                                            ? null
                                            : () => _move(
                                                classes,
                                                index,
                                                -1,
                                                tenant.user.userId,
                                              ),
                                        tooltip: 'Move up',
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.arrow_downward,
                                          size: 18,
                                        ),
                                        onPressed: index == classes.length - 1
                                            ? null
                                            : () => _move(
                                                classes,
                                                index,
                                                1,
                                                tenant.user.userId,
                                              ),
                                        tooltip: 'Move down',
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.menu_book_outlined,
                                        ),
                                        tooltip: 'Manage subjects',
                                        onPressed: () => _manageSubjects(
                                          context,
                                          schoolClass,
                                          tenant.user.userId,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _openForm(
                                          context,
                                          yearKey,
                                          tenant.user.userId,
                                          classes.length,
                                          existing: schoolClass,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
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
