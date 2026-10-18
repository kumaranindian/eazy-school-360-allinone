import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../homework/domain/file_attachment.dart';
import '../../../homework/presentation/widgets/homework_widgets.dart'
    show formatBytes;
import '../../domain/announcement_file_policy.dart';
import '../../domain/attachment_upload_controller.dart';
import '../providers/announcement_providers.dart';

IconData attachmentIcon(String contentType) {
  if (AnnouncementFilePolicy.isImageType(contentType)) {
    return Icons.image_outlined;
  }
  if (AnnouncementFilePolicy.isPdfType(contentType)) {
    return Icons.picture_as_pdf_outlined;
  }
  if (contentType.contains('spreadsheet') || contentType.contains('excel')) {
    return Icons.table_chart_outlined;
  }
  if (contentType.contains('word')) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}

/// Size of an image tile; tiles wrap, so the same widget fits a phone, a
/// tablet and a desktop column.
const double _tile = 112;

/// An image fetched with a short-lived authorised link, decoded at thumbnail
/// size so a list never holds full-resolution pictures.
class _RemoteImage extends ConsumerStatefulWidget {
  final String path;
  final double? cacheWidth;
  final BoxFit fit;

  const _RemoteImage({required this.path, this.cacheWidth, required this.fit});

  @override
  ConsumerState<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends ConsumerState<_RemoteImage> {
  late final Future<String> _url = ref
      .read(announcementFileUploaderProvider)
      .downloadUrl(widget.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: scheme.outline)),
    );
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) return placeholder(Icons.broken_image_outlined);
        if (!snap.hasData) return placeholder(Icons.image_outlined);
        return Image.network(
          snap.data!,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth?.round(),
          errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder(Icons.image_outlined),
        );
      },
    );
  }
}

/// Opens an attachment. Images open in a zoomable preview; everything else
/// opens in the browser or the device's viewer through a short-lived link
/// that works only if the Storage rules allow this caller.
Future<void> openAnnouncementAttachment(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  if (AnnouncementFilePolicy.isImageType(file.contentType)) {
    await showDialog<void>(
      context: context,
      builder: (_) => _ImagePreview(file: file),
    );
    return;
  }
  await _launch(context, ref, file);
}

Future<void> _launch(
  BuildContext context,
  WidgetRef ref,
  FileAttachment file,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final url = await ref
        .read(announcementFileUploaderProvider)
        .downloadUrl(file.path);
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!ok) throw StateError('This device cannot open the file.');
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error is StateError ? error.message : userMessageFor(error),
        ),
      ),
    );
  }
}

class _ImagePreview extends ConsumerWidget {
  final FileAttachment file;
  const _ImagePreview({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(file.name, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Download ${file.name}',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _launch(context, ref, file),
            ),
          ],
        ),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: _RemoteImage(path: file.path, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

/// Read-only list for the announcement detail screen: thumbnails for images,
/// a typed row for everything else.
class AnnouncementAttachmentsView extends ConsumerWidget {
  final List<FileAttachment> attachments;

  const AnnouncementAttachmentsView({super.key, required this.attachments});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = [
      for (final f in attachments)
        if (AnnouncementFilePolicy.isImageType(f.contentType)) f,
    ];
    final docs = [
      for (final f in attachments)
        if (!AnnouncementFilePolicy.isImageType(f.contentType)) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments (${attachments.length})',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (images.isNotEmpty)
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final f in images)
                Semantics(
                  button: true,
                  label: 'Open image ${f.name}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => openAnnouncementAttachment(context, ref, f),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: _tile,
                        height: _tile,
                        child: _RemoteImage(
                          path: f.path,
                          cacheWidth: _tile * 2,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        for (final f in docs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(attachmentIcon(f.contentType)),
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${_typeLabel(f)} · ${formatBytes(f.sizeBytes)}'),
            onTap: () => openAnnouncementAttachment(context, ref, f),
            trailing: IconButton(
              tooltip: 'Download ${f.name}',
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _launch(context, ref, f),
            ),
          ),
      ],
    );
  }
}

String _typeLabel(FileAttachment f) =>
    (AnnouncementFilePolicy.extensionOf(f.name) ?? 'file').toUpperCase();

/// The Attachments section of the announcement form: pick images or
/// documents, see thumbnails and per-file progress, retry or remove a file.
class AnnouncementAttachmentsEditor extends ConsumerWidget {
  final AttachmentUploadController controller;
  final bool enabled;
  final VoidCallback onPickImages;
  final VoidCallback onPickDocuments;
  final void Function(AttachmentItem item) onRetry;
  final String? hint;

  const AnnouncementAttachmentsEditor({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onPickImages,
    required this.onPickDocuments,
    required this.onRetry,
    this.hint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final images = controller.items.where((i) => i.isImage).toList();
        final docs = controller.items.where((i) => !i.isImage).toList();
        final full = controller.items.length >= AnnouncementFilePolicy.maxFiles;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: enabled && !full ? onPickImages : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Upload images'),
                ),
                OutlinedButton.icon(
                  onPressed: enabled && !full ? onPickDocuments : null,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Upload documents'),
                ),
                Text(
                  '${controller.items.length} of '
                  '${AnnouncementFilePolicy.maxFiles}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (controller.isUploading) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                label: 'Uploading attachments',
                child: LinearProgressIndicator(
                  value: controller.overallProgress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
            if (images.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [for (final i in images) _imageTile(context, i)],
              ),
            ],
            for (final i in docs) _docTile(context, i),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hint ??
                  'Images (JPG, PNG, WebP) and documents (PDF, Word, Excel, '
                      'TXT), up to ${AnnouncementFilePolicy.maxBytes ~/ (1024 * 1024)} MB each. '
                      'Files are not scanned for malware.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }

  Widget _status(BuildContext context, AttachmentItem i) {
    final scheme = Theme.of(context).colorScheme;
    switch (i.state) {
      case AttachmentState.uploading:
        return LinearProgressIndicator(value: i.progress, minHeight: 4);
      case AttachmentState.failed:
        return Text(
          i.error ?? 'Upload failed.',
          style: TextStyle(color: scheme.error, fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      case AttachmentState.queued:
        return Text(
          i.bytes == null ? 'Saved' : 'Uploads when you save',
          style: const TextStyle(fontSize: 12),
        );
      case AttachmentState.uploaded:
        return Text(
          i.persisted ? 'Saved' : 'Uploaded',
          style: const TextStyle(fontSize: 12),
        );
    }
  }

  Widget _actions(AttachmentItem i) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (i.state == AttachmentState.failed)
        IconButton(
          tooltip: 'Retry ${i.name}',
          icon: const Icon(Icons.refresh),
          onPressed: enabled ? () => onRetry(i) : null,
        ),
      IconButton(
        tooltip: 'Remove ${i.name}',
        icon: const Icon(Icons.close),
        onPressed: enabled && i.state != AttachmentState.uploading
            ? () => controller.remove(i)
            : null,
      ),
    ],
  );

  Widget _imageTile(BuildContext context, AttachmentItem i) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _tile + 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: _tile + 8,
                  height: _tile,
                  child: i.bytes != null
                      ? Image.memory(
                          i.bytes!,
                          fit: BoxFit.cover,
                          cacheWidth: (_tile * 2).round(),
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        )
                      : _RemoteImage(
                          path: i.file!.path,
                          cacheWidth: _tile * 2,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              Positioned(top: 0, right: 0, child: _actions(i)),
            ],
          ),
          Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          _status(context, i),
        ],
      ),
    );
  }

  Widget _docTile(BuildContext context, AttachmentItem i) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(attachmentIcon(i.contentType)),
    title: Text(i.name, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(formatBytes(i.sizeBytes)), _status(context, i)],
    ),
    trailing: _actions(i),
  );
}
