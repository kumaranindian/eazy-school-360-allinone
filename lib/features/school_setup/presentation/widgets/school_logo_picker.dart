import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/media/image_pick.dart';
import '../providers/school_profile_providers.dart';

/// Logo preview + "Change logo" picker. The image is picked, scaled down and
/// validated by [pickImageForUpload], which reads bytes via
/// [XFile.readAsBytes] (not `dart:io File`) so this works unchanged on Web.
class SchoolLogoPicker extends ConsumerStatefulWidget {
  final String schoolId;
  final String? logoUrl;
  final String updatedBy;

  const SchoolLogoPicker({
    super.key,
    required this.schoolId,
    required this.logoUrl,
    required this.updatedBy,
  });

  @override
  ConsumerState<SchoolLogoPicker> createState() => _SchoolLogoPickerState();
}

class _SchoolLogoPickerState extends ConsumerState<SchoolLogoPicker> {
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

    final success = await ref
        .read(schoolProfileWriteControllerProvider.notifier)
        .uploadLogo(
          schoolId: widget.schoolId,
          fileBytes: image.bytes,
          fileExtension: image.extension,
          updatedBy: widget.updatedBy,
        );

    if (!mounted) return;
    if (success) {
      context.showSnackBar('Logo updated successfully.');
    } else {
      final error = ref.read(schoolProfileWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to update the logo. Please try again.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUploading = ref
        .watch(schoolProfileWriteControllerProvider)
        .isLoading;

    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: context.colors.surfaceContainerHighest,
          backgroundImage: widget.logoUrl != null
              ? NetworkImage(widget.logoUrl!)
              : null,
          child: widget.logoUrl == null
              ? Icon(
                  Icons.school_outlined,
                  size: 32,
                  color: context.colors.outline,
                )
              : null,
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: isUploading ? null : _pickAndUpload,
          icon: isUploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_outlined),
          label: Text(widget.logoUrl == null ? 'Upload logo' : 'Replace logo'),
        ),
      ],
    );
  }
}
