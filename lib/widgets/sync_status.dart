import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';

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

    // A reserved height, so an online write's brief pending state does not
    // resize the chart above. It grows only when large text wraps the note.
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: MediaQuery.textScalerOf(context).scale(32),
      ),
      child: count == 0
          ? null
          : Center(child: NotSyncedMarker(label: text(count))),
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
    if (ref.watch(offlineProvider).value != true) {
      return const SizedBox.shrink();
    }

    final ColorScheme colors = Theme.of(context).colorScheme;

    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: colors.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
