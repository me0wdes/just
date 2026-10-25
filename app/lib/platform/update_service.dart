import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

/// Release builds get their version from CI (`--dart-define=JUST_VERSION`);
/// local builds have none and never look for updates.
const appVersion = String.fromEnvironment('JUST_VERSION');

const _latest = 'https://api.github.com/repos/me0wdes/just/releases/latest';
const releasesPage = 'https://github.com/me0wdes/just/releases/latest';

class AppUpdate {
  final String version;
  final Map<String, String> assets;
  const AppUpdate(this.version, this.assets);
}

/// True when [a] is a newer `x.y.z` than [b].
bool isNewer(String a, String b) {
  List<int> parts(String v) =>
      v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// The latest public release when it is newer than this build, else null.
/// Network problems are silent: the next check simply tries again.
Future<AppUpdate?> checkForUpdate() async {
  if (appVersion.isEmpty ||
      !(Platform.isWindows || Platform.isMacOS || Platform.isAndroid)) {
    return null;
  }
  try {
    final release = jsonDecode(utf8.decode(await _get(_latest))) as Map;
    final version = (release['tag_name'] as String).replaceFirst('v', '');
    if (!isNewer(version, appVersion)) return null;
    return AppUpdate(version, {
      for (final a in release['assets'] as List)
        a['name'] as String: a['browser_download_url'] as String,
    });
  } catch (_) {
    return null;
  }
}

/// The installed Windows build replaces itself; Inno Setup leaves its
/// uninstaller beside it, a copy unpacked from the zip has none.
bool installsInPlace(AppUpdate update) =>
    Platform.isWindows &&
    update.assets['Just-Setup-${update.version}.exe'] != null &&
    File('${File(Platform.resolvedExecutable).parent.path}\\unins000.exe')
        .existsSync();

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

/// Downloads the setup with progress, checks it against SHA256SUMS.txt and
/// starts it with no window of its own (/VERYSILENT): it closes Just,
/// installs and opens the new version. The caller then quits.
Future<void> installInPlace(
  AppUpdate update, {
  void Function(int received, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final setup = 'Just-Setup-${update.version}.exe';
  final bytes = await _get(
    update.assets[setup]!,
    onProgress: onProgress,
    cancelled: cancelled,
  );
  final sums = utf8.decode(await _get(update.assets['SHA256SUMS.txt']!));
  final expected = RegExp('([0-9a-f]{64})\\s+\\*?${RegExp.escape(setup)}')
      .firstMatch(sums)
      ?.group(1);
  if (expected == null || sha256.convert(bytes).toString() != expected) {
    throw const FormatException('Обновление повреждено');
  }
  if (cancelled?.call() == true) throw const UpdateCancelled();
  final file = File('${Directory.systemTemp.path}\\$setup');
  await file.writeAsBytes(bytes);
  await Process.start(file.path, [
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
  ], mode: ProcessStartMode.detached);
}

/// Elsewhere the download opens in the browser; on Android the APK then
/// installs over the current app.
Future<void> openDownload(AppUpdate update) async {
  if (Platform.isAndroid) {
    await const MethodChannel('day/platform').invokeMethod('openUrl', {
      'url':
          update.assets['Just-${update.version}-Android.apk'] ?? releasesPage,
    });
    return;
  }
  final dmg = update.assets['Just-${update.version}.dmg'];
  final url = Platform.isMacOS && dmg != null ? dmg : releasesPage;
  await Process.run(Platform.isMacOS ? 'open' : 'explorer', [url]);
}

Future<List<int>> _get(
  String url, {
  void Function(int received, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final client = HttpClient()..userAgent = 'Just/$appVersion';
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (cancelled?.call() == true) throw const UpdateCancelled();
      bytes.add(chunk);
      onProgress?.call(bytes.length, response.contentLength);
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}
