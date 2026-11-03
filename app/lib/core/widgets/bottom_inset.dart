/// A scrollable that sets its own `padding` drops the automatic gesture-bar
/// inset, so its last row ends under the system gesture pill. Add this to the
/// list's own padding: `EdgeInsets.all(x).withBottomInset(context)`.
library;

import 'package:flutter/widgets.dart';

extension BottomInsetPadding on EdgeInsets {
  /// This padding plus the system bottom inset (gesture bar) at [context].
  EdgeInsets withBottomInset(BuildContext context) =>
      copyWith(bottom: bottom + MediaQuery.paddingOf(context).bottom);
}
