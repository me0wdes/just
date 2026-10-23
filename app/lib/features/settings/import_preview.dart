import 'package:flutter/material.dart';

import '../../data/backup_repository.dart';
import '../../theme/controls.dart';

Future<bool> confirmImport(BuildContext context, ImportPreview preview) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => DayDialog(
        title: const Text('Импортировать задачи?'),
        content: Text(
          'Новых записей: ${preview.newCount}\nСовпадающих: ${preview.matchingCount}\n\nДанные из файла заменят совпадающие записи. Перед импортом сохраним резервную копию.',
        ),
        actions: [
          DayButton(
            kind: DayButtonKind.ghost,
            onPressed: () => Navigator.pop(context, false),
            label: const Text('Отмена'),
          ),
          DayButton(
            kind: DayButtonKind.primary,
            onPressed: () => Navigator.pop(context, true),
            label: const Text('Импортировать'),
          ),
        ],
      ),
    ) ??
    false;
