import '../../theme/fluid_button.dart';

import 'package:flutter/material.dart';

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
  final endpoint = TextEditingController(), key = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    endpoint.dispose();
    key.dispose();
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
        builder: (context) => AlertDialog(
          title: const Text('Подключить устройства'),
          content: SingleChildScrollView(
            child: Text(
              'На устройстве: ${preview.localCount} задач\nНа сервере: ${preview.remoteCount}\nСовпадающих id: ${preview.matchingCount}\nНеотправленных изменений: ${preview.pendingCount}\n\nПри объединении локальные поля заменят совпадающие данные. Отдельный набор сохранит прежние задачи и очередь на этом устройстве. В обоих случаях сохраним резервную копию.',
            ),
          ),
          actions: [
            FluidButton.text(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FluidButton.text(
              onPressed: () =>
                  Navigator.pop(context, ConnectionChoice.openSeparate),
              child: const Text('Открыть отдельно'),
            ),
            FluidButton(
              onPressed: () => Navigator.pop(context, ConnectionChoice.merge),
              child: const Text('Объединить'),
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Синхронизация',
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      if (widget.connected)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Устройства подключены'),
          trailing: FluidButton.text(
            onPressed: busy
                ? null
                : () async {
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
                  },
            child: const Text('Отключить'),
          ),
        ),
      TextField(
        key: const Key('sync-endpoint'),
        controller: endpoint,
        enabled: !busy,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'HTTPS-адрес сервера',
          hintText: 'https://…/sync',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        key: const Key('sync-secret'),
        controller: key,
        enabled: !busy,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Ключ подключения'),
      ),
      const SizedBox(height: 10),
      FluidButton.tonal(
        onPressed: busy ? null : connect,
        child: Text(busy ? 'Проверяем подключение…' : 'Проверить и подключить'),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
