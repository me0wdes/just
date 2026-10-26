import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/settings/connection_panel.dart';
import 'package:day_planner/sync/connection_service.dart';
import 'package:day_planner/sync/sync_engine.dart';
import 'package:day_planner/sync/sync_transport.dart';

import '../sync/connection_service_test.dart' show MemorySecrets;

class _Never implements Scheduler {
  @override
  DateTime now() => DateTime(2026);
  @override
  double jitter() => 0;
  @override
  CancelHandle schedule(Duration delay, void Function() callback) => _Handle();
}

class _Handle implements CancelHandle {
  @override
  void cancel() {}
}

void main() {
  late AppDatabase db;
  late SqliteTaskRepository repo;
  late ConnectionService service;
  setUp(() {
    db = AppDatabase.memory(workspaceId: 'local');
    repo = SqliteTaskRepository(db);
    final dir = Directory.systemTemp.createTempSync('states-');
    service = ConnectionService(
      rootDatabase: db,
      repository: repo,
      backups: BackupRepository(repo, directory: dir),
      directory: dir,
      secrets: MemorySecrets(),
    );
  });
  tearDown(() => db.close());

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('a lost connection keeps «Свой сервер» and says what to do', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ConnectionPanel(
          service: service,
          lost: true,
          onConnected: (_) async {},
          onDisconnected: () async {},
        ),
      ),
    );
    expect(find.byKey(const Key('sync-lost')), findsOneWidget);
    expect(find.text('Вставить и подключить'), findsOneWidget);
    expect(
      find.text('Задачи хранятся только здесь, без синхронизации.'),
      findsNothing,
    );
  });

  testWidgets('connected shows the server and the sync state', (tester) async {
    final engine = SyncEngine(
      repo,
      HttpSyncTransport(
        Uri.parse('https://104.171.128.200:8443/sync'),
        () async => 'k',
        allowDebugLoopback: false,
      ),
      deviceId: 'd',
      scheduler: _Never(),
    );
    await tester.pumpWidget(
      host(
        ConnectionPanel(
          service: service,
          engine: engine,
          server: serverName(Uri.parse('https://104.171.128.200:8443/sync')),
          onConnected: (_) async {},
          onDisconnected: () async {},
        ),
      ),
    );
    expect(find.text('Синхронизация включена'), findsOneWidget);
    expect(
      find.text('104.171.128.200:8443\nСохранено на устройстве'),
      findsOneWidget,
    );
    expect(find.text('Синхронизировать'), findsOneWidget);
    engine.dispose();
  });

  test('task counts and server names read naturally', () {
    expect(tasks(1), '1 задача');
    expect(tasks(3), '3 задачи');
    expect(tasks(12), '12 задач');
    expect(tasks(21), '21 задача');
    expect(serverName(Uri.parse('https://a.example/sync')), 'a.example');
  });
}
