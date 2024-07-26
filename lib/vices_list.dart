import 'package:flutter/material.dart';
import 'package:tracker/vice_tracker_tile.dart';

class VicesList extends StatelessWidget {
  const VicesList({
    super.key,
    required this.data,
    this.onChanged,
  });

  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        ViceTrackerTile(
          tag: 'cannabisPuffs',
          vice: 'Cannabis',
          unitsSingular: 'puff',
          unitsPlural: 'puffs',
          icon: Icons.grass,
          data: data,
          onChanged: onChanged,
        ),
        ViceTrackerTile(
          tag: 'alcoholicDrinks',
          vice: 'Alcoholic drinks',
          unitsSingular: 'drink',
          unitsPlural: 'drinks',
          icon: Icons.wine_bar,
          data: data,
          onChanged: onChanged,
        ),
        ViceTrackerTile(
          tag: 'sweetFood',
          vice: 'Sweet food',
          unitsSingular: 'portion',
          unitsPlural: 'portions',
          icon: Icons.cake,
          data: data,
          onChanged: onChanged,
        ),
        ViceTrackerTile(
          tag: 'caffeinatedDrinks',
          vice: 'Caffeinated drinks',
          unitsSingular: 'drink',
          unitsPlural: 'drinks',
          icon: Icons.coffee,
          data: data,
          onChanged: onChanged,
        ),
        ViceTrackerTile(
          tag: 'cigarillos',
          vice: 'Tobacco',
          unitsSingular: 'cigarillo',
          unitsPlural: 'cigarillos',
          icon: Icons.smoking_rooms,
          data: data,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
