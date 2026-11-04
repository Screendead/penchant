import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/errors/report_error.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/tracker_writes_provider.dart';
import 'package:tracker/providers/vice_activity_history_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';
import 'package:tracker/widgets/sync_status.dart';
import 'package:tracker/writes/rejected_writes.dart';
import 'package:tracker/writes/settle_write.dart';

class ManageData extends ConsumerStatefulWidget {
  const ManageData({super.key});

  static const String archivedLabel = 'Archived';
  static const String countUnavailable = 'Count unavailable';

  static String countText(ActivityCount count) {
    final String activities =
        '${formatCount(count.count)} '
        '${pluralWord(count.count, one: 'activity', other: 'activities')}';
    return switch (count.source) {
      CountSource.server => activities,
      CountSource.deviceOffline => '$activities on this device (offline)',
      CountSource.deviceServerFailed =>
        '$activities on this device (server count unavailable)',
    };
  }

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
        onRejectedLater: ref
            .read(rejectedWritesProvider.notifier)
            .reporter(
              '${archived ? 'Not archived' : 'Not unarchived'}: ${vice.name}',
            ),
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
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(child: _buildBody(viceListValue: viceListValue)),
        ],
      ),
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

        // An archived vice keeps its history, so its row still opens it.
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(vice.name),
          subtitle: Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? child) {
              final AsyncValue<ActivityCount> count = ref.watch(
                viceActivityCountProvider(vice.id),
              );
              // A re-run keeps the last count until the new one arrives.
              final String text = <String>[
                if (vice.archived) ManageData.archivedLabel,
                switch (count.value) {
                  final ActivityCount value => ManageData.countText(value),
                  null when count.hasError => ManageData.countUnavailable,
                  null => '',
                },
              ].where((String part) => part.isNotEmpty).join(', ');
              // A blank line holds the row's height until the count loads.
              return Text(text.isEmpty ? ' ' : text);
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
