import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

class ViceActivityHistoryPage extends ConsumerWidget {
  const ViceActivityHistoryPage({super.key, required this.viceID});

  final String viceID;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vice>? viceList = ref.watch(viceListProvider).value;
    final List<ViceActivity>? activityList =
        ref.watch(viceActivityHistoryProvider(viceID)).value;

    if (viceList == null || activityList == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final Vice? vice = viceList.where((Vice item) => item.id == viceID).isEmpty
        ? null
        : viceList.firstWhere((Vice item) => item.id == viceID);

    if (vice == null) {
      return const Scaffold(
        body: Center(
          child: Text('Vice not found'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${vice.name} history'),
      ),
      body: activityList.isEmpty
          ? const Center(
              child: Text('No activities found for this vice'),
            )
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
                    subtitle: Text('Quantity: ${activity.quantity}'),
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/vices/$viceID/activities/${activity.id}',
                      );
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
                          onPressed: () async {
                            try {
                              await ref
                                  .read(trackerWritesProvider)
                                  .deleteActivity(activity.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Activity deleted'),
                                  ),
                                );
                              }
                            } on FirebaseException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e.message ?? 'Unable to delete activity',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}