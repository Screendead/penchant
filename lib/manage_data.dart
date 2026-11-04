import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
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
    } on FirebaseException catch (e, stack) {
      reportError(e, stack, context: 'while archiving or unarchiving a vice');
      message =
          '${archived ? 'Could not archive' : 'Could not unarchive'} '
          '${vice.name}. ${firestoreErrorMessage(e)}';
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
      body: _buildBody(viceListValue: viceListValue),
    );
  }

  Widget _buildBody({required AsyncValue<List<Vice>> viceListValue}) {
    if (viceListValue.error case final Object error) {
      return ErrorView(
        message: loadErrorMessage('your vices', error),
        onRetry: () => ref.invalidate(viceListForUserProvider, asReload: true),
      );
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
