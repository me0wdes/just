import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

class AppDatabase extends GeneratedDatabase {
  final String workspaceId;
  final updates = StreamController<void>.broadcast();
  final localUpdates = StreamController<void>.broadcast();
  AppDatabase._(super.executor, this.workspaceId);
  factory AppDatabase.open(File file, {required String workspaceId}) =>
      AppDatabase._(NativeDatabase.createInBackground(file), workspaceId);
  factory AppDatabase.memory({required String workspaceId}) =>
      AppDatabase._(NativeDatabase.memory(), workspaceId);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      for (final sql in schemaStatements) {
        await customStatement(sql);
      }
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys=ON');
    },
  );
  Future<List<Map<String, Object?>>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) async => (await customSelect(
    sql,
    variables: args.map((v) => Variable(v)).toList(),
  ).get()).map((r) => r.data).toList();
  Future<void> run(String sql, [List<Object?> args = const []]) =>
      customStatement(sql, args);
  Future<String?> setting(String key) async =>
      (await rows('SELECT value FROM localSettings WHERE key=?', [
            key,
          ])).firstOrNull?['value']
          as String?;
  Future<void> setSetting(String key, String value) => run(
    'INSERT INTO localSettings VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  Future<String?> meta(String key) async =>
      (await rows('SELECT value FROM syncMetadata WHERE key=?', [
            key,
          ])).firstOrNull?['value']
          as String?;
  Future<void> setMeta(String key, String value) => run(
    'INSERT INTO syncMetadata VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );
  void changed({bool local = false}) {
    if (!updates.isClosed) updates.add(null);
    if (local && !localUpdates.isClosed) localUpdates.add(null);
  }

  @override
  Future<void> close() async {
    await updates.close();
    await localUpdates.close();
    await super.close();
  }
}
