import 'package:flutter/material.dart';

import '../../domain/parent.dart';
import '../../domain/parent_duplicates.dart';

/// What the person chose when an existing parent looked like the new one.
sealed class ParentDuplicateChoice {
  const ParentDuplicateChoice();
}

/// Use (link) this existing record instead of creating another.
class UseExistingParent extends ParentDuplicateChoice {
  final Parent parent;
  const UseExistingParent(this.parent);
}

/// Only offered when nothing blocks it (a shared phone, not a shared email).
class CreateParentAnyway extends ParentDuplicateChoice {
  const CreateParentAnyway();
}

/// Lists the matches and lets the person pick one, go back and change the
/// details, or (phone-only matches) create a separate record anyway. Returns
/// null for "go back".
Future<ParentDuplicateChoice?> showParentDuplicatesDialog({
  required BuildContext context,
  required List<ParentMatch> matches,
  String useLabel = 'Use this parent',
}) {
  final blocked = matches.any((m) => m.blocksCreate);
  return showDialog<ParentDuplicateChoice>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: const Text('This parent may already exist'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                blocked
                    ? 'A parent in this branch already has this email. One '
                          'email can only belong to one parent (it is their '
                          'sign-in), so use the existing parent or change the '
                          'email. A parent with several children needs only '
                          'one record and one login.'
                    : 'A parent in this branch already has this phone number. '
                          'A parent with several children needs only one '
                          'record and one login.',
              ),
              const SizedBox(height: 12),
              for (final m in matches)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  // Button under the text, not beside it: a narrow phone at a
                  // large text size has no room for both on one row.
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.parent.displayName,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          [
                            if (m.parent.phone.isNotEmpty) m.parent.phone,
                            if (m.parent.email != null) m.parent.email!,
                            m.parent.hasPortalAccess ? 'Has login' : 'No login',
                            'Matches: ${m.reasonText}',
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(
                              ctx,
                            ).pop(UseExistingParent(m.parent)),
                            child: Text(useLabel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (blocked)
                Text(
                  'Creating a second record with the same email is not '
                  'allowed.',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Change details'),
          ),
          if (!blocked)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(const CreateParentAnyway()),
              child: const Text('Create new anyway'),
            ),
        ],
      );
    },
  );
}
