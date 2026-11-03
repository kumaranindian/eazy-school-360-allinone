/// The standard employee code: `EMP-<sequence>`, e.g. `EMP-0001`. One running
/// series per branch, zero-padded to four digits (it simply grows wider after
/// 9999). Used by the Add staff form. Codes typed in older styles never break
/// the count: only plain `EMP-<digits>` codes are counted.
///
/// Pure: [EmployeeCodeSource] supplies the highest sequence in use.
class EmployeeCodeFormat {
  const EmployeeCodeFormat._();

  static const String prefix = 'EMP-';
  static const int padding = 4;

  static final RegExp _pattern = RegExp(r'^EMP-(\d+)$', caseSensitive: false);

  static String format(int sequence) =>
      '$prefix${sequence.toString().padLeft(padding, '0')}';

  /// The sequence of [code] when it is exactly `EMP-<digits>` (any case),
  /// else null.
  static int? sequenceOf(String? code) {
    final m = _pattern.firstMatch((code ?? '').trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// The highest sequence among [codes], or 0 when none follow the format.
  static int highest(Iterable<String?> codes) {
    var best = 0;
    for (final c in codes) {
      final s = sequenceOf(c);
      if (s != null && s > best) best = s;
    }
    return best;
  }
}

abstract class EmployeeCodeSource {
  /// The highest `EMP-<digits>` sequence already used in the branch, or 0.
  Future<int> highestSequence({
    required String schoolId,
    required String branchId,
  });

  /// The next free code in the branch.
  Future<String> nextCode({
    required String schoolId,
    required String branchId,
  }) async => EmployeeCodeFormat.format(
    await highestSequence(schoolId: schoolId, branchId: branchId) + 1,
  );
}
