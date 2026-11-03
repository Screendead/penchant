import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/user_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/settle_write.dart';

class ViceActivityHistoryPage extends ConsumerStatefulWidget {
  const ViceActivityHistoryPage({super.key, required this.viceID});

  final String viceID;

  static const int pageSize = 50;

  @override
  ConsumerState<ViceActivityHistoryPage> createState() =>
      _ViceActivityHistoryPageState();
}

class _ViceActivityHistoryPageState
    extends ConsumerState<ViceActivityHistoryPage> {
  int shown = ViceActivityHistoryPage.pageSize;
  // Asking for more starts a new query, which has no value until it loads;
  // until then the shorter list stays on screen instead of a spinner.
  ({String uid, List<ViceActivity> activities})? previous;
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
    final String? uid = ref.watch(userProvider).value?.uid;
    final List<Vice>? viceList = ref.watch(viceListProvider).value;
    // One more than is shown, to learn whether there are older entries.
    final List<ViceActivity>? loaded = ref
        .watch(viceActivityHistoryProvider((viceID: viceID, limit: shown + 1)))
        .value;
    if (uid != null && loaded != null) {
      previous = (uid: uid, activities: loaded);
    }
    final List<ViceActivity>? fetched =
        loaded ?? (previous?.uid == uid ? previous?.activities : null);

    if (viceList == null || fetched == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final Vice? vice = viceList.where((Vice item) => item.id == viceID).isEmpty
        ? null
        : viceList.firstWhere((Vice item) => item.id == viceID);

    if (vice == null) {
      return const Scaffold(body: Center(child: Text('Vice not found')));
    }

    final bool hasOlder = fetched.length > shown;
    final List<ViceActivity> activityList = hasOlder
        ? fetched.sublist(0, shown)
        : fetched;

    return Scaffold(
      appBar: AppBar(title: Text('${vice.name} history')),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _list(vice, activityList, hasOlder: hasOlder)),
        ],
      ),
    );
  }

  Widget _list(
    Vice vice,
    List<ViceActivity> activityList, {
    required bool hasOlder,
  }) {
    return activityList.isEmpty
        ? const Center(child: Text('No activities found for this vice'))
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: activityList.length + (hasOlder ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              if (index == activityList.length) {
                return Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        shown += ViceActivityHistoryPage.pageSize;
                      });
                    },
                    child: const Text('Show older'),
                  ),
                );
              }

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
