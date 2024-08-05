import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({
    super.key,
    required this.date,
  });

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Vice>? vices = ref.watch(viceListProvider).value;

    if (vices == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<Map<String, List<ViceActivity>>>(
        stream: FirebaseFirestore.instance
            .collection('activities')
            .where(
              'viceID',
              whereIn: vices.map((vice) => vice.id),
            )
            .where(
              'ownerID',
              isEqualTo: FirebaseAuth.instance.currentUser!.uid,
            )
            .orderBy(
              'createdAt',
              descending: true,
            )
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.fold<Map<String, List<ViceActivity>>>(
                <String, List<ViceActivity>>{},
                (map, doc) {
                  final ViceActivity activity = ViceActivity.fromJson(
                    id: doc.id,
                    json: doc.data(),
                  );

                  if (map.containsKey(activity.viceID)) {
                    map[activity.viceID]!.add(activity);
                  } else {
                    map[activity.viceID] = <ViceActivity>[activity];
                  }

                  return map;
                },
              ),
            ),
        builder: (
          BuildContext context,
          AsyncSnapshot<Map<String, List<ViceActivity>>> snapshot,
        ) {
          if (snapshot.hasError) {
            return InfoBox(
              message:
                  'Error loading activities:\n${snapshot.error.toString()}',
              color: Colors.red,
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (!snapshot.hasData) {
            return const InfoBox(
              message: 'No vice activities found.',
              color: Colors.blue,
            );
          }

          final Map<String, List<ViceActivity>> viceActivities = snapshot.data!;
          final Map<String, int> dailyData = {};
          final int maxQuantity = viceActivities.values
              .expand((activities) => activities)
              .map((activity) => activity.quantity)
              .fold(0, (a, b) => a > b ? a : b);

          for (var vice in vices) {
            dailyData[vice.name] = 0;
          }

          viceActivities.forEach((viceID, activities) {
            for (var activity in activities) {
              if (isSameDay(activity.createdAt.toDate(), date)) {
                final vice = vices.firstWhere((v) => v.id == viceID);
                dailyData[vice.name] =
                    (dailyData[vice.name] ?? 0) + activity.quantity;
              }
            }
          });

          final dataEntries = dailyData.entries
              .map(
                (e) => RadarEntry(
                  value: e.value.toDouble(),
                ),
              )
              .toList();

          final ThemeData theme = Theme.of(context);

          return RadarChart(
            RadarChartData(
              dataSets: [
                RadarDataSet(
                  fillColor: theme.colorScheme.primary.withOpacity(0.2),
                  borderColor: theme.colorScheme.primary,
                  entryRadius: 6,
                  dataEntries: dataEntries,
                  borderWidth: 2,
                ),
              ],
              radarBackgroundColor: Colors.transparent,
              borderData: FlBorderData(
                show: false,
              ),
              radarBorderData: const BorderSide(
                color: Colors.transparent,
              ),
              radarShape: RadarShape.polygon,
              titlePositionPercentageOffset: 0.2,
              titleTextStyle: TextStyle(
                color: theme.colorScheme.secondary,
                fontSize: 14,
              ),
              getTitle: (index, angle) {
                final Vice vice = vices.firstWhere(
                  (v) => v.name == dailyData.keys.elementAt(index),
                );
                final int quantity = dailyData.values.elementAt(index);

                return RadarChartTitle(
                  text: '${vice.name} (${vice.unit.label(quantity)})',
                  angle: angle,
                );
              },
              tickCount: maxQuantity,
              ticksTextStyle: TextStyle(
                color: theme.colorScheme.secondary,
                fontSize: 10,
              ),
              tickBorderData: BorderSide(
                color: theme.colorScheme.tertiary,
              ),
              gridBorderData: BorderSide(
                color: theme.colorScheme.tertiary,
                width: 2,
              ),
            ),
            swapAnimationDuration: const Duration(
              milliseconds: 400,
            ),
          );
        },
      ),
    );
  }

  bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
