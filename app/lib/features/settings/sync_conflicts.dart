import '../../theme/fluid_button.dart';

import 'package:flutter/material.dart';

import '../../data/backup_repository.dart';
import '../../sync/protocol.dart';

class SyncConflicts extends StatefulWidget {
  final BackupRepository backups;
  const SyncConflicts({super.key, required this.backups});
  @override
  State<SyncConflicts> createState() => _SyncConflictsState();
}

class _SyncConflictsState extends State<SyncConflicts> {
  late Future<List<Json>> problems;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    problems = widget.backups.repository.rejectedOperations();
  }

  Future<void> resolve(String id, bool retry) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.backups.createSafetyBackup();
      await widget.backups.repository.resolveRejected(id, retry: retry);
      if (mounted) {
        setState(
          () => problems = widget.backups.repository.rejectedOperations(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Не удалось применить выбор. Данные сохранены.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String reason(Object? code) => switch (code) {
    'invalid_color' => 'Не удалось принять цвет списка.',
    'entity_deleted' => 'Запись удалена на другом устройстве.',
    'entity_missing' => 'На сервере отсутствует эта запись.',
    'rule_missing' => 'На сервере отсутствует связанный повтор.',
    'dependency_rejected' => 'Сначала нужно разрешить предыдущее изменение.',
    _ =>
      'Сервер не принял это изменение. Исправьте запись или выберите версию.',
  };
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Неотправленные изменения'),
    content: SizedBox(
      width: 480,
      child: FutureBuilder<List<Json>>(
        future: problems,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const LinearProgressIndicator();
          return ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Локальная версия заменит совпадающую запись на сервере. Перед выбором сохраним резервную копию.',
              ),
              if (snapshot.data!.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('Все конфликты разобраны.'),
                ),
              for (final problem in snapshot.data!)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        problem['label'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(reason(problem['code'])),
                      Wrap(
                        spacing: 8,
                        children: [
                          FluidButton.text(
                            onPressed: busy
                                ? null
                                : () => resolve(
                                    problem['operationId'] as String,
                                    true,
                                  ),
                            child: const Text('Оставить локальную версию'),
                          ),
                          FluidButton.text(
                            onPressed: busy
                                ? null
                                : () => resolve(
                                    problem['operationId'] as String,
                                    false,
                                  ),
                            child: const Text('Взять версию сервера'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      FluidButton.text(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Готово'),
      ),
    ],
  );
}
