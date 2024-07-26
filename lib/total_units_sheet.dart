import 'package:flutter/material.dart';
import 'package:tracker/utils/file_n_days_ago.dart';
import 'package:tracker/utils/read_data.dart';

class TotalUnitsSheet extends StatelessWidget {
  static const int daysToShow = 30;
  static const double containerInsets = 16;

  const TotalUnitsSheet({
    super.key,
    required Map<String, dynamic> data,
  }) : _data = data;

  final Map<String, dynamic> _data;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);

    return Container(
      padding: const EdgeInsets.all(containerInsets),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue,
            Colors.purple,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 5,
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SizedBox.expand(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Total units consumed',
              style: Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: Colors.white,
                  ),
            ),
            Text(
              '${_data.values.fold<num>(0, (previousValue, element) => previousValue + element)}',
              style: Theme.of(context).textTheme.displayLarge!.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FutureBuilder(
                future: Future.wait(
                  List.generate(
                    daysToShow,
                    (index) =>
                        fileNDaysAgo(daysToShow - index - 1).then(readData),
                  ),
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return SizedBox(
                      width: (mediaQuery.size.width - containerInsets * 2) /
                          daysToShow,
                    );
                  }

                  // Side-scrolling list of colour-coded bars representing daily totals of units consumed
                  return ListView.builder(
                    shrinkWrap: true,
                    scrollDirection: Axis.horizontal,
                    itemCount: daysToShow,
                    itemBuilder: (context, index) {
                      final data = snapshot.data?[index] ?? {};

                      return SizedBox(
                        width: (mediaQuery.size.width - containerInsets * 2) /
                            daysToShow,
                        height: 50,
                        child: Stack(
                          children: data.entries.map((entry) {
                            final totalUnits = entry.value as num;

                            return Positioned(
                              left: (mediaQuery.size.width -
                                      containerInsets * 2) /
                                  daysToShow *
                                  index,
                              bottom: 0,
                              child: ColoredBox(
                                color: Color(
                                  (entry.key.hashCode & 0xFFFFFF) | 0xFF000000,
                                ),
                                child: SizedBox(
                                  width: (mediaQuery.size.width -
                                          containerInsets * 2) /
                                      daysToShow,
                                  height: totalUnits * 10,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/*

ColoredBox(
  // Colour based on hash of tag
  color: Color(
    (data.keys.first.hashCode & 0xFFFFFF) | 0xFF000000,
  ),
  child: SizedBox(
    width: (mediaQuery.size.width - containerInsets * 2) /
        daysToShow,
    height: totalUnits * 10,
  ),
),
*/

/*
if (snapshot.connectionState != ConnectionState.done) {
  return ColoredBox(
    color: Colors.white.withOpacity(0.5),
    child: SizedBox(
      width: (mediaQuery.size.width - containerInsets * 2) /
          daysToShow,
      height: 50,
    ),
  );
}

final data = snapshot.data ?? {};
final totalUnits = data.values.fold<num>(
    0, (previousValue, element) => previousValue + element);

return ColoredBox(
  color: Colors.green,
  child: SizedBox(
    width: (mediaQuery.size.width - containerInsets * 2) /
        daysToShow,
    height: totalUnits * 10,
  ),
);
*/