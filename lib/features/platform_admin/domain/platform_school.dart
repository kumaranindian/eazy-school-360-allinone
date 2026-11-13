/// A school as the platform directory lists it: metadata only.
class PlatformSchool {
  final String id;
  final String name;
  final String code;
  final String status;
  final String city;
  final String country;
  final DateTime? createdAt;

  const PlatformSchool({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.city,
    required this.country,
    required this.createdAt,
  });

  bool get isActive => status == 'ACTIVE';

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        code.toLowerCase().contains(q) ||
        city.toLowerCase().contains(q) ||
        id.toLowerCase() == q;
  }
}
