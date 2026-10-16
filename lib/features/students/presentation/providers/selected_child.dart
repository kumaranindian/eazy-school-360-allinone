import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/student.dart';

/// Which linked child a parent is looking at. Shared by the parent home and
/// the child-scoped parent pages so choosing a child once carries over. Null
/// means "the first child".
class SelectedChildController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String studentId) => state = studentId;
}

final selectedChildIdProvider =
    NotifierProvider<SelectedChildController, String?>(
      SelectedChildController.new,
    );

/// The child to show: the selected one if it is still linked, otherwise the
/// first. Null only when [children] is empty.
Student? resolveSelectedChild(List<Student> children, String? selectedId) {
  if (children.isEmpty) return null;
  return children.firstWhere(
    (c) => c.studentId == selectedId,
    orElse: () => children.first,
  );
}
