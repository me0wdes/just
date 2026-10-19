import 'package:flutter/material.dart';

import '../../data/app_database.dart';

class SettingsController extends ChangeNotifier {
  final AppDatabase database;
  ThemeMode themeMode = ThemeMode.system;
  bool completionSoundEnabled = true, hapticsEnabled = true;
  double volume = .35;
  SettingsController(this.database);
  Future<void> load() async {
    final theme = await database.setting('theme');
    themeMode =
        ThemeMode.values.where((v) => v.name == theme).firstOrNull ??
        ThemeMode.system;
    completionSoundEnabled = await database.setting('sound') != 'false';
    hapticsEnabled = await database.setting('haptics') != 'false';
    volume = (double.tryParse(await database.setting('volume') ?? '') ?? .35)
        .clamp(0, 1);
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode value) async {
    await database.setSetting('theme', value.name);
    themeMode = value;
    notifyListeners();
  }

  Future<void> setSound(bool value) async {
    await database.setSetting('sound', '$value');
    completionSoundEnabled = value;
    notifyListeners();
  }

  Future<void> setHaptics(bool value) async {
    await database.setSetting('haptics', '$value');
    hapticsEnabled = value;
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    value = value.clamp(0, 1);
    await database.setSetting('volume', '$value');
    volume = value;
    notifyListeners();
  }
}
