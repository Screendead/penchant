import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/writes/settle_write.dart';

class ManageData extends ConsumerStatefulWidget {
  const ManageData({super.key});

  @override
  ConsumerState<ManageData> createState() => _ManageDataState();
}

class _ManageDataState extends ConsumerState<ManageData> {
  final Set<String> archiving = <String>{};

  Future<void> _setArchived(Vice vice, {required bool archived}) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      archiving.add(vice.id);
    });

    String? message;
    try {
      if (!await settleWrite(
        ref
            .read(trackerWritesProvider)
            .setViceArchived(vice.id, archived: archived),
      )) {
        message = queuedMessage;
      }
    } on FirebaseException catch (e) {
      message = e.toString();
    }

    if (mounted) {
      setState(() {
        archiving.remove(vice.id);
      });
    }
    if (message != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Vice>?> viceListValue = ref.watch(viceListProvider);
    final AsyncValue<List<ViceActivity>?> viceActivityListValue = ref.watch(
      viceActivityListProvider,
    );

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
      body: _buildBody(
        viceListValue: viceListValue,
        viceActivityListValue: viceActivityListValue,
      ),
    );
  }

  Widget _buildBody({
    required AsyncValue<List<Vice>?> viceListValue,
    required AsyncValue<List<ViceActivity>?> viceActivityListValue,
  }) {
    if (viceListValue.error ?? viceActivityListValue.error
        case final Object error) {
      return Center(child: Text('Unable to load your vices: $error'));
    }

    final List<Vice>? viceList = viceListValue.value;
    final List<ViceActivity>? viceActivityList = viceActivityListValue.value;

    if (viceList == null || viceActivityList == null) {
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
        final List<ViceActivity> viceActivities = viceActivityList
            .where(
              (ViceActivity viceActivity) => viceActivity.viceID == vice.id,
            )
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
                    Navigator.of(context).pushNamed('/vices/${vice.id}/edit');
                  },
                ),
              ),
              vice.archived
                  ? Tooltip(
                      message: 'Unarchive',
                      child: IconButton(
                        icon: const Icon(Icons.unarchive),
                        onPressed: archiving.contains(vice.id)
                            ? null
                            : () => _setArchived(vice, archived: false),
                      ),
                    )
                  : Tooltip(
                      message: 'Archive',
                      child: IconButton(
                        icon: const Icon(Icons.archive),
                        onPressed: archiving.contains(vice.id)
                            ? null
                            : () => _setArchived(vice, archived: true),
                      ),
                    ),
            ],
          ),
          onTap: () {
            Navigator.of(context).pushNamed('/vices/${vice.id}/activities');
          },
        );
      },
    );
  }
}
