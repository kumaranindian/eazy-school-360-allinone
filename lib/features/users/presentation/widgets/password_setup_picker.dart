import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../domain/login_provisioning.dart';

/// The "how should the password be set?" choice shared by "Give login access"
/// and "Reset password": the option list plus, for
/// [PasswordSetupOption.adminDefined], the typed password and its
/// confirmation. Holds no state of its own; the caller owns the values.
class PasswordSetupPicker extends StatelessWidget {
  final String heading;
  final List<PasswordSetupOption> options;
  final PasswordSetupOption option;
  final ValueChanged<PasswordSetupOption> onOptionChanged;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool showPassword;
  final VoidCallback onToggleShowPassword;

  /// Called after either password field changes so the caller can revalidate.
  final VoidCallback onChanged;
  final bool enabled;

  const PasswordSetupPicker({
    super.key,
    required this.heading,
    this.options = PasswordSetupOption.values,
    required this.option,
    required this.onOptionChanged,
    required this.password,
    required this.confirm,
    required this.showPassword,
    required this.onToggleShowPassword,
    required this.onChanged,
    this.enabled = true,
  });

  static String? passwordProblem(String v) {
    if (v.length < AppConstants.minPasswordLength) {
      return 'Use at least ${AppConstants.minPasswordLength} characters.';
    }
    if (!RegExp('[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include at least one letter and one number.';
    }
    return null;
  }

  /// False only while the admin-defined password is missing, weak or
  /// mismatched.
  static bool isValid(
    PasswordSetupOption option,
    String password,
    String confirm,
  ) =>
      option != PasswordSetupOption.adminDefined ||
      (passwordProblem(password) == null && password == confirm);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final o in options)
          RadioListTile<PasswordSetupOption>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: o,
            groupValue: option,
            onChanged: enabled ? (v) => onOptionChanged(v ?? option) : null,
            title: Text(o.label),
            subtitle: Text(o.description),
          ),
        if (option == PasswordSetupOption.nameMobile ||
            option == PasswordSetupOption.adminDefined)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              option == PasswordSetupOption.nameMobile
                  ? 'Less secure: anyone who knows a name and mobile number can '
                        'guess it. People are asked to change it at first '
                        'sign-in. A name of 4+ letters and a mobile of 5+ '
                        'digits are needed.'
                  : 'Less secure: everyone shares this password until they '
                        'change it at first sign-in. It is not stored anywhere.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (option == PasswordSetupOption.adminDefined) ...[
          const SizedBox(height: 8),
          TextField(
            controller: password,
            enabled: enabled,
            obscureText: !showPassword,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'Temporary password',
              isDense: true,
              errorText: password.text.isEmpty
                  ? null
                  : passwordProblem(password.text),
              suffixIcon: IconButton(
                tooltip: showPassword ? 'Hide password' : 'Show password',
                icon: Icon(
                  showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: onToggleShowPassword,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: confirm,
            enabled: enabled,
            obscureText: !showPassword,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              labelText: 'Confirm password',
              isDense: true,
              errorText:
                  confirm.text.isNotEmpty && confirm.text != password.text
                  ? 'Passwords do not match'
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}
