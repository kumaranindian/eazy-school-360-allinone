/// A school as the platform directory lists it: metadata only.
class PlatformSchool {
  final String id;
  final String name;
  final String code;
  final String status;
  final String city;
  final String country;
  final DateTime? createdAt;
  final String email;

  const PlatformSchool({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.city,
    required this.country,
    required this.createdAt,
    this.email = '',
  });

  bool get isActive => status == 'ACTIVE';

  /// Registered in the last [days] days (an unknown date never matches).
  bool registeredWithin(int days, DateTime now) =>
      createdAt != null && now.difference(createdAt!).inDays < days;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        code.toLowerCase().contains(q) ||
        city.toLowerCase().contains(q) ||
        email.toLowerCase().contains(q) ||
        id.toLowerCase() == q;
  }
}
