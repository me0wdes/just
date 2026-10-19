import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../data/task_repository.dart';
import '../data/backup_repository.dart';
import '../domain/commands.dart';
import '../domain/models.dart';
import '../platform/secure_connection_store.dart';
import 'sync_transport.dart';
import 'protocol.dart';

enum ConnectionChoice { merge, openSeparate }

class RemoteWorkspacePreview {
  final String workspaceId;
  final Uri endpoint;
  final int remoteCount, localCount, pendingCount, matchingCount;
  final String _token;
  bool _consumed = false;
  RemoteWorkspacePreview._(
    this.workspaceId,
    this.endpoint,
    this.remoteCount,
    this.localCount,
    this.pendingCount,
    this.matchingCount,
    this._token,
  );
}

class ConnectionResult {
  final AppDatabase database;
  final SqliteTaskRepository repository;
  final String profileId, safetyBackupPath;
  final ConnectionSecret secret;
  const ConnectionResult({
    required this.database,
    required this.repository,
    required this.profileId,
    required this.safetyBackupPath,
    required this.secret,
  });
}

class ConnectionService {
  final AppDatabase rootDatabase;
  final SqliteTaskRepository repository;
  final BackupRepository backups;
  final Directory directory;
  final SecureConnectionStore secrets;
  final Future<void> Function()? beforeConnect, connectFailed, beforeDisconnect;
  final SyncTransport Function(Uri, String) transportFactory;
  ConnectionService({
    required this.rootDatabase,
    required this.repository,
    required this.backups,
    required this.directory,
    required this.secrets,
    this.beforeConnect,
    this.connectFailed,
    this.beforeDisconnect,
    SyncTransport Function(Uri, String)? transportFactory,
  }) : transportFactory =
           transportFactory ??
           ((uri, key) => HttpSyncTransport(
             uri,
             () async => key,
             allowDebugLoopback: false,
           ));
  Future<RemoteWorkspacePreview> inspect(Uri endpoint, String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43,}$').hasMatch(token)) {
      throw const FormatException(
        'Ключ подключения должен содержать минимум 32 байта',
      );
    }
    final transport = transportFactory(endpoint, token);
    final device = const Uuid().v4();
    var cursor = 0;
    String? workspace;
    final remote = <String, Map<String, Object?>>{};
    for (var page = 0; page < 10000; page++) {
      final response = await transport.exchange(
        SyncRequest(deviceId: device, cursor: cursor, operations: []),
      );
      if (workspace != null && workspace != response.workspaceId) {
        throw const FormatException(
          'Сервер сменил пространство во время проверки',
        );
      }
      workspace = response.workspaceId;
      for (final c in response.changes) {
        if (c.entityType == 'task') remote[c.entityId] = c.value;
      }
      if (!response.hasMore) break;
      if (response.nextCursor <= cursor) {
        throw const FormatException('Сервер не продвинул страницу');
      }
      cursor = response.nextCursor;
      if (page == 9999) throw const FormatException('Слишком много страниц');
    }
    final local = (await repository.entities('task'))
        .where((v) => v['deletedAt'] == null)
        .toList();
    final remoteIds = remote.entries
        .where((e) => e.value['deletedAt'] == null)
        .map((e) => e.key)
        .toSet();
    return RemoteWorkspacePreview._(
      workspace!,
      endpoint,
      remoteIds.length,
      local.length,
      (await repository.allPending()).length,
      local.where((v) => remoteIds.contains(v['id'])).length,
      token,
    );
  }

  Future<ConnectionResult> connect(
    RemoteWorkspacePreview preview,
    ConnectionChoice choice,
  ) async {
    if (preview._consumed) throw StateError('Проверка уже использована');
    final verified = await transportFactory(preview.endpoint, preview._token)
        .exchange(
          SyncRequest(
            deviceId: const Uuid().v4(),
            expectedWorkspaceId: preview.workspaceId,
            cursor: 0,
            operations: [],
          ),
        );
    if (verified.workspaceId != preview.workspaceId) {
      throw const FormatException(
        'Пространство сервера изменилось. Проверьте подключение заново.',
      );
    }
    await beforeConnect?.call();
    try {
      final safety = await backups.createSafetyBackup();
      final snapshot = choice == ConnectionChoice.merge
          ? jsonDecode(utf8.decode(await backups.exportBytes())) as Map
          : null;
      final profileId = const Uuid().v4();
      final filename = 'workspace-$profileId.sqlite';
      final database = AppDatabase.open(
        File('${directory.path}/$filename'),
        workspaceId: preview.workspaceId,
      );
      final repo = SqliteTaskRepository(database);
      final secret = ConnectionSecret(
        endpoint: preview.endpoint,
        token: preview._token,
        workspaceId: preview.workspaceId,
      );
      var savedSecret = false;
      try {
        await database.setMeta('remoteWorkspace', preview.workspaceId);
        if (snapshot != null) {
          await database.transaction(() async {
            for (final raw in snapshot['entities'] as List) {
              final entry = raw as Map;
              final value = Map<String, Object?>.from(entry['value'] as Map);
              if (entry['type'] == 'list' && value['id'] == inboxId) continue;
              await repo.execute(
                TaskCommand.importEntity(
                  entry['type'] as String,
                  value['id'] as String,
                  value,
                ),
              );
            }
          });
        }
        await secrets.write(profileId, secret);
        savedSecret = true;
        await rootDatabase.transaction(() async {
          await rootDatabase.setSetting('activeDatabase', filename);
          await rootDatabase.setSetting('activeConnectionProfile', profileId);
        });
        preview._consumed = true;
        return ConnectionResult(
          database: database,
          repository: repo,
          profileId: profileId,
          safetyBackupPath: safety.path,
          secret: secret,
        );
      } catch (_) {
        await database.close();
        if (savedSecret) {
          try {
            await secrets.delete(profileId);
          } catch (_) {}
        }
        rethrow;
      }
    } catch (_) {
      await connectFailed?.call();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await beforeDisconnect?.call();
    final profile = await rootDatabase.setting('activeConnectionProfile');
    await rootDatabase.setSetting('activeConnectionProfile', '');
    if (profile != null && profile.isNotEmpty) await secrets.delete(profile);
  }
}
