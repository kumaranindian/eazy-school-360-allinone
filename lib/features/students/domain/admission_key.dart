/// The reservation key of an admission number (ACAD-2).
///
/// Each number is reserved by a document `admissionNumbers/{key}` created in
/// the same batch as the student who holds it, so "one admission number per
/// branch" is enforced by the database (a create-only document can only be
/// written once) instead of by a check-then-write that two admins can race.
///
/// The key is case- and space-insensitive (`ADM-001`, `adm-001 ` and
/// `Adm-001` are the same number). `/` cannot appear in a document id, so it
/// maps to `~`. `firestore.rules` computes the very same key
/// (`admissionKey()`), so keep the two in step.
class AdmissionKey {
  const AdmissionKey._();

  static const int maxLength = 60;

  /// The number as entered, after trimming; what a student record stores.
  static String clean(String number) => number.trim();

  static String of(String number) =>
      clean(number).toLowerCase().replaceAll('/', '~');

  /// A problem with [number] as an admission number, or null.
  static String? validate(String number) {
    final n = clean(number);
    if (n.isEmpty) return 'Enter the admission number.';
    if (n.length > maxLength) {
      return 'Admission number can be at most $maxLength characters.';
    }
    if (!RegExp(r'^[A-Za-z0-9#]').hasMatch(n) || n.contains('\n')) {
      return 'Admission number must start with a letter or digit.';
    }
    return null;
  }
}
