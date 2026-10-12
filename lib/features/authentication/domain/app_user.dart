/// Authenticated-user shape the rest of the app depends on.
///
/// Deliberately thin — it mirrors what Firebase Auth gives us. Profile
/// data that lives in Firestore (role, schoolId, branchId, ...) belongs to
/// the Users feature once it exists, not here.
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;

  const AppUser({required this.uid, this.email, this.displayName});

  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.uid == uid &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(uid, email, displayName);
}
