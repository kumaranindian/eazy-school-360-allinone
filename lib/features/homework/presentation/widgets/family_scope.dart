import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/tenant/tenant_context.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../fees/presentation/pages/parent_fees_page.dart'
    show linkedChildrenProvider;
import '../../../students/domain/student.dart';

/// Resolves the signed-in parent's linked children (ACTIVE, portal-enabled
/// links only — the same set the fee and leave screens use) and the one
/// currently selected, then hands them to [builder]. Which records a child's
/// parent may *read* is decided by the security rules, not this list.
class FamilyScope extends ConsumerStatefulWidget {
  final Widget Function(
    BuildContext context,
    TenantContext tenant,
    List<Student> children,
    Student child,
  )
  builder;

  const FamilyScope({super.key, required this.builder});

  @override
  ConsumerState<FamilyScope> createState() => _FamilyScopeState();
}

class _FamilyScopeState extends ConsumerState<FamilyScope> {
  String? _childId;

  @override
  Widget build(BuildContext context) {
    return AsyncValueWidget<TenantContext?>(
      value: ref.watch(tenantContextProvider),
      data: (tenant) {
        final schoolId = tenant?.school?.schoolId;
        final parentId = tenant?.user.linkedParentId;
        if (tenant == null || schoolId == null) {
          return const EmptyView(
            icon: Icons.family_restroom_outlined,
            message: 'No school found for your account.',
          );
        }
        if (parentId == null) {
          return const EmptyView(
            icon: Icons.link_off,
            message:
                "Your account isn't linked to a parent record yet. Please "
                'contact the school office.',
          );
        }
        final key = (schoolId: schoolId, parentId: parentId);
        return ref
            .watch(linkedChildrenProvider(key))
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: userMessageFor(e),
                onRetry: () => ref.invalidate(linkedChildrenProvider(key)),
              ),
              data: (children) {
                if (children.isEmpty) {
                  return const EmptyView(
                    icon: Icons.child_care_outlined,
                    message:
                        'No children are linked to your account yet. Please '
                        'contact the school office.',
                  );
                }
                final child = children.firstWhere(
                  (c) => c.studentId == _childId,
                  orElse: () => children.first,
                );
                return Column(
                  children: [
                    if (children.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          0,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: DropdownButtonFormField<String>(
                              value: child.studentId,
                              decoration: const InputDecoration(
                                labelText: 'Child',
                                isDense: true,
                              ),
                              items: [
                                for (final c in children)
                                  DropdownMenuItem(
                                    value: c.studentId,
                                    child: Text(c.displayName),
                                  ),
                              ],
                              onChanged: (v) => setState(() => _childId = v),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: KeyedSubtree(
                        key: ValueKey(child.studentId),
                        child: widget.builder(context, tenant, children, child),
                      ),
                    ),
                  ],
                );
              },
            );
      },
    );
  }
}
