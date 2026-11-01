/// Whether at least one inbox source is connected (Gmail, or the Android
/// notification digest). The Inbox tab is shown only when this is true; until
/// then Today carries a "Set up your inbox" card (spec B2: iOS without Gmail
/// must never see an empty Inbox tab).
///
/// Wave 1 has no inbox source, so this is a constant false. The connector
/// work (Wave 2A / 3B) overrides it with a provider derived from the
/// connector accounts.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final inboxAvailableProvider = Provider<bool>((ref) => false);
