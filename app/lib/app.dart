import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/tasks/task_controller.dart';
import 'features/tasks/task_home.dart';
import 'platform/feedback_service.dart';
import 'theme/app_theme.dart';
import 'theme/day_sound.dart';
import 'theme/toast.dart';
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

  /// A connection was saved, but its key could not be read on this start.
  final bool connectionLost;

  /// Where this device syncs, e.g. `104.171.128.200:8443`.
  final String? server;

  /// A newer release and how to install it, offered in settings.
  final String? updateVersion;
  final VoidCallback? onUpdate;
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
    this.connectionLost = false,
    this.server,
    this.updateVersion,
    this.onUpdate,
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
              ? (connectionLost ? () => openSettings(context) : null)
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
          syncLabel:
              engine?.state.label ??
              (connectionLost
                  ? SyncState.authRequired.label
                  : SyncState.localSaved.label),
          onSettings: settings == null || backups == null
              ? null
              : () => openSettings(context),
        ),
      ),
    ),
  );

  void openSettings(BuildContext context) {
    if (settings == null || backups == null) return;
    DaySound.play(context, UiSound.open);
    // Phone: a full-screen page, not a window over the tasks.
    final phone = MediaQuery.sizeOf(context).width < 600;
    Widget page(BuildContext _) => SettingsPanel(
      settings: settings!,
      backups: backups!,
      files: NativeFileDialogs(),
      updateVersion: updateVersion,
      onUpdate: onUpdate,
      connectionPanel: connections == null
          ? null
          : ConnectionPanel(
              service: connections!,
              engine: engine,
              server: server,
              lost: connectionLost,
              onConnected: (result) async {
                Navigator.of(context).pop();
                await onConnected?.call(result);
                if (context.mounted) {
                  DayToast.show(
                    context,
                    'Подключено к ${serverName(result.secret.endpoint)}. Задачи синхронизируются',
                  );
                }
              },
              onDisconnected: () async {
                Navigator.of(context).pop();
                await onDisconnected?.call();
              },
            ),
    );
    (phone
            ? Navigator.of(context).push<void>(MaterialPageRoute(builder: page))
            : showDialog<void>(context: context, builder: page))
        .then((_) {
          if (context.mounted) DaySound.play(context, UiSound.close);
        });
  }
}
