import 'package:flutter/material.dart';
import 'package:tracker/mockups/trigger_tree/trigger_tree.dart';

// Three candidate starter trees, top two levels only. The free-text tile is the
// picker's, not a node, so no tree carries an "Other" root.

/// A. The tree as written in ideas/insights/trigger-tagging.md: areas of life,
/// mixing what was going on with where and who.
const TriggerTree areasTree = TriggerTree(
  id: 'areas',
  name: 'A. Areas of life',
  prompt: 'What was it about?',
  roots: <TriggerNode>[
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
  ],
);

/// B. Reasons only: every root answers "why". Where and who are left to the
/// separate `place` and `with` context fields in
/// ideas/insights/granular-logging-and-data-model.md.
const TriggerTree reasonsTree = TriggerTree(
  id: 'reasons',
  name: 'B. Reasons only',
  prompt: 'What was behind it?',
  roots: <TriggerNode>[
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
      'body',
      'Body',
      icon: Icons.accessibility_new,
      children: <TriggerNode>[
        TriggerNode('tired', 'Tired'),
        TriggerNode('hungry', 'Hungry'),
        TriggerNode('pain', 'In pain'),
        TriggerNode('no-sleep', "Couldn't sleep"),
        TriggerNode('focus', 'Needed focus'),
        TriggerNode('exercise', 'After exercise'),
      ],
    ),
    TriggerNode(
      'pressure',
      'Pressure',
      icon: Icons.hourglass_bottom,
      children: <TriggerNode>[
        TriggerNode('deadline', 'Deadline'),
        TriggerNode('meeting', 'Meeting'),
        TriggerNode('money', 'Money'),
        TriggerNode('study', 'Study or exams'),
        TriggerNode('hard-talk', 'Hard conversation'),
        TriggerNode('too-much', 'Too much on'),
      ],
    ),
    TriggerNode(
      'occasion',
      'Occasion',
      icon: Icons.celebration_outlined,
      children: <TriggerNode>[
        TriggerNode('celebrating', 'Celebrating'),
        TriggerNode('night-out', 'Night out'),
        TriggerNode('meal', 'A meal'),
        TriggerNode('weekend', 'Weekend'),
        TriggerNode('holiday', 'Holiday'),
        TriggerNode('date', 'Date'),
      ],
    ),
    TriggerNode(
      'people',
      'People',
      icon: Icons.people_outline,
      children: <TriggerNode>[
        TriggerNode('offered', 'Offered one'),
        TriggerNode('others', 'Others were'),
        TriggerNode('company', 'Keeping someone company'),
        TriggerNode('fit-in', 'Fitting in'),
        TriggerNode('conflict', 'After an argument'),
      ],
    ),
    TriggerNode(
      'habit',
      'Habit',
      icon: Icons.repeat,
      children: <TriggerNode>[
        TriggerNode('time', 'Time of day'),
        TriggerNode('after-meal', 'After eating'),
        TriggerNode('wind-down', 'Winding down'),
        TriggerNode('waiting', 'Waiting'),
        TriggerNode('autopilot', 'Without thinking'),
      ],
    ),
    TriggerNode(
      'cue',
      'Cue',
      icon: Icons.visibility_outlined,
      children: <TriggerNode>[
        TriggerNode('saw', 'Saw it'),
        TriggerNode('smelled', 'Smelled it'),
        TriggerNode('feed', 'Ad or feed'),
        TriggerNode('in-reach', 'It was in reach'),
        TriggerNode('wanted', 'Just wanted it'),
      ],
    ),
  ],
);

/// C. Feelings first: the root is how it felt, the second level is what it was
/// about. The same situation (work, money) can appear under several feelings.
const TriggerTree feelingsTree = TriggerTree(
  id: 'feelings',
  name: 'C. Feelings first',
  prompt: 'How were you feeling?',
  roots: <TriggerNode>[
    TriggerNode(
      'stressed',
      'Stressed',
      icon: Icons.thunderstorm_outlined,
      children: <TriggerNode>[
        TriggerNode('work', 'Work'),
        TriggerNode('deadline', 'Deadline'),
        TriggerNode('money', 'Money'),
        TriggerNode('people', 'Someone'),
        TriggerNode('too-much', 'Too much on'),
        TriggerNode('unsure', 'Not sure why'),
      ],
    ),
    TriggerNode(
      'bored',
      'Bored',
      icon: Icons.hourglass_empty,
      children: <TriggerNode>[
        TriggerNode('waiting', 'Waiting'),
        TriggerNode('nothing-on', 'Nothing on'),
        TriggerNode('dull-task', 'Dull task'),
        TriggerNode('travel', 'Travelling'),
        TriggerNode('scrolling', 'Scrolling'),
      ],
    ),
    TriggerNode(
      'tired',
      'Tired',
      icon: Icons.bedtime_outlined,
      children: <TriggerNode>[
        TriggerNode('poor-sleep', 'Poor sleep'),
        TriggerNode('early', 'Early start'),
        TriggerNode('long-day', 'Long day'),
        TriggerNode('focus', 'Needed focus'),
        TriggerNode('late', 'Late night'),
      ],
    ),
    TriggerNode(
      'low',
      'Low',
      icon: Icons.cloud_outlined,
      children: <TriggerNode>[
        TriggerNode('lonely', 'Lonely'),
        TriggerNode('let-down', 'Let down'),
        TriggerNode('missing', 'Missing someone'),
        TriggerNode('unwell', 'Unwell'),
        TriggerNode('unsure', 'Not sure why'),
      ],
    ),
    TriggerNode(
      'anxious',
      'Anxious',
      icon: Icons.waves,
      children: <TriggerNode>[
        TriggerNode('social', 'Social event'),
        TriggerNode('big-day', 'Big day ahead'),
        TriggerNode('health', 'Health'),
        TriggerNode('news', 'News'),
        TriggerNode('unsure', 'Not sure why'),
      ],
    ),
    TriggerNode(
      'good',
      'Good mood',
      icon: Icons.wb_sunny_outlined,
      children: <TriggerNode>[
        TriggerNode('celebrating', 'Celebrating'),
        TriggerNode('friends', 'With friends'),
        TriggerNode('reward', 'A reward'),
        TriggerNode('weekend', 'Weekend'),
        TriggerNode('meal', 'A good meal'),
      ],
    ),
    TriggerNode(
      'neutral',
      'Just routine',
      icon: Icons.repeat,
      children: <TriggerNode>[
        TriggerNode('morning', 'Morning'),
        TriggerNode('meal', 'With a meal'),
        TriggerNode('wind-down', 'Winding down'),
        TriggerNode('offered', 'Offered one'),
        TriggerNode('autopilot', 'Without thinking'),
      ],
    ),
  ],
);

const List<TriggerTree> starterTrees = <TriggerTree>[
  areasTree,
  reasonsTree,
  feelingsTree,
];
