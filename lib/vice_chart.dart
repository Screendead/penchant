import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends StatelessWidget {
  const ViceChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<List<Vice>>(
        stream: FirebaseFirestore.instance
            .collection('vices')
            .orderBy(
              'createdAt',
              descending: true,
            )
            .where(
              'ownerID',
              isEqualTo: FirebaseAuth.instance.currentUser!.uid,
            )
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map(
                    (doc) => Vice.fromJson(
                      id: doc.id,
                      json: doc.data(),
                    ),
                  )
                  .toList(),
            ),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<Vice>> snapshot,
        ) {
          if (snapshot.hasError) {
            return InfoBox(
              message: 'Error loading vices:\n${snapshot.error.toString()}',
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
              message: 'No vices found.',
              color: Colors.blue,
            );
          }

          final List<Vice> vices = snapshot.data!;
          final List<String> viceIDs = vices.map((vice) => vice.id).toList();

          return StreamBuilder<Map<String, List<ViceActivity>>>(
            stream: FirebaseFirestore.instance
                .collection('activities')
                .where(
                  'viceID',
                  whereIn: viceIDs,
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
                  (snapshot) =>
                      snapshot.docs.fold<Map<String, List<ViceActivity>>>(
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

              final Map<String, List<ViceActivity>> viceActivities =
                  snapshot.data!;
              final List<Widget> charts = vices.map((vice) {
                final List<ViceActivity> activities =
                    viceActivities[vice.id] ?? <ViceActivity>[];

                return Column(
                  children: [
                    Text(vice.name),
                    Text(vice.unit.name),
                    Text(activities.length.toString()),
                  ],
                );
              }).toList();

              return ListView(
                children: charts,
              );
            },
          );
        },
      ),
    );
  }
}
