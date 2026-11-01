// "About me": the single prompt-context builder (non-empty fields only,
// capped) and its persistence.

import 'package:dhruva/core/profile/user_profile.dart';
import 'package:dhruva/core/settings/prefs_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildUserContext', () {
    test('empty profile adds nothing', () {
      expect(buildUserContext(const UserProfile()), '');
      expect(
        buildUserContext(const UserProfile(name: '  ', role: '\n', tone: ' ')),
        '',
      );
    });

    test('only non-empty fields appear', () {
      final out = buildUserContext(
        const UserProfile(name: 'Asha', tone: 'Warm'),
      );
      expect(out, contains('About the user'));
      expect(out, contains('- Name: Asha'));
      expect(out, contains('- Writing style they like: Warm'));
      expect(out, isNot(contains('What they do')));
      expect(out, isNot(contains('signature')));
    });

    test('all four fields, signature kept multi-line and indented', () {
      final out = buildUserContext(
        const UserProfile(
          name: 'Asha',
          role: 'nurse',
          tone: 'Short',
          signature: 'Thanks,\nAsha',
        ),
      );
      expect(out, contains('- What they do: nurse'));
      expect(out, contains('- Email signature:\n  Thanks,\n  Asha'));
    });

    test('fields collapse whitespace and are capped', () {
      final out = buildUserContext(
        UserProfile(name: 'A\n\n  B', role: 'x' * 500),
      );
      expect(out, contains('- Name: A B'));
      final roleLine = out.split('\n').firstWhere((l) => l.contains('do:'));
      // "- What they do: " + at most maxRoleChars + ellipsis.
      expect(roleLine.length, lessThanOrEqualTo(16 + maxRoleChars + 1));
    });

    test('the whole block never exceeds the cap', () {
      final out = buildUserContext(
        UserProfile(
          name: 'n' * 1000,
          role: 'r' * 1000,
          tone: 't' * 1000,
          signature: List.filled(50, 'line of signature').join('\n'),
        ),
      );
      expect(out.length, lessThanOrEqualTo(maxUserContextChars));
    });
  });

  group('persistence', () {
    test('round-trips through the prefs store', () async {
      final store = MemoryPrefsStore();
      ProviderContainer make() => ProviderContainer(
        overrides: [prefsStoreProvider.overrideWith((ref) async => store)],
      );
      final a = make();
      addTearDown(a.dispose);
      expect((await a.read(userProfileProvider.future)).isEmpty, isTrue);
      await a
          .read(userProfileProvider.notifier)
          .save(const UserProfile(name: 'Asha', signature: 'A.'));

      final b = make();
      addTearDown(b.dispose);
      final loaded = await b.read(userProfileProvider.future);
      expect(loaded.name, 'Asha');
      expect(loaded.signature, 'A.');
      expect(await b.read(userContextProvider.future), contains('Asha'));
    });

    test('a corrupt value reads as an empty profile', () {
      expect(UserProfile.fromRaw('not json').isEmpty, isTrue);
      expect(UserProfile.fromRaw('[1,2]').isEmpty, isTrue);
      expect(UserProfile.fromRaw('{"name":3}').isEmpty, isTrue);
      expect(UserProfile.fromRaw(null).isEmpty, isTrue);
    });

    test('unreadable prefs give an empty context, never an error', () async {
      final c = ProviderContainer(
        overrides: [
          prefsStoreProvider.overrideWith((ref) async => throw 'disk'),
        ],
      );
      addTearDown(c.dispose);
      expect(await c.read(userContextProvider.future), '');
    });
  });
}
