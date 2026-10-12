import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/paging/paged_list_controller.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../../timetable/presentation/widgets/timetable_scope.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_repositories.dart';
import '../providers/homework_providers.dart';
import '../widgets/homework_widgets.dart';

/// `/homework` — a teacher's own homework, or the branch's for an admin.
/// Counts at the top come from aggregate queries; the list is paginated.
class HomeworkListPage extends ConsumerWidget {
  const HomeworkListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    final canManage = tenant?.can(Permission.manageHomework) ?? false;
    return Scaffold(
      appBar: pageAppBar(context, title: const Text('Homework')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.homeworkNew),
              icon: const Icon(Icons.add),
              label: const Text('New homework'),
            )
          : null,
      body: TimetableScope(builder: (context, tt) => _HomeworkList(tt: tt)),
    );
  }
}

class _HomeworkList extends ConsumerStatefulWidget {
  final TimetableContext tt;
  const _HomeworkList({required this.tt});

  @override
  ConsumerState<_HomeworkList> createState() => _HomeworkListState();
}

class _HomeworkListState extends ConsumerState<_HomeworkList> {
  final _controller = PagedListController<Homework>();
  HomeworkStatus? _status;
  String? _classId;
  String? _sectionId;
  String? _teacherId;
  String? _ownStaffId;
  bool _ready = false;

  bool get _isTeacher => widget.tt.tenant.role == UserRole.teacher;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => mounted ? setState(() {}) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    if (_isTeacher) {
      try {
        final staff = await readAlive(
          ref,
          ownStaffProvider((
            schoolId: widget.tt.schoolId,
            branchId: widget.tt.branchId,
            userId: widget.tt.userId,
          )),
        );
        _ownStaffId = staff?.staffId;
      } catch (_) {
        _ownStaffId = null;
      }
    }
    if (!mounted) return;
    setState(() => _ready = true);
    _configure();
  }

  void _configure() {
    final repo = ref.read(homeworkRepositoryProvider);
    final filter = HomeworkFilter(
      classId: _classId,
      sectionId: _sectionId,
      teacherStaffId: _isTeacher ? _ownStaffId : _teacherId,
      status: _status,
    );
    _controller.fetch = (cursor) => repo.fetch(
      schoolId: widget.tt.schoolId,
      branchId: widget.tt.branchId,
      academicYearId: widget.tt.year.academicYearId,
      filter: filter,
      cursor: cursor,
    );
    _controller.reload();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = widget.tt;
    if (!_ready) return const Center(child: CircularProgressIndicator());
    if (_isTeacher && _ownStaffId == null) {
      return const EmptyView(
        icon: Icons.link_off,
        message:
            "Your account isn't linked to a staff record, so there is no "
            'homework to show. Please contact the school office.',
      );
    }
    final counts = ref.watch(
      homeworkStatusCountProvider((
        schoolId: tt.schoolId,
        branchId: tt.branchId,
        academicYearId: tt.year.academicYearId,
        teacherStaffId: _isTeacher ? _ownStaffId : null,
      )),
    );
    final items = _controller.items;
    final now = DateTime.now();
    final upcoming = [
      for (final h in items)
        if (h.status == HomeworkStatus.published && h.dueAt.isAfter(now)) h,
    ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));

    return PageColumn(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              CountTile(
                label: 'Drafts',
                icon: Icons.edit_outlined,
                value: counts.value?[HomeworkStatus.draft.wireValue],
                onTap: () => _setStatus(HomeworkStatus.draft),
              ),
              CountTile(
                label: 'Published',
                icon: Icons.public,
                value: counts.value?[HomeworkStatus.published.wireValue],
                onTap: () => _setStatus(HomeworkStatus.published),
              ),
              CountTile(
                label: 'Closed',
                icon: Icons.lock_outline,
                value: counts.value?[HomeworkStatus.closed.wireValue],
                onTap: () => _setStatus(HomeworkStatus.closed),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (upcoming.isNotEmpty)
            SectionCard(
              title: 'Upcoming deadlines',
              child: Column(
                children: [
                  for (final h in upcoming.take(3))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: Text(h.title, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${h.subjectName} · ${h.classLabel ?? ''} · '
                        '${dueLabel(h)}',
                      ),
                      onTap: () => context.go(
                        AppRoutes.homeworkDetail.replaceFirst(
                          ':homeworkId',
                          h.homeworkId,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          _filters(tt),
          const SizedBox(height: AppSpacing.sm),
          if (_controller.errorMessage != null && items.isEmpty)
            ErrorView(
              message: _controller.errorMessage!,
              onRetry: _controller.reload,
            )
          else if (!_controller.hasLoaded)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: EmptyView(
                icon: Icons.menu_book_outlined,
                message:
                    'No homework matches these filters yet. Use "New '
                    'homework" to set some.',
              ),
            )
          else ...[
            for (final h in items) _HomeworkTile(homework: h, tt: tt),
            if (_controller.hasMore)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: _controller.isLoading
                      ? const CircularProgressIndicator()
                      : OutlinedButton(
                          onPressed: _controller.loadMore,
                          child: const Text('Load more'),
                        ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _setStatus(HomeworkStatus s) {
    setState(() => _status = _status == s ? null : s);
    _configure();
  }

  Widget _filters(TimetableContext tt) {
    final classes = ref
        .watch(
          classesProvider((
            schoolId: tt.schoolId,
            branchId: tt.branchId,
            academicYearId: tt.year.academicYearId,
          )),
        )
        .value;
    final sections = _classId == null
        ? null
        : ref
              .watch(
                sectionsProvider((
                  schoolId: tt.schoolId,
                  branchId: tt.branchId,
                  academicYearId: tt.year.academicYearId,
                  classId: _classId!,
                )),
              )
              .value;
    final teachers = _isTeacher
        ? null
        : ref
              .watch(
                activeTeachersProvider((
                  schoolId: tt.schoolId,
                  branchId: tt.branchId,
                )),
              )
              .value;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<HomeworkStatus?>(
            value: _status,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Status',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All')),
              for (final s in HomeworkStatus.values)
                DropdownMenuItem(value: s, child: Text(s.displayName)),
            ],
            onChanged: (v) {
              setState(() => _status = v);
              _configure();
            },
          ),
        ),
        if (classes != null)
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              value: _classId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Class',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final c in classes)
                  DropdownMenuItem(value: c.classId, child: Text(c.name)),
              ],
              onChanged: (v) {
                setState(() {
                  _classId = v;
                  _sectionId = null;
                });
                _configure();
              },
            ),
          ),
        if (sections != null)
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              value: _sectionId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Section',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final s in sections)
                  DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
              ],
              onChanged: (v) {
                setState(() => _sectionId = v);
                _configure();
              },
            ),
          ),
        if (teachers != null)
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              value: _teacherId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Teacher',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('All')),
                for (final t in teachers)
                  DropdownMenuItem(
                    value: t.staffId,
                    child: Text(t.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                setState(() => _teacherId = v);
                _configure();
              },
            ),
          ),
      ],
    );
  }
}

class _HomeworkTile extends ConsumerWidget {
  final Homework homework;
  final TimetableContext tt;

  const _HomeworkTile({required this.homework, required this.tt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = homework;
    final open =
        h.status == HomeworkStatus.published ||
        h.status == HomeworkStatus.closed;
    final awaiting = open && h.requiresSubmission
        ? ref
              .watch(
                awaitingReviewProvider((
                  schoolId: h.schoolId,
                  branchId: h.branchId,
                  homeworkId: h.homeworkId,
                )),
              )
              .value
        : null;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${h.subjectName} · ${h.classLabel ?? h.classId}'),
              Text(dueLabel(h)),
              HomeworkStatusPill(h.status),
              if (awaiting != null && awaiting > 0)
                StatusPill(
                  label: '$awaiting to review',
                  icon: Icons.rate_review_outlined,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(
          AppRoutes.homeworkDetail.replaceFirst(':homeworkId', h.homeworkId),
        ),
      ),
    );
  }
}
