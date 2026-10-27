import '../../theme/fluid_switch.dart';
import '../../theme/fluid_button.dart';
import '../../theme/day_icon.dart';

import 'package:flutter/material.dart';

import '../../data/backup_repository.dart';
import '../../platform/feedback_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/day_sound.dart';
import '../../theme/segments.dart';
import '../../platform/file_dialogs.dart';
import 'settings_controller.dart';
import 'import_preview.dart';
import '../../theme/fluid_surface.dart';
import '../../platform/update_service.dart';
import '../../theme/controls.dart';

class SettingsPanel extends StatefulWidget {
  final SettingsController settings;
  final BackupRepository backups;
  final FileDialogs files;
  final Widget? connectionPanel;
  final String? updateVersion;
  final VoidCallback? onUpdate;
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.backups,
    required this.files,
    this.connectionPanel,
    this.updateVersion,
    this.onUpdate,
  });
  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  String? message;
  bool busy = false;
  Future<void> transfer(bool importing) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (importing) {
        final bytes = await widget.files.pickJson();
        if (bytes == null) return;
        final preview = await widget.backups.inspectImport(bytes);
        if (!mounted) return;
        if (!await confirmImport(context, preview)) return;
        final result = await widget.backups.applyImport(preview);
        if (mounted) {
          setState(
            () => message =
                'Импортировано: ${result.appliedCount}. Предыдущие данные сохранены в резервной копии.',
          );
        }
      } else {
        final saved = await widget.files.saveJson(
          'just-tasks.json',
          await widget.backups.exportBytes(),
        );
        if (saved && mounted) setState(() => message = 'Копия сохранена');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is FormatException
              ? e.message
              : e is StateError
              ? e.message
              : 'Не удалось открыть или сохранить файл',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: DayColors.of(context).muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      final s = widget.settings;
      final colors = DayColors.of(context);
      const modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Настройки',
                        style: Theme.of(context).textTheme.titleLarge!
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    FluidIconButton(
                      tooltip: 'Закрыть',
                      sound: null,
                      onPressed: () => Navigator.pop(context),
                      icon: const DayIcon(DayGlyph.close, size: 20),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.divider),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    // Figma «Настройки»: three buttons on a computer, a
                    // dropdown on a phone, where they would not fit.
                    section('Оформление', [
                      if (MediaQuery.sizeOf(context).width < 600)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Тема',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            SizedBox(
                              width: 150,
                              child: DaySelect<ThemeMode>(
                                value: s.themeMode,
                                items: [
                                  for (final (i, label) in const [
                                    'Системная',
                                    'Светлая',
                                    'Тёмная',
                                  ].indexed)
                                    DaySelectItem(modes[i], label),
                                ],
                                onChanged: s.setTheme,
                              ),
                            ),
                          ],
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DaySegments(
                            index: modes.indexOf(s.themeMode),
                            labels: const ['Системная', 'Светлая', 'Тёмная'],
                            onChanged: (i) => s.setTheme(modes[i]),
                          ),
                        ),
                    ]),
                    section('Взаимодействие', [
                      FluidSwitchTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Звуки интерфейса'),
                        value: s.completionSoundEnabled,
                        onChanged: s.setSound,
                      ),
                      if (s.completionSoundEnabled)
                        // Figma «Громкость / Иконки»: quiet and loud at the ends.
                        Row(
                          children: [
                            DayIcon(
                              DayGlyph.volumeLow,
                              size: 20,
                              color: colors.muted,
                            ),
                            Expanded(
                              // Clean track as in Figma: no tick marks, icons
                              // 12 px from its ends.
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  tickMarkShape: SliderTickMarkShape.noTickMark,
                                ),
                                child: Slider(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  value: s.volume,
                                  onChanged: s.setVolume,
                                  // Let the user hear the level they picked.
                                  onChangeEnd: (_) =>
                                      DaySound.play(context, UiSound.complete),
                                  label: 'Громкость',
                                  divisions: 20,
                                ),
                              ),
                            ),
                            DayIcon(
                              DayGlyph.volumeHigh,
                              size: 20,
                              color: colors.muted,
                            ),
                          ],
                        ),
                      FluidSwitchTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Вибрация'),
                        value: s.hapticsEnabled,
                        onChanged: s.setHaptics,
                      ),
                    ]),
                    if (widget.connectionPanel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: widget.connectionPanel!,
                      ),
                    section('Данные', [
                      // Inset so the hover fill does not start at the icon;
                      // the surface lets the icon play its motion.
                      FluidSurface(
                        sound: null,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: const DayIcon(DayGlyph.upload, size: 20),
                          title: const Text('Сохранить копию задач'),
                          onTap: busy
                              ? null
                              : () {
                                  DaySound.play(context, UiSound.tap);
                                  transfer(false);
                                },
                        ),
                      ),
                      // Inset so the hover fill does not start at the icon;
                      // the surface lets the icon play its motion.
                      FluidSurface(
                        sound: null,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: const DayIcon(DayGlyph.download, size: 20),
                          title: const Text('Импортировать копию'),
                          onTap: busy
                              ? null
                              : () {
                                  DaySound.play(context, UiSound.tap);
                                  transfer(true);
                                },
                        ),
                      ),
                    ]),
                    if (busy) const LinearProgressIndicator(),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(message!),
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            // Release builds carry their version from CI.
                            'Just · ${appVersion.isEmpty ? 'dev' : appVersion}',
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: colors.muted),
                          ),
                        ),
                        // A missed «Вышла версия» toast stays reachable here.
                        if (widget.updateVersion != null &&
                            widget.onUpdate != null)
                          DayButton(
                            key: const Key('settings-update'),
                            kind: DayButtonKind.secondary,
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onUpdate!();
                            },
                            label: Text('Обновить до ${widget.updateVersion}'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
