import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/design/dial_theme.dart';
import 'package:tracker/design/tokens.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/widgets/banner_scroll.dart';
import 'package:tracker/widgets/pill_drop.dart';

class NotSyncedMarker extends StatelessWidget {
  const NotSyncedMarker({super.key, this.label = defaultLabel});

  static const String defaultLabel = 'Not yet synced';

  final String label;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.tertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_upload_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class PendingDayNote extends ConsumerWidget {
  const PendingDayNote({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static String text(int count) =>
      '${formatCount(count)} ${pluralWord(count, one: 'entry', other: 'entries')} not yet synced';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ViceActivity>? activities = ref
        .watch(viceActivityDayProvider(selectedDate))
        .value;
    final int count =
        activities?.where((ViceActivity activity) => activity.pending).length ??
        0;

    // Offline only: online, an entry is pending for a moment, the header's
    // pill says Syncing meanwhile, and a note here would shift the tallies
    // twice for each entry logged.
    if (count == 0 || ref.watch(offlineProvider).value != true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(child: NotSyncedMarker(label: text(count))),
    );
  }
}

class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  static const String message =
      'Offline. Showing what this device has saved; new entries sync when '
      'you reconnect.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PillDrop(
      shown: ref.watch(offlineProvider).value == true,
      child: Semantics(
        liveRegion: true,
        child: BannerScroll(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          frame: (Widget scroll) => DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(PillDrop.radius),
              border: Border.all(color: DialColors.of(context).line),
              boxShadow: DialShadows.pop(Theme.of(context).brightness),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PillDrop.radius),
              child: scroll,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 18, color: colors.onSurface),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: DialTypeScale.bodyS.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
