/// Preview-time check used by the bulk imports: is this (normalised) email
/// already on a staff or parent record of the branch? Accounts that exist
/// outside those records are caught when the login is created (the server
/// reports EMAIL_IN_USE per person, never merging).
abstract class EmailLookup {
  Future<bool> staffEmailInUse(String schoolId, String branchId, String email);
  Future<bool> parentEmailInUse(String schoolId, String branchId, String email);
}
