import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/design/habit_mark.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

// Cmd-1 to Cmd-9 log one of the habit in that place on Today; the rest go
// through the fan.
const List<LogicalKeyboardKey> _digits = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

int get habitKeyCount => _digits.length;

// Not on repeats: holding the key down would log an entry for each one, and
// only the last could be undone.
SingleActivator habitKey(int index) =>
    SingleActivator(_digits[index], meta: true, includeRepeats: false);

// A key the framework leaves unhandled goes on to the native menu, which
// would log on each repeat, so the repeats stop here.
KeyEventResult _swallowHabitKeyRepeats(FocusNode node, KeyEvent event) =>
    event is KeyRepeatEvent &&
        HardwareKeyboard.instance.isMetaPressed &&
        _digits.contains(event.logicalKey)
    ? KeyEventResult.handled
    : KeyEventResult.ignored;

/// Today's tally order: the habits in use, oldest first, as their colours
/// are given.
List<Vice> tallyOrder(List<Vice> listed, Map<String, HabitMark> marks) =>
    <Vice>[...listed]..sort(
      (Vice a, Vice b) => (marks[a.id]?.creationIndex ?? 0).compareTo(
        marks[b.id]?.creationIndex ?? 0,
      ),
    );

/// Where the menu bar's Log items send a habit: Today registers its log here
/// while it is mounted, so a log from the menu also brings Today back to the
/// current day, and the status item's popover does while it is open, so the
/// Undo shows where it can be seen. The last registered wins. Held, not
/// state: nothing rebuilds when it changes.
class TodayLogTarget {
  final List<void Function(Vice vice)> _targets = <void Function(Vice)>[];

  void Function(Vice vice)? get log => _targets.isEmpty ? null : _targets.last;

  void add(void Function(Vice vice) target) => _targets.add(target);

  void remove(void Function(Vice vice) target) => _targets.remove(target);
}

final todayLogTargetProvider = Provider<TodayLogTarget>(
  (Ref ref) => TodayLogTarget(),
);

/// The macOS menu bar, with a Log menu naming the first nine habits beside
/// their shortcuts. A PlatformMenuBar replaces the whole native menu, so it
/// carries the app, Edit, View and Window menus too; elsewhere it adds
/// nothing.
class AppMenuBar extends ConsumerWidget {
  const AppMenuBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return child;
    }
    final List<Vice>? listed = ref.watch(unarchivedViceListProvider).value;
    final List<Vice>? all = ref.watch(viceListProvider).value;
    final List<Vice> habits = listed == null
        ? const <Vice>[]
        : tallyOrder(listed, habitMarks(all ?? listed));

    return PlatformMenuBar(
      menus: appMenus(ref, habits),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _swallowHabitKeyRepeats,
        child: child,
      ),
    );
  }
}

@visibleForTesting
List<PlatformMenuItem> appMenus(WidgetRef ref, List<Vice> habits) {
  PlatformMenuItem provided(PlatformProvidedMenuItemType type) =>
      PlatformProvidedMenuItem(type: type);

  // The native Edit items would look for a responder Flutter does not
  // provide, so these hand the focused text field its own intent. A key the
  // field takes never reaches the menu.
  PlatformMenuItem edit(String label, SingleActivator key, Intent intent) =>
      PlatformMenuItem(
        label: label,
        shortcut: key,
        onSelected: () {
          final BuildContext? focused =
              FocusManager.instance.primaryFocus?.context;
          if (focused != null) {
            Actions.maybeInvoke(focused, intent);
          }
        },
      );
  const SelectionChangedCause keyboard = SelectionChangedCause.keyboard;

  return <PlatformMenuItem>[
    PlatformMenu(
      label: 'Penchant',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            provided(PlatformProvidedMenuItemType.about),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            provided(PlatformProvidedMenuItemType.servicesSubmenu),
          ],
        ),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            provided(PlatformProvidedMenuItemType.hide),
            provided(PlatformProvidedMenuItemType.hideOtherApplications),
            provided(PlatformProvidedMenuItemType.showAllApplications),
          ],
        ),
        provided(PlatformProvidedMenuItemType.quit),
      ],
    ),
    PlatformMenu(
      label: 'Edit',
      menus: <PlatformMenuItem>[
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            edit(
              'Undo',
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
              const UndoTextIntent(keyboard),
            ),
            edit(
              'Redo',
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              const RedoTextIntent(keyboard),
            ),
          ],
        ),
        edit(
          'Cut',
          const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          const CopySelectionTextIntent.cut(keyboard),
        ),
        edit(
          'Copy',
          const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          CopySelectionTextIntent.copy,
        ),
        edit(
          'Paste',
          const SingleActivator(LogicalKeyboardKey.keyV, meta: true),
          const PasteTextIntent(keyboard),
        ),
        edit(
          'Select All',
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          const SelectAllTextIntent(keyboard),
        ),
      ],
    ),
    if (habits.isNotEmpty)
      PlatformMenu(
        label: 'Log',
        menus: <PlatformMenuItem>[
          for (final (int i, Vice vice) in habits.indexed.take(habitKeyCount))
            PlatformMenuItem(
              label: vice.name,
              shortcut: habitKey(i),
              onSelected: () =>
                  ref.read(todayLogTargetProvider).log?.call(vice),
            ),
        ],
      ),
    PlatformMenu(
      label: 'View',
      menus: <PlatformMenuItem>[
        provided(PlatformProvidedMenuItemType.toggleFullScreen),
      ],
    ),
    PlatformMenu(
      label: 'Window',
      menus: <PlatformMenuItem>[
        provided(PlatformProvidedMenuItemType.minimizeWindow),
        provided(PlatformProvidedMenuItemType.zoomWindow),
        PlatformMenuItemGroup(
          members: <PlatformMenuItem>[
            provided(PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ],
        ),
      ],
    ),
  ];
}
