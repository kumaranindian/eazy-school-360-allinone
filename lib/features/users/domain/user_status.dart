/// Account status for a [UserProfile]. The wire value is what's stored on
/// `/users/{uid}.status` and what `firestore.rules` compares against.
enum UserStatus {
  active,
  invited,
  disabled;

  static const Map<UserStatus, String> _wireValues = {
    UserStatus.active: 'ACTIVE',
    UserStatus.invited: 'INVITED',
    UserStatus.disabled: 'DISABLED',
  };

  String get wireValue => _wireValues[this]!;

  static UserStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}
