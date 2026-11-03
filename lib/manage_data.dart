import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';

class ManageData extends ConsumerWidget {
  const ManageData({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>> viceListValue = ref.watch(viceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Vices'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add vice',
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).pushNamed('/vices/add');
            },
          ),
        ],
      ),
      body: _buildBody(context, ref, viceListValue: viceListValue),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<List<Vice>> viceListValue,
  }) {
    if (viceListValue.error case final Object error) {
      return Center(child: Text('Unable to load your vices: $error'));
    }

    final List<Vice>? viceList = viceListValue.value;

    if (viceList == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (viceList.isEmpty) {
      return const Center(child: Text('No vices yet. Tap + to add one.'));
    }

    return ListView.builder(
      itemCount: viceList.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (BuildContext context, int index) {
        final Vice vice = viceList[index];

        return ListTile(
          enabled: !vice.archived,
          contentPadding: EdgeInsets.zero,
          title: Text(vice.name),
          subtitle: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final int? count = ref
                  .watch(viceActivityCountProvider(vice.id))
                  .value;
              return Text(count == null ? ' ' : '$count activities');
            },
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'Edit',
                child: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.of(context).pushNamed('/vices/${vice.id}/edit');
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
                            await ref
                                .read(trackerWritesProvider)
                                .setViceArchived(vice.id, archived: false);
                          } on FirebaseException catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
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
                            await ref
                                .read(trackerWritesProvider)
                                .setViceArchived(vice.id, archived: true);
                          } on FirebaseException catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString())),
                              );
                            }
                          }
                        },
                      ),
                    ),
            ],
          ),
          onTap: () async {
            await Navigator.of(
              context,
            ).pushNamed('/vices/${vice.id}/activities');
            // The count is not live; the history page can delete entries.
            if (context.mounted) {
              ref.invalidate(viceActivityCountForUserProvider);
            }
          },
        );
      },
    );
  }
}
