import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config_provider.dart';
import '../core/regional/school_time.dart';
import '../core/routing/app_router.dart';
import '../core/tenant/tenant_context_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/responsive.dart';
import '../features/authentication/presentation/providers/auth_providers.dart';
import '../shared/branding/brand_logo.dart';
import '../shared/loading/loading_indicator.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envConfig = ref.watch(envConfigProvider);
    final router = ref.watch(appRouterProvider);
    // The signed-in account and the loaded tenant profile must belong to the
    // same user. They differ for a moment after an account switch (the old
    // profile is kept while the new one loads); during that moment nothing of
    // the previous account may be on screen, so the whole navigator is taken
    // out of the tree and rebuilt fresh for the new account — which also
    // discards any page state the previous user had open.
    final signedInUid = ref.watch(authStateChangesProvider).value?.uid;
    final loadedUid = ref.watch(tenantContextProvider).value?.user.userId;
    final accountSwitching =
        signedInUid != null && loadedUid != null && signedInUid != loadedUid;

    // The school's regional setup (time zone, date format) for plain functions
    // that have no `ref`; cleared when nobody is signed in to a school. The
    // navigator is re-keyed when it changes so every open screen redraws with
    // the new zone/format instead of keeping old text.
    final school = accountSwitching
        ? null
        : ref.watch(tenantContextProvider).value?.school;
    if (school != null) {
      SchoolTime.use(school.regional);
    } else {
      SchoolTime.reset();
    }
    final regionalKey = school == null
        ? 'none'
        : '${school.regional.timezone}|${school.regional.dateFormat}';

    return MaterialApp.router(
      title: envConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => _AdaptiveText(
        child: _BrandPrecache(
          child: accountSwitching
              ? const Scaffold(body: LoadingIndicator())
              : KeyedSubtree(
                  key: ValueKey(regionalKey),
                  child: child ?? const SizedBox.shrink(),
                ),
        ),
      ),
    );
  }
}

/// App-wide text policy, applied once above every route:
///
/// - The user's system font size is honoured up to [maxTextScale]. Beyond
///   that no layout can be guaranteed to fit a 360px phone, so it is capped
///   (the layouts are tested up to this limit).
/// - On phones the headings use the compact scale ([AppTypography.compact]).
class _AdaptiveText extends StatelessWidget {
  final Widget child;
  const _AdaptiveText({required this.child});

  static const double maxTextScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = MediaQuery.sizeOf(context).width < Breakpoints.mobile;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: phone
          ? Theme(
              data: theme.copyWith(
                textTheme: AppTypography.compact(theme.textTheme),
              ),
              child: child,
            )
          : child,
    );
  }
}

/// Decodes the logo artwork once, as soon as there is a context to do it
/// with, so no screen shows an empty box while it loads.
class _BrandPrecache extends StatefulWidget {
  final Widget child;
  const _BrandPrecache({required this.child});

  @override
  State<_BrandPrecache> createState() => _BrandPrecacheState();
}

class _BrandPrecacheState extends State<_BrandPrecache> {
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done) return;
    _done = true;
    BrandAssets.precache(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
