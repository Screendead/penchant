import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/errors/firestore_errors.dart';
import 'package:tracker/formats.dart';
import 'package:tracker/providers/offline_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_list_provider.dart';
import 'package:tracker/widgets/clean_day.dart';
import 'package:tracker/widgets/info_box.dart';

class ViceChart extends ConsumerWidget {
  const ViceChart({super.key, required this.selectedDate});

  final DateTime selectedDate;

  static const double barHeight = 16;
  static const Duration barAnimation = Duration(milliseconds: 600);

  static String total(Vice vice, int quantity) =>
      '${vice.name}: ${vice.unit.label(quantity)}';

  static String summary(DateTime day, List<Vice> vices, List<int> quantities) {
    final String totals = [
      for (int i = 0; i < vices.length; i++) total(vices[i], quantities[i]),
    ].join('; ');

    return 'Totals for ${formatDay(day)}. $totals';
  }

  // Each bar's length as a share of the day's largest total.
  static double share(int quantity, int largest) =>
      largest == 0 ? 0 : quantity / largest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Vice>> vicesValue = ref.watch(
      unarchivedViceListProvider,
    );
    final AsyncValue<List<ViceActivity>> activitiesValue = ref.watch(
      viceActivityDayProvider(selectedDate),
    );

    final List<Vice>? vices = vicesValue.value;

    // With no vices there is nothing to chart, whatever the day's query did.
    if (!vicesValue.hasError && vices != null && vices.isEmpty) {
      return const InfoBox(
        message: 'No vices yet. Add one from Manage Data in the menu.',
      );
    }

    if (vicesValue.error ?? activitiesValue.error case final Object error) {
      return InfoBox(
        message: loadErrorMessage('this day', error),
        isError: true,
        onRetry: () {
          ref.invalidate(viceListForUserProvider, asReload: true);
          ref.invalidate(viceActivityDayForUserProvider, asReload: true);
        },
      );
    }

    final List<ViceActivity>? activityList = activitiesValue.value;

    if (vices == null || activityList == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final Map<String, int> quantityByViceID = {
      for (final Vice vice in vices) vice.id: 0,
    };

    for (final ViceActivity activity in activityList) {
      final int? quantity = quantityByViceID[activity.viceID];
      if (quantity != null) {
        quantityByViceID[activity.viceID] = quantity + activity.quantity;
      }
    }

    if (quantityByViceID.values.every((int quantity) => quantity == 0)) {
      return CleanDay(
        isToday: daysBetween(selectedDate, startOfDay(DateTime.now())) == 0,
        offline: ref.watch(offlineProvider).value ?? false,
      );
    }

    final List<int> quantities = [
      for (final Vice vice in vices) quantityByViceID[vice.id]!,
    ];
    final int largest = quantities.reduce(max);

    return Semantics(
      container: true,
      label: summary(selectedDate, vices, quantities),
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) =>
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: max(0, constraints.maxHeight - 32),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (int i = 0; i < vices.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _ViceBar(
                          vice: vices[i],
                          quantity: quantities[i],
                          share: share(quantities[i], largest),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}

class _ViceBar extends StatelessWidget {
  const _ViceBar({
    required this.vice,
    required this.quantity,
    required this.share,
  });

  final Vice vice;
  final int quantity;
  final double share;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool none = quantity == 0;
    final Color ink = none ? colors.onSurfaceVariant : colors.onSurface;
    final TextStyle nameStyle = theme.textTheme.titleMedium!.copyWith(
      color: ink,
      fontWeight: none ? FontWeight.w400 : FontWeight.w500,
    );
    final TextStyle countStyle = theme.textTheme.titleMedium!.copyWith(
      color: ink,
      fontWeight: none ? FontWeight.w400 : FontWeight.w700,
    );
    final TextStyle unitStyle = theme.textTheme.bodyMedium!.copyWith(
      color: colors.onSurfaceVariant,
    );
    final BorderRadius radius = BorderRadius.circular(ViceChart.barHeight / 3);

    final TextSpan amount = TextSpan(
      children: [
        TextSpan(text: formatCount(quantity), style: countStyle),
        TextSpan(text: ' ${vice.unit.nameFor(quantity)}', style: unitStyle),
      ],
    );
    final TextPainter amountPainter = TextPainter(
      text: amount,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double amountWidth = amountPainter.width;
    amountPainter.dispose();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              // At large text the amount alone can fill the row and squeeze
              // the name to a letter a line, so it moves under the name.
              amountWidth > constraints.maxWidth / 3
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vice.name, style: nameStyle),
                    Text.rich(amount),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: Text(vice.name, style: nameStyle)),
                    const SizedBox(width: 12),
                    Text.rich(amount),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: ViceChart.barHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: radius,
            ),
            child: AnimatedFractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: share,
              duration: ViceChart.barAnimation,
              curve: Curves.fastOutSlowIn,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: radius,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
