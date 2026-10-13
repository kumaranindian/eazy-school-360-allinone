import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../attendance/domain/attendance_date.dart';
import '../../domain/file_attachment.dart';
import '../../domain/homework.dart';
import '../../domain/homework_enums.dart';
import '../../domain/homework_rules.dart';
import '../providers/homework_providers.dart';

/// "03 Aug 2026" for a `yyyy-MM-dd` key.
String formatDateKey(String key) =>
    DateFormat('d MMM y').format(AttendanceDate.parse(key));

String formatInstant(DateTime? at) =>
    at == null ? '—' : DateFormat('d MMM y, h:mm a').format(at.toLocal());

/// "Due 03 Aug 2026, 5:00 PM" (end of day when no time was set).
String dueLabel(Homework h) {
  final date = formatDateKey(h.dueDateKey);
  final min = h.dueTimeMin;
  if (min == null) return 'Due $date';
  final t = DateTime(2000, 1, 1, min ~/ 60, min % 60);
  return 'Due $date, ${DateFormat('h:mm a').format(t)}';
}

/// "12 KB" / "1.4 MB".
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color? color;
  final IconData? icon;

  const StatusPill({super.key, required this.label, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSecondaryContainer;
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? scheme.secondaryContainer).withValues(
            alpha: color == null ? 1 : 0.15,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeworkStatusPill extends StatelessWidget {
  final HomeworkStatus status;
  const HomeworkStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      HomeworkStatus.draft => StatusPill(
        label: status.displayName,
        icon: Icons.edit_outlined,
      ),
      HomeworkStatus.published => StatusPill(
        label: status.displayName,
        icon: Icons.public,
        color: scheme.primary,
      ),
      HomeworkStatus.closed => StatusPill(
        label: status.displayName,
        icon: Icons.lock_outline,
        color: scheme.tertiary,
      ),
      HomeworkStatus.archived => StatusPill(
        label: status.displayName,
        icon: Icons.inventory_2_outlined,
        color: scheme.outline,
      ),
    };
  }
}

class SubmissionStatusPill extends StatelessWidget {
  final SubmissionStatus status;
  final bool late;
  const SubmissionStatusPill(this.status, {super.key, this.late = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      SubmissionStatus.notSubmitted => scheme.outline,
      SubmissionStatus.submitted ||
      SubmissionStatus.resubmitted => scheme.primary,
      SubmissionStatus.lateSubmitted => scheme.error,
      SubmissionStatus.returnedForRevision => scheme.tertiary,
      SubmissionStatus.graded => AppColors.success,
    };
    return StatusPill(
      label: status.displayName,
      color: color,
      icon: switch (status) {
        SubmissionStatus.graded => Icons.check_circle_outline,
        SubmissionStatus.returnedForRevision => Icons.undo,
        SubmissionStatus.lateSubmitted => Icons.schedule,
        SubmissionStatus.notSubmitted => Icons.radio_button_unchecked,
        _ => Icons.upload_file,
      },
    );
  }
}

class FamilyStatePill extends StatelessWidget {
  final FamilyHomeworkState state;
  const FamilyStatePill(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color, icon) = switch (state) {
      FamilyHomeworkState.upcoming => (
        'To do',
        scheme.primary,
        Icons.pending_actions,
      ),
      FamilyHomeworkState.overdue => (
        'Overdue',
        scheme.error,
        Icons.warning_amber,
      ),
      FamilyHomeworkState.submitted => (
        'Submitted',
        AppColors.success,
        Icons.check,
      ),
      FamilyHomeworkState.revision => (
        'Needs revision',
        scheme.tertiary,
        Icons.undo,
      ),
      FamilyHomeworkState.graded => (
        'Graded',
        AppColors.success,
        Icons.grade_outlined,
      ),
      FamilyHomeworkState.noSubmission => (
        'Read only',
        scheme.outline,
        Icons.visibility_outlined,
      ),
    };
    return StatusPill(label: label, color: color, icon: icon);
  }
}

/// Opens an attachment: a short-lived link is minted on demand and works only
/// if the Storage rules allow this caller.
Future<void> openAttachment(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final url = await ref
        .read(homeworkFileStoreProvider)
        .downloadUrl(file.path);
    if (!await launchUrl(Uri.parse(url))) {
      throw StateError('Could not open the file.');
    }
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(userMessageFor(error))));
  }
}

class AttachmentList extends ConsumerWidget {
  final List<FileAttachment> attachments;
  final void Function(FileAttachment file)? onRemove;
  final String emptyLabel;

  const AttachmentList({
    super.key,
    required this.attachments,
    this.onRemove,
    this.emptyLabel = 'No attachments',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachments.isEmpty) {
      return Text(
        emptyLabel,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    return Column(
      children: [
        for (final f in attachments)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              f.contentType.startsWith('image/')
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
            ),
            title: Text(f.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(formatBytes(f.sizeBytes)),
            onTap: () => openAttachment(context, ref, f),
            trailing: onRemove == null
                ? const Icon(Icons.open_in_new, size: 18)
                : IconButton(
                    tooltip: 'Remove ${f.name}',
                    icon: const Icon(Icons.close),
                    onPressed: () => onRemove!(f),
                  ),
          ),
      ],
    );
  }
}

/// A file picked locally and not uploaded yet (a new homework has no record
/// to upload under until its draft exists).
class PendingFile {
  final String name;
  final Uint8List bytes;

  const PendingFile(this.name, this.bytes);
}

/// Picks files and validates them against [FilePolicy]. Returns the accepted
/// files; [onProblem] receives a message for any that were refused.
Future<List<PendingFile>> pickValidatedFiles({
  required int remaining,
  required void Function(String message) onProblem,
}) async {
  if (remaining <= 0) {
    onProblem('You can attach at most ${FilePolicy.maxFilesPerRecord} files.');
    return const [];
  }
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: FilePolicy.extensions,
    allowMultiple: true,
    withData: true,
  );
  if (result == null) return const [];
  final accepted = <PendingFile>[];
  for (final f in result.files) {
    final bytes = f.bytes;
    if (bytes == null) continue;
    final problem = FilePolicy.validate(
      fileName: f.name,
      sizeBytes: bytes.length,
    );
    if (problem != null) {
      onProblem('${f.name}: $problem');
      continue;
    }
    if (accepted.length >= remaining) {
      onProblem('Only $remaining more file(s) can be added.');
      break;
    }
    accepted.add(PendingFile(f.name, bytes));
  }
  return accepted;
}

/// A unique, safe object name: the folders are create-only, so a clash would
/// be refused, and a user-chosen name is never trusted as a path.
String uniqueFileName(String original) =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_'
    '${FilePolicy.safeName(original)}';

/// A titled card section used across the homework screens.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final List<Widget>? actions;

  const SectionCard({super.key, this.title, required this.child, this.actions});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title!,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    ...?actions,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Centres page content in a readable column on wide screens.
class PageColumn extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const PageColumn({super.key, required this.child, this.maxWidth = 860});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

class CountTile extends StatelessWidget {
  final String label;
  final int? value;
  final IconData icon;
  final VoidCallback? onTap;

  const CountTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  value?.toString() ?? '…',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The homework as teachers and families both read it: instructions, rules
/// of submission and attachments. (Status and actions are the page's.)
class HomeworkContent extends StatelessWidget {
  final Homework homework;

  const HomeworkContent({super.key, required this.homework});

  @override
  Widget build(BuildContext context) {
    final h = homework;
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(h.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${h.subjectName} · ${h.classLabel ?? h.classId} · ${h.teacherName}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Assigned ${formatDateKey(h.assignedDateKey)} · ${dueLabel(h)}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          SelectableText(
            h.description.isEmpty ? 'No written instructions.' : h.description,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              StatusPill(
                label: h.maxMarks == null
                    ? 'Not graded'
                    : 'Out of ${h.maxMarks} marks',
                icon: Icons.grade_outlined,
              ),
              StatusPill(
                label: h.requiresSubmission
                    ? 'Submission required'
                    : 'No submission needed',
                icon: Icons.upload_file,
              ),
              if (h.requiresSubmission && h.allowFiles)
                const StatusPill(
                  label: 'Files allowed',
                  icon: Icons.attach_file,
                ),
              if (h.requiresSubmission)
                StatusPill(
                  label: h.allowLate ? 'Late work accepted' : 'No late work',
                  icon: Icons.schedule,
                ),
              if (h.requiresSubmission)
                StatusPill(
                  label: h.allowResubmission
                      ? 'Resubmission allowed'
                      : 'One submission',
                  icon: Icons.replay,
                ),
            ],
          ),
          if (h.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Files', style: theme.textTheme.titleSmall),
            AttachmentList(attachments: h.attachments),
          ],
        ],
      ),
    );
  }
}
