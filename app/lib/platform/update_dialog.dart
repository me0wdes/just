import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/controls.dart';
import 'update_service.dart';

/// Figma «Обновление»: the download with its progress and «Отмена», then
/// «Устанавливаю» while the silent installer takes over and Just quits.
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(update),
    );

class _UpdateDialog extends StatefulWidget {
  final AppUpdate update;
  const _UpdateDialog(this.update);
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  int received = 0, total = 0;
  bool installing = false, cancelled = false;
  String? error;

  @override
  void initState() {
    super.initState();
    run();
  }

  Future<void> run() async {
    try {
      await installInPlace(
        widget.update,
        cancelled: () => cancelled,
        onProgress: (got, all) {
          if (!mounted) return;
          setState(() {
            received = got;
            total = all;
          });
        },
      );
      if (!mounted) return;
      setState(() => installing = true);
      // Long enough to read; the installer waits for Just to close anyway.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      exit(0);
    } on UpdateCancelled {
      /* Closed by «Отмена». */
    } catch (_) {
      if (mounted) setState(() => error = 'Не удалось загрузить обновление');
    }
  }

  static String _mb(int bytes) =>
      (bytes / 1048576).toStringAsFixed(1).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!;
    final share = total > 0 ? received / total : null;
    final details = error != null
        ? 'Проверьте интернет и попробуйте ещё раз'
        : installing
        ? 'Just закроется и откроется уже новой версией'
        : total > 0
        ? '${_mb(received)} из ${_mb(total)} МБ · ${(share! * 100).round()}%'
        : 'Подключаюсь…';
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 400,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Just ${widget.update.version}',
                style: text.copyWith(
                  fontSize: 17,
                  height: 22 / 17,
                  fontWeight: FontWeight.w600,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                error ??
                    (installing
                        ? 'Устанавливаю обновление'
                        : 'Загружаю обновление'),
                style: text.copyWith(
                  fontSize: 15,
                  height: 21 / 15,
                  color: error != null ? c.overdue : c.muted,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: installing ? 1 : share,
                  minHeight: 6,
                  backgroundColor: c.track,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                details,
                style: text.copyWith(
                  fontSize: 13,
                  height: 18 / 13,
                  color: c.muted,
                ),
              ),
              if (!installing) ...[
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DayButton(
                    kind: DayButtonKind.ghost,
                    onPressed: () {
                      cancelled = true;
                      Navigator.pop(context);
                    },
                    label: Text(error != null ? 'Закрыть' : 'Отмена'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
