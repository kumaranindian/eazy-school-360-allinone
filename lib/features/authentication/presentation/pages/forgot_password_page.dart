import 'package:flutter/material.dart';

import '../widgets/auth_scaffold.dart';
import '../widgets/forgot_password_form.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset your password',
      subtitle: "Enter your email and we'll send you a reset link.",
      child: const ForgotPasswordForm(),
    );
  }
}
