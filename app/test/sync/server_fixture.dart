import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

class ServerFixture {
  final Directory directory;
  final Process process;
  final Uri endpoint;
  final String token;
  ServerFixture._(this.directory, this.process, this.endpoint, this.token);
  static Future<ServerFixture> start() async {
    final dir = Directory.systemTemp.createTempSync('day-server-');
    final token = base64Url
        .encode(
          List.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256),
        )
        .replaceAll('=', '');
    final process = await Process.start(
      'node',
      ['src/index.mjs', '--data', dir.path, '--port', '0'],
      workingDirectory: Directory('../server').absolute.path,
      environment: {'DAY_SYNC_TOKEN': token},
      runInShell: false,
    );
    process.stderr.drain<void>();
    final completer = Completer<Uri>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'http://127\.0\.0\.1:\d+').firstMatch(line);
          if (match != null && !completer.isCompleted) {
            completer.complete(Uri.parse('${match[0]}/sync'));
          }
        });
    process.exitCode.then((code) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('test server exit $code'));
      }
    });
    return ServerFixture._(
      dir,
      process,
      await completer.future.timeout(const Duration(seconds: 10)),
      token,
    );
  }

  Future<void> close() async {
    process.kill();
    await process.exitCode;
    directory.deleteSync(recursive: true);
  }
}

String uuid() => const Uuid().v4();
