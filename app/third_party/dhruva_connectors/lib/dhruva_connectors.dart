/// Native half of the Dhruva connectors. There is no Dart API here: the app
/// talks to this plugin over the `app.dhruva/connectors` method channel from
/// `lib/data/connectors/system_sources.dart` (`ConnectorsChannel`).
///
/// It is a plugin, rather than code in MainActivity, so the WorkManager
/// background engine (which registers plugins but never runs MainActivity)
/// can use it too.
library;
