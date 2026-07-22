import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

class ManageData extends ConsumerWidget {
  const ManageData({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vice>? viceList = ref.watch(viceListProvider).value;
    final List<ViceActivity>? viceActivityList =
        ref.watch(viceActivityListProvider).value;

    if (viceList == null || viceActivityList == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (viceList.isEmpty) {
      return const Center(
        child: Text('No vices found'),
      );
    }

    if (viceActivityList.isEmpty) {
      return const Center(
        child: Text('No activities found'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Vices'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).pushNamed('/vices/add');
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: viceList.length,
        padding: const EdgeInsets.all(16),
        itemBuilder: (BuildContext context, int index) {
          final Vice vice = viceList[index];
          final List<ViceActivity> viceActivities = viceActivityList
              .where(
                  (ViceActivity viceActivity) => viceActivity.viceID == vice.id)
              .toList();

          return ListTile(
            enabled: !vice.archived,
            contentPadding: EdgeInsets.zero,
            title: Text(vice.name),
            subtitle: Text('${viceActivities.length} activities'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: 'Edit',
                  child: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      Navigator.of(context).pushNamed(
                        '/vices/${vice.id}/edit',
                      );
                    },
                  ),
                ),
                vice.archived
                    ? Tooltip(
                        message: 'Unarchive',
                        child: IconButton(
                          icon: const Icon(Icons.unarchive),
                          onPressed: () async {
                            try {
                              await FirebaseFirestore.instance
                                  .collection('vices')
                                  .doc(vice.id)
                                  .update({
                                'archived': false,
                              });
                            } on FirebaseException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString()),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      )
                    : Tooltip(
                        message: 'Archive',
                        child: IconButton(
                          icon: const Icon(Icons.archive),
                          onPressed: () async {
                            try {
                              await FirebaseFirestore.instance
                                  .collection('vices')
                                  .doc(vice.id)
                                  .update({
                                'archived': true,
                              });
                            } on FirebaseException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString()),
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      ),
              ],
            ),
            onTap: () {
              Navigator.of(context).pushNamed(
                '/vices/${vice.id}/activities',
              );
            },
          );
        },
      ),
    );
  }
}
