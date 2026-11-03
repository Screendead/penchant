import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracker/data/day.dart';
import 'package:tracker/data/unit.dart';
import 'package:tracker/data/vice.dart';
import 'package:tracker/data/vice_activity.dart';
import 'package:tracker/mockups/brand/brand_icons.dart';
import 'package:tracker/providers/unarchived_vice_list_provider.dart';
import 'package:tracker/providers/vice_activity_day_provider.dart';
import 'package:tracker/vice_tracker.dart';
import 'package:tracker/widgets/clean_day.dart';

const String storeSubtitle = 'Habit journal & sleep insights';

ThemeData appTheme() => ThemeData(
  fontFamily: 'Roboto',
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.pink,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);

// Round, neutral demo numbers, so the screenshot reads as illustrative.
const List<(String, Unit, int)> _demoDay = [
  ('Coffee', Unit.drink, 3),
  ('Screen time', Unit.hour, 2),
  ('Late nights', Unit.time, 1),
  ('Sugar', Unit.item, 2),
  ('Takeaways', Unit.item, 1),
];

Vice _vice(String name, Unit unit) => Vice(
  id: name,
  name: name,
  unit: unit,
  ownerID: 'demo',
  createdAt: Timestamp.fromMillisecondsSinceEpoch(0),
  archived: false,
);

/// The real Home screen layout over demo data, titled with the brand.
class BrandedTodayScreen extends StatelessWidget {
  const BrandedTodayScreen({
    super.key,
    required this.title,
    this.clean = false,
  });

  final String title;
  final bool clean;

  @override
  Widget build(BuildContext context) {
    final List<Vice> vices = [
      for (final (String name, Unit unit, int _) in _demoDay) _vice(name, unit),
    ];

    return ProviderScope(
      overrides: [
        unarchivedViceListProvider.overrideWith((ref) => Stream.value(vices)),
        viceActivityDayProvider.overrideWith((ref, DateTime day) {
          return Stream.value([
            if (!clean)
              for (final (String name, Unit _, int quantity) in _demoDay)
                ViceActivity(
                  id: '$name-$quantity',
                  viceID: name,
                  quantity: quantity,
                  ownerID: 'demo',
                  createdAt: Timestamp.fromDate(startOfDay(day)),
                ),
          ]);
        }),
      ],
      child: Theme(
        data: appTheme(),
        child: Builder(
          builder: (BuildContext context) {
            return Scaffold(
              appBar: AppBar(
                title: Text(title),
                leading: const Icon(Icons.menu),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                ],
              ),
              body: clean ? const CleanDay(isToday: true) : const ViceTracker(),
              bottomNavigationBar: NavigationBar(
                selectedIndex: 0,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.today_outlined),
                    selectedIcon: Icon(Icons.today),
                    label: 'Today',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.show_chart_outlined),
                    label: 'Graph',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One App Store screenshot: a caption over the app screen, in the icon's
/// palette. 1320 x 2868 px is the 6.9-inch iPhone size; this keeps its ratio.
class StoreScreenshot extends StatelessWidget {
  const StoreScreenshot({
    super.key,
    required this.width,
    required this.caption,
    required this.screen,
  });

  final double width;
  final String caption;
  final Widget screen;

  @override
  Widget build(BuildContext context) {
    final double scale = width / 393;
    final double phoneWidth = width * 0.74;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * scale),
      child: Container(
        width: width,
        height: width * 2868 / 1320,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [IconPalette.inkLight, IconPalette.inkDark],
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: 70 * scale),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 28 * scale),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: IconPalette.cream,
                  fontSize: 38 * scale,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(height: 46 * scale),
            Expanded(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: Container(
                  width: phoneWidth,
                  padding: EdgeInsets.all(8 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF050407),
                    borderRadius: BorderRadius.circular(48 * scale),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40 * scale),
                    child: FittedBox(
                      child: SizedBox(width: 393, height: 852, child: screen),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An App Store product page (393 x 852 pt, light appearance) for one brand.
class StoreListingMock extends StatelessWidget {
  const StoreListingMock({super.key, required this.name, required this.icon});

  final String name;
  final Widget icon;

  static const Color _blue = Color(0xFF007AFF);
  static const Color _grey = Color(0xFF8A8A8E);
  static const Color _rule = Color(0xFFDCDCE0);

  Widget _fact(String label, Widget value, String detail) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _grey,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(height: 26, child: Center(child: value)),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _grey, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget get _divider => const SizedBox(
    height: 44,
    child: VerticalDivider(color: _rule, width: 1),
  );

  @override
  Widget build(BuildContext context) {
    const TextStyle big = TextStyle(
      color: Color(0xFF6C6C70),
      fontSize: 20,
      fontWeight: FontWeight.w700,
    );

    return SizedBox(
      width: 393,
      height: 852,
      child: ColoredBox(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 54,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(44, 16, 30, 0),
                child: Row(
                  children: const [
                    Text(
                      '9:41',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.signal_cellular_alt, size: 18),
                    SizedBox(width: 5),
                    Icon(Icons.wifi, size: 18),
                    SizedBox(width: 5),
                    Icon(Icons.battery_full, size: 20),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.chevron_left, color: _blue, size: 32),
                  Text('Search', style: TextStyle(color: _blue, fontSize: 17)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(27),
                      border: Border.all(color: _rule, width: 0.5),
                    ),
                    child: MaskedIcon(size: 118, child: icon),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 118,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            storeSubtitle,
                            style: TextStyle(color: _grey, fontSize: 15),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _blue,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Get',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.ios_share,
                                color: _blue,
                                size: 22,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Divider(color: _rule, height: 1),
            ),
            Row(
              children: [
                _fact('RATINGS', const Text('—', style: big), 'Not enough'),
                _divider,
                _fact('AGE', const Text('18+', style: big), 'Years Old'),
                _divider,
                _fact(
                  'CATEGORY',
                  const Icon(Icons.favorite_border, color: Color(0xFF6C6C70)),
                  'Health & Fitness',
                ),
                _divider,
                _fact(
                  'DEVELOPER',
                  const Icon(Icons.person_outline, color: Color(0xFF6C6C70)),
                  'Screendead',
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Divider(color: _rule, height: 1),
            ),
            Expanded(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxWidth: double.infinity,
                  maxHeight: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StoreScreenshot(
                          width: 222,
                          caption: 'Your day,\nat a glance',
                          screen: BrandedTodayScreen(title: name),
                        ),
                        const SizedBox(width: 10),
                        StoreScreenshot(
                          width: 222,
                          caption: 'Quiet days,\nnoted too',
                          screen: BrandedTodayScreen(title: name, clean: true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
