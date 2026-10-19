import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/domain/validation.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  test('Unicode titles and real local dates reject invalid boundaries', () {
    expect(normalizeTitle('  Молоко 🥛  '), 'Молоко 🥛');
    expect(normalizeTitle(List.filled(500, '😀').join()).runes.length, 500);
    expect(
      () => normalizeTitle(List.filled(501, '😀').join()),
      throwsFormatException,
    );
    expect(() => normalizeTitle(' \n '), throwsFormatException);
    expect(() => validateNote('x' * 10001), throwsFormatException);
    expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
    expect(LocalDate.parse('2028-02-29').toString(), '2028-02-29');
  });
}
