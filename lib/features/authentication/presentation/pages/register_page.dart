import 'package:flutter/material.dart';

import '../widgets/auth_scaffold.dart';
import '../widgets/register_form.dart';

/// Sign up screen for new school registration.
class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Register your school',
      subtitle: 'Create an account to get started',
      child: const RegisterForm(),
    );
  }
}
