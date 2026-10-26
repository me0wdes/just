import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import 'protocol.dart';
import 'sync_transport.dart';

abstract interface class CancelHandle {
  void cancel();
}

abstract interface class Scheduler {
  CancelHandle schedule(Duration delay, void Function() callback);
  DateTime now();
  double jitter();
}

class _TimerHandle implements CancelHandle {
  final Timer timer;
  _TimerHandle(this.timer);
  @override
  void cancel() => timer.cancel();
}

class TimerScheduler implements Scheduler {
  @override
  CancelHandle schedule(Duration delay, void Function() callback) =>
      _TimerHandle(Timer(delay, callback));
  @override
  DateTime now() => DateTime.now();
  @override
  double jitter() => Random().nextDouble();
}

enum SyncState {
  localSaved('Сохранено на устройстве'),
  syncing('Синхронизация…'),
  synced('Всё синхронизировано'),
  offline('Без сети · задачи сохранены'),
  authRequired('Проверьте подключение в настройках'),
  rejected('Есть конфликт · локальная копия сохранена');

  final String label;
  const SyncState(this.label);
}

class SyncEngine extends ChangeNotifier {
  final TaskRepository repository;
  final SyncTransport transport;
  final String deviceId;
  final Scheduler scheduler;
  SyncState state = SyncState.localSaved;
  DateTime? lastSuccessAt;
  String? lastRejectionCode;
  Future<void>? _running;
  CancelHandle? _timer;
  bool _foreground = false, _disposed = false;
  int _failures = 0;
  SyncEngine(
    this.repository,
    this.transport, {
    required this.deviceId,
    required this.scheduler,
  });
  void _state(SyncState next) {
    state = next;
    if (!_disposed) notifyListeners();
  }

  Future<void> syncNow() {
    if (_disposed) return Future.value();
    return _running ??= _exchange().whenComplete(() => _running = null);
  }

  Future<void> _exchange() async {
    _timer?.cancel();
    _state(SyncState.syncing);
    var rejected = false;
    try {
      for (var iteration = 0; iteration < 10000; iteration++) {
        if (_disposed) return;
        final expectedWorkspace = await repository.expectedWorkspaceId();
        if (_disposed) return;
        final cursor = await repository.getCursor();
        if (_disposed) return;
        final operations = await repository.pendingBatch(
          maxOperations: 100,
          byteBudget: 260000,
        );
        if (_disposed) return;
        final batch = expectedWorkspace == null
            ? <Operation>[]
            : List<Operation>.of(operations);
        while (batch.isNotEmpty &&
            utf8
                    .encode(
                      jsonEncode(
                        SyncRequest(
                          deviceId: deviceId,
                          expectedWorkspaceId: expectedWorkspace,
                          cursor: cursor,
                          operations: batch,
                        ).toJson(),
                      ),
                    )
                    .length >
                262144) {
          batch.removeLast();
        }
        if (_disposed) return;
        final response = await transport.exchange(
          SyncRequest(
            deviceId: deviceId,
            expectedWorkspaceId: expectedWorkspace,
            cursor: cursor,
            operations: batch,
          ),
        );
        if (_disposed) return;
        await repository.applySyncResponse(response);
        if (_disposed) return;
        for (final ack in response.acknowledgements) {
          if (ack.status == 'rejected') {
            rejected = true;
            lastRejectionCode = ack.code;
          }
        }
        if (!response.hasMore &&
            (await repository.pendingBatch(
              maxOperations: 1,
              byteBudget: 260000,
            )).isEmpty) {
          lastSuccessAt = scheduler.now();
          _failures = 0;
          final problems = await repository.rejectedOperations();
          if (_disposed) return;
          if (problems.isNotEmpty) {
            lastRejectionCode = problems.first['code'] as String?;
          }
          _state(
            rejected || problems.isNotEmpty
                ? SyncState.rejected
                : SyncState.synced,
          );
          _schedule(const Duration(seconds: 15));
          return;
        }
      }
      throw StateError('Sync iteration limit reached');
    } catch (e) {
      if (_disposed) return;
      if (e is SyncHttpException && (e.status == 401 || e.status == 409)) {
        _state(SyncState.authRequired);
        return;
      }
      _failures++;
      _state(SyncState.offline);
      final seconds = min(60, 2 * pow(2, min(_failures - 1, 5)).toInt());
      _schedule(
        Duration(
          milliseconds: (seconds * 1000 * (.8 + .2 * scheduler.jitter()))
              .round()
              .clamp(2000, 60000),
        ),
      );
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_foreground && !_disposed) {
      _timer = scheduler.schedule(delay, () => unawaited(syncNow()));
    }
  }

  void localChanged() {
    if (state == SyncState.authRequired) return;
    _schedule(const Duration(milliseconds: 350));
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    _timer?.cancel();
    if (foreground && state != SyncState.authRequired) unawaited(syncNow());
  }

  Future<void> stop() async {
    _disposed = true;
    _timer?.cancel();
    await _running;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
