import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../domain/commands.dart';
import '../domain/validation.dart';
import '../domain/entity_validation.dart';
import '../domain/recurrence.dart';
import '../sync/protocol.dart';
import 'app_database.dart';

abstract class TaskRepository {
  Stream<List<TaskItem>> watchTasks(TaskQuery query);
  Stream<List<TaskList>> watchLists();
  Future<CommandReceipt> execute(TaskCommand command);
  Future<List<Operation>> pendingBatch({
    required int maxOperations,
    required int byteBudget,
  });
  Future<void> applySyncResponse(SyncResponse response);
  Future<int> getCursor();
  Future<String?> expectedWorkspaceId();
  Future<List<Json>> rejectedOperations();
  Future<void> markRejected(String operationId, String code);
  Future<TaskItem?> readTask(String id);
  Future<RecurrenceRule?> readRule(String id);
}

class SqliteTaskRepository implements TaskRepository {
  Future<Json?> latestConflict() async {
    final value = await db.meta('lastConflict');
    return value == null
        ? null
        : Map<String, Object?>.from(jsonDecode(value) as Map);
  }

  @override
  Future<String?> expectedWorkspaceId() => db.meta('remoteWorkspace');
  @override
  Future<List<Json>> rejectedOperations() async {
    final result = <Json>[];
    for (final row in await _queue()) {
      if (row['status'] != 'rejected') continue;
      final op = Operation.fromJson(jsonDecode(row['value'] as String));
      final value = await entity(op.entityType, op.entityId);
      result.add({
        ...op.toJson(),
        'code': row['error'],
        'label': value?['title'] ?? value?['name'] ?? op.entityId,
      });
    }
    return result;
  }

  Future<void> resolveRejected(
    String operationId, {
    required bool retry,
  }) async {
    await db.transaction(() async {
      final queue = await _queue();
      if (!queue.any(
        (r) => r['id'] == operationId && r['status'] == 'rejected',
      )) {
        return;
      }
      final removed = <String>{operationId}, affected = <String, Operation>{};
      for (final row in queue) {
        final op = Operation.fromJson(jsonDecode(row['value'] as String));
        if (removed.contains(op.operationId) ||
            op.dependsOn.any(removed.contains)) {
          removed.add(op.operationId);
          affected['${op.entityType}/${op.entityId}'] = op;
        }
      }
      final snapshots = <({String type, Json value})>[];
      if (retry) {
        for (final op in affected.values) {
          final value = await entity(op.entityType, op.entityId);
          if (value != null) {
            snapshots.add((
              type: op.entityType,
              value: validateSnapshot(op.entityType, {
                for (final e in value.entries)
                  if (snapshotFields(op.entityType).contains(e.key))
                    e.key: e.value,
              }),
            ));
          }
        }
      }
      for (final id in removed) {
        await db.run('DELETE FROM pendingOperations WHERE id=?', [id]);
        await db.run('DELETE FROM completionLinks WHERE operationId=?', [id]);
      }
      const order = {'rule': 0, 'list': 1, 'task': 2};
      snapshots.sort((a, b) => order[a.type]!.compareTo(order[b.type]!));
      for (final snapshot in snapshots) {
        await _enqueueSnapshot(snapshot.type, snapshot.value);
      }
      await _rebuild();
    });
    db.changed(local: true);
  }

  Future<void> _enqueueSnapshot(String type, Json value) async {
    final sequence = int.parse(await db.meta('sequence') ?? '0') + 1;
    await db.setMeta('sequence', '$sequence');
    final op = Operation(
      operationId: newId(),
      entityType: type,
      entityId: value['id'] as String,
      kind: 'restore',
      changes: {'snapshot': value},
      createdAt: clock().toUtc().toIso8601String(),
      localSequence: sequence,
    );
    await db.run(
      'INSERT INTO pendingOperations(id,sequence,value) VALUES (?,?,?)',
      [op.operationId, sequence, jsonEncode(op.toJson())],
    );
  }

  Future<void> _detachProvisional(String operationId, String root) async {
    final tasks = <String, Json>{};
    String? next = root;
    while (next != null && !tasks.containsKey(next)) {
      final value = await entity('task', next);
      if (value == null) break;
      tasks[next] = value;
      next = value['successorId'] as String?;
    }
    final queue = await _queue();
    if (!queue.any(
      (r) => tasks.containsKey(
        Operation.fromJson(jsonDecode(r['value'] as String)).entityId,
      ),
    )) {
      return;
    }
    final remapped = {for (final id in tasks.keys) id: newId()};
    for (final row in queue) {
      final op = Operation.fromJson(jsonDecode(row['value'] as String));
      if (op.entityType == 'task' && tasks.containsKey(op.entityId)) {
        await db.run('DELETE FROM pendingOperations WHERE id=?', [
          op.operationId,
        ]);
        await db.run('DELETE FROM completionLinks WHERE operationId=?', [
          op.operationId,
        ]);
      }
    }
    for (final entry in tasks.entries) {
      final snapshot = {
        for (final e in entry.value.entries)
          if (taskSnapshotFields.contains(e.key)) e.key: e.value,
      };
      snapshot['id'] = remapped[entry.key];
      snapshot['recurrenceRuleId'] = null;
      snapshot['occurrenceDate'] = null;
      snapshot['successorId'] = remapped[snapshot['successorId']];
      await _enqueueSnapshot('task', snapshot);
    }
    await db.setMeta(
      'lastConflict',
      jsonEncode({
        'operationId': operationId,
        'code': 'successor_absent',
        'taskId': remapped[root],
        'successorId': remapped[root],
      }),
    );
  }

  @override
  Future<RecurrenceRule?> readRule(String id) async {
    final value = await entity('rule', id);
    return value == null ? null : RecurrenceRule.fromJson(value);
  }

  final AppDatabase db;
  final DateTime Function() clock;
  final String Function() newId;
  SqliteTaskRepository(
    this.db, {
    DateTime Function()? clock,
    String Function()? newId,
  }) : clock = clock ?? DateTime.now,
       newId = newId ?? const Uuid().v4;
  String _table(String type) => switch (type) {
    'task' => 'projectedTasks',
    'list' => 'projectedLists',
    'rule' => 'recurrenceRules',
    _ => throw const FormatException('Неверный тип записи'),
  };
  Future<Json?> entity(String type, String id) async {
    final row = (await db.rows('SELECT value FROM ${_table(type)} WHERE id=?', [
      id,
    ])).firstOrNull;
    return row == null
        ? null
        : Map<String, Object?>.from(jsonDecode(row['value'] as String) as Map);
  }

  Future<List<Json>> entities(String type) async =>
      (await db.rows('SELECT value FROM ${_table(type)}'))
          .map(
            (r) => Map<String, Object?>.from(
              jsonDecode(r['value'] as String) as Map,
            ),
          )
          .toList();
  @override
  Future<TaskItem?> readTask(String id) async {
    final data = await entity('task', id);
    return data == null ? null : TaskItem.fromJson(data);
  }

  Future<List<TaskItem>> _tasks(TaskQuery query) async {
    final tasks = (await entities('task'))
        .map(TaskItem.fromJson)
        .where(query.matches)
        .toList();
    tasks.sort((a, b) {
      final cmp = a.position.compareTo(b.position);
      return cmp == 0 ? a.id.compareTo(b.id) : cmp;
    });
    return tasks;
  }

  @override
  Stream<List<TaskItem>> watchTasks(TaskQuery query) async* {
    yield await _tasks(query);
    await for (final _ in db.updates.stream) {
      yield await _tasks(query);
    }
  }

  @override
  Stream<List<TaskList>> watchLists() async* {
    Future<List<TaskList>> read() async {
      final lists = (await entities('list'))
          .map(TaskList.fromJson)
          .where((l) => !l.deleted)
          .toList();
      if (!lists.any((l) => l.id == inboxId)) {
        lists.insert(0, TaskList.fromJson({'id': inboxId, 'name': 'Входящие'}));
      }
      lists.sort((a, b) => a.position.compareTo(b.position));
      return lists;
    }

    yield await read();
    await for (final _ in db.updates.stream) {
      yield await read();
    }
  }

  Future<List<Map<String, Object?>>> _queue() =>
      db.rows('SELECT * FROM pendingOperations ORDER BY sequence');
  Future<List<Operation>> allPending() async => (await _queue())
      .map((r) => Operation.fromJson(jsonDecode(r['value'] as String)))
      .toList();
  @override
  Future<int> getCursor() async => int.parse(await db.meta('cursor') ?? '0');
  @override
  Future<List<Operation>> pendingBatch({
    required int maxOperations,
    required int byteBudget,
  }) async {
    final queue = await _queue(), result = <Operation>[];
    var size = 0;
    final blocked = queue
        .where((r) => r['status'] != 'accepted')
        .map((r) => r['id'])
        .toSet();
    for (final row in queue) {
      if (row['status'] != 'pending') continue;
      final op = Operation.fromJson(jsonDecode(row['value'] as String));
      if (op.dependsOn.any(blocked.contains)) continue;
      final bytes = utf8.encode(jsonEncode(op.toJson())).length + 1;
      if (result.length >= maxOperations || size + bytes > byteBudget) break;
      result.add(op);
      size += bytes;
    }
    return result;
  }

  @override
  Future<CommandReceipt> execute(TaskCommand command) async {
    final receipt = await db.transaction(() async {
      final now = clock().toUtc().toIso8601String();
      String type = 'task', kind = 'patch', id;
      Json changes;
      String? completionId, childId;
      switch (command) {
        case CreateTask():
          id = command.id;
          kind = 'create';
          changes = {
            ...command.fields,
            'title': normalizeTitle(command.title),
            'listId': command.listId,
          };
        case PatchTask():
          id = command.id;
          changes = Map.of(command.fields);
          const allowed = {
            'title',
            'note',
            'listId',
            'listIds',
            'dueDate',
            'dueTime',
            'reminderAtUtc',
            'reminderTimezone',
            'plannedForDate',
            'position',
            'recurrenceRuleId',
          };
          if (changes.keys.any((k) => !allowed.contains(k))) {
            throw const FormatException('Недопустимое поле задачи');
          }
        case CompleteTask():
          id = command.id;
          kind = 'complete';
          LocalDate.parse(command.completionDate);
          changes = {'completionDate': command.completionDate};
        case UndoCompletion():
          id = command.id;
          kind = 'undoComplete';
          changes = {'completionId': command.completionId};
        case DeleteTask():
          id = command.id;
          kind = 'delete';
          changes = {};
        case RestoreTask():
          id = command.id;
          kind = 'restore';
          changes = {};
        case CreateList():
          type = 'list';
          id = command.id;
          kind = 'create';
          changes = {
            'name': normalizeTitle(command.name),
            'color': command.color,
            'icon': ?command.icon,
          };
        case PatchList():
          type = 'list';
          id = command.id;
          changes = Map.of(command.fields);
        case DeleteList():
          type = 'list';
          id = command.id;
          kind = 'delete';
          changes = {};
        case UpsertRule():
          type = 'rule';
          id = command.id;
          kind = await entity(type, id) == null ? 'create' : 'patch';
          changes = Map.of(command.fields);
          RecurrenceRule.fromJson({
            'id': id,
            ...?await entity(type, id),
            ...changes,
          });
        case ReorderTask():
          id = command.id;
          changes = {'position': command.position};
        case ImportEntity():
          type = command.type;
          id = command.id;
          kind = 'restore';
          changes = {'snapshot': command.snapshot};
      }
      if (changes.containsKey('title')) {
        changes['title'] = normalizeTitle(changes['title'] as String);
      }
      if (changes.containsKey('note')) validateNote(changes['note'] as String);
      if (changes.containsKey('listIds')) validateListIds(changes['listIds']);
      for (final key in ['dueDate', 'plannedForDate']) {
        if (changes[key] != null) LocalDate.parse(changes[key] as String);
      }
      if (changes['dueTime'] case final Object time
          when !RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch('$time')) {
        throw const FormatException('Неверное время');
      }
      if (type == 'list' && id == inboxId) {
        throw const FormatException('Входящие нельзя изменить');
      }
      if (kind == 'create' && await entity(type, id) != null) {
        throw const FormatException('Запись уже существует');
      }
      if (!['create', 'restore'].contains(kind) &&
          await entity(type, id) == null) {
        throw const FormatException('Запись не найдена');
      }
      final queue = await _queue();
      final dependencies = <String>[];
      for (final row in queue) {
        final previous = Operation.fromJson(jsonDecode(row['value'] as String));
        if (previous.entityType == type && previous.entityId == id) {
          dependencies.add(previous.operationId);
        }
        if (previous.entityId == changes['listId'] ||
            (changes['listIds'] as List?)?.contains(previous.entityId) ==
                true ||
            previous.entityId == changes['recurrenceRuleId']) {
          dependencies.add(previous.operationId);
        }
      }
      final links = await db.rows(
        'SELECT * FROM completionLinks WHERE provisionalId=?',
        [id],
      );
      for (final link in links) {
        dependencies.add(link['operationId'] as String);
      }
      final sequence = int.parse(await db.meta('sequence') ?? '0') + 1;
      await db.setMeta('sequence', '$sequence');
      final opId = newId();
      final op = Operation(
        operationId: opId,
        entityType: type,
        entityId: id,
        kind: kind,
        changes: changes,
        createdAt: now,
        localSequence: sequence,
        dependsOn: dependencies.toSet().toList(),
      );
      await db.run(
        'INSERT INTO pendingOperations(id,sequence,value) VALUES (?,?,?)',
        [opId, sequence, jsonEncode(op.toJson())],
      );
      if (kind == 'complete') {
        completionId = opId;
        final task = await entity('task', id);
        final ruleId = task?['recurrenceRuleId'] as String?;
        if (ruleId != null) {
          final ruleData = await entity('rule', ruleId);
          if (ruleData != null) {
            final rule = RecurrenceRule.fromJson(ruleData);
            if (rule.active) {
              final next = nextOccurrence(
                rule,
                task?['dueDate'] == null
                    ? null
                    : LocalDate.parse(task!['dueDate'] as String),
                LocalDate.parse(changes['completionDate'] as String),
              );
              childId = successorId(ruleId, next);
            }
          }
        }
        await db.run('INSERT INTO completionLinks VALUES (?,?,?,NULL)', [
          opId,
          id,
          childId,
        ]);
      }
      await _rebuild();
      return CommandReceipt(
        opId,
        completionId: completionId,
        provisionalSuccessorId: childId,
      );
    });
    db.changed(local: true);
    return receipt;
  }

  Future<void> _rebuild() async {
    final records = <String, Json>{};
    for (final row in await db.rows('SELECT * FROM canonicalEntities')) {
      records['${row['type']}/${row['id']}'] = Map<String, Object?>.from(
        jsonDecode(row['value'] as String),
      );
    }
    records.putIfAbsent(
      'list/$inboxId',
      () => {'id': inboxId, 'name': 'Входящие', 'position': -1024},
    );
    for (final row in await _queue()) {
      final op = Operation.fromJson(jsonDecode(row['value'] as String));
      final key = '${op.entityType}/${op.entityId}', old = records[key];
      final value = {...?old};
      final effect = row['effect'] == null
          ? null
          : jsonDecode(row['effect'] as String) as Map;
      if (op.kind == 'create') {
        value.addAll({
          'id': op.entityId,
          'position': 0,
          'deletedAt': null,
          ...op.changes,
        });
      } else if (op.kind == 'restore') {
        value.addAll(
          op.changes['snapshot'] as Map<String, Object?>? ??
              {'deletedAt': null},
        );
        value['id'] = op.entityId;
      } else if (old == null) {
        continue;
      } else if (op.kind == 'patch') {
        if (old['deletedAt'] == null) value.addAll(op.changes);
      } else if (op.kind == 'delete') {
        value['deletedAt'] = op.createdAt;
      } else if (op.kind == 'complete' && old['completedAt'] == null) {
        value['completedAt'] = op.createdAt;
        value['completionId'] = effect?['completionId'] ?? op.operationId;
        final rule = records['rule/${value['recurrenceRuleId']}'];
        if (rule != null &&
            rule['active'] != false &&
            rule['deletedAt'] == null &&
            !(effect != null &&
                effect.containsKey('successorId') &&
                effect['successorId'] == null)) {
          final next = nextOccurrence(
            RecurrenceRule.fromJson(rule),
            value['dueDate'] == null
                ? null
                : LocalDate.parse(value['dueDate'] as String),
            LocalDate.parse(op.changes['completionDate'] as String),
          );
          final child =
              effect?['successorId'] as String? ??
              successorId(rule['id'] as String, next);
          value['successorId'] = child;
          records['task/$child'] = {
            ...value,
            'id': child,
            'dueDate': next.toString(),
            'occurrenceDate': next.toString(),
            'plannedForDate': null,
            'reminderAtUtc': nextReminderAt(
              RecurrenceRule.fromJson(rule),
              next,
            )?.toIso8601String(),
            'completedAt': null,
            'completionId': null,
            'successorId': null,
            'position': (value['position'] as num? ?? 0) + 1024,
          };
        }
      } else if (op.kind == 'undoComplete') {
        final child = value['successorId'];
        if (child != null && records['task/$child'] != null) {
          records['task/$child'] = {
            ...records['task/$child']!,
            'deletedAt': op.createdAt,
          };
        }
        value.addAll({
          'completedAt': null,
          'completionId': null,
          'successorId': null,
        });
      }
      records[key] = value;
    }
    for (final entry in records.entries) {
      if (!entry.key.startsWith('task/')) continue;
      final list = records['list/${entry.value['listId']}'];
      if (list == null || list['deletedAt'] != null) {
        entry.value['listId'] = inboxId;
      }
      final ids = entry.value['listIds'];
      if (ids is List) {
        entry.value['listIds'] = [
          for (final id in ids)
            if (records['list/$id'] case final l? when l['deletedAt'] == null)
              id,
        ];
      }
    }
    for (final type in ['task', 'list', 'rule']) {
      final table = _table(type);
      final existing = {
        for (final row in await db.rows('SELECT id,value FROM $table'))
          row['id'] as String: row['value'] as String,
      };
      final projected = records.entries.where(
        (e) => e.key.startsWith('$type/'),
      );
      for (final entry in projected) {
        final id = entry.value['id'] as String;
        final json = jsonEncode(entry.value);
        if (existing.remove(id) != json) {
          await db.run(
            'INSERT INTO $table VALUES (?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value',
            [id, json],
          );
        }
      }
      for (final id in existing.keys) {
        await db.run('DELETE FROM $table WHERE id=?', [id]);
      }
    }
  }

  @override
  Future<void> applySyncResponse(SyncResponse response) async {
    await db.transaction(() async {
      final expected = await db.meta('remoteWorkspace');
      if (expected != null && expected != response.workspaceId) {
        throw const FormatException('Другое пространство задач');
      }
      await db.setMeta('remoteWorkspace', response.workspaceId);
      for (final change in response.changes) {
        await db.run(
          'INSERT INTO canonicalEntities VALUES (?,?,?,?) ON CONFLICT(type,id) DO UPDATE SET value=excluded.value,revision=excluded.revision WHERE excluded.revision>canonicalEntities.revision',
          [
            change.entityType,
            change.entityId,
            jsonEncode(change.value),
            change.revision,
          ],
        );
      }
      for (final ack in response.acknowledgements) {
        if (ack.status == 'rejected') {
          final stored = (await db.rows(
            'SELECT value FROM pendingOperations WHERE id=?',
            [ack.operationId],
          )).firstOrNull;
          final operation = stored == null
              ? null
              : Operation.fromJson(jsonDecode(stored['value'] as String));
          if (operation?.kind == 'undoComplete') {
            final canonical = (await db.rows(
              'SELECT value FROM canonicalEntities WHERE type=? AND id=?',
              ['task', operation!.entityId],
            )).firstOrNull;
            final parent = canonical == null
                ? await entity('task', operation.entityId)
                : Map<String, Object?>.from(
                    jsonDecode(canonical['value'] as String) as Map,
                  );
            await db.setMeta(
              'lastConflict',
              jsonEncode({
                'operationId': operation.operationId,
                'code': ack.code,
                'taskId': operation.entityId,
                'successorId': parent?['successorId'],
              }),
            );
            await db.run('DELETE FROM pendingOperations WHERE id=?', [
              ack.operationId,
            ]);
            for (final row in await _queue()) {
              final pending = Operation.fromJson(
                jsonDecode(row['value'] as String),
              );
              if (pending.dependsOn.contains(ack.operationId)) {
                await db.run(
                  'UPDATE pendingOperations SET value=? WHERE id=?',
                  [
                    jsonEncode({
                      ...pending.toJson(),
                      'dependsOn': pending.dependsOn
                          .where((id) => id != ack.operationId)
                          .toList(),
                    }),
                    pending.operationId,
                  ],
                );
              }
            }
            continue;
          }
        }
        await db.run(
          'UPDATE pendingOperations SET status=?,error=?,effect=? WHERE id=?',
          [
            ack.status == 'rejected' ? 'rejected' : 'accepted',
            ack.code,
            ack.effect == null ? null : jsonEncode(ack.effect),
            ack.operationId,
          ],
        );
        if (ack.effect != null) {
          final link = (await db.rows(
            'SELECT * FROM completionLinks WHERE operationId=?',
            [ack.operationId],
          )).firstOrNull;
          final provisional = link?['provisionalId'] as String?,
              canonical = ack.effect!['successorId'] as String?;
          if (provisional != null &&
              canonical == null &&
              ack.effect!.containsKey('successorId')) {
            await _detachProvisional(ack.operationId, provisional);
          }
          if (provisional != null && canonical != null) {
            await db.run(
              'UPDATE completionLinks SET parentId=? WHERE parentId=?',
              [canonical, provisional],
            );
          }
          for (final row in await _queue()) {
            var op = Operation.fromJson(jsonDecode(row['value'] as String));
            var json = op.toJson();
            if (provisional != null &&
                canonical != null &&
                op.entityId == provisional) {
              json['entityId'] = canonical;
            }
            if (op.kind == 'undoComplete' &&
                op.changes['completionId'] == ack.operationId) {
              json['changes'] = {'completionId': ack.effect!['completionId']};
            }
            await db.run('UPDATE pendingOperations SET value=? WHERE id=?', [
              jsonEncode(json),
              op.operationId,
            ]);
          }
          await db.run(
            'UPDATE completionLinks SET canonicalId=? WHERE operationId=?',
            [canonical, ack.operationId],
          );
        }
      }
      if (!response.hasMore) {
        final accepted = (await db.rows(
          "SELECT id FROM pendingOperations WHERE status='accepted'",
        )).map((r) => r['id']).toSet();
        for (final row in await _queue()) {
          final op = Operation.fromJson(jsonDecode(row['value'] as String));
          if (op.dependsOn.any(accepted.contains)) {
            await db.run('UPDATE pendingOperations SET value=? WHERE id=?', [
              jsonEncode({
                ...op.toJson(),
                'dependsOn': op.dependsOn
                    .where((d) => !accepted.contains(d))
                    .toList(),
              }),
              op.operationId,
            ]);
          }
        }
        await db.run("DELETE FROM pendingOperations WHERE status='accepted'");
      }
      await db.setMeta('cursor', '${response.nextCursor}');
      await _rebuild();
    });
    db.changed();
  }

  @override
  Future<void> markRejected(String operationId, String code) async {
    await db.run(
      "UPDATE pendingOperations SET status='rejected',error=? WHERE id=?",
      [code, operationId],
    );
    db.changed();
  }
}
