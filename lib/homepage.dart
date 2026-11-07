import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/design/dial_icons.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/sync_status_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/penchant_mark.dart';
import 'package:tracker/widgets/sync_status.dart';

class Homepage extends StatefulWidget {
  const Homepage({super.key});

  static const String menuLabel = 'Penchant menu';
  static const Key menuKey = ValueKey<String>('penchant-menu');
  static const String habitsItem = 'Habits';
  static const String settingsItem = 'Settings';

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  // Today's day and the Trends selection outlive their widgets here, as when
  // a load error replaces them. It lives and dies with the signed-in session.
  final PageStorageBucket tabState = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    final double top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: Column(
        children: [
          // The mock-up's bar: 44 pt, 7 pt under the status bar.
          Padding(
            padding: EdgeInsets.only(top: top + 7),
            child: const TodayHeader(),
          ),
          const OfflineBanner(),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: PageStorage(bucket: tabState, child: const ViceTracker()),
            ),
          ),
        ],
      ),
    );
  }
}

class TodayHeader extends StatelessWidget {
  const TodayHeader({super.key});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: DialSize.minTapTarget),
    child: const Padding(
      padding: EdgeInsets.only(left: 14, right: 16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _AppMenu(),
            ),
          ),
          SizedBox(width: DialSpace.xs),
          SyncPill(),
        ],
      ),
    ),
  );
}

class _AppMenu extends StatelessWidget {
  const _AppMenu();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DialColors colors = DialColors.of(context);
    final ButtonStyle itemStyle = MenuItemButton.styleFrom(
      padding: const EdgeInsets.all(12),
      minimumSize: const Size(228, DialSize.minTapTarget),
      // Padded, Material grows each row to 48; the mock-up's rows are 44.
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: DialTypeScale.bodyL.copyWith(fontSize: 15.5, height: 1.2),
      foregroundColor: scheme.onSurface,
      iconColor: colors.muted,
      overlayColor: colors.surface2,
    );

    return MenuAnchor(
      // The card 15 from the screen's edge and 2 under the bar, as the
      // mock-up's. The panel's padding is room for the card's shadow, which
      // the panel would clip; the menu is kept on screen, so the left padding
      // is the card's distance from the edge.
      alignmentOffset: const Offset(-14, 2 - 8),
      style: const MenuStyle(
        // The panel is bare so the card inside it can carry the pop shadow.
        backgroundColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        shadowColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: WidgetStatePropertyAll<double>(0),
        padding: WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.fromLTRB(15, 8, 24, 40),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder()),
      ),
      menuChildren: <Widget>[
        Container(
          width: 244,
          padding: const EdgeInsets.all(DialSpace.xs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(DialRadius.card),
            border: Border.all(color: colors.line),
            boxShadow: DialShadows.pop(theme.brightness),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              MenuItemButton(
                style: itemStyle,
                leadingIcon: const StrokeIcon(DialGlyph.habits, size: 20),
                onPressed: () =>
                    Navigator.of(context).pushNamed('/manage-data'),
                child: const Text(Homepage.habitsItem),
              ),
              MenuItemButton(
                style: itemStyle,
                leadingIcon: const StrokeIcon(DialGlyph.gear, size: 20),
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
                child: const Text(Homepage.settingsItem),
              ),
              const SyncFooter(),
            ],
          ),
        ),
      ],
      builder: (BuildContext context, MenuController menu, Widget? child) {
        void toggle() => menu.isOpen ? menu.close() : menu.open();
        return Semantics(
          button: true,
          label: Homepage.menuLabel,
          expanded: menu.isOpen,
          excludeSemantics: true,
          onTap: toggle,
          child: InkWell(
            key: Homepage.menuKey,
            customBorder: const StadiumBorder(),
            onTap: toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: DialSize.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const PenchantMark(size: 26),
                    const SizedBox(width: DialSpace.xs),
                    Flexible(
                      child: Text(
                        'Penchant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DialTypeScale.displayL.copyWith(
                          fontSize: 21,
                          height: 1.15,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: DialSpace.xs),
                    StrokeIcon(DialGlyph.down, size: 16, color: colors.muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class SyncFooter extends ConsumerWidget {
  const SyncFooter({super.key});

  static String? text(SyncStatus status, {required bool offline}) {
    if (offline) {
      return 'Offline. New entries sync when you reconnect.';
    }
    return switch (status.state) {
      SyncState.unknown => null,
      SyncState.pending => 'Sending entries to the server',
      SyncState.synced => switch (status.lastSynced) {
        final DateTime at => 'All entries synced · last at ${formatClock(at)}',
        null => 'All entries synced',
      },
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool offline = ref.watch(offlineProvider).value ?? false;
    final SyncStatus status = ref.watch(syncStatusProvider);
    final String? line = text(status, offline: offline);
    if (line == null) {
      return const SizedBox.shrink();
    }
    final DialColors colors = DialColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DialSpace.s,
            vertical: DialSpace.xxs,
          ),
          child: Divider(height: 1, thickness: 1, color: colors.line),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StrokeIcon(
                SyncPill.glyph(status.state, offline: offline),
                size: 16,
                color: colors.muted,
              ),
              const SizedBox(width: DialSpace.xs),
              Expanded(
                child: Text(
                  line,
                  style: DialTypeScale.bodyS.copyWith(
                    fontSize: 12.5,
                    height: 1.3,
                    color: colors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// It shows nothing until the app knows.
class SyncPill extends ConsumerStatefulWidget {
  const SyncPill({super.key});

  static const String synced = 'Synced';
  static const String syncing = 'Syncing';
  static const String offlineLabel = 'Offline';

  static DialGlyph glyph(SyncState state, {required bool offline}) => offline
      ? DialGlyph.cloudOff
      : state == SyncState.pending
      ? DialGlyph.cloudUp
      : DialGlyph.cloudOk;

  @override
  ConsumerState<SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends ConsumerState<SyncPill> {
  // AnimatedSwitcher keeps each outgoing label until its fade ends and
  // only drops one keyed like the incoming label, so a label that comes back
  // twice within the fade would put two children with one key in its Stack.
  String? _label;
  int _appearance = 0;

  @override
  Widget build(BuildContext context) {
    final bool offline = ref.watch(offlineProvider).value ?? false;
    final SyncState state = ref.watch(syncStatusProvider).state;
    final String? label = offline
        ? SyncPill.offlineLabel
        : switch (state) {
            SyncState.unknown => null,
            SyncState.pending => SyncPill.syncing,
            SyncState.synced => SyncPill.synced,
          };
    if (label != _label) {
      _label = label;
      _appearance++;
    }
    final DialColors colors = DialColors.of(context);

    return AnimatedSwitcher(
      duration: DialMotion.reducedFade,
      child: label == null
          ? const SizedBox.shrink()
          : Semantics(
              key: ValueKey<(String, int)>((label, _appearance)),
              container: true,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    StrokeIcon(
                      SyncPill.glyph(state, offline: offline),
                      size: 18,
                      color: colors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: DialTypeScale.bodyS.copyWith(
                        fontSize: 12,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
