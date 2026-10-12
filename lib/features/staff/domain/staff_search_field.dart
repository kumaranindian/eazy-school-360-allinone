/// Which field a staff search term is matched against (prefix match).
/// Each maps to one indexed, normalized Firestore field, so a search is a
/// bounded range query — never a scan.
enum StaffSearchField {
  name('Name', 'displayNameLower'),
  employeeCode('Employee code', 'employeeCodeLower'),
  phone('Phone', 'phone'),
  email('Email', 'emailLower');

  final String label;
  final String firestoreField;

  const StaffSearchField(this.label, this.firestoreField);

  /// Phone numbers are stored as typed, so only trimmed; the rest are
  /// stored lower-cased.
  String normalize(String query) {
    final trimmed = query.trim();
    return this == StaffSearchField.phone ? trimmed : trimmed.toLowerCase();
  }
}
