import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/activation_status.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/hub_layout.dart';
import '../../../../shared/layouts/section_page.dart';
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

            return SectionPage(
              title: 'Classes',
              description: 'Grades or standards offered this year',
              parentRoute: AppRoutes.settings,
              primaryAction: canManage
                  ? SectionAction(
                      label: 'Add class',
                      icon: Icons.add,
                      onPressed: () => _openForm(
                        context,
                        yearKey,
                        tenant.user.userId,
                        (classesAsync.value ?? const <SchoolClass>[]).length,
                      ),
                    )
                  : null,
              toolbar: ToolbarField(
                child: AcademicYearSelector(
                  years: years,
                  selectedId: selectedYearId,
                  onChanged: (id) => setState(() => _selectedYearId = id),
                ),
              ),
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
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final schoolClass = classes[index];
                      final userId = tenant.user.userId;
                      return _ClassCard(
                        schoolClass: schoolClass,
                        index: index,
                        count: classes.length,
                        canManage: canManage,
                        onMove: (delta) => _move(classes, index, delta, userId),
                        onSubjects: () =>
                            _manageSubjects(context, schoolClass, userId),
                        onEdit: () => _openForm(
                          context,
                          yearKey,
                          userId,
                          classes.length,
                          existing: schoolClass,
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
  }
}

/// One class in the list. Reorder / subjects / edit are a single "⋮" menu
/// rather than four icon buttons competing with the name on a phone.
class _ClassCard extends StatelessWidget {
  final SchoolClass schoolClass;
  final int index;
  final int count;
  final bool canManage;
  final ValueChanged<int> onMove;
  final VoidCallback onSubjects;
  final VoidCallback onEdit;

  const _ClassCard({
    required this.schoolClass,
    required this.index,
    required this.count,
    required this.canManage,
    required this.onMove,
    required this.onSubjects,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final inactive = schoolClass.status == ActivationStatus.inactive;
    final code = schoolClass.code;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${index + 1}',
                style: text.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(schoolClass.name, style: text.titleSmall),
                  if (code != null && code.isNotEmpty)
                    Text(
                      code,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (inactive)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xs),
                      child: HubBadge(label: 'Inactive'),
                    ),
                ],
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                tooltip: 'Actions for ${schoolClass.name}',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'up':
                      onMove(-1);
                    case 'down':
                      onMove(1);
                    case 'subjects':
                      onSubjects();
                    case 'edit':
                      onEdit();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'subjects',
                    child: ListTile(
                      leading: Icon(Icons.menu_book_outlined),
                      title: Text('Manage subjects'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'up',
                    enabled: index > 0,
                    child: const ListTile(
                      leading: Icon(Icons.arrow_upward),
                      title: Text('Move up'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: index < count - 1,
                    child: const ListTile(
                      leading: Icon(Icons.arrow_downward),
                      title: Text('Move down'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
