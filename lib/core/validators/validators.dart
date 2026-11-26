import '../constants/app_constants.dart';

/// Small, composable form-field validators returning a user-facing error
/// string, or `null` when the value is valid — the shape `TextFormField`
/// and friends expect for `validator:`.
abstract final class Validators {
  // Local part: the RFC 5322 "atext" characters and single dots (no
  // leading, trailing or doubled dot). Domain: dot-separated labels of
  // letters, digits and inner hyphens, ending in a 2+ letter top-level
  // domain. Rejects markup such as `<script>` before it reaches a record.
  static final RegExp _emailPattern = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r'@([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$',
  );

  /// RFC 5321 limits.
  static const int _maxEmailLocalPart = 64;
  static const int _maxEmailLength = 254;

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = required(value, fieldName: 'Email');
    if (requiredError != null) return requiredError;
    final email = value!.trim();
    final at = email.lastIndexOf('@');
    if (email.length > _maxEmailLength ||
        at > _maxEmailLocalPart ||
        !_emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static final RegExp _phonePattern = RegExp(r'^\+?[0-9\-\s()]{7,20}$');

  /// Loose on purpose — this app doesn't know every country's phone
  /// format, just that the value looks like a phone number, not garbage:
  /// digits with optional spaces, hyphens, brackets and one leading `+`,
  /// and 7 to 15 digits in all (the E.164 maximum).
  static String? phone(String? value, {bool required = false}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Phone number is required.' : null;
    }
    final trimmed = value.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '').length;
    if (!_phonePattern.hasMatch(trimmed) || digits < 7 || digits > 15) {
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

  /// A password being chosen (sign-up, first-sign-in change, admin-defined):
  /// at least [AppConstants.minPasswordLength] characters with a letter and
  /// a number. Signing in uses [password], so existing passwords still work.
  static String? newPassword(String? value) {
    final requiredError = required(value, fieldName: 'Password');
    if (requiredError != null) return requiredError;
    return newPasswordProblem(value!);
  }

  /// The [newPassword] rule without the "required" check.
  static String? newPasswordProblem(String value) {
    if (value.length < AppConstants.minPasswordLength) {
      return 'Use at least ${AppConstants.minPasswordLength} characters.';
    }
    if (!RegExp('[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
      return 'Include at least one letter and one number.';
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
