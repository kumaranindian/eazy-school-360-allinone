import '../constants/app_constants.dart';

/// Small, composable form-field validators returning a user-facing error
/// string, or `null` when the value is valid — the shape `TextFormField`
/// and friends expect for `validator:`.
abstract final class Validators {
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = required(value, fieldName: 'Email');
    if (requiredError != null) return requiredError;
    if (!_emailPattern.hasMatch(value!.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static final RegExp _phonePattern = RegExp(r'^[0-9+\-\s()]{7,20}$');

  /// Loose on purpose — this app doesn't know every country's phone
  /// format, just that the value looks like a phone number, not garbage.
  static String? phone(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Phone number is required.' : null;
    }
    if (!_phonePattern.hasMatch(value.trim())) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = required(value, fieldName: 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < AppConstants.minPasswordLength) {
      return 'Password must be at least ${AppConstants.minPasswordLength} characters.';
    }
    return null;
  }

  /// For a logo/photo upload — checks extension and size without touching
  /// `dart:io` (keeps this usable on Web, where there is no `File`).
  /// Returns a user-facing message, or `null` if the file is acceptable.
  static String? imageFile({
    required String fileName,
    required int sizeBytes,
    int maxSizeBytes = 2 * 1024 * 1024,
    Set<String> allowedExtensions = const {'jpg', 'jpeg', 'png', 'webp'},
  }) {
    final extension = fileName.split('.').last.toLowerCase();
    if (!allowedExtensions.contains(extension)) {
      return 'Please choose a ${allowedExtensions.join(', ')} image.';
    }
    if (sizeBytes > maxSizeBytes) {
      final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0);
      return 'Image must be smaller than ${maxMb}MB.';
    }
    return null;
  }

  /// Combine multiple validators, returning the first failure.
  static String? Function(String?) combine(
    List<String? Function(String?)> validators,
  ) {
    return (value) {
      for (final validator in validators) {
        final error = validator(value);
        if (error != null) return error;
      }
      return null;
    };
  }
}
