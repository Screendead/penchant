import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/settle_write.dart';

class ViceActivityHistoryPage extends ConsumerStatefulWidget {
  const ViceActivityHistoryPage({super.key, required this.viceID});

  final String viceID;

  @override
  ConsumerState<ViceActivityHistoryPage> createState() =>
      _ViceActivityHistoryPageState();
}

class _ViceActivityHistoryPageState
    extends ConsumerState<ViceActivityHistoryPage> {
  final Set<String> deleting = <String>{};

  String get viceID => widget.viceID;

  // The messenger is taken from this State, not the row: a delete drops the
  // row from the local snapshot before the server answers.
  Future<void> _delete(String activityID) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      deleting.add(activityID);
    });

    String message;
    try {
      message =
          await settleWrite(
            ref.read(trackerWritesProvider).deleteActivity(activityID),
          )
          ? 'Activity deleted'
          : queuedDeleteMessage;
    } on FirebaseException catch (e) {
      message = e.message ?? 'Unable to delete activity';
    }

    if (mounted) {
      setState(() {
        deleting.remove(activityID);
      });
    }
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Vice>? viceList = ref.watch(viceListProvider).value;
    final List<ViceActivity>? activityList = ref
        .watch(viceActivityHistoryProvider(viceID))
        .value;

    if (viceList == null || activityList == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Vice? vice = viceList.where((Vice item) => item.id == viceID).isEmpty
        ? null
        : viceList.firstWhere((Vice item) => item.id == viceID);

    if (vice == null) {
      return const Scaffold(body: Center(child: Text('Vice not found')));
    }

    return Scaffold(
      appBar: AppBar(title: Text('${vice.name} history')),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _list(vice, activityList)),
        ],
      ),
    );
  }

  Widget _list(Vice vice, List<ViceActivity> activityList) {
    return activityList.isEmpty
        ? const Center(child: Text('No activities found for this vice'))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: activityList.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final ViceActivity activity = activityList[index];
              final DateTime createdAt = activity.createdAt.toDate();

              return Card(
                child: ListTile(
                  title: Text(
                    '${vice.unit.label(activity.quantity)} on ${DateFormat('EEE, MMM d, yyyy • HH:mm').format(createdAt)}',
                  ),
                  subtitle: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Quantity: ${activity.quantity}'),
                      if (activity.pending) const NotSyncedMarker(),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(
                      context,
                    ).pushNamed('/vices/$viceID/activities/${activity.id}');
                  },
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          Navigator.of(context).pushNamed(
                            '/vices/$viceID/activities/${activity.id}',
                          );
                        },
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: deleting.contains(activity.id)
                            ? null
                            : () => _delete(activity.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }
}
