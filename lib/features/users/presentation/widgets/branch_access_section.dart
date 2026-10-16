import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../school_setup/domain/branch.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../domain/user_profile.dart';
import '../providers/login_access_providers.dart';
import '../providers/user_providers.dart';

/// School admins: the role this staff login holds in the school's OTHER
/// branches. Each change is one server call (`setBranchAccess`); the server
/// re-checks that the person is active staff of that branch.
class BranchAccessSection extends ConsumerStatefulWidget {
  final String schoolId;
  final String uid;
  const BranchAccessSection({
    super.key,
    required this.schoolId,
    required this.uid,
  });

  @override
  ConsumerState<BranchAccessSection> createState() =>
      _BranchAccessSectionState();
}

class _BranchAccessSectionState extends ConsumerState<BranchAccessSection> {
  static const _roles = [
    UserRole.teacher,
    UserRole.finance,
    UserRole.branchAdmin,
  ];

  UserProfile? _profile;
  String? _busyBranch;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ref
          .read(userRepositoryProvider)
          .getUserProfile(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userMessageFor(e);
      });
    }
  }

  Future<void> _set(String branchId, UserRole? role) async {
    setState(() {
      _busyBranch = branchId;
      _error = null;
    });
    try {
      await ref
          .read(loginAccessRepositoryProvider)
          .setBranchAccess(
            schoolId: widget.schoolId,
            branchId: branchId,
            uid: widget.uid,
            role: role,
          );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busyBranch = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _profile;
    // Only branch-scoped staff hold per-branch roles.
    if (_loading) return const SizedBox.shrink();
    if (profile == null || !_roles.contains(profile.homeRole)) {
      return const SizedBox.shrink();
    }
    final List<Branch> branches =
        ref.watch(schoolBranchesProvider(widget.schoolId)).value ?? const [];
    final others = [
      for (final b in branches)
        if (b.branchId != profile.homeBranchId) b,
    ];
    if (others.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: AppSpacing.xl),
        Text('Other branches', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Lets this login work in more than one branch, with a different role '
          'in each. The person must already be an active staff member of that '
          'branch (same email).',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final b in others)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(b.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 170,
                  child: DropdownButton<UserRole?>(
                    isExpanded: true,
                    value: profile.branchRoles[b.branchId],
                    hint: const Text('No access'),
                    onChanged: _busyBranch != null
                        ? null
                        : (r) => _set(b.branchId, r),
                    items: [
                      const DropdownMenuItem<UserRole?>(
                        value: null,
                        child: Text('No access'),
                      ),
                      for (final r in _roles)
                        DropdownMenuItem<UserRole?>(
                          value: r,
                          child: Text(r.displayName),
                        ),
                    ],
                  ),
                ),
                if (_busyBranch == b.branchId)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
