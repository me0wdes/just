import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConnectionSecret {
  final Uri endpoint;
  final String token, workspaceId;
  const ConnectionSecret({
    required this.endpoint,
    required this.token,
    required this.workspaceId,
  });
  Map<String, Object?> toJson() => {
    'endpoint': endpoint.toString(),
    'token': token,
    'workspaceId': workspaceId,
  };
  factory ConnectionSecret.fromJson(Map<String, Object?> json) =>
      ConnectionSecret(
        endpoint: Uri.parse(json['endpoint'] as String),
        token: json['token'] as String,
        workspaceId: json['workspaceId'] as String,
      );
  @override
  String toString() => 'ConnectionSecret([redacted])';
}

abstract interface class SecureConnectionStore {
  Future<ConnectionSecret?> read(String profileId);
  Future<void> write(String profileId, ConnectionSecret secret);
  Future<void> delete(String profileId);
}

class OsSecureConnectionStore implements SecureConnectionStore {
  final FlutterSecureStorage storage;
  // On macOS the login keychain needs no signing team or keychain-sharing
  // entitlement, so unsigned local builds keep the sync key too.
  const OsSecureConnectionStore({
    this.storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  });
  @override
  Future<ConnectionSecret?> read(String profileId) async {
    final value = await storage.read(key: 'day.connection.$profileId');
    return value == null
        ? null
        : ConnectionSecret.fromJson(jsonDecode(value) as Map<String, Object?>);
  }

  @override
  Future<void> write(String profileId, ConnectionSecret secret) =>
      storage.write(
        key: 'day.connection.$profileId',
        value: jsonEncode(secret.toJson()),
      );
  @override
  Future<void> delete(String profileId) =>
      storage.delete(key: 'day.connection.$profileId');
}
