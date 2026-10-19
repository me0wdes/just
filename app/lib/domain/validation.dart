String normalizeTitle(String value) {
  final title = value.trim();
  if (title.isEmpty || title.runes.length > 500) {
    throw const FormatException('Название: от 1 до 500 символов');
  }
  return title;
}

String validateNote(String value) {
  if (value.runes.length > 10000) {
    throw const FormatException('Заметка: до 10000 символов');
  }
  return value;
}
