import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/features/settings/settings_controller.dart';

void main() {
  test('theme sound and volume persist only on this device', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    try {
      final settings = SettingsController(db);
      await settings.load();
      await settings.setTheme(ThemeMode.dark);
      await settings.setSound(false);
      await settings.setVolume(.2);
      final next = SettingsController(db);
      await next.load();
      expect(next.themeMode, ThemeMode.dark);
      expect(next.completionSoundEnabled, false);
      expect(next.volume, .2);
      expect(await db.rows('SELECT * FROM pendingOperations'), isEmpty);
    } finally {
      await db.close();
    }
  });
}
