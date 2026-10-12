import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/presentation/widgets/family_scope.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../students/domain/student.dart';
import '../../domain/communication_repository.dart';
import '../../domain/communication_rules.dart';
import '../../domain/conversation.dart';
import '../providers/communication_providers.dart';

/// `/messages/new` — a parent starts a conversation about one of their
/// linked children with a teacher of that child's section. Only teachers who
/// have chosen to accept parent messages are listed; the security rules also
/// check the real assignment and the link when it is saved.
class NewConversationPage extends StatelessWidget {
  const NewConversationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: FamilyScope(
        builder: (context, tenant, children, child) => _Form(
          key: ValueKey(child.studentId),
          child: child,
          parentUserId: tenant.user.userId,
          parentName: tenant.user.name,
          role: tenant.role.wireValue,
        ),
      ),
    );
  }
}

typedef _SectionContactsKey = ({String schoolId, String branchId, String key});

final _contactsProvider = FutureProvider.autoDispose
    .family<List<MessageContact>, _SectionContactsKey>((ref, k) {
      return ref
          .watch(communicationRepositoryProvider)
          .fetchContactsForSection(
            schoolId: k.schoolId,
            branchId: k.branchId,
            sectionKey: k.key,
          );
    });

class _Form extends ConsumerStatefulWidget {
  final Student child;
  final String parentUserId;
  final String parentName;
  final String role;

  const _Form({
    super.key,
    required this.child,
    required this.parentUserId,
    required this.parentName,
    required this.role,
  });

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final String _conversationId = Conversation.newId();
  late final String _messageId = Message.newId();
  (MessageContact, String, String)? _choice; // contact, subjectId, label
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _start(String sectionKey) async {
    if (_sending) return;
    final c = widget.child;
    final choice = _choice;
    if (choice == null) {
      setState(() => _error = 'Choose who to message.');
      return;
    }
    final conversation = Conversation(
      conversationId: _conversationId,
      schoolId: c.schoolId,
      branchId: c.branchId,
      academicYearId: c.currentAcademicYearId!,
      classId: c.currentClassId!,
      sectionId: c.currentSectionId!,
      studentId: c.studentId,
      studentName: c.displayName,
      parentUserId: widget.parentUserId,
      parentName: widget.parentName,
      teacherUserId: choice.$1.userId,
      teacherStaffId: choice.$1.staffId,
      teacherName: choice.$1.name,
      subjectId: choice.$2,
      subjectName: choice.$3,
      title: _title.text,
    );
    final t = CommunicationRules.validateTitle(_title.text);
    if (t != null) {
      setState(() => _error = t);
      return;
    }
    final m = CommunicationRules.validateMessage(_body.text);
    if (m != null) {
      setState(() => _error = m);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      // The ids belong to this form, so pressing Send twice (or retrying
      // after a network error) can create the conversation only once.
      await ref
          .read(communicationRepositoryProvider)
          .start(
            conversation: conversation,
            messageId: _messageId,
            body: _body.text,
            actor: CommunicationActor(
              userId: widget.parentUserId,
              name: widget.parentName,
              role: widget.role,
            ),
          );
      if (!mounted) return;
      context.go(
        '${AppRoutes.messageThread.replaceFirst(':conversationId', _conversationId)}'
        '?branchId=${c.branchId}',
      );
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.child;
    if (c.currentAcademicYearId == null ||
        c.currentClassId == null ||
        c.currentSectionId == null) {
      return const EmptyView(
        icon: Icons.class_outlined,
        message:
            'This child has not been placed in a class and section yet, so '
            'there is no teacher to message.',
      );
    }
    final key = MessageContact.sectionKey(
      c.currentAcademicYearId!,
      c.currentClassId!,
      c.currentSectionId!,
    );
    final contacts = ref.watch(
      _contactsProvider((schoolId: c.schoolId, branchId: c.branchId, key: key)),
    );
    return contacts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: userMessageFor(e),
        onRetry: () => ref.invalidate(_contactsProvider),
      ),
      data: (list) {
        final options = <(MessageContact, String, String)>[
          for (final contact in list)
            for (final (id, label) in contact.subjectsFor(key))
              (contact, id, label),
        ];
        if (options.isEmpty) {
          return const EmptyView(
            icon: Icons.person_search_outlined,
            message:
                'None of this child\'s teachers are taking messages from '
                'parents yet. Please contact the school office.',
          );
        }
        return PageColumn(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SectionCard(
                title: 'About ${c.displayName}',
                child: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      value: _choice == null
                          ? null
                          : options.indexWhere(
                              (o) =>
                                  o.$1.staffId == _choice!.$1.staffId &&
                                  o.$2 == _choice!.$2,
                            ),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Teacher'),
                      items: [
                        for (var i = 0; i < options.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${options[i].$3} — ${options[i].$1.name}',
                            ),
                          ),
                      ],
                      onChanged: _sending
                          ? null
                          : (i) => setState(() => _choice = options[i!]),
                    ),
                    TextField(
                      controller: _title,
                      enabled: !_sending,
                      maxLength: CommunicationRules.maxTitleLength,
                      decoration: const InputDecoration(labelText: 'Subject'),
                    ),
                    TextField(
                      controller: _body,
                      enabled: !_sending,
                      minLines: 4,
                      maxLines: 10,
                      maxLength: CommunicationRules.maxMessageLength,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _sending ? null : () => _start(key),
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                  if (_sending)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Please keep messages about ${c.displayName}\'s schooling. '
                'Either of you can report a conversation; only then can a '
                'school administrator read it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
