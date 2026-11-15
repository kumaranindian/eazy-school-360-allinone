/// An expense category. Categories are never deleted (expenses refer to
/// them); they are switched off. A [system] category (Salaries) is used by
/// other modules and cannot be renamed or switched off.
library;

class ExpenseCategory {
  final String id;
  final String name;
  final bool active;
  final bool system;

  const ExpenseCategory({
    required this.id,
    required this.name,
    this.active = true,
    this.system = false,
  });

  factory ExpenseCategory.fromMap(Map<String, dynamic> m) => ExpenseCategory(
    id: (m['id'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    active: m['active'] != false,
    system: m['system'] == true,
  );

  /// Pure validation shared by the form: null when [name] is acceptable.
  static String? validateName(
    String name,
    Iterable<ExpenseCategory> existing, {
    String? exceptId,
  }) {
    final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.length < 2 || n.length > 60) return 'Use 2 to 60 characters.';
    final taken = existing.any(
      (c) => c.id != exceptId && c.name.toLowerCase() == n.toLowerCase(),
    );
    return taken ? 'A category with that name already exists.' : null;
  }
}
