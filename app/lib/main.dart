import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:timezone/data/latest.dart' as tz;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'app_host.dart';
import 'data/app_database.dart';
import 'features/settings/settings_controller.dart';
import 'platform/secure_connection_store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'ItsHover',
    ], await rootBundle.loadString('assets/licenses/ItsHover-Apache-2.0.txt'));
  });
  // Bootstrap preferences and the active task workspace use independent files.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final directoryIndex = args.indexOf('--data-directory');
  final directory = directoryIndex >= 0 && directoryIndex + 1 < args.length
      ? Directory(args[directoryIndex + 1])
      : await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final root = AppDatabase.open(
    File(path.join(directory.path, 'day.sqlite')),
    workspaceId: 'local',
  );
  final filename = await root.setting('activeDatabase');
  final database =
      filename != null &&
          RegExp(r'^workspace-[0-9a-f-]+\.sqlite$').hasMatch(filename)
      ? AppDatabase.open(
          File(path.join(directory.path, filename)),
          workspaceId: 'local',
        )
      : root;
  final settings = SettingsController(root);
  await settings.load();
  final profile = await root.setting('activeConnectionProfile');
  ConnectionSecret? secret;
  if (profile != null && profile.isNotEmpty) {
    try {
      secret = await const OsSecureConnectionStore().read(profile);
    } catch (_) {
      /* Keep local tasks accessible if the OS credential vault is unavailable. */
    }
  }
  final deviceId = await root.setting('deviceId') ?? const Uuid().v4();
  await root.setSetting('deviceId', deviceId);
  runApp(
    DayHost(
      rootDatabase: root,
      taskDatabase: database,
      directory: directory,
      settings: settings,
      secret: secret,
      deviceId: deviceId,
    ),
  );
}
