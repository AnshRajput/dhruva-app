/// Pure grouping for the Inbox: Today / Earlier sections and per-app filter
/// chips over captured notifications. Mail (0.7b) will add a "Needs reply"
/// section in front; the shape stays the same.
library;

import '../../../data/connectors/connector.dart';

/// What an [InboxEntry] row needs, read out of the item's flags.
extension InboxItem on ConnectorItem {
  String get appLabel {
    final a = flags['app'];
    if (a is String && a.trim().isNotEmpty) return a.trim();
    final p = packageName;
    return p.isEmpty ? 'App' : p;
  }

  String get packageName => (flags['pkg'] as String?) ?? '';

  bool get isRead => flags['read'] == true;

  DateTime get when => sentAt ?? updatedAt;
}

final class InboxSection {
  final String title;
  final List<ConnectorItem> items;
  const InboxSection(this.title, this.items);
}

final class AppFilter {
  final String package;
  final String label;
  final int count;
  const AppFilter(this.package, this.label, this.count);
}

/// Items of [filterPackage] (all when null), newest first, split into Today
/// (the local calendar day of [now]) and Earlier. Empty sections are left out.
List<InboxSection> groupInbox(
  List<ConnectorItem> items,
  DateTime now, {
  String? filterPackage,
}) {
  final start = DateTime(now.year, now.month, now.day);
  final picked = [
    for (final i in items)
      if (filterPackage == null || i.packageName == filterPackage) i,
  ]..sort((a, b) => b.when.compareTo(a.when));
  final today = [
    for (final i in picked)
      if (!i.when.isBefore(start)) i,
  ];
  final earlier = [
    for (final i in picked)
      if (i.when.isBefore(start)) i,
  ];
  return [
    if (today.isNotEmpty) InboxSection('Today', today),
    if (earlier.isNotEmpty) InboxSection('Earlier', earlier),
  ];
}

/// One chip per app that has notifications, busiest first (ties by name).
List<AppFilter> appFilters(List<ConnectorItem> items) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final i in items) {
    final p = i.packageName;
    counts[p] = (counts[p] ?? 0) + 1;
    labels.putIfAbsent(p, () => i.appLabel);
  }
  final out = [
    for (final e in counts.entries) AppFilter(e.key, labels[e.key]!, e.value),
  ];
  out.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}

/// Letters for the round avatar: the app label's first letter (two for a
/// two-word label), upper-case.
String avatarLetters(String label) {
  final words = label
      .trim()
      .split(RegExp(r'[\s._-]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
  return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}
