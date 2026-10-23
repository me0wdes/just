import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/controls.dart';
import '../../theme/day_icon.dart';
import '../../theme/fluid_button.dart';
import '../../theme/motion_tokens.dart';
import '../../theme/segments.dart';

import '../../sync/connection_service.dart';
import '../../sync/sync_transport.dart';

class ConnectionPanel extends StatefulWidget {
  final ConnectionService service;
  final bool connected;
  final Future<void> Function(ConnectionResult) onConnected;
  final Future<void> Function() onDisconnected;
  const ConnectionPanel({
    super.key,
    required this.service,
    required this.connected,
    required this.onConnected,
    required this.onDisconnected,
  });
  @override
  State<ConnectionPanel> createState() => _ConnectionPanelState();
}

class _ConnectionPanelState extends State<ConnectionPanel> {
  final endpoint = TextEditingController(),
      key = TextEditingController(),
      link = TextEditingController();
  late bool serverMode = widget.connected;
  bool manual = false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    endpoint.dispose();
    key.dispose();
    link.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final preview = await widget.service.inspect(
        Uri.parse(endpoint.text.trim()),
        key.text.trim(),
      );
      if (!mounted) return;
      final choice = await showDialog<ConnectionChoice>(
        context: context,
        builder: (context) => DayDialog(
          width: 480,
          title: const Text('Подключить устройства'),
          content: SingleChildScrollView(
            child: Text(
              'На устройстве: ${preview.localCount} задач\nНа сервере: ${preview.remoteCount}\nСовпадающих id: ${preview.matchingCount}\nНеотправленных изменений: ${preview.pendingCount}\n\nПри объединении локальные поля заменят совпадающие данные. Отдельный набор сохранит прежние задачи и очередь на этом устройстве. В обоих случаях сохраним резервную копию.',
            ),
          ),
          actions: [
            DayButton(
              kind: DayButtonKind.ghost,
              onPressed: () => Navigator.pop(context),
              label: const Text('Отмена'),
            ),
            DayButton(
              kind: DayButtonKind.secondary,
              onPressed: () =>
                  Navigator.pop(context, ConnectionChoice.openSeparate),
              label: const Text('Открыть отдельно'),
            ),
            DayButton(
              kind: DayButtonKind.primary,
              onPressed: () => Navigator.pop(context, ConnectionChoice.merge),
              label: const Text('Объединить'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      final result = await widget.service.connect(preview, choice);
      key.clear();
      await widget.onConnected(result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is SyncHttpException && e.status == 401
              ? 'Ключ не подошёл'
              : 'Не удалось подключиться. Проверьте адрес, сертификат и доступность сервера.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Ends sync; tasks stay on this device.
  Future<void> disconnect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.disconnect();
      await widget.onDisconnected();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Синхронизация остановлена, но ключ мог остаться в системном хранилище.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickMode(int index) async {
    if (index == 0 && widget.connected) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => DayDialog(
          title: const Text('Хранить только на этом устройстве?'),
          content: const Text(
            'Синхронизация выключится. Задачи останутся здесь, на сервере они тоже сохранятся.',
          ),
          actions: [
            DayButton(
              kind: DayButtonKind.ghost,
              onPressed: () => Navigator.pop(context, false),
              label: const Text('Отмена'),
            ),
            DayButton(
              kind: DayButtonKind.ghost,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
              label: const Text('Выключить'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await disconnect();
    }
    if (mounted) setState(() => serverMode = index == 1);
  }

  Future<void> connectFromLink() async {
    final parsed = parseConnectionString(link.text);
    if (parsed == null) {
      setState(
        () => error = 'Это не строка подключения. Она начинается с just1: и выводится установщиком сервера.',
      );
      return;
    }
    endpoint.text = parsed.endpoint.toString();
    key.text = parsed.key;
    await connect();
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall!.copyWith(color: c.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Хранение данных',
          style: small.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        DaySegments(
          index: serverMode ? 1 : 0,
          labels: const ['На этом устройстве', 'Свой сервер'],
          onChanged: busy ? (_) {} : pickMode,
        ),
        const SizedBox(height: 10),
        if (!serverMode)
          Text('Задачи хранятся только здесь, без синхронизации.', style: small)
        else if (widget.connected) ...[
          Row(
            children: [
              DayIcon(DayGlyph.cloud, size: 16, color: c.done),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Синхронизация включена',
                  style: theme.textTheme.bodyMedium!.copyWith(color: c.text),
                ),
              ),
              FluidButton.text(
                onPressed: busy ? null : disconnect,
                child: const Text('Отключить'),
              ),
            ],
          ),
        ] else ...[
          Text(
            'Поставьте сервер одной командой на своём Linux-сервере. В конце он покажет строку подключения, вставьте её сюда.',
            style: small,
          ),
          const SizedBox(height: 8),
          _CommandBox(command: installCommand),
          const SizedBox(height: 12),
          if (!manual)
            TextField(
              key: const Key('sync-link'),
              controller: link,
              enabled: !busy,
              enableSuggestions: false,
              autocorrect: false,
              onSubmitted: (_) => connectFromLink(),
              decoration: const InputDecoration(hintText: 'just1:…'),
            )
          else ...[
            TextField(
              key: const Key('sync-endpoint'),
              controller: endpoint,
              enabled: !busy,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://…/sync'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('sync-secret'),
              controller: key,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'Ключ подключения'),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FluidButton(
                onPressed: busy ? null : (manual ? connect : connectFromLink),
                child: Text(busy ? 'Проверяем…' : 'Подключить'),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FluidButton.text(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          manual = !manual;
                          error = null;
                        }),
                  child: Text(
                    manual ? 'Вставить строку' : 'Ввести адрес и ключ',
                  ),
                ),
              ),
            ],
          ),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: small.copyWith(color: c.overdue)),
          ),
      ],
    );
  }
}

const installCommand =
    'curl -fsSL https://raw.githubusercontent.com/me0wdes/just/main/server/install.sh | sudo bash';

/// `just1:` + base64url JSON `{"u": endpoint, "k": key}`, as printed by
/// server/install.sh. Returns null for anything else.
({Uri endpoint, String key})? parseConnectionString(String text) {
  final raw = text.trim();
  if (!raw.startsWith('just1:')) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(raw.substring(6))),
    );
    final json = jsonDecode(payload) as Map<String, Object?>;
    final endpoint = Uri.parse(json['u'] as String);
    final key = json['k'] as String;
    if (endpoint.scheme != 'https' || key.isEmpty) return null;
    return (endpoint: endpoint, key: key);
  } catch (_) {
    return null;
  }
}

class _CommandBox extends StatelessWidget {
  final String command;
  const _CommandBox({required this.command});
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.input,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              command,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
                color: c.text,
              ),
            ),
          ),
          DayButton.icon(
            tooltip: 'Скопировать',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  persist: false,
                  duration: MotionTokens.toast,
                  content: Text('Команда скопирована'),
                ),
              );
            },
            icon: DayIcon(DayGlyph.upload, size: 16, color: c.muted),
          ),
        ],
      ),
    );
  }
}
