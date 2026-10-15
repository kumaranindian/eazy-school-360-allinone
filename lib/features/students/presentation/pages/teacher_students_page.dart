import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../staff/domain/teacher_scope.dart';
import '../../../staff/presentation/providers/teacher_scope_providers.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/student_providers.dart';

/// Roster of one assigned section.
typedef TeacherRosterKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String classId,
  String sectionId,
});

/// The active students of one section, all pages. The query pins the year,
/// class AND section — exactly what `firestore.rules` (`teacherHasSection`)
/// needs to allow it for a teacher assigned to that section.
final teacherRosterProvider = FutureProvider.autoDispose
    .family<List<Student>, TeacherRosterKey>((ref, key) async {
      final repo = ref.watch(studentRepositoryProvider);
      final out = <Student>[];
      Object? cursor;
      do {
        final page = await repo.fetchStudentsByPlacement(
          schoolId: key.schoolId,
          branchId: key.branchId,
          academicYearId: key.academicYearId,
          classId: key.classId,
          sectionId: key.sectionId,
          pageSize: 100,
          cursor: cursor,
        );
        out.addAll(page.items.where((s) => s.status == StudentStatus.active));
        cursor = page.nextCursor;
      } while (cursor != null && out.length < 1000);
      return out;
    });

/// What a TEACHER sees at `/students`: the students of the sections they are
/// assigned to (never the whole branch — the rules refuse that). Search is
/// within the chosen section.
class TeacherStudentsPage extends ConsumerStatefulWidget {
  const TeacherStudentsPage({super.key});

  @override
  ConsumerState<TeacherStudentsPage> createState() =>
      _TeacherStudentsPageState();
}

class _TeacherStudentsPageState extends ConsumerState<TeacherStudentsPage> {
  final _search = TextEditingController();
  TeacherSection? _picked;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    final scopeAsync = ref.watch(teacherScopeProvider);
    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        final schoolId = tenant?.school?.schoolId;
        final branchId = tenant?.user.branchId ?? tenant?.branch?.branchId;
        if (schoolId == null || branchId == null) {
          return const EmptyView(
            icon: Icons.groups_outlined,
            message: 'No branch found for your account.',
          );
        }
        return AsyncValueWidget(
          value: scopeAsync,
          errorMessage: userMessageFor,
          data: (scope) {
            if (scope == null) {
              return const EmptyView(
                icon: Icons.lock_clock_outlined,
                message:
                    "Your class access isn't set up yet. Ask your school "
                    'administrator to check your teaching assignments.',
              );
            }
            if (scope.isEmpty) {
              return const EmptyView(
                icon: Icons.groups_outlined,
                message: 'You have no class assigned yet.',
              );
            }
            final usable = [
              for (final s in scope.sections)
                if (s.academicYearId != null) s,
            ];
            if (usable.isEmpty) {
              return const EmptyView(
                icon: Icons.groups_outlined,
                message:
                    'Your assignments are missing an academic year. Ask your '
                    'school administrator to check them.',
              );
            }
            final current = usable.contains(_picked) ? _picked! : usable.first;
            return _Body(
              schoolId: schoolId,
              branchId: branchId,
              sections: usable,
              current: current,
              search: _search,
              onSearchChanged: () => setState(() {}),
              onPick: (s) => setState(() {
                _picked = s;
                _search.clear();
              }),
            );
          },
        );
      },
    );
  }
}

class _Body extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final List<TeacherSection> sections;
  final TeacherSection current;
  final TextEditingController search;
  final VoidCallback onSearchChanged;
  final ValueChanged<TeacherSection> onPick;

  const _Body({
    required this.schoolId,
    required this.branchId,
    required this.sections,
    required this.current,
    required this.search,
    required this.onSearchChanged,
    required this.onPick,
  });

  String _label(WidgetRef ref, TeacherSection s) => ref.watch(
    teacherSectionLabelProvider((
      schoolId: schoolId,
      branchId: branchId,
      section: s,
    )),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final roster = ref.watch(
      teacherRosterProvider((
        schoolId: schoolId,
        branchId: branchId,
        academicYearId: current.academicYearId!,
        classId: current.classId,
        sectionId: current.sectionId,
      )),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
                child: DropdownButtonFormField<TeacherSection>(
                  isExpanded: true,
                  value: current,
                  decoration: const InputDecoration(
                    labelText: 'My class',
                    isDense: true,
                  ),
                  items: [
                    for (final s in sections)
                      DropdownMenuItem(value: s, child: Text(_label(ref, s))),
                  ],
                  onChanged: (v) {
                    if (v != null) onPick(v);
                  },
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
                child: TextField(
                  controller: search,
                  onChanged: (_) => onSearchChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Search this class',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: roster.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(teacherRosterProvider),
            ),
            data: (all) {
              final q = search.text.trim().toLowerCase();
              final shown = q.isEmpty
                  ? all
                  : [
                      for (final s in all)
                        if (s.displayName.toLowerCase().contains(q) ||
                            s.admissionNumber.toLowerCase().contains(q))
                          s,
                    ];
              if (all.isEmpty) {
                return const EmptyView(
                  icon: Icons.groups_outlined,
                  message: 'No students are placed in this class yet.',
                );
              }
              if (shown.isEmpty) {
                return const EmptyView(
                  icon: Icons.search_off,
                  message: 'No student matches your search.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final s = shown[i];
                  return Card(
                    child: ListTile(
                      title: Text(s.displayName),
                      subtitle: Text(
                        [
                          s.admissionNumber,
                          if ((s.currentRollNumber ?? '').isNotEmpty)
                            'Roll ${s.currentRollNumber}',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/students/${s.studentId}'),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
