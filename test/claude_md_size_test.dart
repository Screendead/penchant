import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Every Claude session loads CLAUDE.md, so its size is paid each time. It grew from 47k to 132k bytes in eight
// days of feature paragraphs before the detail moved to docs/architecture/.
const claudeMdByteCap = 28000;

void main() {
  final claudeMd = File('CLAUDE.md');

  test('CLAUDE.md stays under its byte cap', () {
    final bytes = claudeMd.lengthSync();
    expect(
      bytes,
      lessThanOrEqualTo(claudeMdByteCap),
      reason:
          'CLAUDE.md is $bytes bytes, over its cap of $claudeMdByteCap. '
          'Put feature detail in the area\'s docs/architecture/<area>.md and leave CLAUDE.md '
          'one to three lines per area; raise the cap only with Jack\'s say-so.',
    );
  });

  test('every docs/architecture file CLAUDE.md names exists', () {
    final text = claudeMd.readAsStringSync();
    final table = text.substring(text.indexOf('## Architecture'));
    final named = RegExp(
      r'`([a-z-]+\.md)`',
    ).allMatches(table).map((m) => m.group(1)!).toSet();
    expect(named, isNotEmpty);
    for (final name in named) {
      expect(
        File('docs/architecture/$name').existsSync(),
        isTrue,
        reason: 'docs/architecture/$name is missing',
      );
    }
    final onDisk = Directory('docs/architecture')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.md'))
        .toSet();
    expect(
      onDisk.difference(named),
      isEmpty,
      reason: 'docs/architecture files CLAUDE.md does not name',
    );
  });
}
