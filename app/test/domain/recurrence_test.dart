import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/domain/models.dart';
import 'package:day_planner/domain/recurrence.dart';

void main() {
  test(
    'shared recurrence fixtures use calendar arithmetic and deterministic ids',
    () {
      final fixtures = jsonDecode(
        File('../contracts/fixtures/recurrence.json').readAsStringSync(),
      ) as List;
      for (final f in fixtures) {
        expect(
          nextOccurrence(
            RecurrenceRule.fromJson({
              'id': '11111111-1111-4111-8111-111111111111',
              ...f['rule'] as Map,
            }),
            LocalDate.parse(f['dueDate']),
            LocalDate.parse(f['completionDate']),
          ).toString(),
          f['nextDate'],
        );
      }
      expect(
        successorId('6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'www.example.com'),
        '2ed6657d-e927-568b-95e1-2665a8aea6a2',
      );
    },
  );
}
