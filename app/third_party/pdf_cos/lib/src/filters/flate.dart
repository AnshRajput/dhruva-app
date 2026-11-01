import 'dart:typed_data';

import '../objects.dart';
import 'decode_budget.dart';
import 'filters.dart';

/// FlateDecode: zlib/deflate, optionally followed by a PNG/TIFF predictor.
///
/// The zlib layer is [inflateZlib], which ignores bytes after the stream on
/// every platform, as native zlib and pdf.js do.
class FlateFilter extends CosFilter {
  const FlateFilter();

  @override
  Uint8List decode(
          Uint8List data, CosDictionary? params, DecodeBudget budget) =>
      // dhruva: bounded decode
      applyPredictor(inflateZlib(data, stage: budget.stage()), params, budget);
}
