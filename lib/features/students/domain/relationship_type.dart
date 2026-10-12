/// A [ParentStudentLink]'s relationship to the student. Lives on the
/// relationship, not on [Parent] — the same person can be recorded
/// differently for different children (e.g. "guardian" for one, "father"
/// for another), so putting it on the parent record itself would be the
/// same "two identifiers with overlapping purpose" mistake the brief
/// warns against for admission number vs. student code.
enum RelationshipType {
  father,
  mother,
  guardian,
  other;

  static const Map<RelationshipType, String> _wireValues = {
    RelationshipType.father: 'FATHER',
    RelationshipType.mother: 'MOTHER',
    RelationshipType.guardian: 'GUARDIAN',
    RelationshipType.other: 'OTHER',
  };

  String get wireValue => _wireValues[this]!;

  static RelationshipType fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case RelationshipType.father:
        return 'Father';
      case RelationshipType.mother:
        return 'Mother';
      case RelationshipType.guardian:
        return 'Guardian';
      case RelationshipType.other:
        return 'Other';
    }
  }
}
