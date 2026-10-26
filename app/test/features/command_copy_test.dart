import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/settings/connection_panel.dart';
import 'package:day_planner/sync/connection_service.dart';

import '../sync/connection_service_test.dart' show MemorySecrets;

void main() {
  testWidgets('copying the install command confirms on the button', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    final db = AppDatabase.memory(workspaceId: 'local');
    final repo = SqliteTaskRepository(db);
    final dir = Directory.systemTemp.createTempSync('copy-');
    final service = ConnectionService(
      rootDatabase: db,
      repository: repo,
      backups: BackupRepository(repo, directory: dir),
      directory: dir,
      secrets: MemorySecrets(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectionPanel(
              service: service,
              connected: false,
              onConnected: (_) async {},
              onDisconnected: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Свой сервер'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Скопировать'));
    await tester.pump();
    expect(clipboard, installCommand);
    expect(find.text('Скопировано'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Скопировать'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
}
