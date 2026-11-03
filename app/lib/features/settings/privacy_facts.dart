/// The exact network and storage facts, in plain words. One list, used by the
/// Privacy screen (full) and the About page (headline only), so the two can
/// never disagree. Update this file whenever the app gains or loses a network
/// call; `privacy_facts_test.dart` pins the list.
///
/// Source of truth: daily-assistant spec section 8 "Network, stated exactly".
library;

import 'package:flutter/material.dart';

import '../../core/identity/app_identity.dart';

@immutable
class NetworkFact {
  const NetworkFact({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// The only network calls the app makes.
const networkFacts = <NetworkFact>[
  NetworkFact(
    icon: Icons.download_outlined,
    title: 'Model downloads',
    body:
        'From Hugging Face, only when you tap Download. The request names '
        'the model file you picked and nothing about you.',
  ),
  NetworkFact(
    icon: Icons.newspaper_outlined,
    title: 'AI news',
    body:
        'Only if you turn it on (Models, AI news). It fetches a public list '
        'of small models worth trying.',
  ),
  NetworkFact(
    icon: Icons.system_update_alt_rounded,
    title: 'Update checks',
    body:
        'Automatic when you open the app: asks Shorebird\'s update server '
        'whether a fix exists, sending only the app version and patch number '
        '(like any website, it sees your IP address). Never your chats, files '
        'or anything you typed.',
  ),
  NetworkFact(
    icon: Icons.link_outlined,
    title: 'Your own accounts',
    body:
        'Once you connect one, this phone talks to it directly with your '
        'sign-in. Nothing passes through us.',
  ),
];

/// The headline: there is nothing server-side.
const noServerFact = 'There is no ${AppIdentity.shortName} server.';

/// What lives on the phone.
const storedOnPhoneFact =
    'Your chats, downloaded models, documents you attach, About me, settings '
    'and crash reports. Anything you connect later (calendar, contacts, files, '
    'notifications) is read into a private index here too. Clear chats under '
    'Privacy; revoke a connector to delete its copy.';

/// [storedOnPhoneFact] for [platform]: notifications can only be connected on
/// Android, so iOS never reads about them.
String storedOnPhoneFor(TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? storedOnPhoneFact
    : storedOnPhoneFact.replaceFirst(', notifications)', ')');

/// What the Connectors row lists, for [platform].
String connectorsSummaryFor(TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? 'Calendar, contacts, folder, notifications'
    : 'Calendar, contacts, folder';

/// Why backups are off, including the trade-off.
const backupsOffFact =
    'Backups are off. Android and iOS cloud backups and device transfers '
    'skip this app, so your chats and connected data never reach Google or '
    'iCloud. The catch: they do not move to a new phone by themselves. '
    'Export any chat you want to keep.';
