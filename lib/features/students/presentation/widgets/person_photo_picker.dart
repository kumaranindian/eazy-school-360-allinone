import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/validators/validators.dart';

/// Photo preview + "Upload/Replace photo" picker for a student or parent —
/// the same shape as `SchoolLogoPicker` (Milestone 2), generalized so it
/// isn't duplicated a second and third time. The caller supplies the
/// actual upload (student vs. parent hit different repository methods);
/// this widget only handles picking, validating, and showing progress/
/// errors.
class PersonPhotoPicker extends StatefulWidget {
  final String? photoUrl;
  final bool isUploading;
  final Future<bool> Function(List<int> bytes, String extension) onUpload;

  /// When given, a "Remove" button appears while a photo is set. Optional so
  /// the student/parent usages (which never offered removal) are unchanged.
  final Future<bool> Function()? onRemove;

  const PersonPhotoPicker({
    super.key,
    required this.photoUrl,
    required this.isUploading,
    required this.onUpload,
    this.onRemove,
  });

  @override
  State<PersonPhotoPicker> createState() => _PersonPhotoPickerState();
}

class _PersonPhotoPickerState extends State<PersonPhotoPicker> {
  Future<void> _pickAndUpload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    final validationError = Validators.imageFile(
      fileName: picked.name,
      sizeBytes: bytes.length,
    );
    if (validationError != null) {
      if (mounted) context.showSnackBar(validationError, isError: true);
      return;
    }

    final extension = picked.name.split('.').last.toLowerCase();
    final success = await widget.onUpload(bytes, extension);

    if (!mounted) return;
    if (success) {
      context.showSnackBar('Photo updated successfully.');
    } else {
      context.showSnackBar(
        'Unable to update the photo. Please try again.',
        isError: true,
      );
    }
  }

  Future<void> _remove() async {
    final success = await widget.onRemove!();
    if (!mounted) return;
    if (success) {
      context.showSnackBar('Photo removed.');
    } else {
      context.showSnackBar(
        'Unable to remove the photo. Please try again.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: context.colors.surfaceContainerHighest,
          backgroundImage: widget.photoUrl != null
              ? NetworkImage(widget.photoUrl!)
              : null,
          child: widget.photoUrl == null
              ? Icon(
                  Icons.person_outline,
                  size: 32,
                  color: context.colors.outline,
                )
              : null,
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: widget.isUploading ? null : _pickAndUpload,
          icon: widget.isUploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_outlined),
          label: Text(
            widget.photoUrl == null ? 'Upload photo' : 'Replace photo',
          ),
        ),
        if (widget.photoUrl != null && widget.onRemove != null) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.isUploading ? null : _remove,
            child: const Text('Remove'),
          ),
        ],
      ],
    );
  }
}
