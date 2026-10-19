import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/sync/protocol.dart';
import 'package:day_planner/domain/models.dart';

void main() {
  test('protocol fixtures round trip with nullable task fields', () {
    final fixture = jsonDecode(
      File('../contracts/fixtures/valid-sync.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(SyncRequest.fromJson(fixture).toJson(), fixture);
    final task = TaskItem.fromJson({
      'id': 'x',
      'title': 'Хлеб',
      'dueDate': null,
      'note': '🍞',
    });
    expect(TaskItem.fromJson(task.toJson()).dueDate, isNull);
    expect(task.note, '🍞');
    final response = {
      'protocolVersion': 1,
      'workspaceId': 'workspace',
      'acknowledgements': [
        {
          'operationId': 'op',
          'status': 'applied',
          'effect': {'completionId': 'c', 'successorId': null},
        },
      ],
      'changes': [
        {
          'entityType': 'task',
          'entityId': 'x',
          'revision': 1,
          'value': task.toJson(),
        },
      ],
      'nextCursor': 1,
      'hasMore': false,
    };
    expect(SyncResponse.fromJson(response).toJson(), response);
  });
}
