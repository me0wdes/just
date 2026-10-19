import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../domain/commands.dart';
import '../domain/models.dart';
import '../domain/entity_validation.dart';
import 'task_repository.dart';

class ImportPreview {
  final Uint8List bytes;
  final int newCount, matchingCount;
  final String digest, currentDigest;
  ImportPreview._(
    Uint8List bytes,
    this.newCount,
    this.matchingCount,
    this.digest,
    this.currentDigest,
  ) : bytes = bytes.asUnmodifiableView();
}

class ImportResult {
  final int appliedCount;
  final String safetyBackupPath;
  const ImportResult(this.appliedCount, this.safetyBackupPath);
}

class BackupRepository {
  final SqliteTaskRepository repository;
  final Directory directory;
  BackupRepository(this.repository, {required this.directory});
  static const taskFields = taskSnapshotFields;
  static const listFields = listSnapshotFields;
  static const ruleFields = ruleSnapshotFields;
  Future<Uint8List> exportBytes() => repository.db.transaction(() async {
    final entities = <Map<String, Object?>>[];
    for (final type in ['rule', 'list', 'task']) {
      final allowed = type == 'task'
          ? taskFields
          : type == 'list'
          ? listFields
          : ruleFields;
      final values = await repository.entities(type);
      values.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      for (final value in values) {
        entities.add({
          'type': type,
          'value': {
            for (final e in value.entries)
              if (allowed.contains(e.key)) e.key: e.value,
          },
        });
      }
    }
    if (!entities.any(
      (e) => e['type'] == 'list' && (e['value'] as Map)['id'] == inboxId,
    )) {
      entities.insert(0, {
        'type': 'list',
        'value': {'id': inboxId, 'name': 'Входящие', 'position': -1024},
      });
    }
    return Uint8List.fromList(
      utf8.encode(jsonEncode({'schemaVersion': 1, 'entities': entities})),
    );
  });

  List<Map<String, Object?>> _parse(Uint8List bytes) {
    try {
      if (bytes.length > 16 * 1024 * 1024) {
        throw const FormatException('Файл больше 16 МБ');
      }
      final root = jsonDecode(utf8.decode(bytes));
      if (root is! Map ||
          root['schemaVersion'] != 1 ||
          root['entities'] is! List) {
        throw const FormatException('Неизвестный формат копии');
      }
      final result = <Map<String, Object?>>[];
      final ids = <String>{};
      for (final entry in root['entities']) {
        if (entry is! Map || entry['value'] is! Map) {
          throw const FormatException('Неверная запись');
        }
        final type = entry['type'] as String;
        final value = Map<String, Object?>.from(entry['value'] as Map);
        final id = value['id'];
        if (id is! String ||
            !Uuid.isValidUUID(fromString: id) ||
            !ids.add('$type/$id')) {
          throw const FormatException('Неверный или повторяющийся id');
        }
        final allowed = type == 'task'
            ? taskFields
            : type == 'list'
            ? listFields
            : type == 'rule'
            ? ruleFields
            : throw const FormatException('Неизвестный тип записи');
        if (value.keys.any((k) => !allowed.contains(k))) {
          throw const FormatException('Неизвестное поле записи');
        }
        final validated = validateSnapshot(type, value);
        result.add({'type': type, 'value': validated});
      }
      return result;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Некорректные данные в копии');
    }
  }

  Future<ImportPreview> inspectImport(Uint8List bytes) =>
      repository.db.transaction(() async {
        final entries = _parse(bytes);
        final existing = <String>{};
        for (final type in ['rule', 'list', 'task']) {
          for (final v in await repository.entities(type)) {
            existing.add('$type/${v['id']}');
          }
        }
        existing.add('list/$inboxId');
        final imported = {
          for (final e in entries) '${e['type']}/${(e['value'] as Map)['id']}',
        };
        for (final e in entries) {
          if (e['type'] != 'task') continue;
          final task = e['value'] as Map;
          for (final pair in [
            ('list', task['listId']),
            for (final id in (task['listIds'] as List?) ?? const [])
              ('list', id),
            ('rule', task['recurrenceRuleId']),
          ]) {
            if (pair.$2 != null &&
                !imported.contains('${pair.$1}/${pair.$2}') &&
                !existing.contains('${pair.$1}/${pair.$2}')) {
              throw const FormatException(
                'Ссылка на отсутствующий список или повтор',
              );
            }
          }
        }
        final matching = imported.intersection(existing).length;
        return ImportPreview._(
          Uint8List.fromList(bytes),
          entries.length - matching,
          matching,
          sha256.convert(bytes).toString(),
          sha256.convert(await exportBytes()).toString(),
        );
      });

  Future<File> createSafetyBackup() async {
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/day-backup-${DateTime.now().toUtc().millisecondsSinceEpoch}-${const Uuid().v4()}.json',
    );
    return file.writeAsBytes(await exportBytes(), flush: true);
  }

  Future<ImportResult> applyImport(ImportPreview preview) =>
      repository.db.transaction(() async {
        if (sha256.convert(preview.bytes).toString() != preview.digest) {
          throw StateError('Копия изменилась');
        }
        final checked = await inspectImport(preview.bytes);
        if (checked.currentDigest != preview.currentDigest) {
          throw StateError(
            'Задачи изменились после просмотра. Откройте копию заново.',
          );
        }
        final safety = await createSafetyBackup();
        final entries = _parse(preview.bytes);
        const order = {'rule': 0, 'list': 1, 'task': 2};
        entries.sort((a, b) => order[a['type']]!.compareTo(order[b['type']]!));
        await repository.db.transaction(() async {
          for (final e in entries) {
            final value = e['value'] as Map<String, Object?>;
            if (e['type'] == 'list' && value['id'] == inboxId) continue;
            await repository.execute(
              TaskCommand.importEntity(
                e['type'] as String,
                value['id'] as String,
                value,
              ),
            );
          }
        });
        repository.db.changed();
        return ImportResult(entries.length, safety.path);
      });
}
