import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/tasks/task_controller.dart';
import 'features/tasks/task_home.dart';
import 'platform/feedback_service.dart';
import 'theme/app_theme.dart';
import 'theme/day_sound.dart';
import 'data/backup_repository.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_panel.dart';
import 'platform/file_dialogs.dart';
import 'sync/sync_engine.dart';
import 'sync/connection_service.dart';
import 'features/settings/connection_panel.dart';
import 'features/settings/sync_conflicts.dart';

class DayApp extends StatelessWidget {
  final TaskController controller;
  final ThemeMode themeMode;
  final SettingsController? settings;
  final BackupRepository? backups;
  final SyncEngine? engine;
  final ConnectionService? connections;
  final Future<void> Function(ConnectionResult)? onConnected;
  final Future<void> Function()? onDisconnected;
  final Future<bool> Function()? onRequestReminder;
  final GlobalKey<NavigatorState>? navigatorKey;
  const DayApp({
    super.key,
    required this.controller,
    this.themeMode = ThemeMode.system,
    this.settings,
    this.backups,
    this.engine,
    this.connections,
    this.onConnected,
    this.onDisconnected,
    this.onRequestReminder,
    this.navigatorKey,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      ?settings,
      ?engine,
      if (settings == null && engine == null) controller,
    ]),
    builder: (context, _) => MaterialApp(
      title: 'Just',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: dayTheme(Brightness.light),
      darkTheme: dayTheme(Brightness.dark),
      themeMode: settings?.themeMode ?? themeMode,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          DaySound(feedback: controller.feedback, child: child!),
      home: Builder(
        builder: (context) => TaskHome(
          key: ObjectKey(controller),
          controller: controller,
          onRequestReminder: onRequestReminder,
          onSync: engine == null
              ? null
              : () async {
                  if (engine!.state == SyncState.rejected && backups != null) {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => SyncConflicts(backups: backups!),
                    );
                    if (!context.mounted) return;
                  }
                  await engine!.syncNow();
                },
          syncLabel: engine == null
              ? 'Сохранено на устройстве'
              : switch (engine!.state) {
                  SyncState.localSaved => 'Сохранено на устройстве',
                  SyncState.syncing => 'Синхронизация…',
                  SyncState.synced => 'Всё синхронизировано',
                  SyncState.offline => 'Без сети · задачи сохранены',
                  SyncState.authRequired =>
                    'Проверьте подключение в настройках',
                  SyncState.rejected =>
                    'Есть конфликт · локальная копия сохранена',
                },
          onSettings: settings == null || backups == null
              ? null
              : () {
                  DaySound.play(context, UiSound.open);
                  showDialog<void>(
                    context: context,
                    builder: (_) => SettingsPanel(
                      settings: settings!,
                      backups: backups!,
                      files: NativeFileDialogs(),
                      connectionPanel: connections == null
                          ? null
                          : ConnectionPanel(
                              service: connections!,
                              connected: engine != null,
                              onConnected: (result) async {
                                Navigator.of(context).pop();
                                await onConnected?.call(result);
                              },
                              onDisconnected: () async {
                                Navigator.of(context).pop();
                                await onDisconnected?.call();
                              },
                            ),
                    ),
                  ).then((_) {
                    if (context.mounted) DaySound.play(context, UiSound.close);
                  });
                },
        ),
      ),
    ),
  );
}
