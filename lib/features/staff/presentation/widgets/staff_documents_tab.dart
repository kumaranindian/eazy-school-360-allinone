import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/staff.dart';
import '../../domain/staff_document.dart';
import '../providers/staff_providers.dart';

/// Basic document foundation (brief §28): upload a file with a type and
/// title, list them, open them, remove them. Metadata lives in Firestore,
/// the file in Storage; there is no approval workflow, expiry tracking or
/// versioning — that is a later HR milestone.
class StaffDocumentsTab extends ConsumerStatefulWidget {
  final Staff staff;
  final String currentUserId;

  const StaffDocumentsTab({
    super.key,
    required this.staff,
    required this.currentUserId,
  });

  @override
  ConsumerState<StaffDocumentsTab> createState() => _StaffDocumentsTabState();
}

class _StaffDocumentsTabState extends ConsumerState<StaffDocumentsTab> {
  StaffDocumentType _type = StaffDocumentType.idProof;
  final _title = TextEditingController();
  bool _isUploading = false;

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: StaffDocument.allowedExtensions.toList(),
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;

    final validationError = StaffDocument.validateFile(
      fileName: file.name,
      sizeBytes: bytes.length,
    );
    if (validationError != null) {
      context.showSnackBar(validationError, isError: true);
      return;
    }

    setState(() => _isUploading = true);
    final title = _title.text.trim().isEmpty ? file.name : _title.text.trim();
    final success = await ref
        .read(staffWriteControllerProvider.notifier)
        .uploadDocument(
          widget.staff,
          type: _type,
          title: title,
          fileName: file.name,
          bytes: bytes,
          createdBy: widget.currentUserId,
        );
    if (!mounted) return;
    setState(() => _isUploading = false);
    if (success) {
      _title.clear();
      context.showSnackBar('Document uploaded successfully.');
    } else {
      final error = ref.read(staffWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to upload the document.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  Future<void> _open(StaffDocument document) async {
    try {
      final url = await ref
          .read(staffRepositoryProvider)
          .getDocumentDownloadUrl(document.storagePath);
      if (!await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ) &&
          mounted) {
        context.showSnackBar('Unable to open this document.', isError: true);
      }
    } catch (error) {
      if (mounted) context.showSnackBar(userMessageFor(error), isError: true);
    }
  }

  Future<void> _remove(StaffDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text('"${document.title}" will be hidden from this profile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await ref
        .read(staffWriteControllerProvider.notifier)
        .removeDocument(document, updatedBy: widget.currentUserId);
    if (!mounted) return;
    if (success) {
      context.showSnackBar('Document removed.');
    } else {
      final error = ref.read(staffWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to remove the document.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  static String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';

  @override
  Widget build(BuildContext context) {
    final key = (
      schoolId: widget.staff.schoolId,
      branchId: widget.staff.branchId,
      staffId: widget.staff.staffId,
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<StaffDocumentType>(
                value: _type,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Document type',
                  isDense: true,
                ),
                items: [
                  for (final t in StaffDocumentType.values)
                    DropdownMenuItem(value: t, child: Text(t.displayName)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title (optional)',
                  isDense: true,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _isUploading ? null : _pickAndUpload,
              icon: _isUploading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: const Text('Upload'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'PDF, JPG or PNG, up to 5 MB.',
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        AsyncValueWidget(
          value: ref.watch(staffDocumentsProvider(key)),
          errorMessage: userMessageFor,
          data: (documents) {
            if (documents.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: EmptyView(
                  icon: Icons.folder_open_outlined,
                  message: 'No documents uploaded yet.',
                ),
              );
            }
            return Column(
              children: [
                for (final document in documents)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        document.contentType == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined,
                      ),
                      title: Text(document.title),
                      subtitle: Text(
                        [
                          document.type.displayName,
                          _size(document.sizeBytes),
                          if (document.createdAt != null)
                            formatInstant(document.createdAt),
                        ].join(' · '),
                      ),
                      onTap: () => _open(document),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.open_in_new),
                            tooltip: 'Open',
                            onPressed: () => _open(document),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => _remove(document),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
