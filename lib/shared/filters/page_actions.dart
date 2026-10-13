import 'package:flutter/material.dart';

/// A secondary action of a page (import, export, manage lists, ...).
class PageAction {
  final String label;
  final IconData icon;
  final VoidCallback onSelected;

  const PageAction({
    required this.label,
    required this.icon,
    required this.onSelected,
  });
}

/// The "⋮" menu that holds a page's secondary actions so that only the one
/// primary action (the FAB or a single button) competes for space with the
/// content. Renders nothing when there are no actions.
class PageActionsMenu extends StatelessWidget {
  final List<PageAction> actions;

  const PageActionsMenu({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      icon: const Icon(Icons.more_vert),
      onSelected: (i) => actions[i].onSelected(),
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(actions[i].icon, size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(actions[i].label)),
              ],
            ),
          ),
      ],
    );
  }
}
