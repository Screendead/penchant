import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracker/account/claude_access.dart';
import 'package:tracker/analyst/analyst_setting.dart';
import 'package:tracker/ask/ask_journal.dart';
import 'package:tracker/ask/ask_journal_setting.dart';
import 'package:tracker/design/app_theme.dart';
import 'package:tracker/insights/weekly_words.dart';
import 'package:tracker/letter/letter_setting.dart';
import 'package:tracker/letter/letter_writer.dart';
import 'package:tracker/insights/weekly_words_setting.dart';
import 'package:tracker/notes/follow_up_setting.dart';
import 'package:tracker/notes/note_reader.dart';
import 'package:tracker/notes/note_reader_setting.dart';
import 'package:tracker/providers/account_provider.dart';
import 'package:tracker/providers/user_provider.dart';

import 'fake_account.dart';
import 'fakes.dart';

enum _Caller { guest, unverified, verified }

User _user(_Caller caller) => FakeUser(
  'a',
  email: caller == _Caller.guest ? null : 'someone@example.com',
  emailVerified: caller == _Caller.verified,
  isAnonymous: caller == _Caller.guest,
);

List<Override> _overrides(_Caller caller, {bool guestVerified = false}) {
  final User user = guestVerified
      ? FakeUser('a', emailVerified: true)
      : _user(caller);
  return <Override>[
    userProvider.overrideWith((ref) => Stream.value(user)),
    userProfileProvider.overrideWith((ref) => Stream.value(user)),
    accountProvider.overrideWithValue(
      FakeAccount()..isGuest = caller == _Caller.guest,
    ),
  ];
}

void _switchesOn() => SharedPreferences.setMockInitialValues(<String, Object>{
  NoteReaderEnabled.key: true,
  FollowUpEnabled.key: true,
  WeeklyWordsEnabled.key: true,
  AskJournalEnabled.key: true,
  LetterEnabled.key: true,
  AnalystEnabled.key: true,
});

void main() {
  group('the Claude providers', () {
    Future<ProviderContainer> container(
      _Caller caller, {
      bool guestVerified = false,
    }) async {
      _switchesOn();
      final ProviderContainer c = ProviderContainer(
        overrides: _overrides(caller, guestVerified: guestVerified),
      );
      addTearDown(c.dispose);
      c.listen(noteReaderProvider, (_, _) {});
      c.listen(weeklyWordsProvider, (_, _) {});
      c.listen(askJournalProvider, (_, _) {});
      c.listen(letterWriterProvider, (_, _) {});
      c.listen(investigatorProvider, (_, _) {});
      await pumpEventQueue();
      return c;
    }

    for (final _Caller caller in <_Caller>[_Caller.guest, _Caller.unverified]) {
      test('are null for ${caller.name} accounts, switches on', () async {
        final ProviderContainer c = await container(caller);
        expect(c.read(claudeAllowedProvider), isFalse);
        expect(c.read(noteReaderProvider), isNull);
        expect(c.read(weeklyWordsProvider), isNull);
        expect(c.read(askJournalProvider), isNull);
        expect(c.read(letterWriterProvider), isNull);
        expect(c.read(investigatorProvider), isNull);
      });
    }

    test('are null for a guest even with a verified profile', () async {
      final ProviderContainer c = await container(
        _Caller.guest,
        guestVerified: true,
      );
      expect(c.read(claudeAllowedProvider), isFalse);
      expect(c.read(noteReaderProvider), isNull);
      expect(c.read(letterWriterProvider), isNull);
      expect(c.read(investigatorProvider), isNull);
    });

    test('serve a verified account with the switches on', () async {
      final ProviderContainer c = await container(_Caller.verified);
      expect(c.read(claudeAllowedProvider), isTrue);
      expect(c.read(noteReaderProvider), isA<CallableNoteReader>());
      expect(
        (c.read(noteReaderProvider)! as CallableNoteReader).askQuestions,
        isTrue,
      );
      expect(c.read(weeklyWordsProvider), isA<CallableWeeklyWords>());
      expect(c.read(askJournalProvider), isA<CallableAskJournal>());
      expect(c.read(letterWriterProvider), isA<CallableLetterWriter>());
      expect(c.read(investigatorProvider), isA<CallableInvestigator>());
    });

    test('the investigator is null while Ask is off', () async {
      final ProviderContainer c = await container(_Caller.verified);
      await c.read(askJournalEnabledProvider.notifier).choose(false);
      expect(c.read(analystEnabledProvider), isTrue);
      expect(c.read(investigatorProvider), isNull);
    });
  });

}
