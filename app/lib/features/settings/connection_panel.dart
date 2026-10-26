import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/controls.dart';
import '../../platform/feedback_service.dart';
import '../../theme/day_icon.dart';
import '../../theme/day_sound.dart';
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
        setState(() => error = connectionError(e, endpoint.text.trim()));
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

  /// Step 4: the string the installer printed, straight from the clipboard.
  Future<void> pasteAndConnect() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted) return;
    if (text == null || !text.startsWith('just1:')) {
      setState(
        () => error = 'В буфере обмена нет строки подключения. Скопируйте строку, которая начинается с just1:, и нажмите ещё раз.',
      );
      return;
    }
    link.text = text;
    await connectFromLink();
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
          labels: const ['На устройстве', 'Свой сервер'],
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
          // Figma «Хранение данных · Сервер»: four steps a non-admin can follow.
          Text(
            'Задачи синхронизируются между устройствами через ваш собственный сервер. Понадобится сервер с Linux: его можно арендовать у любого хостинга.',
            style: small,
          ),
          const SizedBox(height: 14),
          const _Step(
            number: 1,
            title: 'Зайдите на сервер',
            text: 'Откройте терминал (на Windows это PowerShell) и подключитесь к серверу по адресу и паролю, которые прислал хостинг.',
          ),
          const _Step(
            number: 2,
            title: 'Установите Just на сервер',
            text: 'Вставьте эту команду в окно сервера правой кнопкой мыши и нажмите Enter. Установка займёт пару минут.',
            child: _CommandBox(command: installCommand),
          ),
          const _Step(
            number: 3,
            title: 'Скопируйте строку подключения',
            text: 'В конце установки появится строка, которая начинается с just1:. Выделите её целиком и скопируйте.',
          ),
          _Step(
            number: 4,
            title: 'Вставьте её в Just',
            text: manual
                ? 'Адрес и ключ тоже выводит установщик.'
                : 'Just возьмёт строку из буфера обмена и сразу подключится.',
            child: manual
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const Key('sync-endpoint'),
                        controller: endpoint,
                        enabled: !busy,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          hintText: 'https://…/sync',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('sync-secret'),
                        controller: key,
                        enabled: !busy,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          hintText: 'Ключ подключения',
                        ),
                      ),
                      const SizedBox(height: 10),
                      DayButton(
                        onPressed: busy ? null : connect,
                        label: Text(busy ? 'Проверяем…' : 'Подключить'),
                      ),
                    ],
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: DayButton(
                      onPressed: busy ? null : pasteAndConnect,
                      label: Text(
                        busy ? 'Проверяем…' : 'Вставить и подключить',
                      ),
                    ),
                  ),
          ),
          DayButton(
            kind: DayButtonKind.ghost,
            onPressed: busy
                ? null
                : () => setState(() {
                    manual = !manual;
                    error = null;
                  }),
            label: Text(
              manual
                  ? 'Вставить строку из буфера'
                  : 'Ввести адрес и ключ вручную',
            ),
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
    // A direct server sends its certificate fingerprint; it rides along in
    // the address as #pin=… and the transport trusts only that certificate.
    final pin = json['p'];
    if (pin == null) return (endpoint: endpoint, key: key);
    if (pin is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
      return null;
    }
    return (endpoint: endpoint.replace(fragment: 'pin=$pin'), key: key);
  } catch (_) {
    return null;
  }
}

/// A command to copy: the text on top, «Скопировать» under it, so a long
/// line keeps its width on a phone too. The button itself confirms the copy
/// for two seconds: a toast would land under the settings dialog.
class _CommandBox extends StatefulWidget {
  final String command;
  const _CommandBox({required this.command});
  @override
  State<_CommandBox> createState() => _CommandBoxState();
}

class _CommandBoxState extends State<_CommandBox> {
  bool copied = false;
  Timer? reset;

  Future<void> copy() async {
    await Clipboard.setData(ClipboardData(text: widget.command));
    if (!mounted) return;
    DaySound.play(context, UiSound.complete);
    SemanticsService.sendAnnouncement(
      View.of(context),
      'Команда скопирована',
      TextDirection.ltr,
    );
    setState(() => copied = true);
    reset?.cancel();
    reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => copied = false);
    });
  }

  @override
  void dispose() {
    reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.input,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            widget.command,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(fontSize: 13, height: 18 / 13, color: c.text),
          ),
          const SizedBox(height: 8),
          DayButton(
            kind: DayButtonKind.secondary,
            sound: null,
            onPressed: copy,
            icon: AnimatedSwitcher(
              duration: MotionTokens.duration(context, MotionTokens.fast),
              child: copied
                  ? DayIcon(
                      DayGlyph.check,
                      key: const ValueKey('done'),
                      size: 16,
                      color: c.done,
                    )
                  : DayIcon(
                      DayGlyph.copy,
                      key: const ValueKey('copy'),
                      size: 16,
                      color: c.text,
                    ),
            ),
            label: Text(copied ? 'Скопировано' : 'Скопировать'),
          ),
        ],
      ),
    );
  }
}

/// What went wrong, in words a person can act on.
String connectionError(Object e, String address) {
  final uri = Uri.tryParse(address);
  final host = uri?.host ?? address;
  final port = uri?.hasPort == true ? uri!.port : 443;
  final pinned = uri?.fragment.startsWith('pin=') ?? false;
  return switch (e) {
    FormatException(:final message) => message,
    SyncHttpException(status: 401) =>
      'Ключ не подошёл. Скопируйте строку подключения ещё раз целиком.',
    SyncHttpException(:final status) => 'Сервер ответил ошибкой $status.',
    HandshakeException() || TlsException() when pinned => 'Сертификат сервера не совпадает со строкой подключения. Возьмите строку заново на сервере: sudo just-sync owner',
    HandshakeException() || TlsException() =>
      'Сервер $host нашёлся, но его сертификат не принят. Проверьте, что HTTPS настроен.',
    SocketException(:final message, :final osError)
        when '$message ${osError?.message}'.contains('lookup') =>
      'Не удаётся найти сервер $host. Проверьте интернет или адрес.',
    SocketException() || TimeoutException() =>
      'Сервер $host не отвечает на порту $port. Проверьте, что он включён и порт $port открыт у хостинга.',
    _ => 'Не удалось подключиться: $e',
  };
}

/// A numbered step: the number in a circle, a title, a line of help and an
/// optional control under it.
class _Step extends StatelessWidget {
  final int number;
  final String title, text;
  final Widget? child;
  const _Step({
    required this.number,
    required this.title,
    required this.text,
    this.child,
  });
  @override
  Widget build(BuildContext context) {
    final c = DayColors.of(context);
    final body = Theme.of(context).textTheme.bodyMedium!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.track, shape: BoxShape.circle),
            child: Text(
              '$number',
              style: body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: body.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: body.copyWith(
                    fontSize: 13,
                    height: 18 / 13,
                    color: c.muted,
                  ),
                ),
                if (child != null) ...[const SizedBox(height: 8), child!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
