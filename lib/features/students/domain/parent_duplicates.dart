import 'parent.dart';

/// Why an existing parent record looks like the one being entered.
enum ParentMatchReason { email, phone }

class ParentMatch {
  final Parent parent;
  final Set<ParentMatchReason> reasons;
  const ParentMatch(this.parent, this.reasons);

  /// The same email is the same sign-in identity: a second record with it
  /// could never get its own login (the server answers EMAIL_IN_USE), so it
  /// is refused, exactly as the bulk import refuses it.
  bool get blocksCreate => reasons.contains(ParentMatchReason.email);

  /// "same email, same phone".
  String get reasonText => [
    if (reasons.contains(ParentMatchReason.email)) 'same email',
    if (reasons.contains(ParentMatchReason.phone)) 'same phone',
  ].join(', ');
}

/// Rules for recognising the same parent/guardian entered twice in one
/// branch. Pure, so the admission wizard, the "Add parent" form and tests
/// all share one definition. Bulk import uses the same normalisation
/// (lowercase email, phone digits).
abstract final class ParentContact {
  static String? normalizeEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isEmpty ? null : e;
  }

  static String phoneDigits(String? phone) =>
      (phone ?? '').replaceAll(RegExp(r'\D'), '');

  /// The ways the same number may have been typed on an existing record
  /// (records keep the phone as entered), for an equality query.
  static List<String> phoneVariants(String? phone) {
    final typed = (phone ?? '').trim();
    final digits = phoneDigits(typed);
    if (digits.isEmpty) return const [];
    return {typed, digits, '+$digits'}.toList();
  }

  /// Same number when the digits agree, or when both carry at least ten
  /// digits and the last ten agree (a country code typed on one only).
  static bool samePhone(String? a, String? b) {
    final da = phoneDigits(a);
    final db = phoneDigits(b);
    if (da.length < 7 || db.length < 7) return false;
    if (da == db) return true;
    return da.length >= 10 &&
        db.length >= 10 &&
        da.substring(da.length - 10) == db.substring(db.length - 10);
  }

  /// Existing records that match [email] or [phone], strongest first.
  /// [excludeParentId] is the record being edited.
  static List<ParentMatch> matches({
    required String? email,
    required String? phone,
    required Iterable<Parent> candidates,
    String? excludeParentId,
  }) {
    final wantEmail = normalizeEmail(email);
    final byId = <String, ParentMatch>{};
    for (final p in candidates) {
      if (p.parentId == excludeParentId) continue;
      final reasons = <ParentMatchReason>{
        if (wantEmail != null && normalizeEmail(p.email) == wantEmail)
          ParentMatchReason.email,
        if (samePhone(phone, p.phone)) ParentMatchReason.phone,
      };
      if (reasons.isEmpty) continue;
      final seen = byId[p.parentId];
      byId[p.parentId] = ParentMatch(p, {...?seen?.reasons, ...reasons});
    }
    final out = byId.values.toList()
      ..sort((a, b) {
        if (a.blocksCreate != b.blocksCreate) return a.blocksCreate ? -1 : 1;
        return a.parent.displayName.compareTo(b.parent.displayName);
      });
    return out;
  }
}

/// Finds existing parent records of a branch that may be the same person.
abstract class ParentDuplicateFinder {
  Future<List<ParentMatch>> find({
    required String schoolId,
    required String branchId,
    required String? email,
    required String? phone,
    required String displayName,
    String? excludeParentId,
  });
}
