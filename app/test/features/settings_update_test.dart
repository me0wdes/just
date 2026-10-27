import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/backup_repository.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/features/settings/settings_controller.dart';
import 'package:day_planner/features/settings/settings_panel.dart';
import 'package:day_planner/platform/file_dialogs.dart';

void main() {
  testWidgets('a found update stays in settings and starts from there', (
    tester,
  ) async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final settings = SettingsController(db);
    await tester.runAsync(settings.load);
    var started = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SettingsPanel(
                settings: settings,
                backups: BackupRepository(
                  SqliteTaskRepository(db),
                  directory: Directory.systemTemp,
                ),
                files: NativeFileDialogs(),
                updateVersion: '9.9.9',
                onUpdate: () => started++,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-update')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Обновить до 9.9.9'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-update')));
    await tester.pumpAndSettle();
    expect(started, 1);
    expect(find.text('Настройки'), findsNothing);
    await db.close();
  });
}
