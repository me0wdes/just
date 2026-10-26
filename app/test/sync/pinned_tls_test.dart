import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/features/settings/connection_panel.dart';
import 'package:day_planner/sync/protocol.dart';
import 'package:day_planner/sync/sync_transport.dart';

void main() {
  late HttpServer server;
  late String pin;
  late Directory dir;
  setUpAll(() async {
    // The same self-signed IP certificate install.sh makes in direct mode.
    dir = Directory.systemTemp.createTempSync('pin-');
    final r = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'ec',
      '-pkeyopt',
      'ec_paramgen_curve:prime256v1',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=Just sync',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
      '-keyout',
      '${dir.path}/key.pem',
      '-out',
      '${dir.path}/cert.pem',
    ]);
    expect(r.exitCode, 0);
    final context = SecurityContext()
      ..useCertificateChain('${dir.path}/cert.pem')
      ..usePrivateKey('${dir.path}/key.pem');
    server = await HttpServer.bindSecure('127.0.0.1', 0, context);
    server.listen((req) async {
      await req.drain<void>();
      req.response
        ..statusCode = 401
        ..write('{"error":{"code":"unauthorized"}}');
      await req.response.close();
    });
    final der = await Process.run('openssl', [
      'x509',
      '-in',
      '${dir.path}/cert.pem',
      '-outform',
      'der',
    ], stdoutEncoding: null);
    pin = sha256.convert(der.stdout as List<int>).toString();
  });
  tearDownAll(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Future<Object?> call(String fingerprint) async {
    final t = HttpSyncTransport(
      Uri.parse('https://127.0.0.1:${server.port}/sync#pin=$fingerprint'),
      () async => 'A' * 43,
      allowDebugLoopback: false,
    );
    try {
      await t.exchange(
        SyncRequest(
          deviceId: '6f0c2a54-4b9e-4f6b-9a51-0d3c7e1a2b01',
          cursor: 0,
          operations: [],
        ),
      );
      return null;
    } catch (e) {
      return e;
    }
  }

  test(
    'a pinned self-signed server is reached; a wrong pin is refused',
    () async {
      // 401 means TLS went through and the server answered.
      expect(await call(pin), isA<SyncHttpException>());
      expect(await call('0' * 64), isA<HandshakeException>());
    },
  );

  test('the connection string carries the pin into the address', () {
    final link =
        'just1:${base64Url.encode(utf8.encode(jsonEncode({'u': 'https://104.171.128.200:8443/sync', 'k': 'A' * 43, 'p': 'a' * 64}))).replaceAll('=', '')}';
    final parsed = parseConnectionString(link)!;
    expect(
      parsed.endpoint.toString(),
      'https://104.171.128.200:8443/sync#pin=${'a' * 64}',
    );
    final bad =
        'just1:${base64Url.encode(utf8.encode(jsonEncode({'u': 'https://h/sync', 'k': 'k', 'p': 'nope'}))).replaceAll('=', '')}';
    expect(parseConnectionString(bad), isNull);
  });
}
