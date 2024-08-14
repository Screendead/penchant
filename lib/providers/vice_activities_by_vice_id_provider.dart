import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/providers/vice_activity_list_provider.dart';

final viceActivityListByViceIDProvider =
    Provider<Map<String, List<ViceActivity>>?>((ref) {
  final List<ViceActivity>? viceActivityList =
      ref.watch(viceActivityListProvider).value;

  if (viceActivityList == null) {
    return null;
  }

  return viceActivityList.fold<Map<String, List<ViceActivity>>>(
    <String, List<ViceActivity>>{},
    (Map<String, List<ViceActivity>> map, ViceActivity viceActivity) {
      if (map.containsKey(viceActivity.viceID)) {
        map[viceActivity.viceID]!.add(viceActivity);
      } else {
        map[viceActivity.viceID] = <ViceActivity>[viceActivity];
      }

      return map;
    },
  );
});
