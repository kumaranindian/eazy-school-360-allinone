import 'package:flutter/material.dart';

import '../widgets/auth_scaffold.dart';
import '../widgets/login_form.dart';

/// Sign-in screen. Centers a bounded-width card on tablet/desktop and goes
/// near-full-width on mobile; the form itself scrolls so it stays usable
/// with the keyboard open.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to continue to EazySchool 360',
      child: const LoginForm(),
    );
  }
}
