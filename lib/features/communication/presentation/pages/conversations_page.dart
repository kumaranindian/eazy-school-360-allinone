import 'package:flutter/material.dart';

import '../../../../shared/layouts/hero_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../../timetable/presentation/providers/timetable_providers.dart';
import '../../domain/conversation.dart';
import '../providers/communication_providers.dart';

const _page = 20;

/// `/messages` — the user's parent–teacher conversations (parents and
/// teachers), or, for an administrator, only the conversations a member has
/// reported. There is no directory and no way to message anyone else.
class ConversationsPage extends ConsumerStatefulWidget {
  const ConversationsPage({super.key});

  @override
  ConsumerState<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends ConsumerState<ConversationsPage> {
  int _limit = _page;
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(notificationScopeProvider).value;
    final isAdmin =
        scope != null &&
        (scope.role == UserRole.schoolAdmin ||
            scope.role == UserRole.branchAdmin ||
            scope.role == UserRole.platformAdmin);
    final isParent = scope?.role == UserRole.parent;
    return Scaffold(
      appBar: pageAppBar(
        context,
        title: Text(isAdmin ? 'Reported conversations' : 'Messages'),
      ),
      floatingActionButton: isParent
          ? FloatingActionButton.extended(
              onPressed: () => context.go(AppRoutes.messageNew),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New conversation'),
            )
          : null,
      body: scope == null
          ? const Center(child: CircularProgressIndicator())
          : isAdmin
          ? _Reported(scope: scope)
          : _Mine(
              scope: scope,
              limit: _limit,
              unreadOnly: _unreadOnly,
              userId: scope.userId,
              onUnreadOnly: (v) => setState(() => _unreadOnly = v),
              onMore: () => setState(() => _limit += _page),
            ),
    );
  }
}

class _Mine extends ConsumerWidget {
  final NotificationScope scope;
  final int limit;
  final bool unreadOnly;
  final String userId;
  final ValueChanged<bool> onUnreadOnly;
  final VoidCallback onMore;

  const _Mine({
    required this.scope,
    required this.limit,
    required this.unreadOnly,
    required this.userId,
    required this.onUnreadOnly,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(conversationListProvider(limit));
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(message: userMessageFor(e)),
      data: (data) {
        final shown = [
          for (final c in data.items)
            if (!unreadOnly || c.unreadFor(userId) > 0) c,
        ];
        return PageColumn(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (scope.role == UserRole.teacher) _ContactCard(scope: scope),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: !unreadOnly,
                    onSelected: (_) => onUnreadOnly(false),
                  ),
                  ChoiceChip(
                    label: Text('Unread (${data.unread})'),
                    selected: unreadOnly,
                    onSelected: (_) => onUnreadOnly(true),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: EmptyView(
                    icon: Icons.forum_outlined,
                    message: 'No conversations yet.',
                  ),
                )
              else
                for (final c in shown) _Tile(conversation: c, userId: userId),
              if (data.mayHaveMore)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: onMore,
                      child: const Text('Load earlier conversations'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final Conversation conversation;
  final String userId;

  const _Tile({required this.conversation, required this.userId});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unreadFor(userId);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        title: Text(
          c.title,
          style: unread > 0
              ? const TextStyle(fontWeight: FontWeight.w600)
              : null,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(c.otherName(userId)),
              Text('about ${c.studentName}'),
              Text(c.subjectName),
              StatusPill(
                label: c.status.displayName,
                icon: c.status == ConversationStatus.open
                    ? Icons.chat_bubble_outline
                    : Icons.lock_outline,
              ),
              if (c.flagged)
                const StatusPill(label: 'Reported', icon: Icons.flag_outlined),
              Text(formatInstant(c.lastMessageAt)),
            ],
          ),
        ),
        trailing: unread > 0
            ? Badge(label: Text('$unread'))
            : const Icon(Icons.chevron_right),
        onTap: () => context.go(
          '${AppRoutes.messageThread.replaceFirst(':conversationId', c.conversationId)}'
          '?branchId=${c.branchId}',
        ),
      ),
    );
  }
}

class _Reported extends ConsumerWidget {
  final NotificationScope scope;
  const _Reported({required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = scope.branchIds.firstOrNull;
    if (branch == null) {
      return const EmptyView(message: 'No branch found for your account.');
    }
    final reported = ref.watch(
      reportedConversationsProvider((
        schoolId: scope.schoolId,
        branchId: branch,
      )),
    );
    return reported.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(reportedConversationsProvider),
      ),
      data: (list) => PageColumn(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'Administrators see a conversation only after one of its '
              'members has reported it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            if (list.isEmpty)
              const EmptyView(
                icon: Icons.flag_outlined,
                message: 'No reported conversations.',
              )
            else
              for (final c in list)
                _Tile(conversation: c, userId: scope.userId),
          ],
        ),
      ),
    );
  }
}

/// A teacher's opt-in: "parents of my sections may message me". Parents find
/// only teachers who have switched this on. What it publishes is where the
/// teacher teaches (their assignment keys) and their name — the security
/// rules still check the real assignment on every conversation.
class _ContactCard extends ConsumerStatefulWidget {
  final NotificationScope scope;
  const _ContactCard({required this.scope});

  @override
  ConsumerState<_ContactCard> createState() => _ContactCardState();
}

class _ContactCardState extends ConsumerState<_ContactCard> {
  bool? _enabled;
  bool _busy = false;
  String? _error;

  Future<void> _set(bool on) async {
    final scope = widget.scope;
    final branchId = scope.branchIds.first;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final staff = await readAlive(
        ref,
        ownStaffProvider((
          schoolId: scope.schoolId,
          branchId: branchId,
          userId: scope.userId,
        )),
      );
      if (staff == null) {
        throw StateError('Your account is not linked to a staff record.');
      }
      final years = await readAlive(
        ref,
        academicYearsProvider((schoolId: scope.schoolId, branchId: branchId)),
      );
      final active = years
          .where((y) => y.status == AcademicYearStatus.active)
          .firstOrNull;
      final scopes = <String>[];
      final sections = <String>{};
      final names = <String, String>{};
      if (active != null) {
        final facts = await readAlive(
          ref,
          yearAssignmentsProvider((
            schoolId: scope.schoolId,
            branchId: branchId,
            academicYearId: active.academicYearId,
          )),
        );
        final subjects = await readAlive(
          ref,
          subjectsProvider((
            schoolId: scope.schoolId,
            branchId: branchId,
            academicYearId: active.academicYearId,
          )),
        );
        final byId = {for (final s in subjects) s.subjectId: s.name};
        for (final f in facts) {
          if (f.teacherStaffId != staff.staffId) continue;
          final sk = MessageContact.sectionKey(
            active.academicYearId,
            f.classId,
            f.sectionId,
          );
          sections.add(sk);
          final subject = f.isClassTeacher ? 'CLASS_TEACHER' : f.subjectId;
          if (subject == null) continue;
          final key = '${sk}__$subject';
          scopes.add(key);
          if (subject != 'CLASS_TEACHER') names[key] = byId[subject] ?? subject;
        }
      }
      await ref
          .read(communicationRepositoryProvider)
          .saveOwnContact(
            schoolId: scope.schoolId,
            branchId: branchId,
            contact: MessageContact(
              staffId: staff.staffId,
              userId: scope.userId,
              name: staff.displayName,
              enabled: on,
              sectionKeys: sections.toList(),
              scopes: scopes,
              subjectNames: names,
            ),
          );
      if (mounted) setState(() => _enabled = on);
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final branchId = scope.branchIds.firstOrNull;
    if (branchId == null) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: _enabled != null
          ? Future.value(_enabled)
          : () async {
              final staff = await readAlive(
                ref,
                ownStaffProvider((
                  schoolId: scope.schoolId,
                  branchId: branchId,
                  userId: scope.userId,
                )),
              );
              if (staff == null) return false;
              final c = await ref
                  .read(communicationRepositoryProvider)
                  .fetchOwnContact(
                    schoolId: scope.schoolId,
                    branchId: branchId,
                    staffId: staff.staffId,
                  );
              return c?.enabled ?? false;
            }(),
      builder: (context, snap) {
        final on = _enabled ?? snap.data ?? false;
        return SectionCard(
          title: 'Parent messages',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Let parents of my sections message me'),
                subtitle: const Text(
                  'Only parents of students you teach (or are class teacher '
                  'of) can start a conversation. You can switch this off at '
                  'any time; existing conversations stay.',
                ),
                value: on,
                onChanged:
                    _busy || snap.connectionState == ConnectionState.waiting
                    ? null
                    : _set,
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        );
      },
    );
  }
}
