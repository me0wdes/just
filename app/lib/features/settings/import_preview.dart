import '../../theme/fluid_button.dart';

import 'package:flutter/material.dart';

import '../../data/backup_repository.dart';

Future<bool> confirmImport(BuildContext context, ImportPreview preview) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Импортировать задачи?'),
        content: Text(
          'Новых записей: ${preview.newCount}\nСовпадающих: ${preview.matchingCount}\n\nДанные из файла заменят совпадающие записи. Перед импортом сохраним резервную копию.',
        ),
        actions: [
          FluidButton.text(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FluidButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Импортировать'),
          ),
        ],
      ),
    ) ??
    false;
