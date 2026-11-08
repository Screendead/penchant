import 'package:flutter/material.dart';
import 'package:tracker/account/account_copy.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';

// Account Settings shows a guest the form that links an email.
void _openSaveJournal(BuildContext context) =>
    Navigator.of(context).pushNamed('/settings/account');

// Today's warning to a guest whose account Firebase will soon delete.
class GuestExpiryBanner extends StatelessWidget {
  const GuestExpiryBanner({super.key, required this.daysLeft});

  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          DialSpace.m,
          DialSpace.s,
          DialSpace.xs,
          DialSpace.xxs,
        ),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(DialRadius.tile),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              AccountCopy.guestExpiry(daysLeft),
              style: DialTypeScale.bodyS.copyWith(
                color: scheme.onErrorContainer,
                height: 1.4,
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  minimumSize: const Size(0, DialSize.minTapTarget),
                ),
                onPressed: () => _openSaveJournal(context),
                child: const Text(AccountCopy.guestExpiryAction),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// The last days' warning: a sheet that stays until the guest picks an answer.
Future<void> showGuestExpirySheet(BuildContext context, int daysLeft) async {
  final bool? save = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    builder: (BuildContext context) => GuestExpirySheet(daysLeft: daysLeft),
  );
  if (save == true && context.mounted) {
    _openSaveJournal(context);
  }
}

class GuestExpirySheet extends StatelessWidget {
  const GuestExpirySheet({super.key, required this.daysLeft});

  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DialSpace.gutter,
        DialSpace.xl,
        DialSpace.gutter,
        DialSpace.m,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              AccountCopy.guestExpiryTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: DialSpace.s),
          Text(
            AccountCopy.guestExpiry(daysLeft),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: DialColors.of(context).muted,
            ),
          ),
          const SizedBox(height: DialSpace.l),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AccountCopy.guestExpiryAction),
          ),
          const SizedBox(height: DialSpace.xs),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AccountCopy.guestExpiryLater),
          ),
        ],
      ),
    );
  }
}
