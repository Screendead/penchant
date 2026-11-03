import 'package:flutter/material.dart';

/// One node of a trigger tree. A node's path is its ancestors' ids and its own
/// joined by '/', e.g. `work/meeting`; that string is what an activity stores.
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

class TriggerTree {
  const TriggerTree({
    required this.id,
    required this.name,
    required this.prompt,
    required this.roots,
  });

  final String id;
  final String name;

  /// The heading above the first level.
  final String prompt;
  final List<TriggerNode> roots;

  static const String customPrefix = 'custom';
  static const String separator = ' › ';

  TriggerNode? root(String id) {
    for (final TriggerNode node in roots) {
      if (node.id == id) {
        return node;
      }
    }

    return null;
  }

  /// The labels along [path], or null when a segment is not in the tree.
  List<String>? labels(String path) {
    final List<String> ids = path.split('/');
    final List<String> labels = <String>[];
    List<TriggerNode> level = roots;

    for (final String id in ids) {
      TriggerNode? match;

      for (final TriggerNode node in level) {
        if (node.id == id) {
          match = node;
        }
      }

      if (match == null) {
        return null;
      }

      labels.add(match.label);
      level = match.children;
    }

    return labels;
  }
}
