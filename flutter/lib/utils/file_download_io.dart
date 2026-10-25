import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> downloadFile({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Salvar arquivo',
    fileName: fileName,
    bytes: bytes,
  );
  return path != null;
}
