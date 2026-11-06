/// A person's name as the form collects it (one "Full name" field) split into
/// the first / middle / last parts the student record stores.
///
/// * one word        -> first name only (the form then asks for a last name);
/// * two words       -> first and last;
/// * three or more   -> first, last, and everything in between as the middle.
///
/// Extra spaces are ignored. This is a presentation convenience: the stored
/// fields and the display name are unchanged.
class StudentNameParts {
  final String first;
  final String? middle;
  final String last;

  const StudentNameParts({required this.first, this.middle, this.last = ''});

  bool get isEmpty => first.isEmpty;

  /// The admission form asks for at least a first and a last name (as the
  /// previous three-field form did).
  bool get isComplete => first.isNotEmpty && last.isNotEmpty;

  /// "First Middle Last" with single spaces.
  String get full => [
    first,
    middle,
    last,
  ].whereType<String>().where((p) => p.isNotEmpty).join(' ');

  factory StudentNameParts.split(String input) {
    final words = input
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const StudentNameParts(first: '');
    if (words.length == 1) return StudentNameParts(first: words.first);
    if (words.length == 2) {
      return StudentNameParts(first: words.first, last: words.last);
    }
    return StudentNameParts(
      first: words.first,
      middle: words.sublist(1, words.length - 1).join(' '),
      last: words.last,
    );
  }
}
