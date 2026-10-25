import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> downloadFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  try {
    web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..click();
    return true;
  } finally {
    web.URL.revokeObjectURL(url);
  }
}
