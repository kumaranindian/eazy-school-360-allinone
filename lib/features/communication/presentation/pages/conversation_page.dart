import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../homework/domain/file_attachment.dart';
import '../../../homework/presentation/providers/homework_providers.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../domain/communication_repository.dart';
import '../../domain/communication_rules.dart';
import '../../domain/conversation.dart';
import '../providers/communication_providers.dart';

const _page = 30;

/// `/messages/:conversationId?branchId=…` — one conversation.
///
/// Opening it does not trust the link: the conversation and its messages are
/// read through the security rules, so a deleted conversation, or one the
/// user is not a member of, simply shows "not available".
class ConversationPage extends ConsumerStatefulWidget {
  final String conversationId;
  final String? branchId;

  const ConversationPage({
    super.key,
    required this.conversationId,
    this.branchId,
  });

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final List<FileAttachment> _files = [];
  int _limit = _page;
  String? _pendingId;
  bool _sending = false;
  bool _uploading = false;
  bool _marking = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(Conversation c, CommunicationActor actor) async {
    if (_sending) return;
    final problem = CommunicationRules.validateMessage(
      _text.text,
      attachments: _files,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    // One id per compose attempt: a retry after a failure re-uses it, so the
    // message can exist once however many times Send is pressed.
    final id = _pendingId ??= Message.newId();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(communicationRepositoryProvider)
          .send(
            conversation: c,
            messageId: id,
            body: _text.text,
            attachments: List.of(_files),
            actor: actor,
          );
      if (!mounted) return;
      setState(() {
        _text.clear();
        _files.clear();
        _pendingId = null;
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '${userMessageFor(e)} Your message was not '
              'sent — press Send to try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach(Conversation c, CommunicationActor actor) async {
    final remaining = CommunicationRules.maxAttachments - _files.length;
    final picked = await pickValidatedFiles(
      remaining: remaining,
      onProblem: (m) {
        if (mounted) setState(() => _error = m);
      },
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      for (final f in picked) {
        _files.add(
          await ref
              .read(homeworkFileStoreProvider)
              .upload(
                path:
                    'schools/${c.schoolId}/branches/${c.branchId}/'
                    'conversations/${c.conversationId}/files/'
                    '${uniqueFileName(f.name)}',
                fileName: f.name,
                bytes: f.bytes,
                uploadedBy: actor.userId,
              ),
        );
      }
    } catch (e) {
      _error = userMessageFor(e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _history(Conversation c) async {
    final events = await ref.read(
      conversationEventsProvider((
        schoolId: c.schoolId,
        branchId: c.branchId,
        conversationId: c.conversationId,
      )).future,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conversation history'),
        content: SizedBox(
          width: 400,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in events)
                ListTile(
                  dense: true,
                  title: Text(
                    '${e.event.toLowerCase()} → ${e.toStatus.toLowerCase()}',
                  ),
                  subtitle: Text(
                    '${e.actorName} · ${formatInstant(e.at)}'
                    '${e.note == null ? '' : '\n${e.note}'}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(notificationScopeProvider).value;
    if (scope == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final branchId = widget.branchId ?? scope.branchIds.firstOrNull;
    if (branchId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversation')),
        body: const EmptyView(message: 'No branch found for your account.'),
      );
    }
    final key = (
      schoolId: scope.schoolId,
      branchId: branchId,
      conversationId: widget.conversationId,
    );
    final conv = ref.watch(conversationProvider(key));
    final actor = CommunicationActor(
      userId: scope.userId,
      name: ref.watch(tenantContextProvider).value?.user.name ?? '',
      role: scope.role.wireValue,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(conv.value?.title ?? 'Conversation'),
        actions: [
          if (conv.value != null)
            PopupMenuButton<String>(
              tooltip: 'Conversation actions',
              onSelected: (v) async {
                final c = conv.value!;
                final repo = ref.read(communicationRepositoryProvider);
                switch (v) {
                  case 'close':
                    if (await _confirm(
                      'Close this conversation?',
                      'No one can send messages until a teacher reopens it.',
                      'Close',
                    )) {
                      await _run(
                        () => repo.close(conversation: c, actor: actor),
                        'Conversation closed.',
                      );
                    }
                  case 'reopen':
                    await _run(
                      () => repo.reopen(conversation: c, actor: actor),
                      'Conversation reopened.',
                    );
                  case 'archive':
                    if (await _confirm(
                      'Archive this conversation?',
                      'It stays on record but leaves your active list.',
                      'Archive',
                    )) {
                      await _run(
                        () => repo.archive(conversation: c, actor: actor),
                        'Conversation archived.',
                      );
                    }
                  case 'report':
                    final reason = await _reason();
                    if (reason != null) {
                      await _run(
                        () => repo.report(
                          conversation: c,
                          reason: reason,
                          actor: actor,
                        ),
                        'Reported. An administrator can now review it.',
                      );
                    }
                  case 'history':
                    await _history(c);
                }
              },
              itemBuilder: (_) {
                final c = conv.value!;
                final member = c.isMember(scope.userId);
                return [
                  if (member && c.status == ConversationStatus.open)
                    const PopupMenuItem(value: 'close', child: Text('Close')),
                  if (CommunicationRules.checkReopen(c, scope.userId) == null)
                    const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                  if (CommunicationRules.checkArchive(c, scope.userId) == null)
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Archive'),
                    ),
                  if (member && !c.flagged)
                    const PopupMenuItem(
                      value: 'report',
                      child: Text('Report this conversation'),
                    ),
                  const PopupMenuItem(value: 'history', child: Text('History')),
                ];
              },
            ),
        ],
      ),
      body: conv.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const EmptyView(
          icon: Icons.lock_outline,
          message: 'This conversation is not available.',
        ),
        data: (c) {
          if (c == null) {
            return const EmptyView(
              icon: Icons.search_off,
              message: 'This conversation is not available.',
            );
          }
          return _thread(c, scope, actor);
        },
      ),
    );
  }

  Future<String?> _reason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report this conversation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'What is wrong?',
            helperText:
                'An administrator will be able to read this conversation.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 3) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  Widget _thread(
    Conversation c,
    NotificationScope scope,
    CommunicationActor actor,
  ) {
    final messages = ref.watch(
      messagesProvider((
        schoolId: c.schoolId,
        branchId: c.branchId,
        conversationId: c.conversationId,
        limit: _limit,
      )),
    );
    // Reading clears the reader's own unread counter, once per change.
    if (c.isMember(scope.userId) &&
        c.unreadFor(scope.userId) > 0 &&
        !_marking) {
      _marking = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await ref
              .read(communicationRepositoryProvider)
              .markRead(conversation: c, actor: actor);
        } catch (_) {
          // Not being able to mark read is not worth interrupting reading.
        } finally {
          _marking = false;
        }
      });
    }
    final canSend = CommunicationRules.checkSend(c, scope.userId) == null;
    return PageColumn(
      maxWidth: 760,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('With ${c.otherName(scope.userId)}'),
                Text('about ${c.studentName}'),
                Text(c.subjectName),
                StatusPill(label: c.status.displayName),
                if (c.flagged)
                  const StatusPill(
                    label: 'Reported',
                    icon: Icons.flag_outlined,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(message: userMessageFor(e)),
              data: (list) => ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  if (list.length >= _limit)
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() => _limit += _page),
                        child: const Text('Load earlier messages'),
                      ),
                    ),
                  if (list.isEmpty)
                    const EmptyView(
                      icon: Icons.chat_bubble_outline,
                      message: 'No messages yet.',
                    ),
                  for (final m in list)
                    _Bubble(message: m, mine: m.senderUserId == scope.userId),
                ],
              ),
            ),
          ),
          if (!canSend && c.isMember(scope.userId))
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                CommunicationRules.checkSend(c, scope.userId) ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (canSend) _composer(c, actor),
        ],
      ),
    );
  }

  Widget _composer(Conversation c, CommunicationActor actor) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_files.isNotEmpty)
              AttachmentList(
                attachments: _files,
                onRemove: _sending
                    ? null
                    : (f) => setState(() => _files.remove(f)),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Attach a file',
                  onPressed: _sending || _uploading
                      ? null
                      : () => _attach(c, actor),
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        control: true,
                      ): () =>
                          _send(c, actor),
                    },
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: CommunicationRules.maxMessageLength,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        helperText: 'Ctrl+Enter sends',
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: _sending ? null : () => _send(c, actor),
                  icon: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    _pendingId != null && _error != null ? 'Retry' : 'Send',
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

class _Bubble extends StatelessWidget {
  final Message message;
  final bool mine;

  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          color: mine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mine ? 'You' : message.senderName,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 2),
                SelectableText(message.body),
                if (message.attachments.isNotEmpty)
                  AttachmentList(attachments: message.attachments),
                const SizedBox(height: 2),
                Text(
                  formatInstant(message.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
