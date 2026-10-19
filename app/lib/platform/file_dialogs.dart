import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

abstract interface class FileDialogs {
  Future<bool> saveJson(String filename, Uint8List bytes);
  Future<Uint8List?> pickJson();
}

class NativeFileDialogs implements FileDialogs {
  @override
  Future<bool> saveJson(String filename, Uint8List bytes) async =>
      await FilePicker.saveFile(
        fileName: filename,
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: 'Сохранить копию задач',
      ) !=
      null;
  @override
  Future<Uint8List?> pickJson() async {
    final selected = await FilePicker.pickFile(
      dialogTitle: 'Открыть копию задач',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (selected == null) return null;
    final length = await selected.length();
    if (length != null && length > 16 * 1024 * 1024) {
      throw const FormatException('Файл больше 16 МБ');
    }
    return selected.readAsBytes();
  }
}
