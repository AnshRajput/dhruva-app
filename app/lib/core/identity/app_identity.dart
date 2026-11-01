/// One place for the product's name strings, so a rename is a one-line change
/// (daily-assistant brief: "Product name: to be decided later").
///
/// Not covered here on purpose: the Android launcher label / iOS display name
/// (`AndroidManifest.xml`, `Info.plist`) and package ids, which stay as they
/// are until the rename is decided; the Dhruva-the-pole-star story on the About
/// page, which is about the myth, not the product name.
library;

abstract final class AppIdentity {
  /// Full product name: store listing, window title, mail subjects.
  static const productName = 'Dhruva AI';

  /// Short name used mid-sentence ("Dhruva can't help with that").
  static const shortName = 'Dhruva';

  /// Text of the wordmark shown beside the brand star in headers.
  static const wordmark = 'Dhruva';

  /// One line that says what the app is.
  static const tagline = 'A private assistant that runs on your phone.';
}
