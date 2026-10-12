/// A student's gender, as recorded on admission. The wire value is what's
/// stored on `Student.gender` and compared nowhere in `firestore.rules` —
/// this is a data field, not an authorization input.
enum Gender {
  male,
  female,
  other;

  static const Map<Gender, String> _wireValues = {
    Gender.male: 'MALE',
    Gender.female: 'FEMALE',
    Gender.other: 'OTHER',
  };

  String get wireValue => _wireValues[this]!;

  static Gender fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case Gender.male:
        return 'Male';
      case Gender.female:
        return 'Female';
      case Gender.other:
        return 'Other';
    }
  }
}
