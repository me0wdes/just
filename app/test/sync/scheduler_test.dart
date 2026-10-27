import 'package:flutter_test/flutter_test.dart';
import 'package:day_planner/data/app_database.dart';
import 'package:day_planner/data/task_repository.dart';
import 'package:day_planner/sync/protocol.dart';
import 'package:day_planner/sync/sync_engine.dart';
import 'package:day_planner/sync/sync_transport.dart';

class Handle implements CancelHandle {
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
}

class TestScheduler implements Scheduler {
  final delays = <Duration>[];
  final handles = <Handle>[];
  final callbacks = <void Function()>[];
  @override
  CancelHandle schedule(Duration delay, void Function() callback) {
    delays.add(delay);
    callbacks.add(callback);
    final handle = Handle();
    handles.add(handle);
    return handle;
  }

  @override
  DateTime now() => DateTime.utc(2026, 10, 19);
  @override
  double jitter() => 0;
}

class FailureTransport implements SyncTransport {
  final int status;
  int calls = 0;
  FailureTransport(this.status);
  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    calls++;
    throw SyncHttpException(status);
  }
}

class EmptyTransport implements SyncTransport {
  int calls = 0;
  @override
  Future<SyncResponse> exchange(SyncRequest request) async {
    calls++;
    return SyncResponse(
      workspaceId: 'remote',
      acknowledgements: [],
      changes: [],
      nextCursor: 0,
      hasMore: false,
    );
  }
}

void main() {
  test(
    'in sync, the next pass comes in 3 seconds without a status flash',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final scheduler = TestScheduler(), transport = EmptyTransport();
      final engine = SyncEngine(
        SqliteTaskRepository(db),
        transport,
        deviceId: 'id',
        scheduler: scheduler,
      );
      try {
        engine.setForeground(true);
        await engine.syncNow();
        expect(engine.state, SyncState.synced);
        expect(scheduler.delays.last, const Duration(seconds: 3));
        final states = <SyncState>[];
        engine.addListener(() => states.add(engine.state));
        scheduler.callbacks.last();
        await engine.syncNow();
        expect(transport.calls, 2);
        expect(states, isNot(contains(SyncState.syncing)));
      } finally {
        engine.dispose();
        await db.close();
      }
    },
  );
  test(
    'foreground network retry stays at least 2 seconds and stops in background',
    () async {
      final db = AppDatabase.memory(workspaceId: 'local');
      final scheduler = TestScheduler();
      final engine = SyncEngine(
        SqliteTaskRepository(db),
        FailureTransport(503),
        deviceId: 'id',
        scheduler: scheduler,
      );
      try {
        engine.setForeground(true);
        await engine.syncNow();
        expect(
          scheduler.delays.single.inMilliseconds,
          greaterThanOrEqualTo(2000),
        );
        engine.setForeground(false);
        expect(scheduler.handles.last.cancelled, true);
      } finally {
        engine.dispose();
        await db.close();
      }
    },
  );
  test('bad credentials stop automatic retries', () async {
    final db = AppDatabase.memory(workspaceId: 'local');
    final scheduler = TestScheduler(), transport = FailureTransport(401);
    final engine = SyncEngine(
      SqliteTaskRepository(db),
      transport,
      deviceId: 'id',
      scheduler: scheduler,
    );
    try {
      engine.setForeground(true);
      await engine.syncNow();
      engine.setForeground(false);
      engine.setForeground(true);
      expect(engine.state, SyncState.authRequired);
      expect(scheduler.delays, isEmpty);
      expect(transport.calls, 1);
    } finally {
      engine.dispose();
      await db.close();
    }
  });
}
