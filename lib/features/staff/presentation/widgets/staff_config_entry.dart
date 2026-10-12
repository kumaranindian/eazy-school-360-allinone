import '../../../../core/constants/activation_status.dart';
import '../../domain/department.dart';
import '../../domain/designation.dart';

/// Departments and designations have the same shape and the same screens;
/// this tells the shared page/dialog which one it is working on.
enum StaffConfigKind {
  department('Department', 'Departments'),
  designation('Designation', 'Designations');

  final String singular;
  final String plural;

  const StaffConfigKind(this.singular, this.plural);
}

/// A kind-agnostic view of a [Department] or [Designation] for the shared
/// config page and form dialog.
class StaffConfigEntry {
  final String id;
  final String schoolId;
  final String branchId;
  final String code;
  final String name;
  final String? description;
  final ActivationStatus status;

  const StaffConfigEntry({
    required this.id,
    required this.schoolId,
    required this.branchId,
    required this.code,
    required this.name,
    this.description,
    required this.status,
  });

  factory StaffConfigEntry.fromDepartment(Department d) => StaffConfigEntry(
    id: d.departmentId,
    schoolId: d.schoolId,
    branchId: d.branchId,
    code: d.code,
    name: d.name,
    description: d.description,
    status: d.status,
  );

  factory StaffConfigEntry.fromDesignation(Designation d) => StaffConfigEntry(
    id: d.designationId,
    schoolId: d.schoolId,
    branchId: d.branchId,
    code: d.code,
    name: d.name,
    description: d.description,
    status: d.status,
  );
}
