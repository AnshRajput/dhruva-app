// flutter_contacts 2.1.0 returns the first contact in the address book when an
// email filter matches nothing. byEmail must re-check the address so an
// unknown attendee is never shown as someone the user knows.
import 'package:dhruva/data/connectors/system_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unrelated contact returned for an unmatched email is rejected', () {
    // The on-device repro: attendee zed.quark@example.org, address book has
    // only Ravi Menon (ravi.menon@example.com); the plugin hands back Ravi.
    expect(
      contactHasEmail(['ravi.menon@example.com'], 'zed.quark@example.org'),
      isFalse,
    );
  });

  test('a real match is accepted, ignoring case and spaces', () {
    expect(
      contactHasEmail([' Ravi.Menon@Example.com '], 'ravi.menon@example.com'),
      isTrue,
    );
    expect(contactHasEmail(['work@x.io', 'ravi@x.io'], 'RAVI@x.io'), isTrue);
  });

  test('no addresses or an empty email never match', () {
    expect(contactHasEmail([], 'ravi@x.io'), isFalse);
    expect(contactHasEmail(['ravi@x.io'], '  '), isFalse);
  });
}
