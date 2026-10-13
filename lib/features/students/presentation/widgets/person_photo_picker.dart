import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../../shared/media/image_pick.dart';

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

  /// Returns the error behind the last failed [onUpload] (the write
  /// controller's state), so the user is told why rather than just "unable".
  final Object? Function()? readError;

  const PersonPhotoPicker({
    super.key,
    required this.photoUrl,
    required this.isUploading,
    required this.onUpload,
    this.onRemove,
    this.readError,
  });

  @override
  State<PersonPhotoPicker> createState() => _PersonPhotoPickerState();
}

class _PersonPhotoPickerState extends State<PersonPhotoPicker> {
  Future<void> _pickAndUpload() async {
    final result = await pickImageForUpload();
    if (!mounted) return;
    final image = result.image;
    if (image == null) {
      if (result.error != null) {
        context.showSnackBar(result.error!, isError: true);
      }
      return;
    }

    final success = await widget.onUpload(image.bytes, image.extension);

    if (!mounted) return;
    if (success) {
      context.showSnackBar('Photo updated successfully.');
    } else {
      final error = widget.readError?.call();
      context.showSnackBar(
        error == null
            ? 'Unable to update the photo. Please try again.'
            : userMessageFor(error),
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
