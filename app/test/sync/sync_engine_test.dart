import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/sync/protocol.dart';
import 'package:day_planner/sync/sync_engine.dart';
import 'package:day_planner/sync/sync_transport.dart';

class ControlledTransport implements SyncTransport {
  int calls = 0;
  final completer = Completer<SyncResponse>();
  @override
  Future<SyncResponse> exchange(SyncRequest request) {
    calls++;
    return completer.future;
  }
}

class PausedRepository extends SqliteTaskRepository {
  final applying = Completer<void>(), release = Completer<void>();
  PausedRepository(super.db);
  @override
  Future<void> applySyncResponse(SyncResponse response) async {
    applying.complete();
    await release.future;
    await super.applySyncResponse(response);
  }
}

class PagingTransport implements SyncTransport {
  final requests = <SyncRequest>[];
  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    requests.add(request);
    return SyncResponse(
      workspaceId: 'remote',
      acknowledgements: [],
      changes: [],
      nextCursor: requests.length,
      hasMore: requests.length == 1,
    );
  }
}

void main() {
  test(
    'dispose during response application prevents a second request',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local'),
          transport = PagingTransport();
      final repo = PausedRepository(db);
      final engine = SyncEngine(
        repo,
        transport,
        deviceId: '11111111-1111-4111-8111-111111111111',
        scheduler: TimerScheduler(),
      );
      final running = engine.syncNow();
      await repo.applying.future;
      engine.dispose();
      repo.release.complete();
      await running;
      expect(transport.requests.length, 1);
      await db.close();
    },
  );
  test('concurrent sync callers share one exchange', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final transport = ControlledTransport();
    final engine = SyncEngine(
      SqliteTaskRepository(db),
      transport,
      deviceId: '11111111-1111-4111-8111-111111111111',
      scheduler: TimerScheduler(),
    );
    try {
      final first = engine.syncNow(), second = engine.syncNow();
      await Future<void>.delayed(Duration.zero);
      transport.completer.complete(
        SyncResponse(
          workspaceId: 'remote',
          acknowledgements: [],
          changes: [],
          nextCursor: 0,
          hasMore: false,
        ),
      );
      await Future.wait([first, second]);
      expect(transport.calls, 1);
    } finally {
      engine.dispose();
      await db.close();
    }
  });
}
