import 'package:flutter/material.dart';

/// Shown instead of the app when a build cannot start correctly (missing or
/// mismatched Firebase configuration, no environment selected).
///
/// Shows only a stable [code] — never keys, project ids or stack traces; the
/// detail is in the log for whoever operates the build.
class StartupErrorApp extends StatelessWidget {
  final String appName;
  final String? code;

  const StartupErrorApp({super.key, required this.appName, this.code});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.build_circle_outlined, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    "$appName can't start",
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This version of the app has not been configured '
                    'correctly. Please contact support and tell them the '
                    'app could not start.',
                    textAlign: TextAlign.center,
                  ),
                  if (code != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      'Code: $code',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
