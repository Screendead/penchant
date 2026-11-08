import 'package:flutter/material.dart';

// The starter trigger tree Jack picked on 2026-11-06 ("Areas of life", option A
// on the tag archive/mockup/trigger-tree). An activity stores a node as its path: the ids from
// the root down, joined by [triggerPathSeparator], such as `work/meeting`.
// Stored paths outlive the app version that wrote them, so a node's id never
// changes once shipped; relabel it instead.

const String triggerPathSeparator = '/';

@immutable
class TriggerNode {
  const TriggerNode(
    this.id,
    this.label, {
    this.icon,
    this.children = const <TriggerNode>[],
  });

  final String id;
  final String label;
  final IconData? icon;
  final List<TriggerNode> children;
}

/// The labels from the root down to [path], or null when [path] does not name
/// a node of [roots] (a free-text trigger).
List<String>? triggerLabels(
  String path, {
  List<TriggerNode> roots = triggerTree,
}) {
  final List<String> labels = <String>[];
  List<TriggerNode> level = roots;
  for (final String id in path.split(triggerPathSeparator)) {
    final TriggerNode? node = level.where((n) => n.id == id).firstOrNull;
    if (node == null) return null;
    labels.add(node.label);
    level = node.children;
  }
  return labels;
}

/// Every node's path, parents before their children.
Iterable<String> triggerPaths({List<TriggerNode> roots = triggerTree}) sync* {
  for (final TriggerNode node in roots) {
    yield node.id;
    for (final String child in triggerPaths(roots: node.children)) {
      yield '${node.id}$triggerPathSeparator$child';
    }
  }
}

const List<TriggerNode> triggerTree = <TriggerNode>[
  TriggerNode(
    'social',
    'Social',
    icon: Icons.people_outline,
    children: <TriggerNode>[
      TriggerNode('friends', 'With friends'),
      TriggerNode('party', 'Party or event'),
      TriggerNode('date', 'Date'),
      TriggerNode('family', 'Family'),
      TriggerNode('offered', 'Offered one'),
      TriggerNode('alone', 'On my own'),
    ],
  ),
  TriggerNode(
    'feeling',
    'Feeling',
    icon: Icons.mood,
    children: <TriggerNode>[
      TriggerNode('stressed', 'Stressed'),
      TriggerNode('bored', 'Bored'),
      TriggerNode('low', 'Low'),
      TriggerNode('anxious', 'Anxious'),
      TriggerNode('lonely', 'Lonely'),
      TriggerNode('happy', 'Happy'),
      TriggerNode('restless', 'Restless'),
    ],
  ),
  TriggerNode(
    'work',
    'Work',
    icon: Icons.work_outline,
    children: <TriggerNode>[
      TriggerNode('meeting', 'Meeting'),
      TriggerNode('deadline', 'Deadline'),
      TriggerNode('break', 'On a break'),
      TriggerNode('done', 'Finished for the day'),
      TriggerNode('hard-talk', 'Hard conversation'),
      TriggerNode('long-day', 'Long day'),
    ],
  ),
  TriggerNode(
    'body',
    'Body',
    icon: Icons.accessibility_new,
    children: <TriggerNode>[
      TriggerNode('tired', 'Tired'),
      TriggerNode('hungry', 'Hungry'),
      TriggerNode('pain', 'In pain'),
      TriggerNode('no-sleep', "Couldn't sleep"),
      TriggerNode('exercise', 'After exercise'),
      TriggerNode('unwell', 'Unwell'),
    ],
  ),
  TriggerNode(
    'routine',
    'Routine',
    icon: Icons.schedule,
    children: <TriggerNode>[
      TriggerNode('morning', 'Morning'),
      TriggerNode('meal', 'With a meal'),
      TriggerNode('wind-down', 'Winding down'),
      TriggerNode('weekend', 'Weekend'),
      TriggerNode('habit', 'Out of habit'),
    ],
  ),
  TriggerNode(
    'place',
    'Place',
    icon: Icons.place_outlined,
    children: <TriggerNode>[
      TriggerNode('home', 'Home'),
      TriggerNode('bar', 'Bar or restaurant'),
      TriggerNode('commute', 'Commute'),
      TriggerNode('travelling', 'Travelling'),
      TriggerNode('outdoors', 'Outdoors'),
    ],
  ),
  TriggerNode(
    'craving',
    'Craving',
    icon: Icons.bolt_outlined,
    children: <TriggerNode>[
      TriggerNode('saw', 'Saw it'),
      TriggerNode('smelled', 'Smelled it'),
      TriggerNode('others', 'Someone else had one'),
      TriggerNode('feed', 'Ad or feed'),
      TriggerNode('wanted', 'Just wanted it'),
    ],
  ),
];
