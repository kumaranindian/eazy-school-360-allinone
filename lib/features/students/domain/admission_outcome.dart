/// What the admission screen tells the user once the student record exists.
///
/// Admitting creates the student first and then (optionally) a guardian and
/// the link between them, as separate writes. If the second part fails the
/// student is still admitted, so the message must not claim a clean success.
class AdmissionOutcome {
  const AdmissionOutcome._();

  static String message({
    required String studentName,
    required bool guardianLinked,
    String? guardianError,
  }) {
    if (guardianLinked) return '$studentName admitted successfully.';
    final reason = guardianError == null ? '' : ' ($guardianError)';
    return '$studentName was admitted, but the guardian could not be '
        'linked$reason. Open the profile to link a guardian.';
  }
}
