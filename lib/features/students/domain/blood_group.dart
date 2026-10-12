/// Optional, informational only — not validated against any medical
/// record. Nullable on [Student] rather than carrying its own "unknown"
/// value.
enum BloodGroup {
  aPositive,
  aNegative,
  bPositive,
  bNegative,
  abPositive,
  abNegative,
  oPositive,
  oNegative;

  static const Map<BloodGroup, String> _wireValues = {
    BloodGroup.aPositive: 'A_POSITIVE',
    BloodGroup.aNegative: 'A_NEGATIVE',
    BloodGroup.bPositive: 'B_POSITIVE',
    BloodGroup.bNegative: 'B_NEGATIVE',
    BloodGroup.abPositive: 'AB_POSITIVE',
    BloodGroup.abNegative: 'AB_NEGATIVE',
    BloodGroup.oPositive: 'O_POSITIVE',
    BloodGroup.oNegative: 'O_NEGATIVE',
  };

  static const Map<BloodGroup, String> _displayNames = {
    BloodGroup.aPositive: 'A+',
    BloodGroup.aNegative: 'A-',
    BloodGroup.bPositive: 'B+',
    BloodGroup.bNegative: 'B-',
    BloodGroup.abPositive: 'AB+',
    BloodGroup.abNegative: 'AB-',
    BloodGroup.oPositive: 'O+',
    BloodGroup.oNegative: 'O-',
  };

  String get wireValue => _wireValues[this]!;

  String get displayName => _displayNames[this]!;

  static BloodGroup fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}
