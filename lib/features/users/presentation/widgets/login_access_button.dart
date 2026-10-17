import 'package:flutter/material.dart';

import '../../../../core/utils/responsive.dart';

/// The key button of a directory row. Shown only to people who may manage
/// staff; the server and rules decide what the dialog then allows.
class LoginAccessButton extends StatelessWidget {
  final VoidCallback onPressed;

  const LoginAccessButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // A table row is 46px tall, so the button is compact there; on a phone it
    // keeps the full 48px touch target.
    final compact = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    return IconButton(
      icon: const Icon(Icons.vpn_key_outlined),
      iconSize: compact ? 20 : 24,
      tooltip: 'Login access',
      onPressed: onPressed,
      style: compact
          ? IconButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 34),
              maximumSize: const Size(40, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )
          : IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }
}
