/// Honest speed labels from measured decode tok/s. Thresholds live here and
/// nowhere else so every surface (Installed tab, chat picker) agrees.
library;

/// Decode tok/s at or above this is [SpeedLabel.fast].
const double kFastDecodeTps = 12;

/// Decode tok/s at or above this (and below [kFastDecodeTps]) is
/// [SpeedLabel.usable]; anything lower is [SpeedLabel.slow].
const double kUsableDecodeTps = 5;

enum SpeedLabel {
  fast('Fast on your phone'),
  usable('Usable'),
  slow('Slow on your phone — try a smaller model');

  /// Plain-language copy shown to the user.
  final String message;
  const SpeedLabel(this.message);
}

SpeedLabel speedLabelFor(double decodeTps) {
  if (decodeTps >= kFastDecodeTps) return SpeedLabel.fast;
  if (decodeTps >= kUsableDecodeTps) return SpeedLabel.usable;
  return SpeedLabel.slow;
}
