import 'package:flutter/material.dart';

import '../../data/backup_repository.dart';
import '../../sync/protocol.dart';
import '../../theme/app_theme.dart';
import '../../theme/controls.dart';

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
        final left = widget.backups.repository.rejectedOperations();
        setState(() {
          problems = left;
        });
        // Figma: no «Готово»; the dialog goes once the last one is settled.
        final rest = await left;
        if (rest.isEmpty && mounted) Navigator.pop(context);
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
  Widget build(BuildContext context) => DayDialog(
    width: 520,
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
                      _Record(
                        type: problem['entityType'] as String?,
                        title: problem['label'] as String,
                      ),
                      const SizedBox(height: 8),
                      Text(reason(problem['code'])),
                      const SizedBox(height: 12),
                      // Figma «Конфликт синхронизации»: two grey buttons,
                      // stacked on a phone, halves of a row on a computer.
                      () {
                        final id = problem['operationId'] as String;
                        final local = DayButton(
                          kind: DayButtonKind.secondary,
                          expand: true,
                          onPressed: busy ? null : () => resolve(id, true),
                          label: const Text('Локальная версия'),
                        );
                        final server = DayButton(
                          kind: DayButtonKind.secondary,
                          expand: true,
                          onPressed: busy ? null : () => resolve(id, false),
                          label: const Text('Версия сервера'),
                        );
                        return isPhone(context)
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  local,
                                  const SizedBox(height: 8),
                                  server,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: local),
                                  const SizedBox(width: 8),
                                  Expanded(child: server),
                                ],
                              );
                      }(),
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
  );
}

/// Figma «Запись конфликта»: the record a change belongs to, on a card,
/// its kind above the name so it reads as «this task» (or list, or repeat).
class _Record extends StatelessWidget {
  final String? type;
  final String title;
  const _Record({required this.type, required this.title});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme;
    final kind = switch (type) {
      'list' => 'Список',
      'rule' => 'Повтор',
      _ => 'Задача',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(kind, style: text.bodySmall!.copyWith(color: c.muted)),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyLarge!.copyWith(color: c.text),
          ),
        ],
      ),
    );
  }
}
