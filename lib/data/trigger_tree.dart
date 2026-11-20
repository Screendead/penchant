import 'package:flutter/material.dart';

// The starter trigger tree, as Jack picked it. An activity stores a node as
// its path: the ids from the root down, joined by [triggerPathSeparator], such
// as `work/meeting`. Stored paths outlive the app version that wrote them, so a
// node's id never changes once shipped; relabel it instead.

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

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[àáâä]'), 'a')
    .replaceAll(RegExp('[èéêë]'), 'e')
    .replaceAll(RegExp('[ìíîï]'), 'i')
    .replaceAll(RegExp('[òóôö]'), 'o')
    .replaceAll(RegExp('[ùúûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp("['’]"), '');

List<String> _words(String s) =>
    _fold(s).split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();

/// Whether [query] names [label] exactly, ignoring case, accents and spacing.
bool triggerLabelIs(String label, String query) =>
    _words(label).join(' ') == _words(query).join(' ');

/// The paths of [roots] whose labels hold every word of [query] as the start
/// of a word, counting an area's label for its tags: those matched on their
/// own label first, then the rest, each in tree order, areas before their
/// tags.
List<String> searchTriggers(
  String query, {
  List<TriggerNode> roots = triggerTree,
}) {
  final List<String> terms = _words(query);
  if (terms.isEmpty) return const <String>[];
  bool holds(List<String> words) =>
      terms.every((String t) => words.any((String w) => w.startsWith(t)));
  final List<String> own = <String>[];
  final List<String> byArea = <String>[];
  for (final TriggerNode area in roots) {
    final List<String> areaWords = _words(area.label);
    if (holds(areaWords)) own.add(area.id);
    for (final TriggerNode tag in area.children) {
      final List<String> tagWords = _words(tag.label);
      final String path = '${area.id}$triggerPathSeparator${tag.id}';
      if (holds(tagWords)) {
        own.add(path);
      } else if (holds(<String>[...areaWords, ...tagWords])) {
        byArea.add(path);
      }
    }
  }
  return <String>[...own, ...byArea];
}

const List<TriggerNode> triggerTree = <TriggerNode>[
  TriggerNode(
    'social',
    'Who was there',
    icon: Icons.people_outline,
    children: <TriggerNode>[
      TriggerNode('friends', 'With friends'),
      TriggerNode('party', 'Party or event'),
      TriggerNode('date', 'Date'),
      TriggerNode('family', 'Family'),
      TriggerNode('offered', 'Offered one'),
      TriggerNode('alone', 'On my own'),
      TriggerNode('partner', 'Partner'),
      TriggerNode('colleagues', 'Colleagues'),
      TriggerNode('housemates', 'Housemates'),
      TriggerNode('kids', 'Kids around'),
      TriggerNode('new-people', 'New people'),
      TriggerNode('everyone', 'Everyone else was'),
      TriggerNode('hosting', 'Hosting'),
      TriggerNode('pressured', 'Felt pressured'),
      TriggerNode('left-out', 'Felt left out'),
      TriggerNode('online', 'Online with others'),
    ],
  ),
  TriggerNode(
    'people',
    'Between people',
    icon: Icons.forum_outlined,
    children: <TriggerNode>[
      TriggerNode('argument', 'Argument'),
      TriggerNode('hard-talk', 'Hard conversation'),
      TriggerNode('tension', 'Tension at home'),
      TriggerNode('criticised', 'Felt criticised'),
      TriggerNode('let-down', 'Let someone down'),
      TriggerNode('rejected', 'Break-up or rejection'),
      TriggerNode('missing', 'Missing someone'),
      TriggerNode('caring', 'Looking after someone'),
      TriggerNode('made-up', 'Made up after a row'),
      TriggerNode('good-time', 'Good time together'),
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
      TriggerNode('angry', 'Angry'),
      TriggerNode('frustrated', 'Frustrated'),
      TriggerNode('overwhelmed', 'Overwhelmed'),
      TriggerNode('sad', 'Sad'),
      TriggerNode('grieving', 'Grieving'),
      TriggerNode('guilty', 'Guilty or ashamed'),
      TriggerNode('embarrassed', 'Embarrassed'),
      TriggerNode('jealous', 'Jealous'),
      TriggerNode('numb', 'Numb'),
      TriggerNode('irritable', 'Irritable'),
      TriggerNode('hopeless', 'Hopeless'),
      TriggerNode('excited', 'Excited'),
      TriggerNode('relieved', 'Relieved'),
      TriggerNode('proud', 'Proud'),
      TriggerNode('content', 'Content'),
      TriggerNode('nostalgic', 'Nostalgic'),
    ],
  ),
  TriggerNode(
    'for',
    'What it was for',
    icon: Icons.flag_outlined,
    children: <TriggerNode>[
      TriggerNode('relax', 'To relax'),
      TriggerNode('reward', 'To reward myself'),
      TriggerNode('celebrate', 'To celebrate'),
      TriggerNode('cope', 'To cope'),
      TriggerNode('sleep', 'To sleep'),
      TriggerNode('wake-up', 'To wake up'),
      TriggerNode('focus', 'To focus'),
      TriggerNode('fit-in', 'To fit in'),
      TriggerNode('feel', 'To feel something'),
      TriggerNode('stop-thinking', 'To stop thinking'),
      TriggerNode('put-off', 'To put something off'),
      TriggerNode('pass-time', 'To pass the time'),
      TriggerNode('stop-craving', 'To stop the craving'),
      TriggerNode('taste', 'For the taste'),
    ],
  ),
  TriggerNode(
    'event',
    'Something happened',
    icon: Icons.newspaper_outlined,
    children: <TriggerNode>[
      TriggerNode('bad-news', 'Bad news'),
      TriggerNode('good-news', 'Good news'),
      TriggerNode('money-worry', 'Money worry'),
      TriggerNode('payday', 'Payday'),
      TriggerNode('health-worry', 'Health worry'),
      TriggerNode('loss', 'Loss or funeral'),
      TriggerNode('birthday', 'Birthday'),
      TriggerNode('anniversary', 'Anniversary'),
      TriggerNode('festival', 'Holiday or festival'),
      TriggerNode('match', 'Match or game on'),
      TriggerNode('big-change', 'Big change'),
      TriggerNode('plans-off', 'Plans fell through'),
      TriggerNode('dreading', 'Dreading tomorrow'),
    ],
  ),
  TriggerNode(
    'work',
    'Work or study',
    icon: Icons.work_outline,
    children: <TriggerNode>[
      TriggerNode('meeting', 'Meeting'),
      TriggerNode('deadline', 'Deadline'),
      TriggerNode('break', 'On a break'),
      TriggerNode('done', 'Finished for the day'),
      TriggerNode('hard-talk', 'Hard conversation'),
      TriggerNode('long-day', 'Long day'),
      TriggerNode('bad-day', 'Bad day'),
      TriggerNode('good-result', 'Good result'),
      TriggerNode('swamped', 'Too much to do'),
      TriggerNode('idle', 'Nothing to do'),
      TriggerNode('working-late', 'Working late'),
      TriggerNode('presenting', 'Presentation or interview'),
      TriggerNode('job-worry', 'Job worry'),
      TriggerNode('exams', 'Exams or studying'),
      TriggerNode('day-off', 'Day off'),
      TriggerNode('work-drinks', 'Work drinks'),
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
      TriggerNode('hungover', 'Hungover'),
      TriggerNode('thirsty', 'Thirsty'),
      TriggerNode('just-ate', 'Just eaten'),
      TriggerNode('headache', 'Headache'),
      TriggerNode('period', 'Period or cycle'),
      TriggerNode('withdrawal', 'Withdrawal'),
      TriggerNode('caffeine', 'Too much caffeine'),
      TriggerNode('jet-lag', 'Jet-lagged'),
      TriggerNode('injured', 'Injured'),
      TriggerNode('medication', 'On medication'),
      TriggerNode('felt-good', 'Felt good'),
    ],
  ),
  TriggerNode(
    'doing',
    'What I was doing',
    icon: Icons.touch_app_outlined,
    children: <TriggerNode>[
      TriggerNode('tv', 'Watching TV'),
      TriggerNode('scrolling', 'Scrolling'),
      TriggerNode('gaming', 'Gaming'),
      TriggerNode('working', 'Working'),
      TriggerNode('driving', 'Driving'),
      TriggerNode('cooking', 'Cooking'),
      TriggerNode('eating-out', 'Eating out'),
      TriggerNode('call', 'On a call'),
      TriggerNode('housework', 'Housework'),
      TriggerNode('reading', 'Reading'),
      TriggerNode('music', 'Listening to music'),
      TriggerNode('sport', 'Watching sport'),
      TriggerNode('waiting', 'Waiting around'),
      TriggerNode('walking', 'Out walking'),
      TriggerNode('nothing', 'Nothing much'),
    ],
  ),
  TriggerNode(
    'routine',
    'Time and routine',
    icon: Icons.schedule,
    children: <TriggerNode>[
      TriggerNode('morning', 'Morning'),
      TriggerNode('meal', 'With a meal'),
      TriggerNode('wind-down', 'Winding down'),
      TriggerNode('weekend', 'Weekend'),
      TriggerNode('habit', 'Out of habit'),
      TriggerNode('first-thing', 'First thing'),
      TriggerNode('after-lunch', 'After lunch'),
      TriggerNode('slump', 'Afternoon slump'),
      TriggerNode('after-work', 'After work'),
      TriggerNode('evening', 'Evening'),
      TriggerNode('late-night', 'Late night'),
      TriggerNode('before-bed', 'Before bed'),
      TriggerNode('mid-night', 'Middle of the night'),
      TriggerNode('coffee', 'With coffee'),
      TriggerNode('drink', 'With a drink'),
      TriggerNode('friday', 'Friday'),
      TriggerNode('sunday', 'Sunday'),
      TriggerNode('broken', 'Routine broken'),
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
      TriggerNode('at-work', 'At work'),
      TriggerNode('their-place', "Someone else's home"),
      TriggerNode('car', 'In the car'),
      TriggerNode('shop', 'Shop'),
      TriggerNode('cafe', 'Café'),
      TriggerNode('gig', 'Gig, club or festival'),
      TriggerNode('gym', 'Gym or sports ground'),
      TriggerNode('hotel', 'Hotel'),
      TriggerNode('station', 'Airport or station'),
      TriggerNode('on-holiday', 'On holiday'),
      TriggerNode('in-bed', 'In bed'),
      TriggerNode('garden', 'Garden or balcony'),
    ],
  ),
  TriggerNode(
    'craving',
    'Cue',
    icon: Icons.bolt_outlined,
    children: <TriggerNode>[
      TriggerNode('saw', 'Saw it'),
      TriggerNode('smelled', 'Smelled it'),
      TriggerNode('others', 'Someone else had one'),
      TriggerNode('feed', 'Ad or feed'),
      TriggerNode('wanted', 'Just wanted it'),
      TriggerNode('in-house', 'It was in the house'),
      TriggerNode('walked-past', 'Walked past the place'),
      TriggerNode('on-offer', 'On offer or free'),
      TriggerNode('on-screen', 'In a film or show'),
      TriggerNode('memory', 'A song or memory'),
      TriggerNode('first-one', 'After the first one'),
      TriggerNode('other-habit', 'Another habit set it off'),
      TriggerNode('all-day', 'Thought about it all day'),
      TriggerNode('out-of-nowhere', 'Out of nowhere'),
      TriggerNode('holding-off', 'Had been holding off'),
    ],
  ),
];
