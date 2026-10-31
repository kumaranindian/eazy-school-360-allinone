/// The standard admission number: `ADM-<sequence>`, e.g. `ADM-0001`. One
/// running series per branch, zero-padded to four digits (it simply grows
/// wider after 9999). Used by the single admission form and the sheet upload.
///
/// Pure: [AdmissionNumberSource] supplies the highest sequence in use.
class AdmissionNumberFormat {
  const AdmissionNumberFormat._();

  static const String prefix = 'ADM-';
  static const int padding = 4;

  static final RegExp _pattern = RegExp(r'^ADM-(\d+)$');

  static String format(int sequence) =>
      '$prefix${sequence.toString().padLeft(padding, '0')}';

  /// The sequence of [number] when it is exactly `ADM-<digits>`, else null
  /// (so differently styled older numbers never break the count).
  static int? sequenceOf(String? number) {
    final m = _pattern.firstMatch((number ?? '').trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// The highest sequence among [numbers], or 0 when none follow the format.
  static int highest(Iterable<String?> numbers) {
    var best = 0;
    for (final n in numbers) {
      final s = sequenceOf(n);
      if (s != null && s > best) best = s;
    }
    return best;
  }
}

abstract class AdmissionNumberSource {
  /// The highest `ADM-<digits>` sequence already used in the branch, or 0.
  Future<int> highestSequence({
    required String schoolId,
    required String branchId,
  });

  /// The next free number in the branch.
  Future<String> nextNumber({
    required String schoolId,
    required String branchId,
  }) async => AdmissionNumberFormat.format(
    await highestSequence(schoolId: schoolId, branchId: branchId) + 1,
  );
}
