import 'package:flutter/foundation.dart';

import 'env_config.dart';
import 'firebase_options/platform_options.dart';
import 'known_firebase_projects.dart';

/// One problem found in the selected Firebase configuration. [code] is a
/// stable, non-sensitive identifier safe to show or log.
class ConfigIssue {
  final String code;
  final String message;

  const ConfigIssue(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// Checks the *selected* environment's options for the *running* platform
/// before Firebase is initialised. Never includes a key or full app id in
/// its output.
abstract final class FirebaseConfigValidator {
  static List<ConfigIssue> validate(
    EnvConfig config, {
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final web = isWeb ?? kIsWeb;
    final target = platform ?? defaultTargetPlatform;
    final o = config.firebaseOptions;
    final issues = <ConfigIssue>[];
    final where = web ? 'web' : target.name;

    void need(String field, String value) {
      if (value.trim().isEmpty) {
        issues.add(
          ConfigIssue('MISSING_$field', '$field is empty for $where.'),
        );
      } else if (isPlaceholder(value)) {
        issues.add(
          ConfigIssue(
            'PLACEHOLDER_$field',
            '$field is still a placeholder for ${config.environment.name}/$where.',
          ),
        );
      }
    }

    need('API_KEY', o.apiKey);
    need('APP_ID', o.appId);
    need('MESSAGING_SENDER_ID', o.messagingSenderId);
    need('PROJECT_ID', o.projectId);
    need('STORAGE_BUCKET', o.storageBucket ?? '');

    if (config.forbiddenProjectIds.contains(o.projectId)) {
      issues.add(
        ConfigIssue(
          'ENV_PROJECT_MISMATCH',
          '${config.environment.name} resolved a project that belongs to '
              'another environment.',
        ),
      );
    }

    if (!isPlaceholder(o.appId) && o.appId.isNotEmpty) {
      final parts = o.appId.split(':');
      final expectedKind = web
          ? 'web'
          : (target == TargetPlatform.android ? 'android' : 'ios');
      if (parts.length != 4 || parts[0] != '1') {
        issues.add(
          const ConfigIssue(
            'APP_ID_FORMAT',
            'App id is not in the expected format.',
          ),
        );
      } else {
        if (parts[2] != expectedKind) {
          issues.add(
            ConfigIssue(
              'APP_ID_PLATFORM',
              'App id is registered for "${parts[2]}", not "$expectedKind".',
            ),
          );
        }
        if (parts[1] != o.messagingSenderId) {
          issues.add(
            const ConfigIssue(
              'APP_ID_SENDER_MISMATCH',
              'App id and messaging sender id belong to different projects.',
            ),
          );
        }
      }
    }

    if (web) {
      final domain = o.authDomain ?? '';
      if (domain.isEmpty || isPlaceholder(domain)) {
        issues.add(
          const ConfigIssue(
            'MISSING_AUTH_DOMAIN',
            'Web authDomain is missing.',
          ),
        );
      } else if (!domain.startsWith('${o.projectId}.')) {
        issues.add(
          const ConfigIssue(
            'AUTH_DOMAIN_PROJECT',
            'Web authDomain does not belong to the configured project.',
          ),
        );
      }
    } else if (target == TargetPlatform.iOS || target == TargetPlatform.macOS) {
      if (o.iosBundleId != kApplicationId) {
        issues.add(
          const ConfigIssue(
            'IOS_BUNDLE_ID',
            'iOS bundle id does not match the application identifier.',
          ),
        );
      }
    }
    return issues;
  }
}
