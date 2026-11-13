import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/permissions/user_role.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../authentication/domain/mfa.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

/// Whether the current session used a second factor. Only platform admins are
/// held to it (rules and callables refuse them otherwise); everyone else
/// reports "secured" without any lookup. The router sends a platform admin
/// without it to the two-step setup page.
final sessionSecurityProvider = FutureProvider<SessionSecurity>((ref) async {
  final tenant = ref.watch(tenantContextProvider).value;
  if (tenant == null || tenant.role != UserRole.platformAdmin) {
    return const SessionSecurity(
      secondFactorSignedIn: true,
      enrolledFactors: 0,
    );
  }
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).sessionSecurity();
}, retry: (retryCount, error) => null);
