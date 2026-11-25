import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the user picked, read fully into memory so it can be uploaded with Dio on any platform.
class PickedFileData {
  const PickedFileData({required this.bytes, required this.name, required this.mimeType});

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

const _mimeByExtension = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'svg': 'image/svg+xml',
};

/// Opens the platform file picker (browser dialog on web, document/photo picker on Android and
/// iOS) and returns the chosen image, or null if the user cancelled.
///
/// [allowedExtensions] limits the choice, e.g. `['png', 'svg', 'jpg', 'jpeg']`. Leave it null to
/// allow any image.
Future<PickedFileData?> pickImageFile({List<String>? allowedExtensions}) async {
  final result = await FilePicker.platform.pickFiles(
    type: allowedExtensions == null ? FileType.image : FileType.custom,
    allowedExtensions: allowedExtensions,
    withData: true, // bytes are needed on mobile too; there is no dart:html File there
  );
  final file = result?.files.single;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  final ext = (file.extension ?? '').toLowerCase();
  return PickedFileData(
    bytes: bytes,
    name: file.name,
    mimeType: _mimeByExtension[ext] ?? 'application/octet-stream',
  );
}
