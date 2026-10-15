import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import 'students_list_page.dart';
import 'teacher_students_page.dart';

/// `/students`: the branch directory for administrators and finance; for a
/// teacher, the roster of the sections they are assigned to. The split is by
/// what `firestore.rules` allows — a teacher cannot list the branch.
class StudentsEntryPage extends ConsumerWidget {
  const StudentsEntryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(tenantContextProvider.select((t) => t.value?.role));
    return role == UserRole.teacher
        ? const TeacherStudentsPage()
        : const StudentsListPage();
  }
}
