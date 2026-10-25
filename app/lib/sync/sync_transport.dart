import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'trusted_roots.dart';

abstract interface class SyncTransport {
  Future<SyncResponse> exchange(SyncRequest request);
}

class SyncHttpException implements Exception {
  final int status;
  const SyncHttpException(this.status);
  @override
  String toString() => 'Ошибка подключения ($status)';
}

class HttpSyncTransport implements SyncTransport {
  final Uri endpoint;
  final Future<String> Function() tokenProvider;
  final bool allowDebugLoopback;
  HttpSyncTransport(
    this.endpoint,
    this.tokenProvider, {
    required this.allowDebugLoopback,
  }) {
    final loopback = [
      '127.0.0.1',
      'localhost',
      '::1',
      '[::1]',
    ].contains(endpoint.host);
    if (endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.host.isEmpty ||
        !(endpoint.scheme == 'https' ||
            (kDebugMode &&
                allowDebugLoopback &&
                loopback &&
                endpoint.scheme == 'http'))) {
      throw const FormatException('Нужен HTTPS адрес без ключа в ссылке');
    }
  }
  static final _context = SecurityContext(withTrustedRoots: true)
    ..setTrustedCertificatesBytes(utf8.encode(letsEncryptRoots));

  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    final bytes = utf8.encode(jsonEncode(request.toJson()));
    if (bytes.length > 262144) {
      throw const FormatException('Слишком большой пакет изменений');
    }
    final client = HttpClient(context: _context)
      ..connectionTimeout = const Duration(seconds: 10);
    Future<SyncResponse> run() async {
      final token = await tokenProvider();
      final req = await client.postUrl(endpoint);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.contentType = ContentType.json;
      req.add(bytes);
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw SyncHttpException(res.statusCode);
      }
      final chunks = <int>[];
      await for (final data in res) {
        if (chunks.length + data.length > 16 * 1024 * 1024) {
          throw const FormatException('Ответ слишком большой');
        }
        chunks.addAll(data);
      }
      return SyncResponse.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(chunks)) as Map),
      );
    }

    try {
      return await run().timeout(const Duration(seconds: 10));
    } finally {
      client.close(force: true);
    }
  }
}
